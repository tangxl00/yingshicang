import Foundation

/// 一条线路（仓内的具体配置文件）。
struct ConfigLine: Codable, Equatable, Identifiable {
    var name: String
    var url: String
    var id: String { "\(name)|\(url)" }

    /// 线路地址可能直接是配置文件 URL，也可能是把多个配置拼成 JSON 数组的「聚合仓」。
    var isAggregate: Bool { url.lowercased().hasSuffix(".json") == false && url.lowercased().hasSuffix(".txt") == false }
}

/// 一个仓（多仓管理页 R-29 的左栏）。
/// 结构依据：R-29 的双栏布局（仓列表 weight 1.3、线路列表 weight 2.0）+ 左滑删除，
/// 证明「仓 → 线路」两级嵌套；持久化键名在文档中标为待确认，本工程自定义并列出。
struct ConfigStore: Codable, Equatable, Identifiable {
    var name: String
    var url: String
    var lines: [ConfigLine]
    var id: String { "\(name)|\(url)" }
}

/// 配置加载与缓存。
/// 设计要点：
/// 1. 拉取失败不抛给 UI——保留上一次成功的配置（离线可用，与原 App 的本地缓存行为一致）。
/// 2. 首页首屏必须快：优先读内存缓存，其次读磁盘快照，最后才走网络。
final class ConfigRepository {
    static let shared = ConfigRepository()

    private let cacheLock = NSLock()
    private var memoryBundle: ConfigBundle?
    private var memorySourceURL: String = ""

    private let snapshotURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("config-snapshot.json")
    }()

    var currentBundle: ConfigBundle {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return memoryBundle ?? loadSnapshot() ?? .init()
    }

    var currentConfigURL: String {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return memorySourceURL
    }

    func setCurrentConfigURL(_ url: String) {
        cacheLock.lock(); memorySourceURL = url; cacheLock.unlock()
    }

    /// 拉取并解析配置。completion 在主线程。
    func load(urlString: String, completion: @escaping (Result<ConfigBundle, ConfigError>) -> Void) {
        guard !urlString.isEmpty else {
            completion(.failure(.emptyURL))
            return
        }
        HTTPClient.shared.request(urlString) { [weak self] response in
            guard let self = self else { return }
            guard response.ok, !response.content.isEmpty else {
                DispatchQueue.main.async { completion(.failure(.http(response.status))) }
                return
            }
            let parsed = ConfigParser.parse(text: response.content)
            if !parsed.sites.isEmpty || !parsed.lives.isEmpty || !parsed.parses.isEmpty {
                self.store(bundle: parsed, sourceURL: urlString)
                DispatchQueue.main.async { completion(.success(parsed)) }
                return
            }
            // 配置本身合法但内容为空：仍算成功（用户可能贴了个空仓）。
            DispatchQueue.main.async { completion(.success(parsed)) }
        }
    }

    /// 解析一段配置文本。优先 JSON，其次容错 JSON（去注释/尾逗号），
    /// 最后尝试「JSON 数组包裹多份配置」的聚合仓格式。
    static func parse(text: String) -> ConfigBundle { ConfigParser.parse(text: text) }

    func store(bundle: ConfigBundle, sourceURL: String) {
        cacheLock.lock()
        memoryBundle = bundle
        memorySourceURL = sourceURL
        cacheLock.unlock()
        if let data = try? JSONEncoder().encode(bundle) {
            try? data.write(to: snapshotURL, options: .atomic)
        }
        // 配置变更后清理站点相关缓存（分类、详情），避免旧规则命中新配置。
        SiteCache.shared.clearAll()
    }

    private func loadSnapshot() -> ConfigBundle? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(ConfigBundle.self, from: data)
    }

    enum ConfigError: Error, LocalizedError {
        case emptyURL
        case http(Int)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .emptyURL: return "配置地址为空"
            case .http(let status): return "配置拉取失败（HTTP \(status)）"
            case .decode(let detail): return "配置格式无法解析：\(detail)"
            }
        }
    }
}

