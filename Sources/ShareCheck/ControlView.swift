import AppKit
import SwiftUI

/// 对照窗口：普通窗口，不做隐藏。共享屏幕时对方应该看得到它；
/// 如果连它都看不到，说明这次测试本身有问题（共享的不是这块屏幕，或者没权限）。
struct ControlView: View {
    @ObservedObject var model: CheckModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                MarkerSquare()
                VStack(alignment: .leading, spacing: 4) {
                    Text("对照窗口").font(.headline)
                    Text("这个窗口没做隐藏，共享屏幕时对方应该看得到它。")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Toggle("悬浮窗共享保护（sharingType = .none）", isOn: $model.protectOverlay)
            Toggle("悬浮窗点击穿透（打开后鼠标点到它下面的窗口）", isOn: $model.clickThrough)

            HStack {
                Button(model.running ? "自检中…" : "本机自检") {
                    Task { await model.runSelfCheck() }
                }
                .disabled(model.running)
                Button("打开截图文件夹") { model.openOutputFolder() }
                    .disabled(model.lastOutputFolder == nil)
            }

            if !model.note.isEmpty {
                Text(model.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if !model.results.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("截屏方式").bold()
                        Text("结果").bold()
                    }
                    ForEach(model.results) { result in
                        GridRow {
                            Text(result.method)
                            Text(result.verdict).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let listed = model.overlayListed {
                    Text("ScreenCaptureKit 的窗口列表里\(listed ? "有" : "没有")悬浮窗")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(context.date.formatted(.dateTime.hour().minute().second()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity, alignment: .topLeading)
    }
}
