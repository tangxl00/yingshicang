import Foundation

/// 播放地址解析的共享入口（质检 P1-6 建议的收口点）。
///
/// ## 为什么需要一个独立入口
/// 修复前 lazy 规则只有 `HTMLSiteProvider.play` 会执行（`JSPlayParser` 全仓唯一调用点），
/// type=3 的 JS 站点走 `JSSiteProvider.play` → 直接 `spider.play()`，lazy 的 106 行逻辑对 JS 站点是死代码。
/// 同时 `PlayResolution.parseIndex` / `needSniff` 只写不读，二次解析与嗅探链路整体断链。
/// 现在三类源统一走这里，管线固定为：
///
/// ```
/// 剧集地址
///   ├─ 1. 直链快路径（m3u8/mp4/mkv/m4a/mp3）→ 直接返回
///   ├─ 2. lazy 规则（站点级，三类源一致）
///   │     ├─ `js:` 脚本 → JS 引擎产出的 {parse,jx,url} 或纯地址串
///   │     └─ `json:` 前缀 → 请求接口取 url
///   ├─ 3. provider 分类（无 lazy 时由站点自身判定：spider 的 parse/jx、HTML/API 的直链判定）
///   ├─ 4. parseIndex 有值 → 二次解析（parses[] 下标）
///   └─ 5. needSniff → 抓页面嗅探 m3u8/mp4
/// ```
///
/// ## 失败语义（质检 P1-4）
/// 任何一步拿不到可用地址都返回 `.failure` 并带明确原因，**不再把入参原样当直链返回**。
/// 「原样返回 + 假装成功」会让播放页停在空白/无限加载，且掩盖规则失效这一真实故障。
final class PlayResolver {

    static let shared = PlayResolver()

    /// 可注入的 HTTP 出口：生产走 `HTTPClient`，测试注入 mock 以便离线、可证伪。
    private let transport: PlayTransport
    /// 配置读取：parses 数组来自当前配置。
    private let bundleProvider: () -> ConfigBundle
    /// 站点脚本引擎注册表（按站点隔离）。
    private let engines: JSEngineRegistry

    init(transport: PlayTransport = LivePlayTransport(),
         bundleProvider: @escaping () -> ConfigBundle = { ConfigRepository.shared.currentBundle },
         engines: JSEngineRegistry = .shared) {
        self.transport = transport
        self.bundleProvider = bundleProvider
        self.engines = engines
    }

    // MARK: - 主流程

    func resolve(site: SiteConfig,
                 provider: SiteProvider,
                 flag: String,
                 url: String,
                 completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        let input = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            completion(.failure(.parse("播放地址为空")))
            return
        }

