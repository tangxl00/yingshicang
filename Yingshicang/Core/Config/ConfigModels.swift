import Foundation

/// 站点对象。字段集合取自 APK 内置 `assets/js/lib/模板.js`（12 个采集站模板）与
/// `spider.js` 的实际取值，是该配置格式的强制证据（见需求文档 4.2）。
///
/// 解码策略：容错。既有配置来自不同作者，同名字段会出现字符串/数字/布尔混合，
/// 故全部用宽松类型包装，任一字段缺失都不应导致整份配置作废。
struct SiteConfig: Codable, Equatable {
    var key: String
    var name: String
    /// 站点类型：0 = HTML 规则（一级/二级/搜索选择器），1 = JSON API，3 = JS 爬虫（spider）。
    /// 具体枚举语义在文档中被标为待确认，本工程按 TVBox 系的通行约定处理，
    /// 并在「默认取值清单」中列明。
    var type: Int
    var api: String
    var ext: String
    /// 爬虫规则地址。iOS 无 JVM：值为 .jar 时按平台级不支持处理。
    var jar: String
    var host: String
    var url: String
    var searchUrl: String
    var detailUrl: String
    var classParse: String
    var className: String
    var classUrl: String
    var cateExclude: String
    var searchable: Int
    var quickSearch: Int
    var filterable: Int
    var filter: String
    var filterUrl: String
    var filterDef: String
    var headers: [String: String]
    var playParse: Bool
    var lazy: String
    var limit: Int
    var double: Bool
    var timeout: Int

    // 规则串：文档 4.2 明确给出五段式语义。
    var ruleRecommend: String
    var ruleHome: String
    var ruleDetail: String
    var ruleSearch: String

    var isJarSpider: Bool {
        jar.lowercased().hasSuffix(".jar") || api.lowercased().hasSuffix(".jar")
    }

    /// 是否可参与全局搜索（searchable 为 2 表示启用；1 的语义在文档中标为待确认，
    /// 本工程按「1 与 2 均参与」实现并列入默认取值清单）。
    var canSearch: Bool { searchable > 0 }

    var displayName: String { name.isEmpty ? key : name }
}

extension SiteConfig {
    /// 宽容解码：字段名同时支持驼峰与下划线两种写法（不同作者的配置混用）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexKey.self)
        key = c.string("key") ?? c.string("siteKey") ?? ""
        name = c.string("name") ?? ""
        type = c.int("type") ?? 0
        api = c.string("api") ?? ""
        ext = c.string("ext") ?? ""
        jar = c.string("jar") ?? ""
        host = c.string("host") ?? ""
        url = c.string("url") ?? ""
        searchUrl = c.string("searchUrl") ?? c.string("search_url") ?? ""
        detailUrl = c.string("detailUrl") ?? c.string("detail_url") ?? ""
        classParse = c.string("class_parse") ?? c.string("classParse") ?? ""
        className = c.string("class_name") ?? ""
        classUrl = c.string("class_url") ?? ""
        cateExclude = c.string("cate_exclude") ?? ""
        searchable = c.int("searchable") ?? 1
        quickSearch = c.int("quickSearch") ?? 0
        filterable = c.int("filterable") ?? 0
        filter = c.string("filter") ?? ""
        filterUrl = c.string("filter_url") ?? ""
        filterDef = c.string("filter_def") ?? ""
        headers = c.dict("headers") ?? [:]
        playParse = c.bool("play_parse") ?? true
        lazy = c.string("lazy") ?? ""
        limit = c.int("limit") ?? 6
        double = c.bool("double") ?? false
        timeout = c.int("timeout") ?? 15
        ruleRecommend = c.string("推荐") ?? c.string("recommend") ?? ""
        ruleHome = c.string("一级") ?? c.string("home") ?? ""
        ruleDetail = c.string("二级") ?? c.string("detail") ?? ""
        ruleSearch = c.string("搜索") ?? c.string("search") ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: FlexKey.self)
        try c.encode(key, forKey: FlexKey("key"))
        try c.encode(name, forKey: FlexKey("name"))
        try c.encode(type, forKey: FlexKey("type"))
        try c.encode(api, forKey: FlexKey("api"))
        try c.encode(ext, forKey: FlexKey("ext"))
        try c.encode(jar, forKey: FlexKey("jar"))
        try c.encode(host, forKey: FlexKey("host"))
        try c.encode(url, forKey: FlexKey("url"))
        try c.encode(searchUrl, forKey: FlexKey("searchUrl"))
        try c.encode(detailUrl, forKey: FlexKey("detailUrl"))
        try c.encode(classParse, forKey: FlexKey("class_parse"))
        try c.encode(className, forKey: FlexKey("class_name"))
        try c.encode(classUrl, forKey: FlexKey("class_url"))
        try c.encode(cateExclude, forKey: FlexKey("cate_exclude"))
        try c.encode(searchable, forKey: FlexKey("searchable"))
        try c.encode(quickSearch, forKey: FlexKey("quickSearch"))
        try c.encode(filterable, forKey: FlexKey("filterable"))
        try c.encode(filter, forKey: FlexKey("filter"))
        try c.encode(filterUrl, forKey: FlexKey("filter_url"))
        try c.encode(filterDef, forKey: FlexKey("filter_def"))
        try c.encode(headers, forKey: FlexKey("headers"))
        try c.encode(playParse, forKey: FlexKey("play_parse"))
        try c.encode(lazy, forKey: FlexKey("lazy"))
        try c.encode(limit, forKey: FlexKey("limit"))
        try c.encode(double, forKey: FlexKey("double"))
        try c.encode(timeout, forKey: FlexKey("timeout"))
        try c.encode(ruleRecommend, forKey: FlexKey("推荐"))
        try c.encode(ruleHome, forKey: FlexKey("一级"))
        try c.encode(ruleDetail, forKey: FlexKey("二级"))
        try c.encode(ruleSearch, forKey: FlexKey("搜索"))
    }
}

