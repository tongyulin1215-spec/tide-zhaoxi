import Carbon
import Foundation

/// A system-wide shortcut via Carbon's RegisterEventHotKey (no accessibility permission needed).
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private(set) var isRegistered = false

    /// Default ⌥Space (⌃⌥Space is the system "next input source" shortcut).
    static let defaultKeyCode = UInt32(kVK_Space)
    static let defaultModifiers = UInt32(optionKey)

    init(keyCode: UInt32 = HotKey.defaultKeyCode, modifiers: UInt32 = HotKey.defaultModifiers, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, me, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4352_4520), id: 1) // "CRE "
        isRegistered = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
