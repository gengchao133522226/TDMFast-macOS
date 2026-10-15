import Foundation
import Combine
import UserNotifications

@MainActor
public class DownloadManager: ObservableObject {
    public static let shared = DownloadManager()

    @Published public var tasks: [DownloadTask] = []
    @Published public var selectedTaskId: String?
    @Published public var selectedCategory: TaskCategory = .all
    @Published public var settings: AppSettings = .load()
    @Published public var pendingCaptureTask: DownloadTask?
    @Published public var showNewDownloadSheet: Bool = false

    private var activeHttpDownloaders: [String: ChunkDownloader] = [:]
    private var activeYtDlpProcesses: [String: Process] = [:]

    private var tasksFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TDMFast", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("tasks.json")
    }

    public init() {
        loadTasks()
        setupSniffer()
        requestNotificationPermission()
    }

    private func setupSniffer() {
        SnifferServer.shared.onCaptureReceived = { [weak self] payload in
            self?.handleIncomingCapture(payload)
        }
        SnifferServer.shared.start()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func handleIncomingCapture(_ payload: [String: Any]) {
        let rawItems = (payload["items"] as? [[String: Any]]) ?? [payload]
        for it in rawItems {
            guard let url = it["url"] as? String, !url.isEmpty else { continue }
            let filename = (it["filename"] as? String) ?? ""
            let normalizedUrl = YtDlpService.shared.normalizeUrl(url)
            let isVideo = YtDlpService.shared.isVideoSite(url: normalizedUrl)

            let task = DownloadTask(
                url: normalizedUrl,
                filename: filename,
                destinationDir: settings.defaultDir,
                connections: settings.defaultConnections,
                kind: isVideo ? "ytdlp" : "http"
            )

            pendingCaptureTask = task
            showNewDownloadSheet = true
            break
        }
    }

    public func addTask(_ task: DownloadTask, startImmediately: Bool = true) {
        var newTask = task
        if newTask.filename.isEmpty {
            newTask.filename = URL(string: newTask.url)?.lastPathComponent ?? "download"
        }
        tasks.insert(newTask, at: 0)
        saveTasks()

        if startImmediately {
            startTask(id: newTask.id)
        }
    }

    public func startTask(id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .probing
        tasks[index].errorMessage = nil
        saveTasks()

        let task = tasks[index]
        if task.kind == "ytdlp" {
            startYtDlpTask(task: task)
        } else {
            startHttpTask(task: task)
        }
    }

    private func startHttpTask(task: DownloadTask) {
        Task {
            do {
                guard let url = URL(string: task.url) else {
                    throw URLError(.badURL)
                }

                let probe = try await ChunkDownloader.probe(
                    url: url,
                    customHeaders: task.customHeaders,
                    proxyConfiguration: settings
                )

                if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    if self.tasks[idx].filename == "download" || self.tasks[idx].filename.isEmpty {
                        self.tasks[idx].filename = probe.filename
                    }
                    self.tasks[idx].totalBytes = probe.totalBytes
                    self.tasks[idx].status = .downloading
                    self.saveTasks()
                }

                let downloader = ChunkDownloader(taskId: task.id, proxyConfiguration: settings)
                self.activeHttpDownloaders[task.id] = downloader

                let destPath = (task.destinationDir as NSString).appendingPathComponent(
                    tasks.first(where: { $0.id == task.id })?.filename ?? task.filename
                )

                try await downloader.download(
                    url: probe.finalURL,
                    destinationPath: destPath,
                    totalBytes: probe.totalBytes,
                    connections: task.connections,
                    customHeaders: task.customHeaders
                ) { [weak self] downloaded, speed, eta, segmentProgress in
                    Task { @MainActor [weak self] in
                        guard let self = self, let idx = self.tasks.firstIndex(where: { $0.id == task.id }) else { return }
                        self.tasks[idx].downloadedBytes = downloaded
                        self.tasks[idx].speed = speed
                        self.tasks[idx].etaSeconds = eta
                        self.tasks[idx].segmentProgress = segmentProgress
                    }
                }

                if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[idx].status = .completed
                    self.tasks[idx].speed = 0
                    self.tasks[idx].etaSeconds = 0
                    self.tasks[idx].segmentProgress = nil
                    self.tasks[idx].completedAt = Date()
                    self.saveTasks()
                    self.notifyTaskCompleted(filename: self.tasks[idx].filename)
                }
            } catch {
                if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[idx].status = .failed
                    self.tasks[idx].speed = 0
                    self.tasks[idx].errorMessage = error.localizedDescription
                    self.saveTasks()
                }
            }
            self.activeHttpDownloaders.removeValue(forKey: task.id)
        }
    }

    private func startYtDlpTask(task: DownloadTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].status = .downloading
            saveTasks()
        }

        let process = YtDlpService.shared.runDownload(
            task: task,
            settings: settings,
            progressHandler: { [weak self] downloaded, total, speed, eta, actualFilename in
                Task { @MainActor [weak self] in
                    guard let self = self, let idx = self.tasks.firstIndex(where: { $0.id == task.id }) else { return }
                    if total > 0 { self.tasks[idx].totalBytes = total }
                    self.tasks[idx].downloadedBytes = downloaded
                    self.tasks[idx].speed = speed
                    self.tasks[idx].etaSeconds = eta
                    if let af = actualFilename, !af.isEmpty {
                        self.tasks[idx].filename = (af as NSString).lastPathComponent
                    }
                }
            },
            terminationHandler: { [weak self] success, errMsg in
                Task { @MainActor [weak self] in
                    guard let self = self, let idx = self.tasks.firstIndex(where: { $0.id == task.id }) else { return }
                    if success {
                        self.tasks[idx].status = .completed
                        self.tasks[idx].completedAt = Date()
                        self.notifyTaskCompleted(filename: self.tasks[idx].filename)
                    } else {
                        self.tasks[idx].status = .failed
                        self.tasks[idx].errorMessage = errMsg ?? "下载遇到错误"
                    }
                    self.tasks[idx].speed = 0
                    self.saveTasks()
                    self.activeYtDlpProcesses.removeValue(forKey: task.id)
                }
            }
        )

        if let proc = process {
            activeYtDlpProcesses[task.id] = proc
        }
    }

    public func pauseTask(id: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .paused
        tasks[index].speed = 0

        if let downloader = activeHttpDownloaders[id] {
            Task { await downloader.pause() }
            activeHttpDownloaders.removeValue(forKey: id)
        }

        if let process = activeYtDlpProcesses[id] {
            process.terminate()
            activeYtDlpProcesses.removeValue(forKey: id)
        }

        saveTasks()
    }

    public func resumeTask(id: String) {
        startTask(id: id)
    }

    public func resumeAll() {
        for task in tasks where task.status == .paused || task.status == .failed {
            startTask(id: task.id)
        }
    }

    public func pauseAll() {
        for task in tasks where task.status == .downloading || task.status == .probing {
            pauseTask(id: task.id)
        }
    }

    public func deleteTask(id: String, deleteFile: Bool = false) {
        pauseTask(id: id)
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            let task = tasks[idx]
            if deleteFile {
                try? FileManager.default.removeItem(atPath: task.destinationPath)
            }
            tasks.remove(at: idx)
            saveTasks()
        }
    }

    public func clearAll(deleteFiles: Bool = false) {
        pauseAll()
        if deleteFiles {
            for t in tasks {
                try? FileManager.default.removeItem(atPath: t.destinationPath)
            }
        }
        tasks.removeAll()
        saveTasks()
    }

    private func notifyTaskCompleted(filename: String) {
        let content = UNMutableNotificationContent()
        content.title = "下载已完成"
        content.body = filename
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func loadTasks() {
        guard let data = try? Data(contentsOf: tasksFileURL),
              let loaded = try? JSONDecoder().decode([DownloadTask].self, from: data) else {
            return
        }
        self.tasks = loaded.map {
            var t = $0
            if t.status == .downloading || t.status == .probing {
                t.status = .paused
                t.speed = 0
            }
            return t
        }
    }

    private func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            try? data.write(to: tasksFileURL)
        }
    }
}