/// 解析源（`parses` 数组）：播放地址需要二次解析时使用。
struct ParseConfig: Codable, Equatable {
    var name: String
    var url: String
    var `type`: Int
    var ext: [String: String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexKey.self)
        name = c.string("name") ?? ""
        url = c.string("url") ?? ""
        type = c.int("type") ?? 0
        ext = c.dict("ext") ?? [:]
    }

    /// 成员构造器：解码路径之外的构造点（解析弹窗单测等）使用。
    init(name: String = "", url: String = "", type: Int = 0, ext: [String: String] = [:]) {
        self.name = name
        self.url = url
        self.type = type
        self.ext = ext
    }
}

/// 配置文件的顶层结构。
/// **顶层键名在需求文档 5.2 被标为待确认**（Java 解析器不可读）。
/// 本工程按 TVBox 系的通行键名 `sites / parses / flags / wallpaper` 解析，
/// 同时兼容若干常见别名，并在「默认取值清单」中明确声明该推断。
///
/// **`lives` 字段自 v2.0.50 build 21 起不再纳入模型**：直播功能已按用户要求在真机验收后移除，
/// 配置里的 `lives`（含 `type:0` 文本源、`group/channels/proxy://…` 重定向形态、`epg` 等）
/// 作为未知键被 Codable 直接跳过，**既不参与任何业务，也不会导致解码失败**。
/// 这一点由 `ConfigParserTests.testRealTop98ConfigIgnoresLives` 用真实 top98.json 结构固化。
struct ConfigBundle: Codable, Equatable {
    var sites: [SiteConfig]
    var parses: [ParseConfig]
    var flags: [String]
    var wallpaper: String
    var spider: String

    init(sites: [SiteConfig] = [],
         parses: [ParseConfig] = [],
         flags: [String] = [],
         wallpaper: String = "",
         spider: String = "") {
        self.sites = sites
        self.parses = parses
        self.flags = flags
        self.wallpaper = wallpaper
        self.spider = spider
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexKey.self)
        sites = c.array("sites", SiteConfig.self)
            ?? c.array("api_site", SiteConfig.self)
            ?? []
        parses = c.array("parses", ParseConfig.self)
            ?? c.array("parse", ParseConfig.self)
            ?? []
        flags = c.array("flags", String.self) ?? []
        wallpaper = c.string("wallpaper") ?? ""
        spider = c.string("spider") ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: FlexKey.self)
        try c.encode(sites, forKey: FlexKey("sites"))
        try c.encode(parses, forKey: FlexKey("parses"))
        try c.encode(flags, forKey: FlexKey("flags"))
        try c.encode(wallpaper, forKey: FlexKey("wallpaper"))
        try c.encode(spider, forKey: FlexKey("spider"))
    }
}

