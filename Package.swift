// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tyto",
    // 本机语音识别（SpeechAnalyzer）和代码里直接调用的本机翻译要 macOS 26
    platforms: [.macOS("26.0")],
    dependencies: [
        // 提词器：Markdown 转 HTML（苹果维护，底下是 cmark-gfm，支持表格、任务列表、删除线）
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
        // 自动更新（macOS 上不走 App Store 的 App 的标准做法）：查 GitHub Releases 上的 appcast.xml，EdDSA 验签后替换
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0"),
    ],
    targets: [
        // 正式 app：悬浮窗字幕、翻译、回复建议
        .executableTarget(name: "Tyto",
                          dependencies: [.product(name: "Markdown", package: "swift-markdown"),
                                         .product(name: "Sparkle", package: "Sparkle")],
                          path: "Sources/Tyto",
                          // Sparkle.framework 放在 Tyto.app/Contents/Frameworks 里
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        // 验证程序：共享屏幕时悬浮窗会不会被对方看到
        .executableTarget(name: "ShareCheck", path: "Sources/ShareCheck"),
    ]
)
