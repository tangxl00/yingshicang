import Foundation
import SwiftSoup

/// HTML 规则站点（type=0）。这是配置生态里最常见的类型：
/// 站点用 `url` / `searchUrl` 模板拼地址，用「一级/二级/搜索」三段规则抓页面。
///
/// 规则串语义来自 APK 内置 `模板.js`（12 个采集站模板），例如：
///   一级: 'ul.vodlist li;a&&title;a&&data-original;.pic_text&&Text;a&&href'
///   搜索: '*'
///   二级: { title:'h2&&Text;.content_detail:eq(1)&&li&&a:eq(2)&&Text', ... lists:'.content_playlist:eq(#id) li' }
/// 其中 `:eq(#id)` 是「按线路序号取第 id 组」，不是 CSS 的 eq，需单独展开。
final class HTMLSiteProvider: SiteProvider {
    let site: SiteConfig

    init(site: SiteConfig) { self.site = site }

    private var baseHost: String {
        if !site.host.isEmpty { return site.host }
        if !site.api.isEmpty { return site.api }
        return ""
    }

    // MARK: - 首页

    func home(completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        let key = "home|\(site.key)"
        if let cached = SiteCache.shared.value(key, as: [VodItem].self) {
            completion(.success(cached)); return
        }
        // 推荐规则为空时，退回一级规则抓首页列表。
        let rule = site.ruleRecommend.isEmpty ? site.ruleHome : site.ruleRecommend
        guard !rule.isEmpty, !baseHost.isEmpty else {
            completion(.success([])); return
        }
        let url = baseHost
        HTTPClient.shared.request(url, options: options()) { [weak self] response in
            guard let self = self else { return }
            guard response.ok else { completion(.failure(.from(response))); return }
            let items = self.parseList(response.content, rule: rule)
            SiteCache.shared.set(key, items)
            completion(.success(items))
        }
    }

    // MARK: - 分类

    func categories(completion: @escaping (Result<[SiteCategory], SiteError>) -> Void) {
        let key = "cats|\(site.key)"
        if let cached = SiteCache.shared.value(key, as: [SiteCategory].self) {
            completion(.success(cached)); return
        }
        // 直接给定分类（class_name / class_url）优先，免解析。
        if !site.className.isEmpty {
            let names = splitGrouped(site.className)
            let urls = splitGrouped(site.classUrl)
            var result: [SiteCategory] = []
            for (index, name) in names.enumerated() {
                let id = index < urls.count ? urls[index] : "\(index + 1)"
                result.append(SiteCategory(id: id, name: name))
            }
            SiteCache.shared.set(key, result)
            completion(.success(result)); return
        }
        guard !site.classParse.isEmpty, !baseHost.isEmpty else {
            completion(.success([])); return
        }
        // class_parse: '选择器;名称;链接;正则' —— 四段式。
        let fields = HTMLRule.splitFields(site.classParse)
        guard fields.count >= 3 else {
            completion(.success([])); return
        }
        HTTPClient.shared.request(baseHost, options: options()) { [weak self] response in
            guard let self = self else { return }
            guard response.ok else { completion(.failure(.from(response))); return }
            let result = self.parseCategories(response.content,
                                              selector: fields[0],
                                              nameRule: fields[1],
                                              linkRule: fields[2],
                                              regex: fields.count > 3 ? fields[3] : "")
            SiteCache.shared.set(key, result)
            completion(.success(result))
        }
    }

    func category(id: String, page: Int, extend: [String: String],
                  completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        guard !site.url.isEmpty else {
            completion(.success([])); return
        }
        var path = site.url
            .replacingOccurrences(of: "fyclass", with: id)
            .replacingOccurrences(of: "fypage", with: "\(page)")
        // 筛选参数拼接：filter_url 模板里带 fyfilter 占位时替换，否则直接追加查询串。
        if !extend.isEmpty {
            let extendString = extend
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
            if site.filterUrl.contains("fyfilter") {
                path = site.filterUrl
                    .replacingOccurrences(of: "fyclass", with: id)
                    .replacingOccurrences(of: "fypage", with: "\(page)")
                    .replacingOccurrences(of: "fyfilter", with: extendString)
            } else {
                path += (path.contains("?") ? "&" : "?") + extendString
            }
        }
        let url = absolute(path)
        let rule = site.ruleHome
        guard !rule.isEmpty else {
            completion(.success([])); return
        }
        HTTPClient.shared.request(url, options: options()) { [weak self] response in
            guard let self = self else { return }
            guard response.ok else { completion(.failure(.from(response))); return }
            completion(.success(self.parseList(response.content, rule: rule)))
        }
    }