        // 1. lazy 规则优先（三类源一致）。lazy 为空时才交给 provider 自己分类。
        //
        // 这里刻意不设「直链快路径」：spider 常返回 `{url:"...m3u8", parse:2, jx:1}`，
        // 那种 m3u8 是必须送解析源的加密/防盗链地址，提前按后缀短路就会丢掉 parseIndex，
        // 正好复现 P1-1 的断链缺陷。是否直链交给 provider 自行判定（它们知道自己的 jx 语义）。
        let lazy = site.lazy.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lazy.isEmpty {
            resolveLazy(site: site, lazy: lazy, input: input) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error): completion(.failure(error))
                case .success(let resolution): self.finish(resolution: resolution, site: site, completion: completion)
                }
            }
            return
        }

        // 3. provider 分类。
        provider.play(flag: flag, url: input) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let resolution): self.finish(resolution: resolution, site: site, completion: completion)
            }
        }
    }

    /// 拿到初判结果后统一收口：二次解析 → 嗅探 → 成功/失败。
    private func finish(resolution: PlayResolution,
                        site: SiteConfig,
                        completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        if let index = resolution.parseIndex {
            applySecondaryParse(url: resolution.url, parseIndex: index, completion: completion)
            return
        }
        if resolution.needSniff {
            sniff(url: resolution.url, completion: completion)
            return
        }
        guard !resolution.url.isEmpty else {
            completion(.failure(.parse("规则未产出播放地址")))
            return
        }
        completion(.success(resolution))
    }

    // MARK: - lazy

    private func resolveLazy(site: SiteConfig,
                             lazy: String,
                             input: String,
                             completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        let lowered = lazy.lowercased()
        if lowered.hasPrefix("json:") {
            let prefix = String(lazy.dropFirst("json:".count)).trimmingCharacters(in: .whitespaces)
            guard !prefix.isEmpty else {
                completion(.failure(.parse("lazy 的 json: 前缀缺少接口地址")))
                return
            }
            requestJSONResolution(target: prefix + input, source: "lazy(json:)") { completion($0) }
            return
        }

        var script = lazy
        if lowered.hasPrefix("js:") { script = String(script.dropFirst(3)) }
        let engine = engines.lazyEngine(for: site)
        let wrapper = """
        (function(){
          var input = \(JSStringLiteral.encode(input));
          var rule = \(siteSettingJSON(site));
          var MY_URL = \(JSStringLiteral.encode(site.host.isEmpty ? site.api : site.host));
          var HOST = MY_URL;
          \(script)
          return JSON.stringify(input);
        })();
        """
        DispatchQueue.global(qos: .userInitiated).async {
            switch engine.evaluateJSON(wrapper, filename: "lazy-\(site.key).js") {
            case .failure(let error):
                completion(.failure(.parse("lazy 脚本执行失败：\(error.localizedDescription ?? "未知")")))
            case .success(let value):
                completion(Self.resolutionFromLazyOutput(value))
            }
        }
    }

    /// lazy 产物归一：字典走 `parse/jx/url`，纯字符串当作直链地址。
    static func resolutionFromLazyOutput(_ value: Any) -> Result<PlayResolution, SiteError> {
        if let dict = value as? [String: Any] {
            let resolution = JSSiteProvider.parsePlay(dict)
            guard !resolution.url.isEmpty else {
                return .failure(.parse("lazy 脚本返回的对象里没有 url"))
            }
            return .success(resolution)
        }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .failure(.parse("lazy 脚本返回空地址"))
            }
            if let direct = PlayURLClassifier.directMediaURL(trimmed) {
                return .success(PlayResolution(url: direct, parseIndex: nil, needSniff: false))
            }
            return .success(PlayResolution(url: trimmed, parseIndex: nil, needSniff: true))
        }
        return .failure(.parse("lazy 脚本返回值无法识别（期望对象或地址字符串）"))
    }

    // MARK: - 二次解析（质检 P1-1）

    /// 按 `resolution.parseIndex` 取 `parses[]` 的解析源，真正执行二次解析。
    /// 失败必须显式返回错误：下标越界、接口不通、返回体没有地址，三种都要能定位。
    func applySecondaryParse(url: String,
                             parseIndex: Int,
                             completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        let parses = bundleProvider().parses
        guard parses.indices.contains(parseIndex) else {
            completion(.failure(.parse("解析源下标 \(parseIndex) 越界（当前配置共 \(parses.count) 个解析源）")))
            return
        }
        let parse = parses[parseIndex]
        guard !parse.url.isEmpty else {
            completion(.failure(.parse("解析源「\(parse.name)」未配置接口地址")))
            return
        }

        let target = parse.url + url
        // type 0 = 网页解析（返回页面，地址在 HTML 里）；type 1 = JSON 接口（返回体带 url）。
        // 其余取值（聚合/未知）先按 JSON 试，失败再按网页嗅探，两边都失败才报错。
        switch parse.type {
        case 1:
            requestJSONResolution(target: target, source: "解析源「\(parse.name)」") { result in
                switch result {
                case .success(let resolution):
                    completion(.success(PlayResolution(url: resolution.url, parseIndex: nil, needSniff: false)))
                case .failure(let error):
                    completion(.failure(.parse("解析源「\(parse.name)」二次解析失败：\(error.errorDescription ?? "")")))
                }
            }
        case 0:
            sniff(target: target, source: "解析源「\(parse.name)」", completion: completion)
        default:
            requestJSONResolution(target: target, source: "解析源「\(parse.name)」") { result in
                switch result {
                case .success(let resolution):
                    completion(.success(PlayResolution(url: resolution.url, parseIndex: nil, needSniff: false)))
                case .failure:
                    self.sniff(target: target, source: "解析源「\(parse.name)」", completion: completion)
                }
            }
        }
    }

    // MARK: - 嗅探

    func sniff(url: String,
               completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        sniff(target: url, source: "嗅探", completion: completion)
    }

    private func sniff(target: String,
                       source: String,
                       completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        guard PlayURLClassifier.isFetchable(target) else {
            completion(.failure(.parse("\(source)目标不是可抓取的 http(s) 地址：\(target)")))
            return
        }
        transport.get(target) { response in
            guard response.ok else {
                completion(.failure(.network(response.status)))
                return
            }
            guard let media = PlaySniffer.extractMediaURL(from: response.content, base: target) else {
                completion(.failure(.parse("\(source)未在响应中找到 m3u8/mp4 地址（HTTP \(response.status)，\(response.content.count) 字节）")))
                return
            }
            completion(.success(PlayResolution(url: media, parseIndex: nil, needSniff: false)))
        }
    }

    // MARK: - JSON 解析

    private func requestJSONResolution(target: String,
                                       source: String,
                                       completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        transport.get(target) { response in
            guard response.ok else {
                completion(.failure(.network(response.status)))
                return
            }
            guard let data = response.content.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let url = PlayJSONResolver.extractPlayURL(from: object) else {
                completion(.failure(.parse("\(source)响应中没有 url 字段")))
                return
            }
            completion(.success(PlayResolution(url: url, parseIndex: nil, needSniff: false)))
        }
    }

    // MARK: - 工具

    private func siteSettingJSON(_ site: SiteConfig) -> String {
        var dict: [String: Any] = [
            "key": site.key, "name": site.name, "type": site.type,
            "api": site.api, "ext": site.ext, "jar": site.jar,
            "host": site.host, "url": site.url,
            "searchUrl": site.searchUrl, "detailUrl": site.detailUrl,
            "headers": site.headers, "lazy": site.lazy
        ]
        if !site.ext.isEmpty {
            // ext 常是 `?key=xxx` 形式的查询串，规则脚本会拼出完整接口地址。
            dict["parse_url"] = ""
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

// MARK: - 依赖注入接缝

/// 播放解析使用的 HTTP 出口。测试注入 mock，生产走全局客户端。
protocol PlayTransport {
    func get(_ url: String, completion: @escaping (HTTPResponse) -> Void)
}

struct LivePlayTransport: PlayTransport {
    func get(_ url: String, completion: @escaping (HTTPResponse) -> Void) {
        HTTPClient.shared.request(url, options: HTTPOptions()) { completion($0) }
    }
}

// MARK: - 直链判定

enum PlayURLClassifier {
    static let directExtensions: Set<String> = ["m3u8", "mp4", "mkv", "m4a", "mp3"]

    /// 地址是直链则返回归一化后的地址（`m3u8://` → `http://`），否则 nil。
    static func directMediaURL(_ raw: String) -> String? {
        let lowered = raw.lowercased()
        if lowered.hasPrefix("m3u8://") || lowered.hasPrefix("mp4://") {
            let stripped = raw.replacingOccurrences(of: "m3u8://", with: "http://")
                .replacingOccurrences(of: "mp4://", with: "http://")
            return stripped
        }
        // 查询串里可能带 `.m3u8?token=...`，所以按「路径含后缀」判断而不是 hasSuffix。
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        let ext = url.pathExtension.lowercased()
        if directExtensions.contains(ext) { return raw }
        return nil
    }

    /// 是否可作为嗅探/二次解析的抓取目标（只允许 http/https）。
    static func isFetchable(_ raw: String) -> Bool {
        guard let url = HTTPClient.normalize(raw),
              let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

// MARK: - 页面嗅探

enum PlaySniffer {
    /// 从页面/接口响应里抽第一个 m3u8/mp4 地址。
    /// 支持 JSON 转义的 `\/`、HTML 属性里的相对协议地址 `//host/path`。
    static func extractMediaURL(from text: String, base: String) -> String? {
        guard !text.isEmpty else { return nil }
        let unescaped = text.replacingOccurrences(of: "\\/", with: "/")
        // 粗筛所有 http(s) 串，随后按媒体后缀过滤；不做完整 HTML 解析，嗅探只需要第一个命中。
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s"'<>\\\)\]]+"#, options: []) else {
            return nil
        }
        let range = NSRange(unescaped.startIndex..., in: unescaped)
        let matches = regex.matches(in: unescaped, options: [], range: range)
        for match in matches {
            guard let hit = Range(match.range, in: unescaped) else { continue }
            let candidate = String(unescaped[hit])
            let lower = candidate.lowercased()
            if lower.contains(".m3u8") || lower.contains(".mp4") || lower.contains(".mkv") {
                return candidate
            }
        }
        return nil
    }
}

// MARK: - JSON 地址提取

enum PlayJSONResolver {
    /// 常见解析接口的返回形态：`{"url":...}` / `{"data":{"url":...}}` / `{"data":"http..."}`。
    static func extractPlayURL(from object: Any) -> String? {
        if let dict = object as? [String: Any] {
            for key in ["url", "playUrl", "play_url", "src"] {
                if let value = dict[key] as? String, !value.isEmpty { return value }
            }
            if let data = dict["data"] { return extractPlayURL(from: data) }
            if let list = dict["list"] as? [Any], let first = list.first { return extractPlayURL(from: first) }
            return nil
        }
        if let text = object as? String, text.contains("://") { return text }
        return nil
    }
}

// MARK: - JS 字符串字面量

enum JSStringLiteral {
    /// 把 Swift 字符串编码成安全的 JS 字符串字面量（含引号）。
    static func encode(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        // ["value"] → "value"
        return String(text.dropFirst().dropLast())
    }
}
