import Foundation

public struct VideoFormatInfo: Identifiable, Codable {
    public var id: String { formatId }
    public let formatId: String
    public let ext: String
    public let resolution: String
    public let filesize: Int64?
    public let note: String?
    public let hasVideo: Bool
    public let hasAudio: Bool

    public var displayLabel: String {
        var parts: [String] = []
        if !resolution.isEmpty && resolution != "unknown" {
            parts.append(resolution)
        }
        parts.append(ext.uppercased())
        if let note = note, !note.isEmpty {
            parts.append("(\(note))")
        }
        if let size = filesize, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.joined(separator: " - ")
    }
}

public struct VideoMetadata: Codable {
    public let title: String
    public let url: String
    public let thumbnail: String?
    public let duration: Double?
    public let formats: [VideoFormatInfo]
}
