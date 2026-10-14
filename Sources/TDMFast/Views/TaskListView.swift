import SwiftUI

public struct TaskListView: View {
    @ObservedObject var manager: DownloadManager
    @State private var searchText = ""

    public var body: some View {
        VStack(spacing: 0) {
            if filteredTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text(emptyMessage)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Button("新建下载任务") {
                        manager.showNewDownloadSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $manager.selectedTaskId) {
                    ForEach(filteredTasks) { task in
                        TaskRowView(task: task, manager: manager)
                            .tag(task.id)
                            .contextMenu {
                                Button("复制下载链接") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(task.url, forType: .string)
                                }
                                Button("在访达中显示") {
                                    NSWorkspace.shared.selectFile(task.destinationPath, inFileViewerRootedAtPath: task.destinationDir)
                                }
                                Divider()
                                if task.status == .downloading || task.status == .probing {
                                    Button("暂停任务") { manager.pauseTask(id: task.id) }
                                } else {
                                    Button("继续任务") { manager.resumeTask(id: task.id) }
                                }
                                Divider()
                                Button("从列表删除") {
                                    manager.deleteTask(id: task.id, deleteFile: false)
                                }
                                Button("删除任务及源文件", role: .destructive) {
                                    manager.deleteTask(id: task.id, deleteFile: true)
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: "搜索已下载或正在下载的任务...")
    }

    private var filteredTasks: [DownloadTask] {
        var result = manager.tasks
        switch manager.selectedCategory {
        case .all: break
        case .downloading:
            result = result.filter { $0.status == .downloading || $0.status == .probing }
        case .completed:
            result = result.filter { $0.status == .completed }
        default:
            result = result.filter { $0.category == manager.selectedCategory }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.filename.localizedCaseInsensitiveContains(searchText) ||
                $0.url.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var emptyMessage: String {
        switch manager.selectedCategory {
        case .all: return "暂无任何下载任务"
        case .downloading: return "当前没有正在下载的任务"
        case .completed: return "没有已完成的任务"
        default: return "该分类下暂无文件"
        }
    }
}
