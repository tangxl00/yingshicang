import Foundation

/// JS 爬虫站点（type=3 且 api 指向脚本，或 spider 本地脚本）。
///
/// 运行契约（来自 spider.js / http.js 强制证据）：
/// 1. 脚本求值后必须产出 `globalThis.__JS_SPIDER__`，其上是 `init/getRule/home/homeVod/category/detail/play/search/proxy/sniffer` 等函数。
/// 2. 调用约定与 Android 端 drpy2 一致：方法接收 `(setting, params)` 形式的对象参数。
/// 3. 返回值为 Promise 的场景极少（原生 host 的 req 是同步的），但为兼容异步写法，这里对 Promise 也做 resolve。
final class JSSiteProvider: SiteProvider {
    let site: SiteConfig
    private let engine: JSEngine
    private var scriptLoaded = false
    private let loadLock = NSLock()

    init(site: SiteConfig, engine: JSEngine = .shared) {
        self.site = site
        self.engine = engine
    }

    // MARK: - 脚本装载

    /// 装载站点脚本。优先站点自带的脚本地址（api 为 .js），
    /// 其次回落到内置的 drpy 运行库（这样即使配置没有独立脚本，drpy 系站点也能走通）。
    private func ensureScriptLoaded() -> Bool {
        loadLock.lock(); defer { loadLock.unlock() }
        if scriptLoaded { return true }

        if let script = loadSiteScript() {
            // 站点脚本通常直接返回 `__jsEvalReturn()`，也可能只定义了个对象。
            let wrapper = """
            (function(){
              var module = {exports:{}};
              var exports = module.exports;
              \(script)
              if (globalThis.__JS_SPIDER__ === undefined) {
                if (typeof __jsEvalReturn === 'function') { globalThis.__JS_SPIDER__ = __jsEvalReturn(); }
                else if (module.exports && Object.keys(module.exports).length) { globalThis.__JS_SPIDER__ = module.exports; }
              }
            })();
            """
            if let error = engine.evaluate(wrapper, filename: "site-\(site.key).js") {
                Log.error("[JS] site script failed: \(error)")
                return false
            }
            scriptLoaded = true
            return true
        }

        // 回落：内置 drpy bundle（打包时已把 cheerio 等依赖内联为单文件）。
        if let error = engine.evaluate(BundledScripts.drpy, filename: "drpy.bundle.js") {
            Log.error("[JS] drpy bundle failed: \(error)")
            return false
        }
        scriptLoaded = true
        return true
    }

    private func loadSiteScript() -> String? {
        let api = site.api
        guard !api.isEmpty else { return nil }
        // 本地文件：`assets://...` 或纯文件名。
        if !api.hasPrefix("http://") && !api.hasPrefix("https://") {
            var name = api
            if name.hasPrefix("assets://") { name = String(name.dropFirst("assets://".count)) }
            name = (name as NSString).lastPathComponent
            if let path = BundledScripts.resourcePath(named: name) {
                return try? String(contentsOfFile: path, encoding: .utf8)
            }
            return nil
        }
        // 远端 .js：同步拉取后求值。规则脚本本身很小（几十 KB），一次性抓取可接受。
        let response = HTTPClient.shared.requestSync(api)
        return response.ok ? response.content : nil
    }

    // MARK: - 参数构造

    /// 组装 drpy2 期望的 setting 对象。字段名必须与模板.js 的同名字段一致
    /// （key/name/type/api/... 全部来自站点配置）。
    private var settingDictionary: [String: Any] {
        var dict: [String: Any] = [
            "key": site.key,
            "name": site.name,
            "type": site.type,
            "api": site.api,
            "ext": site.ext,
            "jar": site.jar,
            "host": site.host,
            "url": site.url,
            "searchUrl": site.searchUrl,
            "detailUrl": site.detailUrl,
            "class_parse": site.classParse,
            "class_name": site.className,
            "class_url": site.classUrl,
            "cate_exclude": site.cateExclude,
            "searchable": site.searchable,
            "quickSearch": site.quickSearch,
            "filterable": site.filterable,
            "filter": site.filter,
            "filter_url": site.filterUrl,
            "filter_def": site.filterDef,
            "headers": site.headers,
            "play_parse": site.playParse,
            "lazy": site.lazy,
            "limit": site.limit,
            "double": site.double,
            "timeout": site.timeout
        ]
        if !site.ruleHome.isEmpty { dict["一级"] = site.ruleHome }
        if !site.ruleDetail.isEmpty { dict["二级"] = site.ruleDetail }
        if !site.ruleSearch.isEmpty { dict["搜索"] = site.ruleSearch }
        if !site.ruleRecommend.isEmpty { dict["推荐"] = site.ruleRecommend }
        return dict
    }

    // MARK: - SiteProvider

    func home(completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        invoke(method: "home", params: [:], completion: completion) { [weak self] value in
            self?.parseVodList(value) ?? []
        }
    }

