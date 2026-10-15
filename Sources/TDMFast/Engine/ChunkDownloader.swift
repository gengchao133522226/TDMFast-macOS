import Foundation
import Darwin

/// High-performance chunk downloader using URLSessionDataDelegate + POSIX pwrite
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
    private var session: URLSession?
    private let sessionDelegate = ChunkSessionDelegate()
    private var activeDataTasks: [URLSessionDataTask] = []

    public init(taskId: String, proxyConfiguration: AppSettings? = nil) {
        self.taskId = taskId
        let config = URLSessionConfiguration.default
        ProxyHelper.apply(to: config, userSettings: proxyConfiguration)
        self.session = URLSession(configuration: config, delegate: self.sessionDelegate, delegateQueue: nil)
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
        progressUpdate: @escaping (Int64, Int64, Int64, [Double]) -> Void
    ) async throws {
        isCancelled = false
        isPaused = false

        let destURL = URL(fileURLWithPath: destinationPath)
        let parentDir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let fd = open(destinationPath, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else {
            throw NSError(domain: "TDMFast", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "无法创建或写入目标文件"])
        }
        defer { close(fd) }

        if totalBytes > 0 {
            ftruncate(fd, off_t(totalBytes))
        }

        let threadCount = (totalBytes > 1024 * 1024 && connections > 1) ? min(connections, 32) : 1

        if threadCount == 1 || totalBytes <= 0 {
            try await downloadSingleStream(
                url: url,
                fd: fd,
                totalBytes: totalBytes,
                customHeaders: customHeaders,
                progressUpdate: progressUpdate
            )
        } else {
            try await downloadMultiChunk(
                url: url,
                fd: fd,
                totalBytes: totalBytes,
                threadCount: threadCount,
                customHeaders: customHeaders,
                progressUpdate: progressUpdate
            )
        }
    }

    private func downloadSingleStream(
        url: URL,
        fd: Int32,
        totalBytes: Int64,
        customHeaders: [String: String]?,
        progressUpdate: @escaping (Int64, Int64, Int64, [Double]) -> Void
    ) async throws {
        guard let session = self.session else { throw URLError(.cancelled) }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let custom = customHeaders {
            for (k, v) in custom { request.setValue(v, forHTTPHeaderField: k) }
        }

        let tracker = ChunkProgressTracker(totalBytes: totalBytes, segmentCount: 1, progressUpdate: progressUpdate)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var currentOffset: Int64 = 0
            let task = session.dataTask(with: request)
            self.activeDataTasks = [task]

            sessionDelegate.register(taskId: task.taskIdentifier, onResponse: { _ in }, onData: { data in
                let count = data.count
                guard count > 0 else { return }
                data.withUnsafeBytes { raw in
                    if let ptr = raw.baseAddress {
                        pwrite(fd, ptr, count, off_t(currentOffset))
                    }
                }
                currentOffset += Int64(count)
                Task {
                    await tracker.updateSegment(
                        index: 0,
                        downloaded: currentOffset,
                        total: max(totalBytes, currentOffset),
                        deltaBytes: Int64(count)
                    )
                }
            }, onCompletion: { error in
                if let err = error {
                    continuation.resume(throwing: err)
                } else {
                    continuation.resume(returning: ())
                }
            })

            task.resume()
        }

        await tracker.finish()
    }

    private func downloadMultiChunk(
        url: URL,
        fd: Int32,
        totalBytes: Int64,
        threadCount: Int,
        customHeaders: [String: String]?,
        progressUpdate: @escaping (Int64, Int64, Int64, [Double]) -> Void
    ) async throws {
        let chunkSize = Int64(ceil(Double(totalBytes) / Double(threadCount)))
        var segments: [FileSegment] = []

        for i in 0..<threadCount {
            let start = Int64(i) * chunkSize
            let end = min(start + chunkSize - 1, totalBytes - 1)
            segments.append(FileSegment(index: i, startOffset: start, endOffset: end, downloadedBytes: 0))
        }

        let tracker = ChunkProgressTracker(totalBytes: totalBytes, segmentCount: threadCount, progressUpdate: progressUpdate)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for seg in segments {
                group.addTask {
                    try await self.downloadSegmentWithRetry(
                        segment: seg,
                        url: url,
                        fd: fd,
                        customHeaders: customHeaders,
                        tracker: tracker,
                        maxRetries: 3
                    )
                }
            }
            try await group.waitForAll()
        }

        await tracker.finish()
    }

    private func downloadSegmentWithRetry(
        segment: FileSegment,
        url: URL,
        fd: Int32,
        customHeaders: [String: String]?,
        tracker: ChunkProgressTracker,
        maxRetries: Int
    ) async throws {
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
                    throw error
                }
                // Exponential backoff before retry (500ms, 1000ms...)
                try? await Task.sleep(nanoseconds: UInt64(attempt * 500_000_000))
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
        guard let session = self.session else { throw URLError(.cancelled) }

        let segmentStart = segment.startOffset + startFrom
        if segmentStart > segment.endOffset { return }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=\(segmentStart)-\(segment.endOffset)", forHTTPHeaderField: "Range")
        if let custom = customHeaders {
            for (k, v) in custom { request.setValue(v, forHTTPHeaderField: k) }
        }

        let totalSegmentLength = segment.endOffset - segment.startOffset + 1

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var currentOffset = segmentStart
            var currentSegmentDownloaded = startFrom

            let task = session.dataTask(with: request)
            self.activeDataTasks.append(task)

            sessionDelegate.register(taskId: task.taskIdentifier, onResponse: { _ in }, onData: { data in
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
            }, onCompletion: { error in
                if let err = error {
                    continuation.resume(throwing: err)
                } else {
                    continuation.resume(returning: ())
                }
            })

            task.resume()
        }
    }

    public func pause() {
        isPaused = true
        for task in activeDataTasks {
            task.cancel()
        }
        activeDataTasks.removeAll()
    }

    public func cancel() {
        isCancelled = true
        pause()
        session?.invalidateAndCancel()
    }
}

