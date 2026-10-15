import Foundation
import Darwin

/// High-performance chunk downloader with breakpoint resume (断点续传),
/// auto-reconnection on network drops/timeouts, and POSIX atomic pwrite.
public actor ChunkDownloader {
    public struct ProbeResult {
        public let finalURL: URL
        public let totalBytes: Int64
        public let supportsRange: Bool
        public let filename: String
    }

    private let taskId: String
    private let proxyConfiguration: AppSettings?
    private var isCancelled = false
    private var isPaused = false
    private var activeSessions: [URLSession] = []
    private var tracker: ChunkProgressTracker?

    public init(taskId: String, proxyConfiguration: AppSettings? = nil) {
        self.taskId = taskId
        self.proxyConfiguration = proxyConfiguration
    }

    public static func probe(
        url: URL,
        customHeaders: [String: String]? = nil,
        proxyConfiguration: AppSettings? = nil
    ) async throws -> ProbeResult {
        let config = URLSessionConfiguration.default
        ProxyHelper.apply(to: config, userSettings: proxyConfiguration)
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let custom = customHeaders {
            for (k, v) in custom { request.setValue(v, forHTTPHeaderField: k) }
        }

        let (_, response) = try await session.data(for: request)
        guard var httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Fallback for servers rejecting HEAD (405 or 403)
        if httpResponse.statusCode == 405 || httpResponse.statusCode == 403 {
            request.httpMethod = "GET"
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            let (_, responseRetry) = try await session.data(for: request)
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
        existingSegments: [FileSegment]? = nil,
        progressUpdate: @escaping (Int64, Int64, Int64, [Double]) -> Void,
        segmentPersistence: @escaping ([FileSegment]) -> Void
    ) async throws {
        isCancelled = false
        isPaused = false
        activeSessions.removeAll()

        let destURL = URL(fileURLWithPath: destinationPath)
        let parentDir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let fileExists = FileManager.default.fileExists(atPath: destinationPath)
        let fd = open(destinationPath, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else {
            throw NSError(domain: "TDMFast", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "无法创建或写入目标文件"])
        }
        defer { close(fd) }

        // Only allocate file space on first creation so existing downloaded data is preserved
        if !fileExists && totalBytes > 0 {
            ftruncate(fd, off_t(totalBytes))
        }

        let threadCount = (totalBytes > 1024 * 1024 && connections > 1) ? min(connections, 32) : 1

        if threadCount == 1 || totalBytes <= 0 {
            try await downloadSingleStream(
                url: url,
                fd: fd,
                totalBytes: totalBytes,
                customHeaders: customHeaders,
                initialDownloaded: existingSegments?.first?.downloadedBytes ?? 0,
                progressUpdate: progressUpdate,
                segmentPersistence: segmentPersistence
            )
        } else {
            try await downloadMultiChunk(
                url: url,
                fd: fd,
                totalBytes: totalBytes,
                threadCount: threadCount,
                customHeaders: customHeaders,
                existingSegments: existingSegments,
                progressUpdate: progressUpdate,
                segmentPersistence: segmentPersistence
            )
        }
    }

    private func downloadSingleStream(
        url: URL,
        fd: Int32,
        totalBytes: Int64,
        customHeaders: [String: String]?,
        initialDownloaded: Int64,
        progressUpdate: @escaping (Int64, Int64, Int64, [Double]) -> Void,
        segmentPersistence: @escaping ([FileSegment]) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let custom = customHeaders {
            for (k, v) in custom { request.setValue(v, forHTTPHeaderField: k) }
        }

        var startOffset: Int64 = 0
        if initialDownloaded > 0 && totalBytes > 0 && initialDownloaded < totalBytes {
            startOffset = initialDownloaded
            request.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range")
        }

        let singleSegment = [FileSegment(index: 0, startOffset: 0, endOffset: totalBytes > 0 ? totalBytes - 1 : 0, downloadedBytes: startOffset)]
        let progressTracker = ChunkProgressTracker(
            totalBytes: totalBytes,
            segments: singleSegment,
            progressUpdate: progressUpdate,
            segmentPersistence: segmentPersistence
        )
        self.tracker = progressTracker

        var attempt = 0
        let maxRetries = 10
        var currentOffset = startOffset

        while attempt <= maxRetries {
            if isPaused || isCancelled { return }

            let config = URLSessionConfiguration.ephemeral
            ProxyHelper.apply(to: config, userSettings: self.proxyConfiguration)
            let delegate = SegmentDataDelegate()
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            self.activeSessions = [session]

            if currentOffset > 0 && totalBytes > 0 {
                request.setValue("bytes=\(currentOffset)-", forHTTPHeaderField: "Range")
            }

            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    delegate.onData = { data in
                        let count = data.count
                        guard count > 0 else { return }
                        data.withUnsafeBytes { raw in
                            if let ptr = raw.baseAddress {
                                pwrite(fd, ptr, count, off_t(currentOffset))
                            }
                        }
                        currentOffset += Int64(count)
                        Task {
                            await progressTracker.updateSegment(
                                index: 0,
                                downloaded: currentOffset,
                                total: max(totalBytes, currentOffset),
                                deltaBytes: Int64(count)
                            )
                        }
                    }

                    delegate.onCompletion = { error in
                        session.finishTasksAndInvalidate()
                        if let err = error {
                            continuation.resume(throwing: err)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }

                    let task = session.dataTask(with: request)
                    task.resume()
                }
                await progressTracker.finish()
                return
            } catch {
                session.invalidateAndCancel()
                attempt += 1
                if attempt > maxRetries || isPaused || isCancelled {
                    await progressTracker.flush()
                    throw error
                }
                let delay = min(5, attempt)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func downloadMultiChunk(
        url: URL,
        fd: Int32,
        totalBytes: Int64,
        threadCount: Int,
        customHeaders: [String: String]?,
        existingSegments: [FileSegment]?,
        progressUpdate: @escaping (Int64, Int64, Int64, [Double]) -> Void,
        segmentPersistence: @escaping ([FileSegment]) -> Void
    ) async throws {
        var segments: [FileSegment] = []

        // If existing segments match the configuration and totalBytes, resume from them
        if let existing = existingSegments, existing.count == threadCount,
           existing.map({ $0.endOffset - $0.startOffset + 1 }).reduce(0, +) == totalBytes {
            segments = existing
        } else {
            let chunkSize = Int64(ceil(Double(totalBytes) / Double(threadCount)))
            for i in 0..<threadCount {
                let start = Int64(i) * chunkSize
                let end = min(start + chunkSize - 1, totalBytes - 1)
                segments.append(FileSegment(index: i, startOffset: start, endOffset: end, downloadedBytes: 0))
            }
        }

        let progressTracker = ChunkProgressTracker(
            totalBytes: totalBytes,
            segments: segments,
            progressUpdate: progressUpdate,
            segmentPersistence: segmentPersistence
        )
        self.tracker = progressTracker

        try await withThrowingTaskGroup(of: Void.self) { group in
            for seg in segments {
                // If this segment is already completely downloaded, skip downloading!
                if seg.isCompleted {
                    continue
                }

                group.addTask {
                    try await self.downloadSegmentWithRetry(
                        segment: seg,
                        url: url,
                        fd: fd,
                        customHeaders: customHeaders,
                        tracker: progressTracker,
                        maxRetries: 10
                    )
                }
            }
            try await group.waitForAll()
        }

        await progressTracker.finish()
    }

    private func downloadSegmentWithRetry(
        segment: FileSegment,
        url: URL,
        fd: Int32,
        customHeaders: [String: String]?,
        tracker: ChunkProgressTracker,
        maxRetries: Int = 10
    ) async throws {
        if segment.isCompleted { return }

        var attempt = 0
        var currentDownloaded = segment.downloadedBytes

        while attempt <= maxRetries {
            if isPaused || isCancelled { return }
            do {
                try await downloadSegment(
                    segment: segment,
                    startFrom: currentDownloaded,
                    url: url,
                    fd: fd,
                    customHeaders: customHeaders,
                    tracker: tracker,
                    onBytesReceived: { bytes in
                        currentDownloaded += bytes
                    }
                )
                return
            } catch {
                attempt += 1
                if attempt > maxRetries || isPaused || isCancelled {
                    await tracker.flush()
                    throw error
                }
                // Exponential backoff before retry (1s, 2s, 3s, max 5s)
                let delay = min(5, attempt)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func downloadSegment(
        segment: FileSegment,
        startFrom: Int64,
        url: URL,
        fd: Int32,
        customHeaders: [String: String]?,
        tracker: ChunkProgressTracker,
        onBytesReceived: @escaping (Int64) -> Void
    ) async throws {
        if isPaused || isCancelled { return }

        let segmentStart = segment.startOffset + startFrom
        if segmentStart > segment.endOffset { return }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=\(segmentStart)-\(segment.endOffset)", forHTTPHeaderField: "Range")
        if let custom = customHeaders {
            for (k, v) in custom { request.setValue(v, forHTTPHeaderField: k) }
        }

        let totalSegmentLength = segment.endOffset - segment.startOffset + 1
        let config = URLSessionConfiguration.ephemeral
        ProxyHelper.apply(to: config, userSettings: self.proxyConfiguration)

        let delegate = SegmentDataDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.activeSessions.append(session)
        defer { session.finishTasksAndInvalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var currentOffset = segmentStart
            var currentSegmentDownloaded = startFrom

            delegate.onData = { data in
                let count = data.count
                guard count > 0 else { return }

                data.withUnsafeBytes { raw in
                    if let ptr = raw.baseAddress {
                        pwrite(fd, ptr, count, off_t(currentOffset))
                    }
                }
                currentOffset += Int64(count)
                currentSegmentDownloaded += Int64(count)
                onBytesReceived(Int64(count))

                Task {
                    await tracker.updateSegment(
                        index: segment.index,
                        downloaded: currentSegmentDownloaded,
                        total: totalSegmentLength,
                        deltaBytes: Int64(count)
                    )
                }
            }

            delegate.onCompletion = { error in
                if let err = error {
                    continuation.resume(throwing: err)
                } else {
                    continuation.resume(returning: ())
                }
            }

            let task = session.dataTask(with: request)
            task.resume()
        }
    }

    public func pause() {
        isPaused = true
        for s in activeSessions {
            s.invalidateAndCancel()
        }
        activeSessions.removeAll()
        Task {
            await tracker?.flush()
        }
    }

    public func cancel() {
        isCancelled = true
        pause()
    }
}

/// Thread-safe URLSessionDataDelegate handling streaming data chunks for an individual connection
final class SegmentDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var onData: ((Data) -> Void)?
    var onCompletion: ((Error?) -> Void)?

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onData?(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onCompletion?(error)
    }
}

/// Actor tracking real-time aggregated speed, per-segment progress, and persistent state
private actor ChunkProgressTracker {
    let totalBytes: Int64
    var segments: [FileSegment]
    var segmentProgress: [Double]
    let progressUpdate: (Int64, Int64, Int64, [Double]) -> Void
    let segmentPersistence: ([FileSegment]) -> Void
    var totalDownloaded: Int64
    var lastTick = Date()
    var lastDownloaded: Int64
    var lastPersistTick = Date()

    init(
        totalBytes: Int64,
        segments: [FileSegment],
        progressUpdate: @escaping (Int64, Int64, Int64, [Double]) -> Void,
        segmentPersistence: @escaping ([FileSegment]) -> Void
    ) {
        self.totalBytes = totalBytes
        self.segments = segments
        self.progressUpdate = progressUpdate
        self.segmentPersistence = segmentPersistence

        var initialDownloaded: Int64 = 0
        var initialProgress: [Double] = []
        for s in segments {
            initialDownloaded += s.downloadedBytes
            let length = max(1, s.endOffset - s.startOffset + 1)
            initialProgress.append(min(1.0, max(0.0, Double(s.downloadedBytes) / Double(length))))
        }
        self.totalDownloaded = initialDownloaded
        self.lastDownloaded = initialDownloaded
        self.segmentProgress = initialProgress
    }

    func updateSegment(index: Int, downloaded: Int64, total: Int64, deltaBytes: Int64) {
        totalDownloaded += deltaBytes
        if index >= 0 && index < segments.count {
            segments[index].downloadedBytes = downloaded
            if total > 0 {
                segmentProgress[index] = min(1.0, max(0.0, Double(downloaded) / Double(total)))
            }
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        if elapsed >= 0.25 {
            let delta = totalDownloaded - lastDownloaded
            let speed = Int64(Double(delta) / elapsed)
            let remaining = totalBytes > totalDownloaded ? (totalBytes - totalDownloaded) : 0
            let eta = speed > 0 ? (remaining / speed) : 0
            progressUpdate(totalDownloaded, speed, eta, segmentProgress)
            lastTick = now
            lastDownloaded = totalDownloaded
        }

        if now.timeIntervalSince(lastPersistTick) >= 1.0 {
            segmentPersistence(segments)
            lastPersistTick = now
        }
    }

    func flush() {
        segmentPersistence(segments)
    }

    func finish() {
        for i in 0..<segments.count {
            segments[i].downloadedBytes = segments[i].endOffset - segments[i].startOffset + 1
        }
        segmentProgress = Array(repeating: 1.0, count: segments.count)
        segmentPersistence(segments)
        progressUpdate(totalBytes > 0 ? totalBytes : totalDownloaded, 0, 0, segmentProgress)
    }
}
