import Foundation

/// 传输层失败（请求没有拿到任何 HTTP 响应）。
///
/// 存在的理由：这类失败**没有 HTTP 状态码**。历史实现把它统一标成 `500` / `-1`，
/// 于是在用户界面上出现「HTTP 500」「HTTP -1」这种虚构状态码——服务端实返 200，
/// 用户却看到一个根本不存在的 500，真正的失败原因（如 ATS 拦截 -1022）被彻底掩埋。
/// 现在改为保留 NSURLError 的原始 domain / code / localizedDescription，原样透出。
struct TransportFailure: Equatable {
    /// NSURLErrorDomain 的原始 code（如 -1022 = ATS 要求安全连接、-1009 = 网络不可达）。
    var code: Int
    /// 原始错误域（`NSURLErrorDomain` / `NSPOSIXErrorDomain` 等）。
    var domain: String
    /// 系统给出的原始描述文本，不做改写。
    var message: String

    /// 面向用户的一行原文：`NSURLErrorDomain -1022：<系统描述>`。
    var displayText: String {
        let prefix = domain.isEmpty ? "错误 \(code)" : "\(domain) \(code)"
        return message.isEmpty ? prefix : "\(prefix)：\(message)"
    }
}

/// 统一的 HTTP 响应载体。字段命名与 APK 内置 http.js 的返回结构保持一致
/// （ok / status / content / headers / url），这样 JS 侧的 `req(...)` 拿到的对象
/// 与 Android 端同构，既有爬虫规则不需要改写。
struct HTTPResponse {
    var ok: Bool
    /// 真实 HTTP 状态码；传输层失败时为 0（**不伪造任何状态码**，失败原因见 `transport`）。
    var status: Int
    var content: String
    var headers: [String: String]
    var url: String
    var data: Data?
    /// 传输层失败信息；有值即表示「根本没拿到 HTTP 响应」。
    var transport: TransportFailure? = nil

    /// 带真实状态码的 HTTP 失败（仅用于确实拿到了非 2xx 响应的情况）。
    static func failure(_ url: String, status: Int) -> HTTPResponse {
        HTTPResponse(ok: false, status: status, content: "", headers: [:], url: url, data: nil)
    }

    /// 传输层失败：不伪造状态码，只带原始 NSURLError。
    static func transportFailure(_ url: String, error: Error?) -> HTTPResponse {
        HTTPResponse(ok: false, status: 0, content: "", headers: [:], url: url, data: nil,
                     transport: NetworkErrorMapper.describe(error))
    }

    /// 供 JS 桥转换用的字典（JSValue 由 host 层再包）。
    var jsDictionary: [String: Any] {
        ["ok": ok, "status": status, "content": content, "headers": headers, "url": url]
    }
}

/// 配置一次请求的可选项。语义对齐 http.js 支持的 options：
/// headers、method、body、timeout、以及“是否同步”。
struct HTTPOptions {
    var method: String = "GET"
    var headers: [String: String] = [:]
    var body: Data?
    var timeout: TimeInterval = 20

    init() {}

    /// 从 JS 传入的 options 字典解析。未知键忽略，不报错（规则脚本会带各种附加字段）。
    init(jsOptions: [String: Any]) {
        if let m = jsOptions["method"] as? String, !m.isEmpty { method = m.uppercased() }
        if let h = jsOptions["headers"] as? [String: String] { headers = h }
        if let b = jsOptions["body"] as? String { body = b.data(using: .utf8) }
        if let t = jsOptions["timeout"] as? NSNumber, t.doubleValue > 0 { timeout = min(t.doubleValue, 60) }
        if let t = jsOptions["timeout"] as? String, let v = Double(t), v > 0 { timeout = min(v, 60) }
    }
}

/// 全局共享的 HTTP 客户端。
/// 采集站的图片、接口、播放地址全走这里，故统一注入一套桌面 UA：
/// 大量采集站对移动 UA 返回阉割页面，原 App 也是用固定 UA 抓取。
final class HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession
    private let config: URLSessionConfiguration
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    private init() {
        config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        session = URLSession(configuration: config)
    }

    /// 供图片管线复用的配置（走磁盘缓存）。
    static func makeImageSession() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"]
        return URLSession(configuration: cfg)
    }

    /// 异步请求。completion 在后台线程回调，调用方自行切换队列。
    func request(_ urlString: String, options: HTTPOptions = HTTPOptions(), completion: @escaping (HTTPResponse) -> Void) {
        guard let url = Self.normalize(urlString) else {
            // 地址本身不合法：同样没有 HTTP 状态码，不能编造 400。
            completion(HTTPResponse(ok: false, status: 0, content: "", headers: [:],
                                    url: urlString, data: nil,
                                    transport: TransportFailure(code: 0, domain: "", message: "地址无效：\(urlString)")))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = options.method
        request.timeoutInterval = options.timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in options.headers where !key.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body = options.body {
            request.httpBody = body
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            }
        }

        session.dataTask(with: request) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                // 没拿到 HTTP 响应就是传输层失败：带真实 NSURLError 出去，绝不编造 500。
                completion(.transportFailure(urlString, error: error))
                return
            }
            let body = data ?? Data()
            var headers: [String: String] = [:]
            for (k, v) in httpResponse.allHeaderFields {
                if let key = k as? String, let value = v as? String { headers[key] = value }
            }
            let contentType = headers.first { $0.key.lowercased() == "content-type" }?.value ?? ""
            let text = BodyDecoder.decode(body, contentType: contentType)
            completion(HTTPResponse(ok: (200...299).contains(httpResponse.statusCode),
                                    status: httpResponse.statusCode,
                                    content: text,
                                    headers: headers,
                                    url: urlString,
                                    data: body))
        }.resume()
    }

    /// 同步包装：仅供 JS 桥在专用串行队列上使用（详见 JSBridge 的同步语义说明）。
    func requestSync(_ urlString: String, options: HTTPOptions = HTTPOptions()) -> HTTPResponse {
        let semaphore = DispatchSemaphore(value: 0)
        // 超时兜底也属于传输层失败：不伪造状态码。
        var result = HTTPResponse.transportFailure(urlString, error: nil)
        // 放到独立并发队列，避免与 JS 串行队列互锁。
        DispatchQueue.global(qos: .userInitiated).async {
            self.request(urlString, options: options) { response in
                result = response
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + options.timeout + 10)
        return result
    }

    /// 采集站经常给不带 scheme 的地址，或给 `//host/path` 这种协议相对地址。
    static func normalize(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        if value.hasPrefix("//") { return URL(string: "http:" + value) }
        if !value.contains("://") { return URL(string: "http://" + value) }
        return URL(string: value)
    }
}

