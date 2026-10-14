import SwiftUI
import AppKit

public struct MenuBarView: View {
    @ObservedObject var manager: DownloadManager

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TDM Fast")
                    .font(.headline)
                Spacer()
                if activeSpeed > 0 {
                    Text(formatSpeed(activeSpeed))
                        .font(.subheadline.bold())
                        .foregroundStyle(.blue)
                }
            }

            Divider()

            let downloading = manager.tasks.filter { $0.status == .downloading || $0.status == .probing }
            if downloading.isEmpty {
                Text("暂无下载中的任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(downloading.prefix(5)) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.filename)
                            .font(.caption.bold())
                            .lineLimit(1)
                        HStack {
                            ProgressView(value: task.progress)
                                .scaleEffect(y: 0.6)
                            Text("\(Int(task.progress * 100))%")
                                .font(.caption2)
                        }
                    }
                }
            }

            Divider()

            Button("新建下载...") {
                manager.showNewDownloadSheet = true
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("全部开始") {
                manager.resumeAll()
            }

            Button("全部暂停") {
                manager.pauseAll()
            }

            Divider()

            Button("退出 TDM Fast") {
                NSApp.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 260)
    }

    private var activeSpeed: Int64 {
        manager.tasks.reduce(0) { $0 + ($1.status == .downloading ? $1.speed : 0) }
    }

    private func formatSpeed(_ bytesPerSec: Int64) -> String {
        let formatted = ByteCountFormatter.string(fromByteCount: bytesPerSec, countStyle: .file)
        return "\(formatted)/s"
    }
}
