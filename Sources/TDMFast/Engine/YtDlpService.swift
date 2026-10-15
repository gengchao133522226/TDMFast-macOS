import Foundation

public class YtDlpService {
    public static let shared = YtDlpService()

    private let videoHostRegex = try! NSRegularExpression(
        pattern: #"(^|\.)(youtube\.com|youtu\.be|twitter\.com|x\.com|reddit\.com|redd\.it|tiktok\.com|vimeo\.com|bilibili\.com|facebook\.com|instagram\.com|twitch\.tv|dailymotion\.com|nicovideo\.jp|weibo\.com|douyin\.com)$"#,
        options: .caseInsensitive
    )

    public func isVideoSite(url: String) -> Bool {
        guard let host = URL(string: url)?.host else { return false }
        let range = NSRange(location: 0, length: host.utf16.count)
        return videoHostRegex.firstMatch(in: host, options: [], range: range) != nil
    }

    public func normalizeUrl(_ rawUrl: String) -> String {
        var s = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return s }
        if s.hasPrefix("magnet:") { return s }
        if !s.contains("://") {
            if s.hasPrefix("//") {
                s = "https:" + s
            } else {
                s = "https://" + s
            }
        }
        return s
    }

    public func resolveYtDlpPath(customPath: String = "") -> String? {
        if !customPath.isEmpty && FileManager.default.isExecutableFile(atPath: customPath) {
            return customPath
        }

        let candidates = [
            Bundle.main.resourcePath.map { ($0 as NSString).appendingPathComponent("bin/yt-dlp") },
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    public func resolveFfmpegDir(customPath: String = "") -> String? {
        if !customPath.isEmpty && FileManager.default.fileExists(atPath: customPath) {
            return (customPath as NSString).deletingLastPathComponent
        }

        let candidates = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            Bundle.main.resourcePath.map { ($0 as NSString).appendingPathComponent("bin") }
        ].compactMap { $0 }

        for dir in candidates {
            let ffmpeg = (dir as NSString).appendingPathComponent("ffmpeg")
            if FileManager.default.isExecutableFile(atPath: ffmpeg) {
                return dir
            }
        }
        return nil
    }

    public func fetchMetadata(url: String, settings: AppSettings) async throws -> VideoMetadata {
        guard let binary = resolveYtDlpPath(customPath: settings.ytDlpCustomPath) else {
            throw NSError(domain: "TDMFast", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到 yt-dlp 可执行文件。请通过 Homebrew 安装 (brew install yt-dlp) 或在设置中指定路径。"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        var args = ["-J", "--flat-playlist", "--no-warnings", url]

        if let proxyURL = ProxyHelper.resolveProxyUrl(userSettings: settings) {
            args.append(contentsOf: ["--proxy", proxyURL])
        }

        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "TDMFast", code: 500, userInfo: [NSLocalizedDescriptionKey: "解析视频信息失败。"])
        }

        let title = (json["title"] as? String) ?? "Video"
        let thumbnail = json["thumbnail"] as? String
        let duration = json["duration"] as? Double

        var formats: [VideoFormatInfo] = []
        if let rawFormats = json["formats"] as? [[String: Any]] {
            for rf in rawFormats {
                let fid = (rf["format_id"] as? String) ?? ""
                let ext = (rf["ext"] as? String) ?? "mp4"
                let res = (rf["resolution"] as? String) ?? (rf["format_note"] as? String ?? "")
                let size = (rf["filesize"] as? Int64) ?? (rf["filesize_approx"] as? Int64)
                let note = rf["format_note"] as? String
                let vcodec = rf["vcodec"] as? String
                let acodec = rf["acodec"] as? String
                let hasVideo = vcodec != nil && vcodec != "none"
                let hasAudio = acodec != nil && acodec != "none"

                if !fid.isEmpty {
                    formats.append(VideoFormatInfo(
                        formatId: fid,
                        ext: ext,
                        resolution: res,
                        filesize: size,
                        note: note,
                        hasVideo: hasVideo,
                        hasAudio: hasAudio
                    ))
                }
            }
        }

        return VideoMetadata(
            title: title,
            url: url,
            thumbnail: thumbnail,
            duration: duration,
            formats: formats
        )
    }

    public func runDownload(
        task: DownloadTask,
        settings: AppSettings,
        progressHandler: @escaping (Int64, Int64, Int64, Int64, String?) -> Void,
        terminationHandler: @escaping (Bool, String?) -> Void
    ) -> Process? {
        guard let binary = resolveYtDlpPath(customPath: settings.ytDlpCustomPath) else {
            terminationHandler(false, "未找到 yt-dlp 二进制文件")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)

        var args = [
            "--newline",
            "--progress-template", "%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.speed)s|%(progress.eta)s|%(progress.filename)s",
            "-o", (task.destinationDir as NSString).appendingPathComponent("%(title)s.%(ext)s")
        ]

        if let ffmpegDir = resolveFfmpegDir(customPath: settings.ffmpegCustomPath) {
            args.append(contentsOf: ["--ffmpeg-location", ffmpegDir])
            args.append(contentsOf: ["--merge-output-format", "mp4"])
        }

        if let selector = task.formatSelector, !selector.isEmpty {
            args.append(contentsOf: ["-f", selector])
        } else {
            args.append(contentsOf: ["-f", "bestvideo+bestaudio/best"])
        }

        if let proxyURL = ProxyHelper.resolveProxyUrl(userSettings: settings) {
            args.append(contentsOf: ["--proxy", proxyURL])
        }

        let fragments = min(max(task.connections, 4), 16)
        args.append(contentsOf: [
            "--continue",
            "--part",
            "--concurrent-fragments", "\(fragments)",
            "--retries", "20",
            "--fragment-retries", "20",
            "--socket-timeout", "30",
            "--buffer-size", "1024k",
            "--http-chunk-size", "10M"
        ])

        args.append(task.url)
        process.arguments = args

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.split(separator: "|")
                if parts.count >= 4 {
                    let downloaded = Int64(parts[0]) ?? 0
                    let total = Int64(parts[1]) ?? 0
                    let speed = Int64(Double(parts[2]) ?? 0)
                    let eta = Int64(parts[3]) ?? 0
                    let actualFilename = parts.count >= 5 ? String(parts[4]) : nil
                    progressHandler(downloaded, total, speed, eta, actualFilename)
                }
            }
        }

        process.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let success = p.terminationStatus == 0
            var errMsg: String? = nil
            if !success {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            terminationHandler(success, errMsg)
        }

        do {
            try process.run()
            return process
        } catch {
            terminationHandler(false, error.localizedDescription)
            return nil
        }
    }
}
