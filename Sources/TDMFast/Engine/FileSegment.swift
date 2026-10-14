import Foundation

public struct FileSegment: Codable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let startOffset: Int64
    public let endOffset: Int64
    public var downloadedBytes: Int64

    public var isCompleted: Bool {
        return downloadedBytes >= (endOffset - startOffset + 1)
    }

    public var currentRangeHeader: String {
        let currentStart = startOffset + downloadedBytes
        return "bytes=\(currentStart)-\(endOffset)"
    }
}
