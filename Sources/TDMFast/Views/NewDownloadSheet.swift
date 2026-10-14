import SwiftUI
import AppKit

public struct NewDownloadSheet: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    @State private var url: String = ""
    @State private var filename: String = ""
    @State private var saveDirectory: String = ""
    @State private var connections: Int = 8
    @State private var isVideoSite: Bool = false
    @State private var isProbing: Bool = false
    @State private var showQualityPicker: Bool = false
    @State private var videoMetadata: VideoMetadata?
    @State private var errorMessage: String?

    public init(manager: DownloadManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
                Text("新建下载任务")
                    .font(.title2.bold())
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下载链接 URL:")
                        .font(.headline)
                    HStack {
                        TextField("https://...", text: $url)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: url) { newValue in
                                checkUrlType(newValue)
                            }

                        Button("从剪贴板粘贴") {
                            if let paste = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                               paste.hasPrefix("http") {
                                url = paste
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("重命名文件 (可选):")
                        .font(.subheadline)
                    TextField("留空则自动从服务器获取文件名", text: $filename)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("保存至目录:")
                        .font(.subheadline)
                    HStack {
                        TextField("", text: $saveDirectory)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        Button("浏览...") {
                            chooseDirectory()
                        }
                    }
                }

                HStack {
                    Text("下载加速线程数:")
                        .font(.subheadline)
                    Picker("", selection: $connections) {
                        ForEach([1, 2, 4, 8, 16, 32, 64], id: \.self) { c in
                            Text("\(c) 线程").tag(c)
                        }
                    }
                    .frame(width: 120)
                    Spacer()
                }

                if isVideoSite {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.purple)
                        Text("检测到主流流媒体/视频网站链接 (将调用 yt-dlp 进行高效解析)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isVideoSite && manager.settings.askVideoQuality {
                    Button(action: probeVideoQuality) {
                        HStack {
                            if isProbing {
                                ProgressView().scaleEffect(0.6)
                            }
                            Text("解析清晰度...")
                        }
                    }
                    .disabled(url.isEmpty || isProbing)
                }

                Button("稍后下载") {
                    createTask(startImmediately: false)
                }
                .disabled(url.isEmpty)

                Button("立即下载") {
                    createTask(startImmediately: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(url.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540, height: 400)
        .onAppear {
            setupInitialValues()
        }
        .sheet(isPresented: $showQualityPicker) {
            if let meta = videoMetadata {
                VideoQualitySheet(metadata: meta) { selectedFormat in
                    createVideoTask(formatSelector: selectedFormat)
                    showQualityPicker = false
                    dismiss()
                }
            }
        }
    }

    private func setupInitialValues() {
        saveDirectory = manager.settings.defaultDir
        connections = manager.settings.defaultConnections

        if let pending = manager.pendingCaptureTask {
            url = pending.url
            filename = pending.filename
            manager.pendingCaptureTask = nil
        } else if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  clip.hasPrefix("http") {
            url = clip
        }
        checkUrlType(url)
    }

    private func checkUrlType(_ testUrl: String) {
        let norm = YtDlpService.shared.normalizeUrl(testUrl)
        isVideoSite = YtDlpService.shared.isVideoSite(url: norm)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: saveDirectory)
        if panel.runModal() == .OK, let selected = panel.url?.path {
            saveDirectory = selected
        }
    }

    private func createTask(startImmediately: Bool) {
        let normalized = YtDlpService.shared.normalizeUrl(url)
        let isVid = YtDlpService.shared.isVideoSite(url: normalized)

        let task = DownloadTask(
            url: normalized,
            filename: filename.trimmingCharacters(in: .whitespacesAndNewlines),
            destinationDir: saveDirectory,
            connections: connections,
            kind: isVid ? "ytdlp" : "http"
        )

        manager.addTask(task, startImmediately: startImmediately)
        dismiss()
    }

    private func probeVideoQuality() {
        isProbing = true
        errorMessage = nil
        let normalized = YtDlpService.shared.normalizeUrl(url)

        Task {
            do {
                let meta = try await YtDlpService.shared.fetchMetadata(url: normalized, settings: manager.settings)
                await MainActor.run {
                    self.videoMetadata = meta
                    self.isProbing = false
                    self.showQualityPicker = true
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProbing = false
                }
            }
        }
    }

    private func createVideoTask(formatSelector: String) {
        let normalized = YtDlpService.shared.normalizeUrl(url)
        let task = DownloadTask(
            url: normalized,
            filename: filename.trimmingCharacters(in: .whitespacesAndNewlines),
            destinationDir: saveDirectory,
            connections: connections,
            kind: "ytdlp",
            formatSelector: formatSelector
        )
        manager.addTask(task, startImmediately: true)
    }
}