/// NSURLError → 用户可读原因。只做**如实呈现**，不改写、不降级成假状态码。
///
/// 历史缺陷（v2.0.50 build 20）：`HTTPClient` 丢弃 URLSession 的 `error` 并硬编码
/// `status: 500`，`APISiteProvider` 丢弃 `error` 并硬编码 `.network(-1)`。
/// 两者都让「ATS 拦截 / DNS 失败 / 超时 / 证书错误」在界面上伪装成不存在的 HTTP 状态码。
enum NetworkErrorMapper {
    /// 保留原始 domain / code / 系统描述。
    static func describe(_ error: Error?) -> TransportFailure {
        guard let error = error else {
            return TransportFailure(code: 0, domain: "", message: "请求未返回任何响应，且无错误信息")
        }
        let nsError = error as NSError
        return TransportFailure(code: nsError.code,
                                domain: nsError.domain,
                                message: nsError.localizedDescription)
    }

    /// 常见错误码的补充说明（不改写原文，只追加一句「这意味着什么」）。
    static func hint(for failure: TransportFailure) -> String {
        guard failure.domain == NSURLErrorDomain else { return "" }
        switch failure.code {
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "（ATS 拦截了明文 HTTP 请求）"
        case NSURLErrorNotConnectedToInternet:
            return "（设备未联网）"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "（域名无法解析）"
        case NSURLErrorTimedOut:
            return "（请求超时）"
        case NSURLErrorCannotConnectToHost:
            return "（无法建立到服务器的连接）"
        case NSURLErrorNetworkConnectionLost:
            return "（连接被中断）"
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid:
            return "（TLS/证书校验失败）"
        default:
            return ""
        }
    }
}

/// 文本解码：优先按 Content-Type 声明的 charset，其次按 HTML meta 声明，最后回落 GB18030。
/// 国内采集站大量使用 GBK/GB2312 页面，直接按 UTF-8 解码会得到满屏乱码。
enum BodyDecoder {
    static func decode(_ data: Data, contentType: String) -> String {
        if data.isEmpty { return "" }
        if let charset = charsetName(in: contentType) ?? metaCharset(in: data) {
            if let encoding = encoding(for: charset), let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let encoding = encoding(for: "gb18030"), let text = String(data: data, encoding: encoding) { return text }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    private static func charsetName(in contentType: String) -> String? {
        guard let range = contentType.range(of: "charset=", options: .caseInsensitive) else { return nil }
        var value = String(contentType[range.upperBound...])
        if let semicolon = value.firstIndex(of: ";") { value = String(value[value.startIndex..<semicolon]) }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        return value.isEmpty ? nil : value.lowercased()
    }

    private static func metaCharset(in data: Data) -> String? {
        // 只看前 4KB，避免整页扫描。
        let head = data.prefix(4096)
        guard let text = String(data: head, encoding: .isoLatin1) else { return nil }
        let lowered = text.lowercased()
        guard let range = lowered.range(of: "charset=") else { return nil }
        let tail = text[range.upperBound...]
        var value = ""
        for ch in tail.prefix(24) {
            if ch == "\"" || ch == "'" || ch == ">" || ch == " " || ch == ";" { break }
            value.append(ch)
        }
        return value.isEmpty ? nil : value.lowercased()
    }

    private static func encoding(for charset: String) -> String.Encoding? {
        switch charset {
        case "utf-8", "utf8": return .utf8
        case "gbk", "gb2312", "gb18030", "x-gbk": return gb18030
        case "big5": return big5
        case "iso-8859-1", "latin1": return .isoLatin1
        default: return nil
        }
    }

    /// CFString 编码表里的 GB18030（扩展到 0x0632）。
    private static let gb18030: String.Encoding = {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }()

    private static let big5: String.Encoding = {
        let cfEncoding = CFStringEncoding(CFStringEncodings.big5.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }()
}