    // MARK: - 详情

    func detail(id: String, completion: @escaping (Result<VodDetail, SiteError>) -> Void) {
        let key = "detail|\(site.key)|\(id)"
        if let cached = SiteCache.shared.value(key, as: VodDetail.self) {
            completion(.success(cached)); return
        }
        let url = detailURL(for: id)
        HTTPClient.shared.request(url, options: options()) { [weak self] response in
            guard let self = self else { return }
            guard response.ok else { completion(.failure(.from(response))); return }
            let detail = self.parseDetail(response.content, id: id)
            SiteCache.shared.set(key, detail)
            completion(.success(detail))
        }
    }

    // MARK: - 搜索

    func search(keyword: String, page: Int, completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        guard !site.searchUrl.isEmpty else {
            completion(.success([])); return
        }
        let path = site.searchUrl
            .replacingOccurrences(of: "**", with: keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)
            .replacingOccurrences(of: "fypage", with: "\(page)")
        let rule = site.ruleSearch
        // 模板里搜索规则常写 '*'，表示「结果结构与一级列表相同」。
        let effectiveRule = (rule.isEmpty || rule == "*") ? site.ruleHome : rule
        guard !effectiveRule.isEmpty else {
            completion(.success([])); return
        }
        HTTPClient.shared.request(absolute(path), options: options()) { [weak self] response in
            guard let self = self else { return }
            guard response.ok else { completion(.failure(.from(response))); return }
            completion(.success(self.parseList(response.content, rule: effectiveRule)))
        }
    }

    // MARK: - 播放解析