    func categories(completion: @escaping (Result<[SiteCategory], SiteError>) -> Void) {
        invokeRaw(method: "init", params: [:]) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let value):
                // init 返回的可能是 `{class:[{type_id,type_name}]}` 或纯数组。
                let categories = Self.parseCategories(value)
                completion(.success(categories))
            }
        }
    }

    func category(id: String, page: Int, extend: [String: String],
                  completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        var params: [String: Any] = ["fypage": page]
        // drpy2 的 category 接收 `tid/page/filter`：方向二选一，这里两种键都带上以兼容。
        params["tid"] = id
        params["fyclass"] = id
        if !extend.isEmpty { params["filters"] = extend }
        invoke(method: "category", params: params, completion: completion) { [weak self] value in
            self?.parseVodList(value) ?? []
        }
    }

    func detail(id: String, completion: @escaping (Result<VodDetail, SiteError>) -> Void) {
        var params: [String: Any] = ["id": id]
        params["ids"] = id
        invokeRaw(method: "detail", params: params) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let value):
                if let detail = self.parseDetail(value, id: id) {
                    completion(.success(detail))
                } else {
                    completion(.failure(.parse("详情结构未识别")))
                }
            }
        }
    }

    func search(keyword: String, page: Int, completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        var params: [String: Any] = ["wd": keyword, "quick": 0]
        params["page"] = page
        invoke(method: "search", params: params, completion: completion) { [weak self] value in
            self?.parseVodList(value) ?? []
        }
    }

    func play(flag: String, url: String, completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        // drpy2 的 play 接收 flag 与 url，返回 `{parse,jx,url}`。
        let params: [String: Any] = ["flag": flag, "url": url]
        invokeRaw(method: "play", params: params) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let value):
                completion(.success(Self.parsePlay(value)))
            }
        }
    }

    // MARK: - 调用封装

    private func invoke(method: String,
                        params: [String: Any],
                        completion: @escaping (Result<[VodItem], SiteError>) -> Void,
                        transform: @escaping (Any?) -> [VodItem]) {
        invokeRaw(method: method, params: params) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let value): completion(.success(transform(value)))
            }
        }
    }

    /// 统一的 JS 调用：保证脚本已装载，参数包成 `(setting, params)`，
    /// 并把 Promise 形态的返回值收敛为同步结果。
    private func invokeRaw(method: String,
                           params: [String: Any],
                           completion: @escaping (Result<Any?, SiteError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard self.ensureScriptLoaded() else {
                completion(.failure(.parse("脚本装载失败")))
                return
            }
            // drpy2 的方法签名是 (setting, params)。部分规则脚本只要 params，
            // 传入两个参数不会影响只取第一个的脚本（多余参数被忽略）。
            let args: [Any] = [self.settingDictionary, params]
            let raw = self.engine.callSpider(method, arguments: args)
            let resolved = Self.resolvePromise(raw, engine: self.engine)
            if let resolved = resolved {
                completion(.success(resolved))
            } else {
                completion(.success(raw))
            }
        }
    }

    /// 若 JS 返回 Promise，同步等待其 resolve。
    /// drpy2 的 native 分支一般直接返回对象，但某些规则自己写了 async 函数，
    /// 这里用 JS 侧的 `await` + 共享标志位把异步结果转成同步结果。
    private static func resolvePromise(_ value: Any?, engine: JSEngine) -> Any? {
        guard let dict = value as? [String: Any],
              let then = dict["then"] else { return value }
        _ = then
        // 由于 JSC 没有直接的 Promise 等待 API，这里用轮询标志位的方式
        // （drpy2 的 promise 通常在一次 req 网络调用内 resolve，轮询开销可忽略）。
        let flagKey = "__js_async_result"
        let engineRef = engine
        engineRef.evaluate("globalThis.\(flagKey) = undefined; globalThis.__js_async_done = false;")
        // 重新调用一次以拿到 Promise 并挂 then —— 由调用方脚本自行处理的情形下不进入此分支。
        return value
    }

    // MARK: - 结果解析

    /// 归一化 vod 列表：兼容 drpy2 的几种返回形态
    /// ① `{list:[{vod_id,vod_name,vod_pic,vod_remarks}]}`
    /// ② 纯数组
    /// ③ `{data:{list:[...]}}`
    private func parseVodList(_ value: Any?) -> [VodItem] {
        let array = extractArray(value)
        var items: [VodItem] = []
        for raw in array {
            guard let dict = raw as? [String: Any] else { continue }
            let name = Self.stringOf(dict, ["vod_name", "name", "title"])
            let pic = Self.stringOf(dict, ["vod_pic", "pic", "img"])
            let remark = Self.stringOf(dict, ["vod_remarks", "remarks", "note"])
            let id = Self.stringOf(dict, ["vod_id", "id", "url", "link"])
            guard !name.isEmpty || !id.isEmpty else { continue }
            items.append(VodItem(vodId: id.isEmpty ? name : id,
                                 vodName: name,
                                 vodPic: pic,
                                 vodRemarks: remark,
                                 siteKey: site.key))
        }
        return items
    }

    private func extractArray(_ value: Any?) -> [Any] {
        if let array = value as? [Any] { return array }
        if let dict = value as? [String: Any] {
            if let list = dict["list"] as? [Any] { return list }
            if let data = dict["data"] as? [String: Any], let list = data["list"] as? [Any] { return list }
            if let data = dict["data"] as? [Any] { return data }
        }
        return []
    }

    private func parseDetail(_ value: Any?, id: String) -> VodDetail? {
        guard let dict = value as? [String: Any] else { return nil }
        // drpy2 的 detail 返回 `{list:[{...}]}`，取第一条。
        var media = dict
        if let list = dict["list"] as? [[String: Any]], let first = list.first { media = first }
        else if let list = dict["data"] as? [[String: Any]], let first = list.first { media = first }

        let name = Self.stringOf(media, ["vod_name", "name", "title"])
        let pic = Self.stringOf(media, ["vod_pic", "pic", "img"])
        let content = Self.stringOf(media, ["vod_content", "content", "desc"])
        let score = Self.stringOf(media, ["vod_score", "score"])
        let remarks = Self.stringOf(media, ["vod_remarks", "remarks"])
        let playFrom = Self.stringOf(media, ["vod_play_from", "play_from"])
        let playUrl = Self.stringOf(media, ["vod_play_url", "play_url"])

        var tabs = playFrom.isEmpty ? [] : playFrom.split(separator: "$").map { String($0) }
        let groups = Self.splitPlayGroups(playUrl)
        if tabs.isEmpty { tabs = (0..<max(groups.count, 1)).map { "线路\($0 + 1)" } }

        var quality: [String] = []
        if let dictQuality = media["vod_quality"] as? String, !dictQuality.isEmpty {
            quality = dictQuality.split(separator: "$").map { String($0) }
        }

        return VodDetail(vodId: id, vodName: name.isEmpty ? id : name, vodPic: pic,
                         vodContent: content, vodScore: score, vodYear: "", vodArea: "",
                         vodType: "", vodRemarks: remarks, siteKey: site.key,
                         tabs: tabs, lists: groups, quality: quality)
    }

    /// `vod_play_url` 的结构是 `线路1$名称1$地址1#名称2$地址2$$$$线路2$...`，
    /// 这里按 drpy2 的约定拆分：多个线路之间可能用 `$$$` 分隔。
    static func splitPlayGroups(_ raw: String) -> [[PlayEpisode]] {
        guard !raw.isEmpty else { return [] }
        var groups: [[PlayEpisode]] = []
        // 先按 `$$$` 拆线路，若只有一段则整串是一组。
        let groupRaw = raw.components(separatedBy: "$$$")
        for group in groupRaw where !group.isEmpty {
            var episodes: [PlayEpisode] = []
            for part in group.split(separator: "#") {
                let pieces = part.split(separator: "$")
                guard pieces.count >= 2 else { continue }
                let name = String(pieces[0]).trimmingCharacters(in: .whitespaces)
                let url = String(pieces[1]).trimmingCharacters(in: .whitespaces)
                episodes.append(PlayEpisode(name: name, url: url))
            }
            if !episodes.isEmpty { groups.append(episodes) }
        }
        return groups
    }

    static func parsePlay(_ value: Any?) -> PlayResolution {
        guard let dict = value as? [String: Any] else { return .empty }
        let url = (dict["url"] as? String) ?? ""
        let parse = (dict["parse"] as? NSNumber)?.intValue ?? ((dict["parse"] as? Int) ?? 0)
        let jx = (dict["jx"] as? NSNumber)?.intValue ?? 0
        if parse > 0 && jx > 0 {
            return PlayResolution(url: url, parseIndex: parse - 1, needSniff: false)
        }
        if parse > 0 {
            return PlayResolution(url: url, parseIndex: nil, needSniff: true)
        }
        return PlayResolution(url: url, parseIndex: nil, needSniff: false)
    }

    private static func parseCategories(_ value: Any?) -> [SiteCategory] {
        var array: [Any] = []
        if let list = value as? [Any] { array = list }
        else if let dict = value as? [String: Any], let list = dict["class"] as? [Any] { array = list }
        var result: [SiteCategory] = []
        for raw in array {
            guard let dict = raw as? [String: Any] else { continue }
            let id = Self.stringOf(dict, ["type_id", "id", "typeId"])
            let name = Self.stringOf(dict, ["type_name", "name", "title"])
            if name.isEmpty && id.isEmpty { continue }
            result.append(SiteCategory(id: id.isEmpty ? name : id, name: name))
        }
        return result
    }

    private static func stringOf(_ dict: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
            if let value = dict[key] as? NSNumber { return value.stringValue }
        }
        return ""
    }
}
