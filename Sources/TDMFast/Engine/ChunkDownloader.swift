import Foundation

public actor ChunkDownloader {
    public struct ProbeResult {
        public let finalURL: URL
        public let totalBytes: Int64
        public let supportsRange: Bool
        public let filename: String
    }

    private let taskId: String
    private var isCancelled = false
    private var isPaused = false
    private var session: URLSession

    public init(taskId: String, proxyConfiguration: AppSettings? = nil) {
        self.taskId = taskId
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 3600.0

        if let p = proxyConfiguration, p.proxyEnabled {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: p.proxyHost,
                kCFNetworkProxiesHTTPPort as String: p.proxyPort,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: p.proxyHost,
                kCFNetworkProxiesHTTPSPort as String: p.proxyPort
            ]
        }
        self.session = URLSession(configuration: config)
    }

    public static func probe(
        url: URL,
        customHeaders: [String: String]? = nil,
        proxyConfiguration: AppSettings? = nil
    ) async throws -> ProbeResult {
        let config = URLSessionConfiguration.default
        if let p = proxyConfiguration, p.proxyEnabled {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: p.proxyHost,
                kCFNetworkProxiesHTTPPort as String: p.proxyPort,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: p.proxyHost,
                kCFNetworkProxiesHTTPSPort as String: p.proxyPort
            ]
        }
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let custom = customHeaders {
            for (k, v) in custom { request.setValue(v, forHTTPHeaderField: k) }
        }

        var (data, response) = try await session.data(for: request)
        guard var httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // If HEAD is rejected with 405 Method Not Allowed or 403, retry with GET Range bytes=0-0
        if httpResponse.statusCode == 405 || httpResponse.statusCode == 403 {
            request.httpMethod = "GET"
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            let (dataRetry, responseRetry) = try await session.data(for: request)
            data = dataRetry
            if let resp = responseRetry as? HTTPURLResponse {
                httpResponse = resp
            }
        }

        let finalURL = httpResponse.url ?? url
        var totalBytes: Int64 = -1
        var supportsRange = false

        if let acceptRanges = httpResponse.value(forHTTPHeaderField: "Accept-Ranges"),
           acceptRanges.lowercased().contains("bytes") {
            supportsRange = true
        }

        if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
            // e.g. "bytes 0-0/1234567"
            supportsRange = true
            if let slashIdx = contentRange.lastIndex(of: "/") {
                let sizeStr = contentRange[contentRange.index(after: slashIdx)...].trimmingCharacters(in: .whitespaces)
                if let size = Int64(sizeStr) {
                    totalBytes = size
                }
            }
        }

        if totalBytes <= 0 {
            if let lengthHeader = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let length = Int64(lengthHeader) {
                totalBytes = length
            }
        }

        // Filename resolution from Content-Disposition
        var filename = ""
        if let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition") {
            if let match = disposition.range(of: "filename\\*?=['\"]?(?:UTF-8'')?([^;'\"]+)", options: .regularExpression) {
                let rawMatch = String(disposition[match])
                if let equalIdx = rawMatch.firstIndex(of: "=") {
                    let extracted = String(rawMatch[rawMatch.index(after: equalIdx)...])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    filename = extracted.removingPercentEncoding ?? extracted
                }
            }
        }

        if filename.isEmpty {
            filename = finalURL.lastPathComponent
            if filename.isEmpty || filename == "/" {
                filename = "download"
            }
        }

        return ProbeResult(
            finalURL: finalURL,
            totalBytes: totalBytes,
            supportsRange: supportsRange,
            filename: filename
        )
    }

    public func download(
        url: URL,
        destinationPath: String,
        totalBytes: Int64,
        connections: Int,
        customHeaders: [String: String]?,
        progressUpdate: @escaping (Int64, Int64, Int64) -> Void // downloadedBytes, speedBytesPerSec, etaSec
    ) async throws {
        isCancelled = false
        isPaused = false

        let destURL = URL(fileURLWithPath: destinationPath)
        let parentDir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let threadCount = (totalBytes > 0 && connections > 1) ? min(connections, 64) : 1

        if !FileManager.default.fileExists(atPath: destinationPath) {
            FileManager.default.createFile(atPath: destinationPath, contents: nil)
            if totalBytes > 0 {
                let fileHandle = try FileHandle(forWritingTo: destURL)
                try fileHandle.truncate(atOffset: UInt64(totalBytes))
                try fileHandle.close()
            }
        }

        if threadCount == 1 || totalBytes <= 0 {
            try await downloadSingleStream(
                url: url,
                destURL: destURL,
                totalBytes: totalBytes,
                customHeaders: customHeaders,
                progressUpdate: progressUpdate
            )
        } else {
            try await downloadMultiChunk(
                url: url,
                destURL: destURL,
                totalBytes: totalBytes,
                threadCount: threadCount,
                customHeaders: customHeaders,
                progressUpdate: progressUpdate
            )
        }
    }

    private func downloadSingleStream(
        url: URL,
        destURL: URL,
        totalBytes: Int64,
        customHeaders: [String: String]?,
        progressUpdate: @escaping (Int64, Int64, Int64) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let custom = customHeaders {
            for (k, v) in custom { request.setValue(v, forHTTPHeaderField: k) }
        }

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let fileHandle = try FileHandle(forWritingTo: destURL)
        defer { try? fileHandle.close() }

        var downloaded: Int64 = 0
        var lastTick = Date()
        var lastDownloaded: Int64 = 0
        var speed: Int64 = 0

        for try await byte in asyncBytes {
            if isPaused || isCancelled { break }
            try fileHandle.write(contentsOf: Data([byte]))
            downloaded += 1

            let now = Date()
            let elapsed = now.timeIntervalSince(lastTick)
            if elapsed >= 0.5 {
                let delta = downloaded - lastDownloaded
                speed = Int64(Double(delta) / elapsed)
                let remaining = totalBytes > downloaded ? (totalBytes - downloaded) : 0
                let eta = speed > 0 ? (remaining / speed) : 0
                progressUpdate(downloaded, speed, eta)
                lastTick = now
                lastDownloaded = downloaded
            }
        }
        progressUpdate(downloaded, 0, 0)
    }

    private func downloadMultiChunk(
        url: URL,
        destURL: URL,
        totalBytes: Int64,
        threadCount: Int,
        customHeaders: [String: String]?,
        progressUpdate: @escaping (Int64, Int64, Int64) -> Void
    ) async throws {
        let chunkSize = Int64(ceil(Double(totalBytes) / Double(threadCount)))
        var segments: [FileSegment] = []

        for i in 0..<threadCount {
            let start = Int64(i) * chunkSize
            let end = min(start + chunkSize - 1, totalBytes - 1)
            segments.append(FileSegment(index: i, startOffset: start, endOffset: end, downloadedBytes: 0))
        }

        let progressTracker = ChunkProgressTracker(totalBytes: totalBytes, progressUpdate: progressUpdate)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for seg in segments {
                group.addTask {
                    try await self.downloadSegment(
                        segment: seg,
                        url: url,
                        destURL: destURL,
                        customHeaders: customHeaders,
                        tracker: progressTracker
                    )
                }
            }
            try await group.waitForAll()
        }
        progressTracker.finish()
    }

    private func downloadSegment(
        segment: FileSegment,
        url: URL,
        destURL: URL,
        customHeaders: [String: String]?,
        tracker: ChunkProgressTracker
    ) async throws {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(segment.currentRangeHeader, forHTTPHeaderField: "Range")
        if let custom = customHeaders {
            for (k, v) in custom { request.setValue(v, forHTTPHeaderField: k) }
        }

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 206 || httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let fileHandle = try FileHandle(forWritingTo: destURL)
        defer { try? fileHandle.close() }

        var currentOffset = segment.startOffset
        var buffer = Data()
        buffer.reserveCapacity(65536)

        for try await byte in asyncBytes {
            if isPaused || isCancelled { break }
            buffer.append(byte)

            if buffer.count >= 65536 {
                try fileHandle.seek(toOffset: UInt64(currentOffset))
                try fileHandle.write(contentsOf: buffer)
                currentOffset += Int64(buffer.count)
                await tracker.addBytes(Int64(buffer.count))
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if !buffer.isEmpty {
            try fileHandle.seek(toOffset: UInt64(currentOffset))
            try fileHandle.write(contentsOf: buffer)
            await tracker.addBytes(Int64(buffer.count))
        }
    }

    public func pause() {
        isPaused = true
    }

    public func cancel() {
        isCancelled = true
        session.invalidateAndCancel()
    }
}

private actor ChunkProgressTracker {
    let totalBytes: Int64
    let progressUpdate: (Int64, Int64, Int64) -> Void
    var totalDownloaded: Int64 = 0
    var lastTick = Date()
    var lastDownloaded: Int64 = 0

    init(totalBytes: Int64, progressUpdate: @escaping (Int64, Int64, Int64) -> Void) {
        self.totalBytes = totalBytes
        self.progressUpdate = progressUpdate
    }

    func addBytes(_ count: Int64) {
        totalDownloaded += count
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        if elapsed >= 0.5 {
            let delta = totalDownloaded - lastDownloaded
            let speed = Int64(Double(delta) / elapsed)
            let remaining = totalBytes > totalDownloaded ? (totalBytes - totalDownloaded) : 0
            let eta = speed > 0 ? (remaining / speed) : 0
            progressUpdate(totalDownloaded, speed, eta)
            lastTick = now
            lastDownloaded = totalDownloaded
        }
    }

    func finish() {
        progressUpdate(totalDownloaded, 0, 0)
    }
}
