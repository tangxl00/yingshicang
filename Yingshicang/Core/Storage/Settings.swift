import Foundation

/// 应用设置。
///
/// 键集合来自需求文档 4.1 与 R-17 / R-27 / R-30 的逐行文案（强证据），
/// 存储介质选 UserDefaults（布尔/短字符串为主，无关系查询需求）。
/// 每个键的中文注释对应该选项在界面上的显示文案，便于核对。
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    private let prefix = "tpc_settings."

    private init() {
        registerDefaults()
    }

    private func registerDefaults() {
        // 文档 4.1 明确「搜索模式默认值『精确匹配』」「去广告默认『开』」
        defaults.register(defaults: [
            k("searchMode"): SearchMode.exact.rawValue,
            k("removeAd"): true,
            k("historyMerge"): true,
            k("posterStyle"): PosterStyle.grid.rawValue,
            k("searchResultStyle"): SearchResultStyle.grid.rawValue,
            k("rate"): 1.0,
            k("decodeMode"): 0,
            k("renderMode"): 0,
            k("scaleMode"): 0,
            k("autoLandscape"): true,
            k("fullScreenStyle"): 0,
            k("exoBuffer"): 0,
            k("exoCache"): 0,
            k("playerAutoSwitch"): true,
            k("miniProgress"): true,
            k("windowPreview"): false,
            k("floatWindow"): false,
            k("danmaku"): false,
            k("interfaceCache"): true,
            k("showTime"): true,
            k("showFloatHistory"): true,
            k("searchThreadCount"): 20,
            k("playerKernel"): PlayerKernel.avplayer.rawValue,
            k("dns"): ""
        ])
    }

    private func k(_ name: String) -> String { prefix + name }

    // MARK: - 通用读写

    func bool(_ name: String) -> Bool { defaults.bool(forKey: k(name)) }
    func set(_ name: String, _ value: Bool) { defaults.set(value, forKey: k(name)) }
    func integer(_ name: String) -> Int { defaults.integer(forKey: k(name)) }
    func set(_ name: String, _ value: Int) { defaults.set(value, forKey: k(name)) }
    func double(_ name: String) -> Double { defaults.double(forKey: k(name)) }
    func set(_ name: String, _ value: Double) { defaults.set(value, forKey: k(name)) }
    func string(_ name: String) -> String { defaults.string(forKey: k(name)) ?? "" }
    func set(_ name: String, _ value: String) { defaults.set(value, forKey: k(name)) }

    // MARK: - 播放器选项（R-17 十一项）

    /// 播放器：0 = 系统播放器（AVPlayer），1 = VLC。
    var playerKernel: PlayerKernel {
        get { PlayerKernel(rawValue: integer("playerKernel")) ?? .avplayer }
        set { set("playerKernel", newValue.rawValue) }
    }
    /// 迷你进度
    var miniProgress: Bool {
        get { bool("miniProgress") } set { set("miniProgress", newValue) }
    }
    /// 解码方式
    var decodeMode: Int { get { integer("decodeMode") } set { set("decodeMode", newValue) } }
    /// 渲染方式
    var renderMode: Int { get { integer("renderMode") } set { set("renderMode", newValue) } }
    /// 窗口预览
    var windowPreview: Bool { get { bool("windowPreview") } set { set("windowPreview", newValue) } }
    /// 画面缩放
    var scaleMode: Int { get { integer("scaleMode") } set { set("scaleMode", newValue) } }
    /// 播放页自动横屏
    var autoLandscape: Bool { get { bool("autoLandscape") } set { set("autoLandscape", newValue) } }
    /// 全屏样式
    var fullScreenStyle: Int { get { integer("fullScreenStyle") } set { set("fullScreenStyle", newValue) } }
    /// EXO 缓冲
    var exoBuffer: Int { get { integer("exoBuffer") } set { set("exoBuffer", newValue) } }
    /// EXO 磁盘缓存
    var exoCache: Int { get { integer("exoCache") } set { set("exoCache", newValue) } }
    /// 播放器自动切换
    var playerAutoSwitch: Bool { get { bool("playerAutoSwitch") } set { set("playerAutoSwitch", newValue) } }

    // MARK: - 个性化选项（R-30 十一项）

    /// 悬浮窗
    var floatWindow: Bool { get { bool("floatWindow") } set { set("floatWindow", newValue) } }
    /// 开启弹幕
    var danmaku: Bool { get { bool("danmaku") } set { set("danmaku", newValue) } }
    /// 历史记录合并
    var historyMerge: Bool { get { bool("historyMerge") } set { set("historyMerge", newValue) } }
    /// 去广告
    var removeAd: Bool { get { bool("removeAd") } set { set("removeAd", newValue) } }
    /// 接口缓存
    var interfaceCache: Bool { get { bool("interfaceCache") } set { set("interfaceCache", newValue) } }
    /// 屏显时间
    var showTime: Bool { get { bool("showTime") } set { set("showTime", newValue) } }
    /// 海报展示样式
    var posterStyle: PosterStyle {
        get { PosterStyle(rawValue: integer("posterStyle")) ?? .grid }
        set { set("posterStyle", newValue.rawValue) }
    }
    /// 搜索结果样式
    var searchResultStyle: SearchResultStyle {
        get { SearchResultStyle(rawValue: integer("searchResultStyle")) ?? .grid }
        set { set("searchResultStyle", newValue.rawValue) }
    }
    /// 底部悬浮播放记录
    var showFloatHistory: Bool { get { bool("showFloatHistory") } set { set("showFloatHistory", newValue) } }
    /// 搜索模式（默认「精确匹配」）
    var searchMode: SearchMode {
        get { SearchMode(rawValue: integer("searchMode")) ?? .exact }
        set { set("searchMode", newValue.rawValue) }
    }

    // MARK: - 其他

    /// 倍速（R-16 倍速设置 / 播放页倍速标签）
    var rate: Double { get { double("rate") } set { set("rate", newValue) } }
    /// 搜索线程数（R-27）
    var searchThreadCount: Int { get { integer("searchThreadCount") } set { set("searchThreadCount", newValue) } }
    /// 安全 DNS
    var dns: String { get { string("dns") } set { set("dns", newValue) } }
    /// 壁纸虚化开关（R-27）
    var wallpaperBlur: Bool { get { bool("wallpaperBlur") } set { set("wallpaperBlur", newValue) } }
    /// 壁纸（用户自选图片路径）
    var wallpaperPath: String { get { string("wallpaperPath") } set { set("wallpaperPath", newValue) } }
    /// 上次停留 Tab（R-01）
    var lastTabIndex: Int { get { integer("lastTabIndex") } set { set("lastTabIndex", newValue) } }
    /// WebDAV 三项凭据（R-45）。密码属凭证类数据，走 Keychain 而不是 UserDefaults（质检 P2）。
    var webDavURL: String { get { string("webDavURL") } set { set("webDavURL", newValue) } }
    var webDavAccount: String { get { string("webDavAccount") } set { set("webDavAccount", newValue) } }
    var webDavPassword: String {
        get { KeychainStore.get(account: "webDavPassword") }
        set {
            if newValue.isEmpty {
                KeychainStore.remove(account: "webDavPassword")
            } else {
                KeychainStore.set(newValue, account: "webDavPassword")
            }
        }
    }
    /// 阿里 token（R-48，32 位）。与 WebDAV 密码同类——是可用来访问用户网盘的凭证，
    /// 明文存 UserDefaults 会随沙箱备份外泄（质检 P2 安全项），因此同样走 Keychain。
    /// 首次读取时做一次性迁移：旧版本写在 UserDefaults 明文里的值搬进 Keychain 并从
    /// UserDefaults 删除，避免「升级后 token 丢失」与「明文残留」两种问题同时存在。
    var aliToken: String {
        get {
            let migrated = KeychainStore.get(account: "aliToken")
            if migrated.isEmpty {
                let legacy = string("aliToken")
                if !legacy.isEmpty {
                    KeychainStore.set(legacy, account: "aliToken")
                    defaults.removeObject(forKey: k("aliToken"))
                    return legacy
                }
                return ""
            }
            // Keychain 已有值时顺手清掉可能残留的明文副本。
            if !string("aliToken").isEmpty { defaults.removeObject(forKey: k("aliToken")) }
            return migrated
        }
        set {
            if newValue.isEmpty {
                KeychainStore.remove(account: "aliToken")
            } else {
                KeychainStore.set(newValue, account: "aliToken")
            }
            // 无论写还是清，都不再落 UserDefaults 明文。
            defaults.removeObject(forKey: k("aliToken"))
        }
    }
    /// 阿里云盘开放平台 Client ID（R-47 网页授权用）。
    /// 这是公开的应用标识符、不是凭证，存 UserDefaults 即可；留空表示未配置，
    /// 网页授权入口会如实提示改走手动粘贴。
    var aliClientID: String { get { string("aliClientID") } set { set("aliClientID", newValue) } }
    /// 片头/片尾跳过秒数（R-13 / F-13）
    var introSeconds: Int { get { integer("introSeconds") } set { set("introSeconds", newValue) } }
    var outroSeconds: Int { get { integer("outroSeconds") } set { set("outroSeconds", newValue) } }

    /// 清空全部设置（R-27「重置 App」）。
    /// Keychain 里的凭证不在 UserDefaults 里，必须单独清，否则重置后密码仍残留。
    func resetAll() {
        let dict = defaults.dictionaryRepresentation()
        for key in dict.keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
        KeychainStore.remove(account: "webDavPassword")
        KeychainStore.remove(account: "aliToken")
        registerDefaults()
    }
}

enum PlayerKernel: Int {
    case avplayer = 0
    case vlc = 1
}

enum PosterStyle: Int, CaseIterable {
    case grid = 0
    case list = 1
    case block = 2

    var title: String {
        switch self {
        case .grid: return "海报"
        case .list: return "列表"
        case .block: return "区块"
        }
    }
}

enum SearchResultStyle: Int, CaseIterable {
    case grid = 0
    case list = 1
    var title: String { self == .grid ? "海报" : "列表" }
}

enum SearchMode: Int, CaseIterable {
    case exact = 0
    case fuzzy = 1
    var title: String { self == .exact ? "精确匹配" : "模糊匹配" }
}
