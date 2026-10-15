import Foundation
import CFNetwork

public enum ProxyHelper {
    public struct ProxyInfo {
        public let host: String
        public let port: Int
        public let type: String // "http", "https", "socks5"

        public var urlString: String {
            return "\(type)://\(host):\(port)"
        }
    }

    /// Automatically detects system proxy configured in macOS Network preferences
    public static func getSystemProxy() -> ProxyInfo? {
        guard let dict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        // 1. Check HTTP proxy
        if let enable = dict[kCFNetworkProxiesHTTPEnable as String] as? Int, enable == 1,
           let host = dict[kCFNetworkProxiesHTTPProxy as String] as? String,
           let port = dict[kCFNetworkProxiesHTTPPort as String] as? Int,
           !host.isEmpty, port > 0 {
            return ProxyInfo(host: host, port: port, type: "http")
        }

        // 2. Check HTTPS proxy
        if let enable = dict[kCFNetworkProxiesHTTPSEnable as String] as? Int, enable == 1,
           let host = dict[kCFNetworkProxiesHTTPSProxy as String] as? String,
           let port = dict[kCFNetworkProxiesHTTPSPort as String] as? Int,
           !host.isEmpty, port > 0 {
            return ProxyInfo(host: host, port: port, type: "http")
        }

        // 3. Check SOCKS proxy
        if let enable = dict[kCFNetworkProxiesSOCKSEnable as String] as? Int, enable == 1,
           let host = dict[kCFNetworkProxiesSOCKSProxy as String] as? String,
           let port = dict[kCFNetworkProxiesSOCKSPort as String] as? Int,
           !host.isEmpty, port > 0 {
            return ProxyInfo(host: host, port: port, type: "socks5")
        }

        // 4. Check scoped interface dictionaries if utun/VPN is active
        if let scoped = dict["__SCOPED__"] as? [String: [String: Any]] {
            for (_, scopeDict) in scoped {
                if let enable = scopeDict[kCFNetworkProxiesHTTPEnable as String] as? Int, enable == 1,
                   let host = scopeDict[kCFNetworkProxiesHTTPProxy as String] as? String,
                   let port = scopeDict[kCFNetworkProxiesHTTPPort as String] as? Int,
                   !host.isEmpty, port > 0 {
                    return ProxyInfo(host: host, port: port, type: "http")
                }
                if let enable = scopeDict[kCFNetworkProxiesHTTPSEnable as String] as? Int, enable == 1,
                   let host = scopeDict[kCFNetworkProxiesHTTPSProxy as String] as? String,
                   let port = scopeDict[kCFNetworkProxiesHTTPSPort as String] as? Int,
                   !host.isEmpty, port > 0 {
                    return ProxyInfo(host: host, port: port, type: "http")
                }
                if let enable = scopeDict[kCFNetworkProxiesSOCKSEnable as String] as? Int, enable == 1,
                   let host = scopeDict[kCFNetworkProxiesSOCKSProxy as String] as? String,
                   let port = scopeDict[kCFNetworkProxiesSOCKSPort as String] as? Int,
                   !host.isEmpty, port > 0 {
                    return ProxyInfo(host: host, port: port, type: "socks5")
                }
            }
        }

        return nil
    }

    /// Applies proxy settings to URLSessionConfiguration (preferring app settings if enabled, otherwise fallback to system proxy)
    public static func apply(to config: URLSessionConfiguration, userSettings: AppSettings?) {
        config.httpMaximumConnectionsPerHost = 64
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 3600.0

        if let p = userSettings, p.proxyEnabled, !p.proxyHost.isEmpty, p.proxyPort > 0 {
            if p.proxyType.lowercased() == "socks5" {
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesSOCKSEnable as String: true,
                    kCFNetworkProxiesSOCKSProxy as String: p.proxyHost,
                    kCFNetworkProxiesSOCKSPort as String: p.proxyPort
                ]
            } else {
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable as String: true,
                    kCFNetworkProxiesHTTPProxy as String: p.proxyHost,
                    kCFNetworkProxiesHTTPPort as String: p.proxyPort,
                    kCFNetworkProxiesHTTPSEnable as String: true,
                    kCFNetworkProxiesHTTPSProxy as String: p.proxyHost,
                    kCFNetworkProxiesHTTPSPort as String: p.proxyPort
                ]
            }
        } else if let sys = getSystemProxy() {
            if sys.type == "socks5" {
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesSOCKSEnable as String: true,
                    kCFNetworkProxiesSOCKSProxy as String: sys.host,
                    kCFNetworkProxiesSOCKSPort as String: sys.port
                ]
            } else {
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable as String: true,
                    kCFNetworkProxiesHTTPProxy as String: sys.host,
                    kCFNetworkProxiesHTTPPort as String: sys.port,
                    kCFNetworkProxiesHTTPSEnable as String: true,
                    kCFNetworkProxiesHTTPSProxy as String: sys.host,
                    kCFNetworkProxiesHTTPSPort as String: sys.port
                ]
            }
        }
    }

    /// Resolves the proxy URL string for command-line tools like yt-dlp
    public static func resolveProxyUrl(userSettings: AppSettings?) -> String? {
        if let p = userSettings, p.proxyEnabled, !p.proxyHost.isEmpty, p.proxyPort > 0 {
            return "\(p.proxyType)://\(p.proxyHost):\(p.proxyPort)"
        }
        if let sys = getSystemProxy() {
            return sys.urlString
        }
        return nil
    }
}