/// 配置文本 → ConfigBundle。
enum ConfigParser {
    static func parse(text: String) -> ConfigBundle {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .init() }

        // 直接 JSON
        if let data = trimmed.data(using: .utf8),
           let bundle = try? JSONDecoder().decode(ConfigBundle.self, from: data) {
            return bundle
        }
        // 去 BOM / 注释 / 尾逗号后再试
        let cleaned = stripJSONNoise(trimmed)
        if let data = cleaned.data(using: .utf8),
           let bundle = try? JSONDecoder().decode(ConfigBundle.self, from: data) {
            return bundle
        }
        // 聚合仓：`[{"name":..,"url":..}, ...]` 需要再拉取，此处返回空并由调用方转成多仓。
        return .init()
    }

    /// 解析多仓索引文件（R-29 的仓列表来源）。
    /// 兼容两种形态：
    ///   [ { "name": "...", "url": "...", "lines": [ ... ] } ]
    ///   { "urls": [ { "url": "...", "name": "..." } ] }   （TVBox 多仓入口）
    static func parseStoreIndex(text: String) -> [ConfigStore] {
        let trimmed = stripJSONNoise(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [] }

        if let list = object as? [[String: Any]] {
            return list.compactMap { storeFromDictionary($0) }
        }
        if let root = object as? [String: Any] {
            if let urls = root["urls"] as? [[String: Any]] {
                return urls.compactMap { storeFromDictionary($0) }
            }
            if let stores = root["stores"] as? [[String: Any]] {
                return stores.compactMap { storeFromDictionary($0) }
            }
        }
        return []
    }

    private static func storeFromDictionary(_ dict: [String: Any]) -> ConfigStore? {
        let name = (dict["name"] as? String) ?? (dict["title"] as? String) ?? ""
        let url = (dict["url"] as? String) ?? ""
        guard !url.isEmpty else { return nil }
        var lines: [ConfigLine] = []
        if let rawLines = dict["lines"] as? [[String: Any]] {
            for item in rawLines {
                let lineName = (item["name"] as? String) ?? (item["title"] as? String) ?? ""
                let lineURL = (item["url"] as? String) ?? ""
                if !lineURL.isEmpty {
                    lines.append(ConfigLine(name: lineName, url: lineURL))
                }
            }
        }
        if lines.isEmpty { lines = [ConfigLine(name: name, url: url)] }
        return ConfigStore(name: name.isEmpty ? url : name, url: url, lines: lines)
    }

    /// 去掉 // 行注释、/* */ 块注释、尾逗号、BOM。
    /// 这些在用户手工编辑的配置文件里极常见，严格 JSON 解析会直接失败。
    private static func stripJSONNoise(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        // 逐字符扫描，跳过字符串内部的注释符号。
        var output = ""
        var inString = false
        var escaped = false
        var i = output.startIndex
        var chars = Array(result)
        var index = 0
        let count = chars.count
        while index < count {
            let ch = chars[index]
            if inString {
                output.append(ch)
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                index += 1
                continue
            }
            if ch == "\"" {
                inString = true
                output.append(ch)
                index += 1
                continue
            }
            if ch == "/", index + 1 < count, chars[index + 1] == "/" {
                while index < count, chars[index] != "\n" { index += 1 }
                continue
            }
            if ch == "/", index + 1 < count, chars[index + 1] == "*" {
                index += 2
                while index + 1 < count, !(chars[index] == "*" && chars[index + 1] == "/") { index += 1 }
                index = min(index + 2, count)
                continue
            }
            output.append(ch)
            index += 1
        }
        result = output
        // 尾逗号：`,}` 与 `,]`
        result = result.replacingOccurrences(of: ",\\s*\\}", with: "}", options: .regularExpression)
        result = result.replacingOccurrences(of: ",\\s*\\]", with: "]", options: .regularExpression)
        _ = i
        return result
    }
}
