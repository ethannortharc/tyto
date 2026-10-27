// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tyto",
    // 本机语音识别（SpeechAnalyzer）和代码里直接调用的本机翻译要 macOS 26
    platforms: [.macOS("26.0")],
    dependencies: [
        // 提词器：Markdown 转 HTML（苹果维护，底下是 cmark-gfm，支持表格、任务列表、删除线）
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
    ],
    targets: [
        // 正式 app：悬浮窗字幕、翻译、回复建议
        .executableTarget(name: "Tyto", dependencies: [.product(name: "Markdown", package: "swift-markdown")],
                          path: "Sources/Tyto"),
        // 验证程序：共享屏幕时悬浮窗会不会被对方看到
        .executableTarget(name: "ShareCheck", path: "Sources/ShareCheck"),
    ]
)
