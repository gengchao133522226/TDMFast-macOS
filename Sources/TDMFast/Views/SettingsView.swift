import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject var manager: DownloadManager
    @State private var settings: AppSettings = .load()
    @State private var activeTab: Int = 0

    public var body: some View {
        TabView(selection: $activeTab) {
            generalTab
                .tabItem {
                    Label("常规", systemImage: "gearshape")
                }
                .tag(0)

            networkTab
                .tabItem {
                    Label("网络与代理", systemImage: "network")
                }
                .tag(1)

            binaryTab
                .tabItem {
                    Label("外部引擎", systemImage: "terminal")
                }
                .tag(2)
        }
        .padding(20)
        .frame(width: 520, height: 380)
        .onAppear {
            settings = manager.settings
        }
    }

    private var generalTab: some View {
        Form {
            Section("下载行为") {
                HStack {
                    Text("默认保存目录:")
                    TextField("", text: $settings.defaultDir)
                        .disabled(true)
                    Button("更改...") {
                        chooseDir()
                    }
                }

                Stepper(value: $settings.maxConcurrent, in: 1...10) {
                    Text("最大同时下载任务数: \(settings.maxConcurrent)")
                }

                Picker("单任务默认线程数:", selection: $settings.defaultConnections) {
                    ForEach([1, 2, 4, 8, 16, 32, 64], id: \.self) { c in
                        Text("\(c) 线程").tag(c)
                    }
                }

                Toggle("下载流媒体前提示选择清晰度", isOn: $settings.askVideoQuality)
            }

            Spacer()

            HStack {
                Spacer()
                Button("保存设置") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var networkTab: some View {
        Form {
            Section("网络代理设置") {
                Toggle("启用下载网络代理", isOn: $settings.proxyEnabled)

                if settings.proxyEnabled {
                    Picker("代理协议:", selection: $settings.proxyType) {
                        Text("HTTP / HTTPS").tag("http")
                        Text("SOCKS5").tag("socks5")
                    }

                    TextField("代理服务器地址:", text: $settings.proxyHost)
                    TextField("代理端口:", value: $settings.proxyPort, format: .number)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("保存设置") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var binaryTab: some View {
        Form {
            Section("视频及混流引擎") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("yt-dlp 可执行文件路径:")
                        .font(.caption.bold())
                    HStack {
                        TextField("默认自动从 /opt/homebrew 或系统 PATH 查找", text: $settings.ytDlpCustomPath)
                        Button("浏览...") {
                            chooseExecutable { settings.ytDlpCustomPath = $0 }
                        }
                    }
                    if let detected = YtDlpService.shared.resolveYtDlpPath(customPath: settings.ytDlpCustomPath) {
                        Text("当前使用: \(detected)")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Text("⚠️ 未检测到 yt-dlp，可通过 'brew install yt-dlp' 安装")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("ffmpeg 目录/二进制路径:")
                        .font(.caption.bold())
                    HStack {
                        TextField("默认自动查找", text: $settings.ffmpegCustomPath)
                        Button("浏览...") {
                            chooseExecutable { settings.ffmpegCustomPath = $0 }
                        }
                    }
                    if let detectedDir = YtDlpService.shared.resolveFfmpegDir(customPath: settings.ffmpegCustomPath) {
                        Text("当前使用目录: \(detectedDir)")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Text("⚠️ 未检测到 ffmpeg，音视频混流功能将受限")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("保存设置") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let p = panel.url?.path {
            settings.defaultDir = p
        }
    }

    private func chooseExecutable(completion: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let p = panel.url?.path {
            completion(p)
        }
    }

    private func save() {
        settings.save()
        manager.settings = settings
    }
}
