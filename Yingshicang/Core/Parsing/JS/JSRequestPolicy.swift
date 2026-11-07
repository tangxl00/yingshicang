import Foundation

/// JS 桥 `req` 的请求准入策略（质检 P1-5）。
///
/// 恶意/被篡改的规则源可以通过 `req` 做两件事：探测内网地址、跨站读取数据。
/// 因此在把请求交给 `URLSession` 之前先过一遍准入判定：
/// 1. **协议白名单**：只允许 `http` / `https`；`file:`、`data:`、`javascript:`、`ftp:`、`about:` 一律拒绝
///    （`file:` 直接被 `URLSession` 支持，是最容易被用来读沙箱/系统文件的入口）。
/// 2. **内网/回环屏蔽**：`localhost`、`127.x`、`10.x`、`192.168.x`、`169.254.x`、`172.16-31.x`
///    默认拒绝，只有站点白名单显式包含该 host 时才放行（用于局域网自建接口场景）。
/// 3. **站点域白名单**：站点配置里能推导出的 host（`host` / `api` / `url`）构成白名单，
///    同注册域（`api.example.com` 与 `www.example.com`）视为同站放行；
///    无关第三方域拒绝，避免一个站点规则读别的站点/CDN 之外的任意数据。
///    配置里推导不出 host 时（大量采集站如此）退化为「允许任意公网 host，但仍受第 1、2 条约束」。
struct JSRequestPolicy: Equatable {
    /// 允许访问的域（小写，不含端口）。空集合表示「不限制公网 host」（内网仍禁）。
    var allowedHosts: Set<String>

    init(allowedHosts: Set<String> = []) {
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
    }

    /// 从站点配置推导白名单域。`host` 字段有时是裸域（无 scheme），也要能识别出来。
    static func allowedHosts(for site: SiteConfig) -> Set<String> {
        var hosts: Set<String> = []
        for raw in [site.host, site.api, site.url] {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let absolute = value.contains("://") ? value : "http://" + value
            if let host = URL(string: absolute)?.host?.lowercased(), !host.isEmpty, host.contains(".") {
                hosts.insert(host)
            }
        }
        return hosts
    }

    /// 准入判定。返回 true 表示允许发起请求。
    func allows(_ rawURL: String) -> Bool {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // 1. 协议前缀先行判定：`normalize` 会给无 scheme 的串补 `http://`，
        //    所以必须在归一化之前拦掉危险 scheme，否则 `data:` 会被补成 `http://data:...` 绕过检查。
        let lowered = trimmed.lowercased()
        let bannedSchemes = ["file:", "data:", "javascript:", "vbscript:", "about:", "ftp:", "blob:", "chrome:", "phar:"]
        for scheme in bannedSchemes where lowered.hasPrefix(scheme) { return false }

        guard let normalized = HTTPClient.normalize(trimmed),
              let scheme = normalized.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = normalized.host?.lowercased(), !host.isEmpty else {
            return false
        }

        // 2. 内网 / 回环：默认拒绝，白名单显式包含才放行。
        if Self.isPrivateOrLoopback(host) {
            return containsHost(host)
        }

        // 3. 站点域白名单：配置能推导出 host 时做域限制；推导不出时只做公网约束。
        if allowedHosts.isEmpty { return true }
        return containsHost(host)
    }

    /// 白名单匹配：精确命中、子域命中、或同注册域命中。
    func containsHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if allowedHosts.contains(h) { return true }
        for allowed in allowedHosts {
            if h.hasSuffix("." + allowed) || allowed.hasSuffix("." + h) { return true }
            if Self.registrableSuffix(h) == Self.registrableSuffix(allowed) { return true }
        }
        return false
    }

    /// 取最后两级标签（`api.example.com` → `example.com`）。
    /// 不做完整 eTLD+1 判定（需要 Public Suffix List），这个粒度足够挡住跨站读取。
    static func registrableSuffix(_ host: String) -> String {
        let labels = host.lowercased().split(separator: ".")
        guard labels.count >= 2 else { return host.lowercased() }
        return labels.suffix(2).joined(separator: ".")
    }

    /// 内网/回环地址判定（够用即可：不做完整 IP 解析，按网段前缀识别）。
    static func isPrivateOrLoopback(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h == "::1" || h == "0.0.0.0" { return true }
        if h.hasPrefix("127.") { return true }
        if h.hasPrefix("10.") { return true }
        if h.hasPrefix("192.168.") { return true }
        if h.hasPrefix("169.254.") { return true }
        if h.hasPrefix("172.") {
            let parts = h.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) { return true }
        }
        return false
    }
}
