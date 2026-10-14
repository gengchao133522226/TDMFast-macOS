import Foundation

public struct AppSettings: Codable {
    public var defaultDir: String
    public var maxConcurrent: Int
    public var defaultConnections: Int
    public var maxRateKB: Int
    public var askVideoQuality: Bool
    public var showProgressOnStart: Bool
    public var proxyEnabled: Bool
    public var proxyType: String // "http", "socks5"
    public var proxyHost: String
    public var proxyPort: Int
    public var ytDlpCustomPath: String
    public var ffmpegCustomPath: String

    public static var `default`: AppSettings {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? (NSHomeDirectory() + "/Downloads")
        return AppSettings(
            defaultDir: downloads,
            maxConcurrent: 3,
            defaultConnections: 8,
            maxRateKB: 0,
            askVideoQuality: true,
            showProgressOnStart: true,
            proxyEnabled: false,
            proxyType: "http",
            proxyHost: "127.0.0.1",
            proxyPort: 7890,
            ytDlpCustomPath: "",
            ffmpegCustomPath: ""
        )
    }

    private static var settingsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TDMFast", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("settings.json")
    }

    public static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsFileURL),
              let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return loaded
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.settingsFileURL)
        }
    }
}
