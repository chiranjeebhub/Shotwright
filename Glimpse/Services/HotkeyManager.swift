import Carbon.HIToolbox

/// System-wide hotkeys via Carbon's RegisterEventHotKey, which (unlike NSEvent
/// global monitors) needs no Accessibility permission.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    func register(keyCode: Int, modifiers: Int, handler: @escaping @MainActor () -> Void) {
        installEventHandlerIfNeeded()
        let id = nextID
        nextID += 1
        handlers[id] = handler

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x474C_4D50), id: id) // 'GLMP'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
        } else {
            NSLog("Glimpse: couldn't register hotkey \(keyCode) (status \(status)); it may be taken by another app.")
        }
    }

    func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let id = hotKeyID.id
            Task { @MainActor in HotkeyManager.shared.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}

extension HotkeyManager {
    /// ⌥⇧ + number, so the defaults don't collide with macOS's own ⌘⇧3/4/5.
    func registerDefaults() {
        let mods = optionKey | shiftKey
        register(keyCode: kVK_ANSI_4, modifiers: mods) { CaptureCoordinator.shared.captureArea() }
        register(keyCode: kVK_ANSI_5, modifiers: mods) { CaptureCoordinator.shared.captureWindow() }
        register(keyCode: kVK_ANSI_3, modifiers: mods) { CaptureCoordinator.shared.captureFullscreen() }
        register(keyCode: kVK_ANSI_6, modifiers: mods) { CaptureCoordinator.shared.capturePreviousArea() }
        register(keyCode: kVK_ANSI_2, modifiers: mods) { CaptureCoordinator.shared.captureText() }
    }
}
