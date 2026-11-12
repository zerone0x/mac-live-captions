import Foundation

/// Coalesces volatile caption updates so the overlay redraws at a readable
/// pace (docs/DECISIONS.md, 0012).
///
/// - A snapshot with new finalized text, or an empty snapshot, is shown at
///   once.
/// - A snapshot that only changes volatile text is shown at once if the last
///   update is at least `interval` old; otherwise it waits, and only the
///   newest waiting snapshot is shown when the interval is over.
///
/// Pure value type: the caller passes the time and runs the timer.
public struct CaptionUpdateThrottle: Sendable {
    public enum Decision: Sendable, Hashable {
        /// Show this snapshot now.
        case presentNow(CaptionSnapshot)
        /// The snapshot is kept as `pending`; call `flush(at:)` at `until`.
        case deferred(until: TimeInterval)
    }

    /// Default: about four volatile updates a second (research §2.3 suggests
    /// merging updates every 200–300 ms).
    public static let defaultInterval: TimeInterval = 0.25

    public let interval: TimeInterval
    /// The newest snapshot that is waiting to be shown.
    public private(set) var pending: CaptionSnapshot?
    private var lastPresented: TimeInterval?
    private var presentedFinalIDs: [SegmentID] = []

    public init(interval: TimeInterval = Self.defaultInterval) {
        self.interval = max(0, interval)
    }

    public mutating func submit(_ snapshot: CaptionSnapshot, at now: TimeInterval) -> Decision {
        let finalIDs = Self.finalIDs(of: snapshot)
        let hasNewFinalText = snapshot.isEmpty || finalIDs != presentedFinalIDs
        if hasNewFinalText || interval == 0 {
            return present(snapshot, at: now)
        }
        guard let lastPresented, now < lastPresented + interval else {
            return present(snapshot, at: now)
        }
        pending = snapshot
        return .deferred(until: lastPresented + interval)
    }

    /// Returns the waiting snapshot, if any, and marks it shown at `now`.
    public mutating func flush(at now: TimeInterval) -> CaptionSnapshot? {
        guard let pending else { return nil }
        record(pending, at: now)
        return pending
    }

    // MARK: - Private

    private mutating func present(_ snapshot: CaptionSnapshot, at now: TimeInterval) -> Decision {
        record(snapshot, at: now)
        return .presentNow(snapshot)
    }

    private mutating func record(_ snapshot: CaptionSnapshot, at now: TimeInterval) {
        pending = nil
        lastPresented = now
        presentedFinalIDs = Self.finalIDs(of: snapshot)
    }

    private static func finalIDs(of snapshot: CaptionSnapshot) -> [SegmentID] {
        snapshot.lines.filter(\.isFinal).map(\.id)
    }
}

/// Runs one caption session: audio source → transcriber → caption store →
/// presenter, with volatile updates throttled.
///
/// The app owns the source and stops it to end the session; `run()` then
/// returns once the transcriber has delivered its last final result.
/// Errors from the source (permission, capture failure) and from the
/// transcriber (model missing) are thrown from `run()`.
///
/// Transcripts stay in memory (`CaptionStore`, bounded) and are never written
/// to disk or logged.
@MainActor
public final class CaptionPipeline {
    /// Session time in seconds, for throttling.
    public typealias Now = @MainActor () -> TimeInterval
    /// Waits for the given number of seconds (or until cancelled).
    public typealias Sleep = @Sendable (TimeInterval) async -> Void

    private let source: any AudioSource
    private let transcriber: any Transcriber
    private let presenter: any CaptionPresenter
    private let now: Now
    private let sleep: Sleep
    private var store: CaptionStore
    private var throttle: CaptionUpdateThrottle
    private var flushTask: Task<Void, Never>?

    public init(
        source: any AudioSource,
        transcriber: any Transcriber,
        presenter: any CaptionPresenter,
        store: CaptionStore.Configuration = CaptionStore.Configuration(),
        throttleInterval: TimeInterval = CaptionUpdateThrottle.defaultInterval,
        now: Now? = nil,
        sleep: Sleep? = nil
    ) {
        self.source = source
        self.transcriber = transcriber
        self.presenter = presenter
        self.store = CaptionStore(configuration: store)
        self.throttle = CaptionUpdateThrottle(interval: throttleInterval)
        if let now {
            self.now = now
        } else {
            let start = ContinuousClock.now
            self.now = { Self.seconds(ContinuousClock.now - start) }
        }
        self.sleep = sleep ?? { seconds in
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    /// The finalized transcript of this session, in memory only.
    public var transcript: [TranscriptSegment] { store.transcript }

    /// Captures and transcribes until the audio ends (after the source is
    /// stopped) or fails.
    public func run() async throws {
        let audio = try await source.start()
        defer {
            flushTask?.cancel()
            flushTask = nil
            if let snapshot = throttle.flush(at: now()) {
                presenter.present(snapshot)
            }
        }
        for try await event in transcriber.transcribe(audio) {
            if store.apply(event).changedState {
                submit(store.snapshot)
            }
        }
    }

    // MARK: - Private

    private func submit(_ snapshot: CaptionSnapshot) {
        switch throttle.submit(snapshot, at: now()) {
        case .presentNow(let snapshot):
            flushTask?.cancel()
            flushTask = nil
            presenter.present(snapshot)
        case .deferred(let deadline):
            guard flushTask == nil else { return }
            let delay = max(0, deadline - now())
            let sleep = self.sleep
            flushTask = Task { [weak self] in
                await sleep(delay)
                guard !Task.isCancelled else { return }
                self?.flushDue()
            }
        }
    }

    private func flushDue() {
        flushTask = nil
        if let snapshot = throttle.flush(at: now()) {
            presenter.present(snapshot)
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
