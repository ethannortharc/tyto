// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tyto",
    // 本机语音识别（SpeechAnalyzer）和代码里直接调用的本机翻译要 macOS 26
    platforms: [.macOS("26.0")],
    targets: [
        // 正式 app：悬浮窗字幕、翻译、回复建议
        .executableTarget(name: "Tyto", path: "Sources/Tyto"),
        // 验证程序：共享屏幕时悬浮窗会不会被对方看到
        .executableTarget(name: "ShareCheck", path: "Sources/ShareCheck"),
    ]
)
