import AppKit
import Combine
import Sparkle

/// 自动更新（Sparkle）：每天查一次 GitHub Releases 上的 appcast.xml，有新版就在后台下载，下次退出时装好。
/// 更新包要用我们的 EdDSA 私钥签过名（公钥在 Info.plist 的 SUPublicEDKey），还要是同一个开发者签名，才会装。
/// 自己编译的（build/、dist/ 里的）不查：免得开发版被替换成发布版。
@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    @Published private(set) var canCheck = false
    private var observation: NSKeyValueObservation?
    /// 自测用：换一个 appcast 地址
    private let feedOverride: String?
    /// 自测用：装完不重新打开；每一步报给 onEvent
    var relaunchesAfterUpdate = true
    var onEvent: ((String) -> Void)?

    /// 这一份能不能自动更新（自己编译的不能）
    let isEnabled: Bool

    init(feedOverride: String? = nil, forceEnabled: Bool = false) {
        self.feedOverride = feedOverride
        isEnabled = forceEnabled || !Installer.isDevBuild(Bundle.main.bundleURL.resolvingSymlinksInPath().path)
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: isEnabled, updaterDelegate: self, userDriverDelegate: nil)
        // Sparkle 在主线程上改这个值
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let can = change.newValue ?? false
            MainActor.assumeIsolated { self?.canCheck = can }
        }
    }

    var updater: SPUUpdater { controller.updater }

    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// 自动下载并在退出时装好（关掉时有新版会弹窗问）
    var automaticallyDownloads: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    var lastCheck: Date? { updater.lastUpdateCheckDate }

    /// 菜单里的「检查更新…」：有没有新版都会告诉你
    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        feedOverride
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { onEvent?("found \(version)") }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { onEvent?("no update") }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated { onEvent?("error \(message)") }
    }

    /// 新版下载好了，等退出时装（返回 false：按 Sparkle 默认的"退出时安装"走）
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock: @escaping () -> Void) -> Bool {
        let version = item.displayVersionString
        MainActor.assumeIsolated { onEvent?("ready \(version)") }
        return false
    }

    nonisolated func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        MainActor.assumeIsolated { relaunchesAfterUpdate }
    }
}
