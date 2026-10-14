import SwiftUI

@main
struct TDMFastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager = DownloadManager.shared

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .frame(minWidth: 800, minHeight: 500)
                .onOpenURL { url in
                    handleCustomScheme(url: url)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新建下载...") {
                    manager.showNewDownloadSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("从剪贴板添加 URL") {
                    if let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       text.hasPrefix("http") {
                        let isVideo = YtDlpService.shared.isVideoSite(url: text)
                        manager.pendingCaptureTask = DownloadTask(
                            url: text,
                            destinationDir: manager.settings.defaultDir,
                            connections: manager.settings.defaultConnections,
                            kind: isVideo ? "ytdlp" : "http"
                        )
                    }
                    manager.showNewDownloadSheet = true
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }

            CommandMenu("任务控制") {
                Button("全部开始") { manager.resumeAll() }
                Button("全部暂停") { manager.pauseAll() }
                Divider()
                Button("清空所有任务") { manager.clearAll(deleteFiles: false) }
            }
        }

        MenuBarExtra("TDM Fast", systemImage: "arrow.down.circle") {
            MenuBarView(manager: manager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(manager: manager)
        }
    }

    private func handleCustomScheme(url: URL) {
        // e.g. tdmfast://capture?url=https%3A%2F%2F... or tdmfast://capture?data=base64
        guard url.scheme == "tdmfast" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let dataBase64 = components?.queryItems?.first(where: { $0.name == "data" })?.value,
           let decodedData = Data(base64Encoded: dataBase64),
           let json = try? JSONSerialization.jsonObject(with: decodedData) as? [String: Any] {
            manager.handleIncomingCapture(json)
            return
        }

        if let rawUrl = components?.queryItems?.first(where: { $0.name == "url" })?.value {
            manager.handleIncomingCapture(["url": rawUrl])
            return
        }
    }
}
