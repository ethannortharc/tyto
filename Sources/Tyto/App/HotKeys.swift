import Carbon.HIToolbox
import Foundation

/// 全局快捷键（会议软件在前台时也能用）。用 Carbon 的热键接口，不需要辅助功能权限。
@MainActor
final class HotKeys {
    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    /// - keyCode: 如 kVK_ANSI_T
    /// - modifiers: 如 optionKey | cmdKey
    /// - Returns: 编号，用来 unregister（只在某个窗口开着时才要的快捷键）
    @discardableResult
    func register(keyCode: Int, modifiers: Int, _ handler: @escaping () -> Void) -> UInt32 {
        installIfNeeded()
        let id = nextID
        nextID += 1
        handlers[id] = handler
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5459_544F), id: id) // "TYTO"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &reference)
        if status == noErr, let reference {
            references[id] = reference
        } else {
            RunLog.write("快捷键注册失败（键码 \(keyCode)，\(status)），可能被别的 App 占用了")
        }
        return id
    }

    func unregister(_ id: UInt32) {
        if let reference = references.removeValue(forKey: id) { UnregisterEventHotKey(reference) }
        handlers[id] = nil
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKeys.handlers[id]?() }
            return noErr
        }, 1, &eventType, me, nil)
    }
}