    /// HTML 源在本类只做「分类」：直链直接放行，非直链标记需要嗅探。
    ///
    /// lazy 规则不在这里执行——三类源统一由 `PlayResolver` 在调本方法之前处理，
    /// 避免 lazy 被执行两次（质检 P1-6 的收口点）。
    func play(flag: String, url: String, completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        if let direct = PlayURLClassifier.directMediaURL(url) {
            completion(.success(PlayResolution(url: direct, parseIndex: nil, needSniff: false)))
            return
        }
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(.parse("剧集地址为空")))
            return
        }
        completion(.success(PlayResolution(url: url, parseIndex: nil, needSniff: true)))
    }

    // MARK: - 内部：列表解析

    private func parseList(_ html: String, rule: String) -> [VodItem] {
        guard let doc = HTMLSelector.shared.parse(html) else { return [] }
        // 五段式：选择器;标题;图片;备注;链接
        let fields = HTMLRule.splitFields(rule)
        guard let itemSelector = fields.first, !itemSelector.isEmpty else { return [] }

        var items: [VodItem] = []
        // 「区块样式」规则（double=true 或选择器带 `*`）需要先取容器再取项，
        // 这里统一按「先按 itemSelector 取容器，再逐容器取子项」的通用路径。
        let containers = (try? doc.select(itemSelector).array())?.map { HTMLElementNode(element: $0) } ?? []
        guard !containers.isEmpty else { return [] }

        for container in containers {
            let name = fieldValue(fields, at: 1, in: container)
            let pic = fieldValue(fields, at: 2, in: container)
            let remark = fieldValue(fields, at: 3, in: container)
            let link = fieldValue(fields, at: 4, in: container)
            let name2 = fieldValue(fields, at: 5, in: container)
            let displayName = name.isEmpty ? name2 : name
            guard !displayName.isEmpty || !link.isEmpty else { continue }
            let vodId = extractVodId(link)
            items.append(VodItem(vodId: vodId,
                                 vodName: displayName,
                                 vodPic: absolute(pic),
                                 vodRemarks: remark,
                                 siteKey: site.key))
        }
        return items
    }

    /// 在单个容器上取某一段规则的值。`*` 表示「容器自身」，其余按选择器下钻。
    private func fieldValue(_ fields: [String], at index: Int, in container: HTMLElementNode) -> String {
        guard index < fields.count else { return "" }
        var rule = fields[index].trimmingCharacters(in: .whitespaces)
        guard !rule.isEmpty else { return "" }
        if rule == "*" {
            return container.text
        }
        // 常见的 `a&&title` 形式：先在本容器里找 a，再取 title 属性。
        let steps = HTMLRule.splitChain(rule)
        var nodes = [container]
        for (i, step) in steps.enumerated() {
            let isLast = i == steps.count - 1
            if isLast && HTMLRule.looksLikeAttribute(step) && !step.contains("*") {
                guard let first = nodes.first else { return "" }
                if HTMLRule.isTextToken(step) { return first.text }
                if HTMLRule.isHtmlToken(step) { return first.html }
                return first.attrAny(attributeAliases(step))
            }
            var next: [HTMLElementNode] = []
            for node in nodes {
                if let matched = try? node.element.select(step) {
                    next.append(contentsOf: matched.array().map { HTMLElementNode(element: $0) })
                }
            }
            nodes = next
            if nodes.isEmpty { return "" }
            if isLast {
                let first = nodes[0]
                return first.text.isEmpty ? first.attr("href") : first.text
            }
        }
        return nodes.first?.text ?? ""
    }

    private func attributeAliases(_ name: String) -> [String] {
        switch name.lowercased() {
        case "src": return ["src", "data-src", "data-original", "data-echo", "data-lazy-src"]
        case "href": return ["href", "data-href"]
        default: return [name]
        }
    }

    // MARK: - 内部：分类解析

    private func parseCategories(_ html: String, selector: String, nameRule: String,
                                 linkRule: String, regex: String) -> [SiteCategory] {
        guard let doc = HTMLSelector.shared.parse(html) else { return [] }
        guard let containers = try? doc.select(selector).array() else { return [] }
        var result: [SiteCategory] = []
        for element in containers {
            let node = HTMLElementNode(element: element)
            let name: String
            if nameRule.isEmpty || nameRule == "*" { name = node.text }
            else { name = HTMLSelector.shared.pdfh(node.outerHtml.isEmpty ? node.html : node.html, nameRule) }
            var link: String
            if linkRule.isEmpty || linkRule == "*" { link = node.attr("href") }
            else { link = HTMLSelector.shared.pdfh(node.html, linkRule) }
            if link.isEmpty { link = node.attr("href") }
            let id = applyRegex(link, pattern: regex)
            if name.isEmpty && id.isEmpty { continue }
            result.append(SiteCategory(id: id.isEmpty ? name : id, name: name))
        }
        return result
    }

    /// 规则末段的 `.*/(.*?)/` 这类是「从链接里正则捕获分类 id」。
    private func applyRegex(_ value: String, pattern: String) -> String {
        guard !pattern.isEmpty, !value.isEmpty else { return value }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: value) else { return value }
        return String(value[captured])
    }

    // MARK: - 内部：详情解析

    private func parseDetail(_ html: String, id: String) -> VodDetail {
        let rule = site.ruleDetail
        let detail = DetailRule(raw: rule)

        var result = VodDetail(vodId: id, vodName: "", vodPic: "", vodContent: "",
                               vodScore: "", vodYear: "", vodArea: "", vodType: "",
                               vodRemarks: "", siteKey: site.key,
                               tabs: [], lists: [], quality: [])
        result.vodName = HTMLSelector.shared.pdfh(html, detail.title)
        result.vodPic = absolute(HTMLSelector.shared.pdfh(html, detail.img))
        result.vodContent = HTMLSelector.shared.pdfh(html, detail.content)
        result.vodScore = HTMLSelector.shared.pdfh(html, detail.score)
        result.vodYear = HTMLSelector.shared.pdfh(html, detail.year)
        result.vodArea = HTMLSelector.shared.pdfh(html, detail.area)
        result.vodType = HTMLSelector.shared.pdfh(html, detail.type)

        // 线路名（tabs）：规则给的是「选择器 + 取值」两段，例如 '.play_source_tab&&a'
        let tabValues = HTMLSelector.shared.pdfa(html, detail.tabs)
        result.tabs = tabValues.filter { !$0.isEmpty }
        if result.tabs.isEmpty { result.tabs = ["线路1"] }

        // 剧集：`lists` 里的 `:eq(#id)` 需要按线路序号逐个展开。
        result.lists = parseEpisodeLists(html: html, listsRule: detail.lists, tabCount: max(result.tabs.count, 1))

        if result.vodName.isEmpty {
            // 详情页取不到片名时用 id 兜底，避免收藏/历史里出现空标题。
            result.vodName = id
        }
        return result
    }

    /// 剧集列表解析：`lists` 规则里若含 `:eq(#id)`，把 `#id` 依次替换为 0..<tabCount 再解析。
    private func parseEpisodeLists(html: String, listsRule: String, tabCount: Int) -> [[PlayEpisode]] {
        guard !listsRule.isEmpty else { return [] }
        var output: [[PlayEpisode]] = []
        if listsRule.contains("#id") {
            for index in 0..<tabCount {
                let rule = listsRule.replacingOccurrences(of: "#id", with: "\(index)")
                let episodes = parseEpisodes(html, rule: rule)
                output.append(episodes)
            }
            // 某些站点的播放列表统一在一个容器里，`:eq` 越界会返回空；
            // 若只有第一组有数据，把空组补成第一组，避免线路切换后颗粒无收。
            if output.filter({ !$0.isEmpty }).count == 1, let first = output.first(where: { !$0.isEmpty }) {
                output = output.map { $0.isEmpty ? first : $0 }
            }
            return output
        }
        // 无 #id：整体一组。
        let episodes = parseEpisodes(html, rule: listsRule)
        if !episodes.isEmpty { output = [episodes] }
        return output
    }

    /// 剧集项：`名称$地址#名称$地址` 或选择器 + `a&&Text;a&&href` 两段式。
    private func parseEpisodes(_ html: String, rule: String) -> [PlayEpisode] {
        guard let doc = HTMLSelector.shared.parse(html) else { return [] }
        // 形态一：标准 brvah 站点的「选择器;文本;链接」
        let fields = HTMLRule.splitFields(rule)
        if fields.count >= 3 {
            let selector = fields[0]
            guard let elements = try? doc.select(selector).array(), !elements.isEmpty else { return [] }
            var episodes: [PlayEpisode] = []
            for element in elements {
                let node = HTMLElementNode(element: element)
                let name = fieldValue(fields, at: 1, in: node)
                let link = fieldValue(fields, at: 2, in: node)
                if name.isEmpty && link.isEmpty { continue }
                episodes.append(PlayEpisode(name: name.isEmpty ? "第\(episodes.count + 1)集" : name,
                                            url: cleanPlayURL(link)))
            }
            return episodes
        }
        // 形态二：选择器只给容器，容器文本里是 `名称$地址#...` 的串。
        guard let containers = try? doc.select(fields.first ?? "").array() else { return [] }
        var episodes: [PlayEpisode] = []
        for element in containers {
            let text = (try? element.text()) ?? ""
            for part in text.split(separator: "#") {
                let pieces = part.split(separator: "$")
                guard pieces.count >= 2 else { continue }
                let name = String(pieces[0]).trimmingCharacters(in: .whitespaces)
                let url = String(pieces[1]).trimmingCharacters(in: .whitespaces)
                episodes.append(PlayEpisode(name: name, url: url))
            }
        }
        return episodes
    }

    /// 剧集地址常带 `m3u8://` / `mp4://` 这类自定义 scheme 前缀（用于标记类型），
    /// 播放前需要剥掉；也常是相对地址。
    private func cleanPlayURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["m3u8://", "mp4://", "m3u8:", "mp4:"] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        return absolute(value)
    }

    // MARK: - 内部：地址工具

    private func absolute(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.hasPrefix("//") {
            let base = baseHost
            if let scheme = URL(string: base)?.scheme { return "\(scheme):\(trimmed)" }
            return "http:\(trimmed)"
        }
        guard !baseHost.isEmpty, let baseURL = URL(string: baseHost) else { return trimmed }
        if trimmed.hasPrefix("/") {
            let root = "\(baseURL.scheme ?? "http")://\(baseURL.host ?? "")"
            return root + trimmed
        }
        return baseURL.appendingRulePath(trimmed).absoluteString
    }

    private func detailURL(for id: String) -> String {
        if !site.detailUrl.isEmpty {
            return absolute(site.detailUrl.replacingOccurrences(of: "fyid", with: id))
        }
        // 没有 detailUrl 模板时，把 id 当相对路径拼到 host 上。
        if id.hasPrefix("http") { return id }
        return absolute(id)
    }

    /// 从详情链接里取 vod id：模板里常是 `/detail/12345.html` 或 `?id=12345`。
    private func extractVodId(_ link: String) -> String {
        guard !link.isEmpty else { return "" }
        if let regex = try? NSRegularExpression(pattern: "(?:\\.|/)([0-9]{2,})[^0-9]*(?:$|\\?)") {
            let range = NSRange(link.startIndex..., in: link)
            if let match = regex.firstMatch(in: link, range: range),
               let captured = Range(match.range(at: 1), in: link) {
                return String(link[captured])
            }
        }
        return link
    }

    private func options() -> HTTPOptions {
        var opts = HTTPOptions()
        opts.headers = site.headers
        if site.timeout > 0 { opts.timeout = TimeInterval(min(site.timeout, 60)) }
        return opts
    }

    /// 解析 `class_name` / `class_url` 这类「&& 分隔」的成组字符串。
    private func splitGrouped(_ raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        if raw.contains("&&") { return raw.components(separatedBy: "&&").filter { !$0.isEmpty } }
        if raw.contains(";") { return raw.components(separatedBy: ";").filter { !$0.isEmpty } }
        return [raw]
    }
}
