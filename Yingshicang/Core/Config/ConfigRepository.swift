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
                // 透出真实原因：传输层失败带原始 NSURLError，HTTP 失败带真实状态码。
                let error = ConfigError.from(response)
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            switch ConfigParser.parseResult(text: response.content) {
            case .success(let parsed):
                if !parsed.sites.isEmpty || !parsed.parses.isEmpty {
                    self.store(bundle: parsed, sourceURL: urlString)
                }
                // 结构合法但没有站点：仍算成功（用户可能贴了个空仓）。
                DispatchQueue.main.async { completion(.success(parsed)) }
            case .failure(let failure):
                // 结构/解码失败必须透出真实原因，不再静默成「成功但没内容」。
                DispatchQueue.main.async { completion(.failure(.decode(failure.message))) }
            }
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
        /// 拿到了真实 HTTP 响应但非 2xx：携带真实状态码。
        case http(Int)
        /// 传输层失败：没拿到 HTTP 响应，携带原始 NSURLError（绝不伪装成 500）。
        case transport(TransportFailure)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .emptyURL: return "配置地址为空"
            case .http(let status):
                return status > 0 ? "配置拉取失败（HTTP \(status)）" : "配置拉取失败（服务端未返回状态码）"
            case .transport(let failure):
                return "配置拉取失败（\(failure.displayText)\(NetworkErrorMapper.hint(for: failure))）"
            case .decode(let detail): return "配置格式无法解析：\(detail)"
            }
        }

        /// 由 HTTPResponse 归一，供 load 使用（与 SiteError.from 同一语义）。
        static func from(_ response: HTTPResponse) -> ConfigError {
            if let transport = response.transport { return .transport(transport) }
            return .http(response.status)
        }
    }
}

/// 配置文本 → ConfigBundle。
enum ConfigParser {

    /// 解析失败的**真实原因**（不再静默返回空 bundle 让上层误判成「加载成功但没内容」）。
    enum Failure: Error, Equatable {
        /// 文本为空。
        case emptyText
        /// 能当 JSON 读，但顶层结构与配置格式不符（例如是纯数组/字符串）。
        case wrongShape(String)
        /// 结构里有 `sites` 但一个都没解出来（说明站点字段与解码器不匹配）。
        case sitesUndecodable(String)
        /// 既不是合法 JSON，也不是可容错的 JSON。
        case invalidJSON(String)

        var message: String {
            switch self {
            case .emptyText: return "配置内容为空"
            case .wrongShape(let detail): return "配置顶层结构不符：\(detail)"
            case .sitesUndecodable(let detail): return "站点字段无法解码：\(detail)"
            case .invalidJSON(let detail): return "不是合法 JSON：\(detail)"
            }
        }
    }

    /// 可诊断的解析入口。`load` 用它，把真实原因透出到界面。
    ///
    /// 顺序：能解码且**解出了内容** → 成功；否则做结构诊断，给出真实原因。
    /// 关键点：`ConfigBundle` 是宽容解码，任何 JSON 对象都能"解码成功"成空 bundle，
    /// 所以不能只看「解码有没有抛错」，必须再看「解出来的东西是不是真的配置」。
    static func parseResult(text: String) -> Result<ConfigBundle, Failure> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyText) }

        let cleaned = stripJSONNoise(trimmed)
        // 1) 直接解码；2) 去 BOM / 注释 / 尾逗号后再试。
        for candidate in [trimmed, cleaned] {
            guard let bundle = decode(candidate) else { continue }
            if !bundle.sites.isEmpty || !bundle.parses.isEmpty { return .success(bundle) }
            // 解出来是空的：要么真是空仓，要么这份文本根本不是配置 —— 交给结构诊断判定。
            if let failure = analyze(cleaned) { return .failure(failure) }
            return .success(bundle)
        }
        return .failure(analyze(cleaned) ?? .invalidJSON("无法解析为 JSON"))
    }

    /// 兼容旧签名：解析不出内容时返回空 bundle（仅测试与非关键路径使用）。
    static func parse(text: String) -> ConfigBundle {
        if case .success(let bundle) = parseResult(text: text) { return bundle }
        return .init()
    }

    private static func decode(_ text: String) -> ConfigBundle? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ConfigBundle.self, from: data)
    }

    /// 结构诊断：返回 nil 表示「确实是一份合法的空配置」，返回 Failure 表示真实原因。
    private static func analyze(_ cleaned: String) -> Failure? {
        guard let data = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            let head = String(cleaned.prefix(60)).replacingOccurrences(of: "\n", with: " ")
            return .invalidJSON("以「\(head)」开头的内容不是 JSON 对象或数组")
        }
        guard let root = object as? [String: Any] else {
            return .wrongShape("顶层是 JSON 数组或标量，不是配置对象")
        }
        if let rawSites = root["sites"] ?? root["api_site"] {
            if let list = rawSites as? [Any], !list.isEmpty {
                return .sitesUndecodable("sites 有 \(list.count) 项，但没有任何一项满足站点字段约束")
            }
            return nil                    // sites 是空数组 / null：合法的空仓
        }
        if root["urls"] != nil || root["stores"] != nil {
            return .wrongShape("这是多仓索引文件（urls/stores），不是单仓配置文件")
        }
        if root["parses"] != nil || root["flags"] != nil
            || root["wallpaper"] != nil || root["spider"] != nil {
            return nil                    // 有配置字段但没有 sites：合法的空仓
        }
        return .wrongShape("JSON 对象缺少 sites/parses 等配置字段")
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
            // TVBox 多仓入口：`{"urls":["...","..."]}` 纯字符串数组，
            // 每个 URL 就是一条线路，整体作为一个仓返回。
            if let urls = root["urls"] as? [String] {
                let lines: [ConfigLine] = urls.enumerated().compactMap { pair -> ConfigLine? in
                    let url = pair.element.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !url.isEmpty else { return nil }
                    return ConfigLine(name: "线路\(pair.offset + 1)", url: url)
                }
                guard !lines.isEmpty else { return [] }
                return [ConfigStore(name: "默认仓", url: lines[0].url, lines: lines)]
            }
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