/// 分类项（站点 class_parse 的解析结果，或 JSON API 的 ac=list 返回）。
struct SiteCategory: Codable, Equatable, Hashable {
    var id: String
    var name: String
}

/// vod 列表项。字段名对齐 APK 模板与 JSON API 的通行命名
/// （vod_id / vod_name / vod_pic / vod_remarks），这三组是配置生态的既有事实，
/// 不自行创造字段名。
struct VodItem: Codable, Equatable, Hashable {
    var vodId: String
    var vodName: String
    var vodPic: String
    var vodRemarks: String
    /// 归属站点 key，用于「按源分组」「屏蔽源」「收藏去重」。
    var siteKey: String

    var hasPoster: Bool { !vodPic.isEmpty }
}

/// 详情。tabs = 线路名数组，lists = 每条线路下的剧集
/// （`名称$地址#名称$地址` 的原始串在解析层已拆开）。
struct VodDetail: Codable, Equatable {
    var vodId: String
    var vodName: String
    var vodPic: String
    var vodContent: String
    var vodScore: String
    var vodYear: String
    var vodArea: String
    var vodType: String
    var vodRemarks: String
    var siteKey: String
    var tabs: [String]
    var lists: [[PlayEpisode]]
    /// 画质选项（quality 字段），文档 F-12。
    var quality: [String]
}

struct PlayEpisode: Codable, Equatable, Hashable {
    var name: String
    var url: String
}

/// 播放地址解析结果（lazy 的三种形态归一后的产物）。
struct PlayResolution: Equatable {
    /// 直出地址（m3u8/mp4 等）。
    var url: String
    /// 需要二次解析时，携带的解析源下标（对应 parses 数组）。
    var parseIndex: Int?
    /// 需要嗅探时置 true。
    var needSniff: Bool

    static let empty = PlayResolution(url: "", parseIndex: nil, needSniff: false)
}

/// 键值编码容器：用于宽容解码任意字段名。
struct FlexKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
}

extension KeyedDecodingContainer where Key == FlexKey {
    func string(_ name: String) -> String? {
        if let v = try? decodeIfPresent(String.self, forKey: FlexKey(name)) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: FlexKey(name)) { return "\(v)" }
        if let v = try? decodeIfPresent(Double.self, forKey: FlexKey(name)) { return "\(v)" }
        if let v = try? decodeIfPresent(Bool.self, forKey: FlexKey(name)) { return v ? "1" : "0" }
        return nil
    }

    func int(_ name: String) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: FlexKey(name)) { return v }
        if let v = try? decodeIfPresent(String.self, forKey: FlexKey(name)) { return Int(v) }
        if let v = try? decodeIfPresent(Bool.self, forKey: FlexKey(name)) { return v ? 1 : 0 }
        return nil
    }

    func bool(_ name: String) -> Bool? {
        if let v = try? decodeIfPresent(Bool.self, forKey: FlexKey(name)) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: FlexKey(name)) { return v != 0 }
        if let v = try? decodeIfPresent(String.self, forKey: FlexKey(name)) {
            return v == "1" || v.lowercased() == "true"
        }
        return nil
    }

    func dict(_ name: String) -> [String: String]? {
        if let v = try? decodeIfPresent([String: String].self, forKey: FlexKey(name)) { return v }
        // 有些配置把 headers 写成一整串 JSON 字符串。
        if let v = try? decodeIfPresent(String.self, forKey: FlexKey(name)),
           let data = v.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var result: [String: String] = [:]
            for (k, val) in obj { result[k] = "\(val)" }
            return result
        }
        return nil
    }

    func array<T: Decodable>(_ name: String, _ type: T.Type) -> [T]? {
        if let v = try? decodeIfPresent([T].self, forKey: FlexKey(name)) { return v }
        // 部分配置把数组写成 JSON 字符串。
        if let v = try? decodeIfPresent(String.self, forKey: FlexKey(name)),
           let data = v.data(using: .utf8),
           let list = try? JSONDecoder().decode([T].self, from: data) {
            return list
        }
        return nil
    }
}
