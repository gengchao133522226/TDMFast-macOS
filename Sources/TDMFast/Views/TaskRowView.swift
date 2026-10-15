import SwiftUI

public struct TaskRowView: View {
    public let task: DownloadTask
    @ObservedObject var manager: DownloadManager

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: iconForCategory(task.category))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(iconColor(task.status))

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.filename)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        Text(statusDescription)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(statusColor)

                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                            Text(threadDescription)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.12))
                        )
                        .foregroundStyle(.blue)

                        if task.status == .downloading && task.speed > 0 {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(formatSpeed(task.speed))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.blue)

                            if task.etaSeconds > 0 {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("剩余: \(formatETA(task.etaSeconds))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if task.status == .failed, let err = task.errorMessage {
                            Text("(\(err))")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if task.status == .downloading || task.status == .probing {
                        Button {
                            manager.pauseTask(id: task.id)
                        } label: {
                            Image(systemName: "pause.fill")
                        }
                        .buttonStyle(.plain)
                        .help("暂停下载")
                    } else if task.status == .paused || task.status == .failed {
                        Button {
                            manager.resumeTask(id: task.id)
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.plain)
                        .help("恢复下载")
                    }

                    if task.status == .completed {
                        Button {
                            NSWorkspace.shared.selectFile(task.destinationPath, inFileViewerRootedAtPath: task.destinationDir)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                        .help("在访达中显示")
                    }

                    Menu {
                        Button("复制下载链接") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(task.url, forType: .string)
                        }
                        Button("打开所在文件夹") {
                            NSWorkspace.shared.selectFile(task.destinationPath, inFileViewerRootedAtPath: task.destinationDir)
                        }
                        Divider()
                        Button("从列表中删除") {
                            manager.deleteTask(id: task.id, deleteFile: false)
                        }
                        Button("删除任务并移至废纸篓", role: .destructive) {
                            manager.deleteTask(id: task.id, deleteFile: true)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 18)
                }
            }

            if task.status == .downloading || task.status == .probing || task.status == .paused {
                ProgressView(value: task.totalBytes > 0 ? Double(task.downloadedBytes) : 0, total: Double(max(task.totalBytes, 1)))
                    .progressViewStyle(.linear)

                if let segments = task.segmentProgress, segments.count > 1 {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 2) {
                            ForEach(0..<segments.count, id: \.self) { idx in
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(Color(nsColor: .separatorColor).opacity(0.25))
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.cyan, Color.blue],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: geo.size.width * CGFloat(max(0.0, min(1.0, segments[idx]))))
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                        .frame(height: 5)

                        HStack {
                            Text("多线程分段状态 (\(segments.count) 线程并行)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Spacer()
                            let completedCount = segments.filter { $0 >= 0.999 }.count
                            Text("\(completedCount)/\(segments.count) 段就绪")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 1)
                }

                HStack {
                    Text("\(formatBytes(task.downloadedBytes)) / \(task.totalBytes > 0 ? formatBytes(task.totalBytes) : "未知大小")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if task.totalBytes > 0 {
                        Text("\(Int(task.progress * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var threadDescription: String {
        if task.kind == "ytdlp" {
            let frags = min(max(task.connections, 4), 16)
            return "\(frags) 片段并发"
        } else {
            return "\(task.connections) 线程"
        }
    }

    private var statusDescription: String {
        return task.status.rawValue
    }

    private var statusColor: Color {
        switch task.status {
        case .downloading: return .blue
        case .completed: return .green
        case .paused: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }

    private func iconForCategory(_ cat: TaskCategory) -> String {
        return cat.iconName
    }

    private func iconColor(_ status: TaskStatus) -> Color {
        switch status {
        case .completed: return .green
        case .downloading: return .blue
        case .failed: return .red
        case .paused: return .orange
        default: return .secondary
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatSpeed(_ bytesPerSec: Int64) -> String {
        let formatted = ByteCountFormatter.string(fromByteCount: bytesPerSec, countStyle: .file)
        return "\(formatted)/s"
    }

    private func formatETA(_ seconds: Int64) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m >= 60 {
            let h = m / 60
            let remM = m % 60
            return String(format: "%02d:%02d:%02d", h, remM, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
