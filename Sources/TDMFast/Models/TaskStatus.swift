import Foundation

public enum TaskStatus: String, Codable, CaseIterable {
    case pending = "等待中"
    case probing = "解析中"
    case downloading = "下载中"
    case paused = "已暂停"
    case completed = "已完成"
    case failed = "下载失败"
    case merging = "混流合并中"

    public var iconName: String {
        switch self {
        case .pending: return "clock"
        case .probing: return "magnifyingglass"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .merging: return "gearshape.2.fill"
        }
    }
}

public enum TaskCategory: String, Codable, CaseIterable {
    case all = "全部任务"
    case downloading = "正在下载"
    case completed = "已完成"
    case video = "视频媒体"
    case archive = "压缩包"
    case document = "文档文件"
    case music = "音频音乐"
    case other = "其他文件"

    public var iconName: String {
        switch self {
        case .all: return "tray.full"
        case .downloading: return "arrow.down.circle"
        case .completed: return "checkmark.circle"
        case .video: return "play.rectangle"
        case .archive: return "doc.zipper"
        case .document: return "doc.text"
        case .music: return "music.note"
        case .other: return "folder"
        }
    }
}
