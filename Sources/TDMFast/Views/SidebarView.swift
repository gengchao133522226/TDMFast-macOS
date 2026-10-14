import SwiftUI

public struct SidebarView: View {
    @ObservedObject var manager: DownloadManager

    public var body: some View {
        List(selection: $manager.selectedCategory) {
            Section("下载任务") {
                ForEach([TaskCategory.all, TaskCategory.downloading, TaskCategory.completed], id: \.self) { cat in
                    NavigationLink(value: cat) {
                        Label {
                            HStack {
                                Text(cat.rawValue)
                                Spacer()
                                Text("\(count(for: cat))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: cat.iconName)
                                .foregroundColor(color(for: cat))
                        }
                    }
                }
            }

            Section("分类过滤") {
                ForEach([TaskCategory.video, TaskCategory.archive, TaskCategory.document, TaskCategory.music, TaskCategory.other], id: \.self) { cat in
                    NavigationLink(value: cat) {
                        Label {
                            HStack {
                                Text(cat.rawValue)
                                Spacer()
                                Text("\(count(for: cat))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: cat.iconName)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }

    private func count(for cat: TaskCategory) -> Int {
        switch cat {
        case .all: return manager.tasks.count
        case .downloading: return manager.tasks.filter { $0.status == .downloading || $0.status == .probing }.count
        case .completed: return manager.tasks.filter { $0.status == .completed }.count
        default: return manager.tasks.filter { $0.category == cat }.count
        }
    }

    private func color(for cat: TaskCategory) -> Color {
        switch cat {
        case .downloading: return .blue
        case .completed: return .green
        default: return .primary
        }
    }
}
