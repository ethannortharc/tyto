import AppKit
import ServiceManagement

/// 装到「应用程序」、开机自动打开。
@MainActor
enum Installer {
    // MARK: - 移到「应用程序」

    /// 从下载文件夹、磁盘映像里直接打开时，问一句要不要移到「应用程序」：放在那里才能自动更新，开机打开也稳。
    /// 自己编译的（build/、dist/ 里的）不问；说过"不用了"就不再问。
    static func offerMoveToApplications() {
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let path = bundle.path
        guard bundle.pathExtension == "app", !isInApplications(path), !isDevBuild(path),
              !UserDefaults.standard.bool(forKey: declinedKey)
        else { return }

        let alert = NSAlert()
        alert.messageText = tr("把 Tyto 移到「应用程序」文件夹？", "Move Tyto to your Applications folder?")
        alert.informativeText = tr("放在「应用程序」里才能自动更新，开机自动打开也更可靠。移过去以后会从那里重新打开。",
                                   "Tyto can update itself and open at login reliably only from Applications. It will reopen from there.")
        alert.addButton(withTitle: tr("移过去", "Move to Applications"))
        alert.addButton(withTitle: tr("不用了", "Not Now"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = tr("不再提醒", "Don't ask again")
        NSApp.activate()
        let answer = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: declinedKey) }
        guard answer == .alertFirstButtonReturn else { return }

        let destination = URL(filePath: "/Applications").appending(path: bundle.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: bundle, to: destination)
        } catch {
            let failed = NSAlert()
            failed.messageText = tr("移不过去", "Couldn't move Tyto")
            failed.informativeText = tr("\(error.localizedDescription)\n可以手动把 Tyto 拖进「应用程序」文件夹。",
                                        "\(error.localizedDescription)\nYou can drag Tyto into the Applications folder yourself.")
            failed.runModal()
            return
        }
        // 原来那份：在可写的位置（下载文件夹）就扔进废纸篓；从磁盘映像或系统隔离的临时位置打开的删不了，留着
        if !path.contains("/AppTranslocation/"), FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) {
            try? FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
        }
        relaunch(at: destination)
    }

    private static let declinedKey = "declinedMoveToApplications"

    static func isInApplications(_ path: String) -> Bool {
        path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// 自己编译、打包时生成的那几份
    static func isDevBuild(_ path: String) -> Bool {
        ["/build/", "/.build/", "/dist/", "/DerivedData/"].contains { path.contains($0) }
    }

    /// 等这个进程退出后再打开新位置的那份（同一个 App 不能同时开两个）
    private static func relaunch(at url: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$1\""
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script, "sh", url.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: - 开机自动打开

    static var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// 系统要你在「登录项」里点一下同意
    static var loginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setOpensAtLogin(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
