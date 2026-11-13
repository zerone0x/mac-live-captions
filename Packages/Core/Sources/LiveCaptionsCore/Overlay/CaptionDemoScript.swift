import Foundation

/// A scripted English caption feed for the "Demo Captions" menu item, so the
/// overlay can be seen without audio or permissions.
///
/// Each utterance goes through several volatile hypotheses (growing word by
/// word, with a few mishearings that get corrected) and then finalizes, the way
/// `SpeechTranscriber` reports results. Snapshots are shaped like the ones a
/// caption store would publish: the latest final segments plus the volatile one.
public struct CaptionDemoScript: Sendable {
    public struct Step: Sendable, Hashable {
        /// Seconds to wait after the previous step before presenting this one.
        public var delay: TimeInterval
        public var snapshot: CaptionSnapshot

        public init(delay: TimeInterval, snapshot: CaptionSnapshot) {
            self.delay = delay
            self.snapshot = snapshot
        }
    }

    /// One utterance: volatile hypotheses in order, then the final text.
    public struct Utterance: Sendable, Hashable {
        public var hypotheses: [String]
        public var final: String
        /// Silence before the utterance starts, in seconds.
        public var pauseBefore: TimeInterval

        public init(hypotheses: [String], final: String, pauseBefore: TimeInterval = 0.6) {
            self.hypotheses = hypotheses
            self.final = final
            self.pauseBefore = pauseBefore
        }
    }

    public var steps: [Step]

    public init(steps: [Step]) {
        self.steps = steps
    }

    /// Builds the steps for `utterances`.
    ///
    /// - Parameters:
    ///   - volatileInterval: seconds between volatile revisions.
    ///   - keptFinals: how many earlier final segments each snapshot repeats.
    public init(
        utterances: [Utterance],
        volatileInterval: TimeInterval = 0.3,
        keptFinals: Int = 2,
        origin: AudioOrigin = .system
    ) {
        var steps: [Step] = []
        var finals: [CaptionLine] = []
        for (index, utterance) in utterances.enumerated() {
            let id = SegmentID(Self.demoUUID(index))
            for (revision, hypothesis) in utterance.hypotheses.enumerated() {
                let line = CaptionLine(id: id, text: hypothesis, origin: origin, isFinal: false)
                steps.append(
                    Step(
                        delay: revision == 0 ? utterance.pauseBefore : volatileInterval,
                        snapshot: CaptionSnapshot(lines: Array(finals.suffix(keptFinals)) + [line])
                    ))
            }
            let final = CaptionLine(id: id, text: utterance.final, origin: origin, isFinal: true)
            finals.append(final)
            steps.append(
                Step(
                    delay: utterance.hypotheses.isEmpty ? utterance.pauseBefore : volatileInterval,
                    snapshot: CaptionSnapshot(lines: Array(finals.suffix(keptFinals)))
                ))
        }
        self.init(steps: steps)
    }

    /// Total running time in seconds.
    public var duration: TimeInterval {
        steps.reduce(0) { $0 + $1.delay }
    }

    private static func demoUUID(_ index: Int) -> UUID {
        let suffix = String(index, radix: 16)
        let padded = String(repeating: "0", count: max(0, 12 - suffix.count)) + suffix
        return UUID(uuidString: "DE300000-0000-4000-8000-\(padded)")!
    }

    /// The feed the "Demo Captions" menu item plays (about 20 seconds). The
    /// long pause before the last utterance lets the overlay collapse once.
    public static let english = CaptionDemoScript(utterances: [
        Utterance(
            hypotheses: ["Welcome", "Welcome to", "Welcome to live", "Welcome to live captions"],
            final: "Welcome to LiveCaptions.",
            pauseBefore: 0.3
        ),
        Utterance(
            hypotheses: [
                "Everything",
                "Everything you here",
                "Everything you hear on",
                "Everything you hear on your Mac",
                "Everything you hear on your Mac is transcribed",
            ],
            final: "Everything you hear on your Mac is transcribed on device."
        ),
        Utterance(
            hypotheses: [
                "Gray",
                "Gray text",
                "Grey text is still",
                "Grey text is still a guess",
                "Grey text is still a guess from the recognizer",
            ],
            final: "Grey text is still a guess from the recognizer;"
        ),
        Utterance(
            hypotheses: [
                "white",
                "white text is",
                "white text is final",
                "white text is final and never",
                "white text is final and never moves",
            ],
            final: "white text is final and never moves."
        ),
        Utterance(
            hypotheses: [
                "Lines scroll",
                "Lines scroll up as",
                "Lines scroll up as the speaker keeps",
                "Lines scroll up as the speaker keeps talking",
                "Lines scroll up as the speaker keeps talking, two lines",
            ],
            final: "Lines scroll up as the speaker keeps talking, two lines at a time."
        ),
        Utterance(
            hypotheses: [
                "When the",
                "When the room",
                "When the room goes quiet",
                "When the room goes quiet the overlay",
            ],
            final: "When the room goes quiet, the overlay folds away."
        ),
        Utterance(
            hypotheses: [
                "And it",
                "And it comes back",
                "And it comes back as soon as",
                "And it comes back as soon as someone speaks",
            ],
            final: "And it comes back as soon as someone speaks again.",
            pauseBefore: 8
        ),
    ])
}
