import AppKit

/// 共享屏幕时不让对方看到 Tyto 的任何窗口：sharingType = .none 的窗口，系统截屏、录屏、会议软件共享都截不到。
/// 弹出来的小窗口（下拉菜单、提示气泡、改名气泡、更新窗口、提示框……）是另建的，不会自动继承这个设置，
/// 所以在主线程每一轮事件处理完、画到屏幕上之前（Core Animation 提交之前）把所有窗口检查一遍。
/// 菜单打开时主线程在"事件跟踪"模式下跑，也算在 commonModes 里，照样检查。
@MainActor
enum SharingGuard {
    private static var observer: CFRunLoopObserver?
    /// 自测用：暂停（对照组要故意让窗口被截到）
    static var paused = false
    /// 自测用：这些窗口不管（自测铺的背景要能被截到）
    static var exempt: Set<ObjectIdentifier> = []

    static func install() {
        guard observer == nil else { return }
        // order 0：排在 Core Animation 提交（2000000）之前
        let created = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, _ in
            MainActor.assumeIsolated { sweep() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), created, .commonModes)
        observer = created
        sweep()
    }

    static func sweep() {
        guard !paused else { return }
        for window in NSApp.windows where window.sharingType != .none && !exempt.contains(ObjectIdentifier(window)) {
            window.sharingType = .none
        }
    }
}
