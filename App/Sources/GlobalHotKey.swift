import Carbon.HIToolbox
import Foundation

/// The global shortcut that starts and stops captions from any app:
/// Control-Option-C (⌃⌥C).
///
/// Uses Carbon's `RegisterEventHotKey`, which needs no Accessibility or Input
/// Monitoring permission (unlike a global `NSEvent` monitor) and only sees
/// this one key combination.
@MainActor
final class GlobalHotKey {
    /// Shown in the menu and in Settings.
    static let displayName = "⌃⌥C"

    private static var action: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Whether the system accepted the shortcut (another app may own it).
    private(set) var isRegistered = false

    init(action: @escaping @MainActor () -> Void) {
        Self.action = action
        register()
    }

    static func fire() {
        action?()
    }

    private func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        guard installStatus == noErr else { return }

        // 'LCAP'
        let id = EventHotKeyID(signature: OSType(0x4C43_4150), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_C),
            UInt32(controlKey | optionKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        isRegistered = registerStatus == noErr
    }
}

/// Carbon calls this on the main thread when the shortcut is pressed.
private func globalHotKeyHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    Task { @MainActor in
        GlobalHotKey.fire()
    }
    return noErr
}
