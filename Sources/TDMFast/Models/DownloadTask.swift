import Foundation

public struct DownloadTask: Identifiable, Codable {
    public let id: String
    public var url: String
    public var filename: String
    public var destinationDir: String
    public var totalBytes: Int64
    public var downloadedBytes: Int64
    public var connections: Int
    public var status: TaskStatus
    public var kind: String // "http", "ytdlp"
    public var speed: Int64 // bytes per second
    public var etaSeconds: Int64
    public var formatSelector: String?
    public var createdAt: Date
    public var completedAt: Date?
    public var errorMessage: String?
    public var customHeaders: [String: String]?
    public var segmentProgress: [Double]?

    public var progress: Double {
        guard totalBytes > 0 else { return 0.0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }

    public var destinationPath: String {
        (destinationDir as NSString).appendingPathComponent(filename)
    }

    public var category: TaskCategory {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "mov", "avi", "flv", "webm", "m4v":
            return .video
        case "zip", "tar", "gz", "7z", "rar", "bz2", "xz", "dmg", "iso", "pkg":
            return .archive
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md":
            return .document
        case "mp3", "flac", "wav", "aac", "ogg", "m4a":
            return .music
        default:
            return .other
        }
    }

    public init(
        id: String = UUID().uuidString,
        url: String,
        filename: String = "",
        destinationDir: String,
        totalBytes: Int64 = -1,
        connections: Int = 8,
        kind: String = "http",
        formatSelector: String? = nil,
        customHeaders: [String: String]? = nil
    ) {
        self.id = id
        self.url = url
        self.filename = filename.isEmpty ? (URL(string: url)?.lastPathComponent ?? "download") : filename
        self.destinationDir = destinationDir
        self.totalBytes = totalBytes
        self.downloadedBytes = 0
        self.connections = connections
        self.status = .pending
        self.kind = kind
        self.speed = 0
        self.etaSeconds = 0
        self.formatSelector = formatSelector
        self.createdAt = Date()
        self.customHeaders = customHeaders
        self.segmentProgress = nil
    }
}
