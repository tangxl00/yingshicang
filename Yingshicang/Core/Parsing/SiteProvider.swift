import Foundation

/// 站点数据源统一契约。
/// 架构文档要求「SiteProvider 协议收口三类源」：
/// ① HTML 规则源（type=0）② JSON API 源（type=1）③ JS 爬虫源（type=3）
/// 三者对上层的调用方式完全一致，差异全部封装在各自实现里。
protocol SiteProvider {
    var site: SiteConfig { get }

    /// 首页推荐。
    func home(completion: @escaping (Result<[VodItem], SiteError>) -> Void)
    /// 分类列表（分页）。
    func category(id: String, page: Int, extend: [String: String], completion: @escaping (Result<[VodItem], SiteError>) -> Void)
    /// 分类定义。
    func categories(completion: @escaping (Result<[SiteCategory], SiteError>) -> Void)
    /// 详情。
    func detail(id: String, completion: @escaping (Result<VodDetail, SiteError>) -> Void)
    /// 搜索。
    func search(keyword: String, page: Int, completion: @escaping (Result<[VodItem], SiteError>) -> Void)
    /// 播放地址解析。
    func play(flag: String, url: String, completion: @escaping (Result<PlayResolution, SiteError>) -> Void)
}

/// 站点级错误。jar 源在 iOS 属平台级不支持，用独立 case 显式表达，
/// 由 UI 给出明确提示，绝不静默降级为空列表（需求「不静默降级」）。
/// `Equatable` 让测试可以对错误值做精确断言（如 `XCTAssertEqual(error, .parse("..."))`），
/// 关联值均为 String/Int/TimeInterval/TransportFailure，合成实现即可，不改变运行时行为。
enum SiteError: Error, LocalizedError, Equatable {
    case unsupportedJar(String)
    /// 拿到了真实 HTTP 响应但状态码非 2xx。
    case network(Int)
    /// 传输层失败：没拿到 HTTP 响应，携带原始 NSURLError（不伪造状态码）。
    case transport(TransportFailure)
    case parse(String)
    case empty
    case cancelled
    /// 加载在给定时限内没有任何结果。这是**兜底状态**，不是推断：
    /// 底层请求可能仍在跑，但 UI 不能继续挂起，必须终止并提供重试。
    case timeout(TimeInterval)

    /// 由 HTTPResponse 归一：先看传输层失败，再看真实状态码。
    /// 这是「不再伪装成 500 / -1」的唯一入口，所有 provider 共用。
    static func from(_ response: HTTPResponse) -> SiteError {
        if let transport = response.transport { return .transport(transport) }
        return .network(response.status)
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedJar(let site):
            return "「\(site)」使用 jar 爬虫规则，iOS 无 Java 运行环境，该站点在当前平台不可用"
        case .network(let status):
            return status > 0 ? "网络请求失败（HTTP \(status)）" : "网络请求失败（服务端未返回状态码）"
        case .transport(let failure):
            return "网络请求失败（\(failure.displayText)\(NetworkErrorMapper.hint(for: failure))）"
        case .parse(let detail): return "页面解析失败：\(detail)"
        case .empty: return "没有数据"
        case .cancelled: return "已取消"
        case .timeout(let seconds):
            return "加载超时（\(Int(seconds)) 秒内没有返回结果），请检查网络后重试"
        }
    }
}

/// Provider 工厂：按站点形态路由。判定走 `SiteConfig.spiderKind`（唯一事实源），
/// 不再依赖 `.jar` 后缀——真实配置把 jar 包声明在顶层 `spider`，
/// 站点 `api` 只写 jar 内的 Java 类名（`csp_DouDou` / `py_qie`），
/// 旧实现按后缀判定会把这类站点放行给 JS/API Provider，直接造成首屏无限加载。
enum SiteProviderFactory {
    static func make(site: SiteConfig) -> SiteProvider {
        switch site.spiderKind {
        case .jarClass:
            return UnsupportedSiteProvider(site: site)
        case .jsScript:
            return JSSiteProvider(site: site)
        case .httpAPI:
            return APISiteProvider(site: site)
        case .htmlRule:
            return HTMLSiteProvider(site: site)
        }
    }
}

/// jar 源的显式降级实现：所有方法立即返回 unsupportedJar，
/// UI 层据此展示「该站点在当前平台不可用」，而不是给出空列表让用户误以为没内容。
final class UnsupportedSiteProvider: SiteProvider {
    let site: SiteConfig
    init(site: SiteConfig) { self.site = site }

    func home(completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        completion(.failure(.unsupportedJar(site.displayName)))
    }
    func category(id: String, page: Int, extend: [String: String], completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        completion(.failure(.unsupportedJar(site.displayName)))
    }
    func categories(completion: @escaping (Result<[SiteCategory], SiteError>) -> Void) {
        completion(.failure(.unsupportedJar(site.displayName)))
    }
    func detail(id: String, completion: @escaping (Result<VodDetail, SiteError>) -> Void) {
        completion(.failure(.unsupportedJar(site.displayName)))
    }
    func search(keyword: String, page: Int, completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        completion(.failure(.unsupportedJar(site.displayName)))
    }
    func play(flag: String, url: String, completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        completion(.failure(.unsupportedJar(site.displayName)))
    }
}

/// 站点级缓存：分类、首页、详情。
/// 关键约束：配置切换后必须整体失效（ConfigRepository.store 里已调用 clearAll）。
final class SiteCache {
    static let shared = SiteCache()
    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    func value<T>(_ key: String, as type: T.Type) -> T? {
        lock.lock(); defer { lock.unlock() }
        return storage[key] as? T
    }

    func set(_ key: String, _ value: Any) {
        lock.lock(); storage[key] = value; lock.unlock()
    }

    func clearAll() {
        lock.lock(); storage.removeAll(); lock.unlock()
    }

    func clear(prefix: String) {
        lock.lock()
        storage = storage.filter { !$0.key.hasPrefix(prefix) }
        lock.unlock()
    }
}