/// Thread-safe URLSessionDataDelegate handling streaming data chunks
final class ChunkSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Callbacks {
        var onResponse: ((HTTPURLResponse) -> Void)?
        var onData: ((Data) -> Void)?
        var onCompletion: ((Error?) -> Void)?
    }

    private let lock = NSLock()
    private var callbacks: [Int: Callbacks] = [:]

    func register(
        taskId: Int,
        onResponse: ((HTTPURLResponse) -> Void)? = nil,
        onData: @escaping (Data) -> Void,
        onCompletion: @escaping (Error?) -> Void
    ) {
        lock.lock()
        callbacks[taskId] = Callbacks(onResponse: onResponse, onData: onData, onCompletion: onCompletion)
        lock.unlock()
    }

    func unregister(taskId: Int) {
        lock.lock()
        callbacks.removeValue(forKey: taskId)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            lock.lock()
            let cb = callbacks[dataTask.taskIdentifier]?.onResponse
            lock.unlock()
            cb?(http)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let cb = callbacks[dataTask.taskIdentifier]?.onData
        lock.unlock()
        cb?(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let cb = callbacks[task.taskIdentifier]?.onCompletion
        callbacks.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        cb?(error)
    }
}

/// Actor tracking real-time aggregated speed and per-segment thread progress
private actor ChunkProgressTracker {
    let totalBytes: Int64
    let segmentCount: Int
    var segmentProgress: [Double]
    let progressUpdate: (Int64, Int64, Int64, [Double]) -> Void
    var totalDownloaded: Int64 = 0
    var lastTick = Date()
    var lastDownloaded: Int64 = 0

    init(totalBytes: Int64, segmentCount: Int, progressUpdate: @escaping (Int64, Int64, Int64, [Double]) -> Void) {
        self.totalBytes = totalBytes
        self.segmentCount = segmentCount
        self.segmentProgress = Array(repeating: 0.0, count: segmentCount)
        self.progressUpdate = progressUpdate
    }

    func updateSegment(index: Int, downloaded: Int64, total: Int64, deltaBytes: Int64) {
        totalDownloaded += deltaBytes
        if index >= 0 && index < segmentProgress.count && total > 0 {
            segmentProgress[index] = min(1.0, max(0.0, Double(downloaded) / Double(total)))
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
    }

    func finish() {
        segmentProgress = Array(repeating: 1.0, count: segmentCount)
        progressUpdate(totalDownloaded, 0, 0, segmentProgress)
    }
}
