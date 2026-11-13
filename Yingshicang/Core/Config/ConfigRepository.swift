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

    /// 扫码 / 手填入口的地址准入（build 23 质检 P2-4）。
    ///
    /// 扫码拿到的字符串来自外部二维码，是最典型的不可信输入：
    /// 必须先是 http/https 且带非空 host，才允许进入 `load`。
    /// 拦掉 `file:` / `javascript:` / `data:` / 自定义 scheme 与 `http:///` 这类空 host，
    /// 避免把任意协议直接灌进 `URLSession`（ATS 放开明文后这层是唯一防线）。
    /// 返回 nil 表示不可接受，调用方应显式提示而不是静默失败。
    static func acceptableConfigURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        guard let host = url.host, !host.isEmpty else { return nil }
        _ = scheme
        return url
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
