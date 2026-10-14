import SwiftUI
import AppKit

public struct MainWindowView: View {
    @StateObject private var manager = DownloadManager.shared
    @State private var showSettings = false

    public var body: some View {
        NavigationSplitView {
            SidebarView(manager: manager)
        } detail: {
            TaskListView(manager: manager)
        }
        .navigationTitle("TDM Fast for Mac")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    manager.showNewDownloadSheet = true
                } label: {
                    Label("新建下载", systemImage: "plus")
                }
                .help("新建下载任务 (Cmd+N)")
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    manager.resumeAll()
                } label: {
                    Label("全部开始", systemImage: "play.fill")
                }
                .help("恢复所有已暂停任务")

                Button {
                    manager.pauseAll()
                } label: {
                    Label("全部暂停", systemImage: "pause.fill")
                }
                .help("暂停全部下载任务")

                Divider()

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: manager.settings.defaultDir))
                } label: {
                    Label("打开下载文件夹", systemImage: "folder")
                }
                .help("在访达中打开下载目录")

                Button {
                    showSettings = true
                } label: {
                    Label("偏好设置", systemImage: "gearshape")
                }
                .help("偏好设置 (Cmd+,)")
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .sheet(isPresented: $manager.showNewDownloadSheet) {
            NewDownloadSheet(manager: manager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(manager: manager)
        }
    }
}
