// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tyto",
    platforms: [.macOS(.v14)],
    targets: [
        // 验证程序：共享屏幕时悬浮窗会不会被对方看到
        .executableTarget(name: "ShareCheck", path: "Sources/ShareCheck"),
    ]
)
