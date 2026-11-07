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
enum SiteError: Error, LocalizedError {
    case unsupportedJar(String)
    case network(Int)
    case parse(String)
    case empty
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedJar(let site):
            return "「\(site)」使用 jar 爬虫规则，iOS 无 Java 运行环境，该站点在当前平台不可用"
        case .network(let status): return "网络请求失败（HTTP \(status)）"
        case .parse(let detail): return "页面解析失败：\(detail)"
        case .empty: return "没有数据"
        case .cancelled: return "已取消"
        }
    }
}

/// Provider 工厂：按站点类型路由。jar 判定优先于 type，
/// 因为不少配置里 jar 与 api 并存，只要有 jar 就必须走 spider 路径。
enum SiteProviderFactory {
    static func make(site: SiteConfig) -> SiteProvider {
        if site.isJarSpider {
            return UnsupportedSiteProvider(site: site)
        }
        switch site.type {
        case 1:
            return APISiteProvider(site: site)
        case 3:
            // type=3 但无 jar：规则以 api 指向的 .js 脚本形式提供，走 JS 引擎。
            return JSSiteProvider(site: site)
        default:
            if !site.api.isEmpty && (site.api.hasPrefix("http") || site.api.hasPrefix("csp_")) {
                // TVBox 系里 csp_ 前缀的 api 表示 JSON 接口源。
                if site.api.hasPrefix("csp_") { return APISiteProvider(site: site) }
            }
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
