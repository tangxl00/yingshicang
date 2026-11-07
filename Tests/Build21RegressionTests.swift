import XCTest
@testable import Yingshicang

/// v2.0.50 build 21 真机验收四项修复的回归守卫。
///
/// 覆盖：
/// 1. 错误码不再伪装 —— 传输层失败带原始 NSURLError，HTTP 失败带真实状态码，绝不出现 500 / -1 这类假码
/// 2. 真实 top98.json 结构可完整解码（24 站点），`lives` 被忽略且不报错
/// 3. Tab 数量收敛为 3，直播 / 短视频入口消失
/// 4. 左滑返回与点击收键盘的载体存在且挂载方式正确
final class Build21RegressionTests: XCTestCase {

    // MARK: - 1. 错误码不再伪装

    /// 传输层失败（无 HTTP 响应）必须 status=0 且带原始 NSURLError，而不是 500。
    func testTransportFailureDoesNotFakeHTTP500() {
        let nsError = NSError(domain: NSURLErrorDomain,
                              code: NSURLErrorAppTransportSecurityRequiresSecureConnection,
                              userInfo: [NSLocalizedDescriptionKey: "The resource could not be loaded because the App Transport Security policy requires the use of a secure connection."])
        let response = HTTPResponse.transportFailure("http://home.jundie.top:81/top98.json", error: nsError)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.status, 0, "传输层失败不得伪造 HTTP 状态码")
        XCTAssertNotEqual(response.status, 500, "历史缺陷：曾硬编码 500")
        guard let transport = response.transport else {
            return XCTFail("传输层失败必须携带 transport 信息")
        }
        XCTAssertEqual(transport.code, NSURLErrorAppTransportSecurityRequiresSecureConnection)
        XCTAssertEqual(transport.domain, NSURLErrorDomain)
        XCTAssertTrue(transport.message.contains("App Transport Security"), "实际: \(transport.message)")
    }

    /// 有真实 HTTP 响应时，状态码必须原样透出（不透出成 500 / -1）。
    func testHTTPFailureKeepsRealStatusCode() {
        let response = HTTPResponse.failure("http://example.com/x.json", status: 404)
        let siteError = SiteError.from(response)
        XCTAssertEqual(siteError, .network(404))
        XCTAssertEqual(siteError.errorDescription, "网络请求失败（HTTP 404）")
    }

    /// 传输层失败经 SiteError 转换后，文案里必须有 NSURLError 的 code 与 domain，
    /// 且**不能**出现「HTTP 500」「HTTP -1」这类假状态码。
    func testSiteErrorExposesOriginalNSErrorNotFakeStatus() {
        let nsError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost,
                              userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."])
        let response = HTTPResponse.transportFailure("http://home.jundie.top:81/top98.json", error: nsError)
        let siteError = SiteError.from(response)
        guard case .transport(let failure) = siteError else {
            return XCTFail("传输层失败必须映射为 .transport，实际 \(siteError)")
        }
        XCTAssertEqual(failure.code, NSURLErrorCannotFindHost)

        let text = siteError.errorDescription ?? ""
        XCTAssertTrue(text.contains("NSURLErrorDomain"), "必须带原始 error domain，实际: \(text)")
        XCTAssertTrue(text.contains("\(NSURLErrorCannotFindHost)"), "必须带原始 error code，实际: \(text)")
        XCTAssertFalse(text.contains("HTTP 500"), "不得伪装成 500，实际: \(text)")
        XCTAssertFalse(text.contains("HTTP -1"), "不得出现 -1 这种非法状态码，实际: \(text)")
        XCTAssertTrue(text.contains("域名无法解析"), "应追加可读提示，实际: \(text)")
    }

    /// 配置拉取失败同理：传输层失败带原始错误，HTTP 失败带真实状态码。
    func testConfigErrorExposesRealCause() {
        let nsError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                              userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        let transportResponse = HTTPResponse.transportFailure("http://home.jundie.top:81/top98.json", error: nsError)
        let transportError = ConfigRepository.ConfigError.from(transportResponse)
        let transportText = transportError.errorDescription ?? ""
        XCTAssertTrue(transportText.contains("NSURLErrorDomain"), "实际: \(transportText)")
        XCTAssertTrue(transportText.contains("\(NSURLErrorTimedOut)"), "实际: \(transportText)")
        XCTAssertFalse(transportText.contains("HTTP 500"), "实际: \(transportText)")

        let httpError = ConfigRepository.ConfigError.from(HTTPResponse.failure("http://x/y.json", status: 503))
        XCTAssertEqual(httpError.errorDescription, "配置拉取失败（HTTP 503）")
    }

    /// status=0 的 HTTP 失败不得渲染成「HTTP 0」。
    func testZeroStatusIsDescribedAsMissingNotFakeCode() {
        XCTAssertEqual(ConfigRepository.ConfigError.http(0).errorDescription,
                       "配置拉取失败（服务端未返回状态码）")
        XCTAssertEqual(SiteError.network(0).errorDescription,
                       "网络请求失败（服务端未返回状态码）")
    }

    // MARK: - 2. 真实 top98.json

    /// 用户真机反馈的那个配置：24 个站点必须全部解出来。
    /// 结构与线上一致（sites 全为 type:3 + csp_ api，含 playerType/ext 等非常规字段、
    /// 相对路径 spider、proxy:// 直播项）。
    func testRealTop98ConfigDecodes24Sites() {
        let text = Self.top98JSON
        guard case .success(let bundle) = ConfigParser.parseResult(text: text) else {
            return XCTFail("真实 top98.json 必须可解析")
        }
        XCTAssertEqual(bundle.sites.count, 24, "用户 URL 必须完整加载 24 个站点")
        XCTAssertEqual(bundle.parses.count, 15)
        XCTAssertEqual(bundle.flags.count, 12)
        XCTAssertEqual(bundle.spider, "./jar/top98_1.jar", "相对路径 spider 必须原样保留")
        XCTAssertEqual(bundle.wallpaper, "http://www.kf666888.cn/api/tvbox/img")

        // 站点字段抽查：csp_ 前缀 api 与 type:3 都必须保留，playerType 等未知字段不影响解码
        let first = bundle.sites[0]
        XCTAssertEqual(first.key, "360")
        XCTAssertEqual(first.type, 3)
        XCTAssertEqual(first.api, "csp_SP360")
        XCTAssertTrue(bundle.sites.allSatisfy { $0.type == 3 })
        // 24 个站点里 22 个是 `csp_` 前缀的 JS 爬虫，2 个是 drpy.min.js 远程脚本 —— 两种都必须保留。
        XCTAssertEqual(bundle.sites.filter { $0.api.hasPrefix("csp_") }.count, 22)
        XCTAssertEqual(bundle.sites.filter { $0.api.contains("drpy.min.js") }.count, 2)
        // `ext`（同一份配置里混用 dict / 字符串 / null）与 `playerType` 等非常规字段不得导致解码失败。
        XCTAssertTrue(bundle.sites.contains { $0.key == "csp_Alist" }, "ext 为 dict 的站点必须解码出来")
    }

    /// `lives`（含 type:0 文本源与 proxy:// redirect 形态）必须被静默忽略：不报错、不入模型。
    func testRealTop98ConfigIgnoresLives() {
        let result = ConfigParser.parseResult(text: Self.top98JSON)
        guard case .success = result else {
            return XCTFail("含 lives 的配置不得因 lives 报错，实际: \(result)")
        }
        // ConfigBundle 自 build 21 起没有 lives 字段（编译期即保证）；此处再固化「不因此失败」。
        XCTAssertEqual(ConfigParser.parse(text: Self.top98JSON).sites.count, 24)
        // proxy:// 这类非常规 URL 出现在 lives 里，不应污染站点解析结果。
        let bundle = ConfigParser.parse(text: Self.top98JSON)
        XCTAssertFalse(bundle.sites.contains { $0.api.contains("proxy://") })
    }

    /// 坏配置必须给出**真实原因**，而不是静默成「成功但空」。
    func testBadConfigReportsRealReason() {
        if case .failure(let failure) = ConfigParser.parseResult(text: "not json at all {{{") {
            XCTAssertTrue(failure.message.contains("不是合法 JSON"), "实际: \(failure.message)")
        } else {
            XCTFail("非 JSON 必须报失败")
        }

        if case .failure(let failure) = ConfigParser.parseResult(text: "{\"urls\":[\"http://a/1.json\"]}") {
            XCTAssertTrue(failure.message.contains("多仓索引"), "实际: \(failure.message)")
        } else {
            XCTFail("多仓索引文件不是单仓配置，必须报失败")
        }

        if case .failure(let failure) = ConfigParser.parseResult(text: "") {
            XCTAssertEqual(failure.message, "配置内容为空")
        } else {
            XCTFail("空文本必须报失败")
        }
    }

    // MARK: - 3. Tab 收敛为 3，直播 / 短视频入口消失

    func testTabBarHasExactlyThreeEntries() {
        XCTAssertEqual(TabBarView.tabTitles.count, 3)
        XCTAssertEqual(TabBarView.tabTitles, ["主页", "历史·收藏", "我的"])
        XCTAssertEqual(TabBarView.tabIcons.count, TabBarView.tabTitles.count)
        XCTAssertFalse(TabBarView.tabTitles.contains("直播"))
        XCTAssertFalse(TabBarView.tabTitles.contains("短视频"))
    }

    /// 直播 / 短视频页面类型必须已从模块中消失（编译期保证：删掉后此处无法引用）。
    func testLiveAndShortVideoModulesRemoved() {
        // ConfigBundle 不再有 lives 字段 —— 用反射确认模型里没有残留直播数据。
        let bundle = ConfigParser.parse(text: Self.top98JSON)
        let mirror = Mirror(reflecting: bundle)
        let names = mirror.children.compactMap { $0.label }
        XCTAssertFalse(names.contains("lives"), "配置模型不应再有 lives 字段，实际字段: \(names)")
        XCTAssertEqual(Set(names), ["sites", "parses", "flags", "wallpaper", "spider"])
    }

    // MARK: - 4. 左滑返回 / 点击收键盘

    /// 所有被 fullScreen present 的二级页面都必须继承 SwipeBackViewController，
    /// 否则该页面就没有左滑返回。
    func testPresentedScreensUseSwipeBackBase() {
        let cases: [(UIViewController.Type, String)] = [
            (DetailViewController.self, "详情页"),
            (SearchViewController.self, "搜索页"),
            (PlayerViewController.self, "播放页"),
            (CategoryContentViewController.self, "分类内容页"),
            (HistoryListViewController.self, "历史页"),
            (FavoriteViewController.self, "收藏页"),
            (StoreHouseViewController.self, "仓库页"),
            (SiteManageViewController.self, "站点管理页"),
            (SettingsListViewController.self, "设置列表页"),
            (WebDavViewController.self, "WebDAV 页"),
            (LocalDataViewController.self, "本地数据页"),
            (UpdateCheckViewController.self, "检查更新页"),
            (AboutViewController.self, "关于页"),
            (InteractionViewController.self, "互动页")
        ]
        for (type, name) in cases {
            XCTAssertTrue((type as AnyClass).isSubclass(of: SwipeBackViewController.self),
                          "\(name)（\(type)）必须继承 SwipeBackViewController 才有左滑返回")
        }
    }

    /// 手势挂载：左边缘 24pt 起手才触发返回；手势不吞点击（cancelsTouchesInView=false）。
    func testSwipeBackGesturesAreEdgeOnlyAndNonSwallowing() {
        let controller = SwipeBackViewController()
        controller.loadViewIfNeeded()

        let gestures = controller.view.gestureRecognizers ?? []
        let edgePan = gestures.compactMap { $0 as? UIScreenEdgePanGestureRecognizer }.first
        XCTAssertNotNil(edgePan, "必须装 UIScreenEdgePanGestureRecognizer")
        XCTAssertEqual(edgePan?.edges, .left, "只认左边缘，避免与内容区横向拖动冲突")
        XCTAssertEqual(edgePan?.maximumNumberOfTouches, 1)

        let tap = gestures.compactMap { $0 as? UITapGestureRecognizer }.first
        XCTAssertNotNil(tap, "必须装点击收键盘手势")
        XCTAssertFalse(tap?.cancelsTouchesInView ?? true, "点击手势不得吞掉其他控件事件")
        XCTAssertEqual(gestures.count, 2, "只应有两个手势，避免与其他页面手势打架")
    }

    /// 点击落在 UIControl（按钮 / 滑块 / 开关 / 输入框）上时，收键盘手势必须让路；
    /// 落在普通容器 / 背景上时才接管。
    func testTapGestureYieldsToControls() {
        let button = UIButton(type: .system)
        XCTAssertFalse(SwipeBackViewController.tapMayReceive(on: button),
                       "按钮上的点击必须交给按钮自己处理")

        let slider = UISlider()
        XCTAssertFalse(SwipeBackViewController.tapMayReceive(on: slider),
                       "滑块上的点击必须交给滑块")

        let field = UITextField()
        XCTAssertFalse(SwipeBackViewController.tapMayReceive(on: field),
                       "输入框上的点击不能被收键盘手势截获")

        // 控件内部的子视图（如按钮里的 label）也要一路向上识别到 UIControl。
        let label = UILabel()
        button.addSubview(label)
        XCTAssertFalse(SwipeBackViewController.tapMayReceive(on: label),
                       "控件子视图的点击同样要还给它所属的控件")

        XCTAssertTrue(SwipeBackViewController.tapMayReceive(on: UIView()),
                      "空白容器上的点击应当用于收键盘")
        XCTAssertTrue(SwipeBackViewController.tapMayReceive(on: nil))
    }

    // MARK: - Fixtures

    /// 真实 top98.json 文本（由 `http://home.jundie.top:81/top98.json` 实际拉取后内联，
    /// 使测试不依赖网络，同时保证断言走的是线上真实结构：
    /// 24 sites 全为 type:3 + csp_ 前缀 api、15 parses、2 lives（含 proxy:// redirect）、
    /// 12 flags、相对路径 spider、wallpaper）。
    /// 用 Swift **原始字符串**字面量内联：配置里含 JSON 转义（如 `\\?` 的正则在原始文本中写作 `\\\\?`），
    /// 普通 `"""` 会把 `\\` 再吃成 `\`，导致内联出来的文本不再是合法 JSON，测试就会"通过"在一个假配置上。
    static let top98JSON: String = #"""
{
  "spider": "./jar/top98_1.jar",
  "lives": [
    {
      "name": "直播",
      "type": 0,
      "url": "http://home.jundie.top:81/Cat/tv/live.txt",
      "epg": "http://epg.51zmt.top:8000/api/diyp/?ch={name}&date={date}"
    },
    {
      "group": "redirect",
      "channels": [
        {
          "name": "live",
          "urls": [
            "proxy://do=live&type=txt&ext=aHR0cDovL2hvbWUuanVuZGllLnRvcDo4MS9DYXQvdHYvbGl2ZS50eHQ="
          ]
        }
      ],
      "epg":"http://epg.51zmt.top:8000/api/diyp/"
    }
  ],
  "rules": [
    {
      "host": "www.6080dy1.com",
      "rule": [
        "m3u8.php",
        ".m3u8"
      ]
    },
    {
      "host": "*",
      "rule": [
        "default.365yg.com"
      ]
    },
    {
      "host": "www.agemys.cc",
      "rule": [
        "cdn-tos",
        "obj/tos-cn"
      ]
    },
    {
      "host": "zjmiao.com",
      "rule": [
        "play.videomiao.vip/API.php",
        "time="
      ]
    },
    {
      "host": "www.sharenice.net",
      "rule": [
        "http.*?/play.{0,3}\\?[^url]{2,8}=.*"
      ]
    },
    {
      "host": "www.sharenice.net",
      "rule": [
        "qianpailive.com",
        "vid="
      ]
    },
    {
      "host": "*",
      "rule": [
        "douyin.com/aweme",
        "video_id="
      ]
    },
    {
      "host": "*",
      "rule": [
        "huoshan.com",
        "/item/video/"
      ]
    },
    {
      "host": "*",
      "rule": [
        "http((?!http).){12,}?\\.(m3u8|mp4|flv|avi|mkv|rm|wmv|mpg|m4a)\\?.*|http((?!http).){12,}\\.(m3u8|mp4|flv|avi|mkv|rm|wmv|mpg|m4a)|http((?!http).)*?xg.php\\?id=|http((?!http).)*?/m3/(.*)\\.css"
      ]
    }
  ],
  "sites": [
    {
      "key": "360",
      "name": "360",
      "type": 3,
      "api": "csp_SP360",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 1
    },
    {
      "key": "nbys",
      "name": "泥巴(墙)",
      "type": 3,
      "api": "csp_Nbys",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 1
    },
    {
      "key": "csp_Alist",
      "name": "Alist(SP)",
      "type": 3,
      "api": "csp_Alist",
      "searchable": 0,
      "playerType": 2,
      "quickSearch": 0,
      "filterable": 0,
      "ext": {
        "💢小雅":"http://alistxy.ganggang.live:5678",
        "🦀9T(Adult)": "https://drive.9t.ee",
        "🌤晴园的宝藏库": "https://alist.52qy.repl.co",
        "🐭米奇妙妙屋": "https://anime.mqmmw.ga",
        "💂小兵组网盘影视": "https://6vv.app",
        "🐋一只鱼": "https://alist.youte.ml",
        "🌊七米蓝": "https://al.chirmyram.com",
        "🥼帅盘": "https://hi.shuaipeng.wang",
        "🐉神族九帝": "https://alist.shenzjd.com",
        "☃️姬路白雪": "https://pan.jlbx.xyz",
        "🎧听闻网盘": "https://wangpan.sangxuesheng.com",
        "💾DISK": "http://124.222.140.243:8080",
        "🌨云播放": "https://quanzi.laoxianghuijia.cn",
        "✨星梦": "https://pan.bashroot.top",
        "💫触光": "https://pan.ichuguang.com",
        "🕵️好汉吧": "https://8023.haohanba.cn",
        "💢repl": "https://ali.liucn.repl.co",
        "🌨秋雨分享": "https://share.laowang.me",
        "💦讯维云盘": "https://pan.xwbeta.com"
      }
    },
    {
      "key": "csp_xb_lez",
      "name": "乐猪(XBiu)",
      "type": 3,
      "api": "csp_XBiu",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext": {
        "homeUrl": "http://www.lezhutv.com/type/{cateId}-{datePg}.html",
        "playlist":{
          "sort":1
        }
      }
    },
    {
      "key": "csp_XBPQ_6080",
      "name": "6080电影(XBPQ)",
      "type": 3,
      "api": "csp_XBPQ",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext":{
        "请求头": "手机",
        "起始页": "1",
        "二次截取": "<div class=\"module-list\">&&<div class=\"mx-lrmenu\">[替换:<div class=\"fixed_right_bar\">>><div class=\"module-item\">]||首页--最新热播&&<div  class=\"module-main\"[替换:<div class=\"module module-wrapper\">>><div class=\"module-item\">]",
        "数组": "<div class=\"module-item-pic\">&&<div class=\"module-item\">[不包含:理论片]",
        "副标题": "class=\"module-item-text\"&&<",
        "线路数组": "class=\"module-tab-item tab-item\"&&</div>[排序:极速播放>在线观看]",
        "线路标题": "<span>&&</small>[替换:</span>>>（更至]+集）",
        "影片年代": "<a class=\"tag-link\"*>&&</a>",
        "导演": "导演：</span>&&</a>",
        "演员": "主演：</span>&&</div>",
        "简介": "剧情：</span>&&</span>",
        "播放数组": "<div class=\"sort-item\"&&</div>",
        "播放列表": "<!--&&-->",
        "免嗅": "1",
        "嗅探词": ".m3u8#.mp4",
        "过滤词": ".html#url=http",
        "搜索模式": "0",
        "搜索链接前缀": "/video/",
        "搜索链接后缀": ".html",
        "分类url": "https://www.6080dy1.com/vodshow/{cateId}-{area}-{by}-{class}-----{catePg}---{year}.html",
        "分类": "电影&电视剧&综艺&动漫",
        "分类值": "1&2&3&4",
        "类型": "动作片&喜剧片&爱情片&科幻片&恐怖片&剧情片&战争片&纪录片&悬疑片&犯罪片&冒险片&动画片&惊悚片&奇幻片国产剧&欧美剧&日韩剧&港台剧&泰剧&海外剧大陆综艺&日韩综艺&港台综艺&欧美综艺&演唱会||国产动漫&日韩动漫&欧美动漫&港台动漫",
        "类型值": "25&26&27&28&30&31&33&35&36&38&40&41&43&4442&45&47&49&51&5220&21&22&23&24||29&32&34&37",
        "剧情": "喜剧&爱情&恐怖&动作&科幻&剧情&战争&警匪&犯罪&动画&奇幻&武侠&冒险&枪战&恐怖&悬疑&惊悚&经典&青春&文艺&微电影&古装&历史&运动&农村&儿童&网络电影古装&战争&青春偶像&喜剧&家庭&犯罪&动作&奇幻&剧情&历史&经典&乡村&情景&商战&网剧&其他选秀&情感&访谈&播报&旅游&音乐&美食&纪实&曲艺&生活&游戏互动&财经&求职||情感&科幻&热血&推理&搞笑&冒险&萝莉&校园&动作&机战&运动&战争&少年&少女&社会&原创&亲子&益智&励志&其他",
        "剧情值": "*",
        "地区": "大陆&香港&台湾&美国&法国&英国&日本&韩国&德国&泰国&印度&意大利&西班牙&加拿大&其他内地&韩国&香港&台湾&日本&美国&泰国&英国&新加坡&其他内地&港台&日韩&欧美||国产&日本&欧美&其他",
        "筛选": "1"
      }
    },
    {"key": "csp_XBPQ_南瓜影视",
      "name": "南瓜影视",
      "type": 3,
      "api": "csp_XBPQ",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext": "https://www.ngys8.com/vodshow/id/{cateId}/page{catePg}.html"
    },
    {"key": "csp_biubiu_短视频","name": "️短视频(XB)","type": 3,"api": "csp_XBPQ","searchable": 1,"quickSearch": 1,"filterable": 0,"ext": "分类url:http://www.sharenice.net/{cateId}?page={catePg},分类:抖音,直接播放:1,嗅探词:play/?#?item#qianpailive#.flv#mp4"},
    {
      "key": "csp_xb_zxzj",
      "name": "在线之家(XBiu)",
      "type": 3,
      "api": "csp_XBiu",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext": "http://home.jundie.top:666/json/XBiu/zxzj.json"
    },
    {
      "key": "csp_xb_auete",
      "name": "AUETE(XBiu)",
      "type": 3,
      "api": "csp_XBiu",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext": "http://home.jundie.top:666/json/XBiu/auete.json"
    },
    {
      "key": "csp_xb_lib",
      "name": "LIB(XBiu)",
      "type": 3,
      "api": "csp_XBiu",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext": " https://www.libvio.me/type/{cateId}-{catePg}.html"
    },
    {
      "key": "csp_xbpq_lgyy",
      "name": "蓝光影院(XBPQ)",
      "type": 3,
      "api": "csp_XBPQ",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext": "https://lgyy.tv/vodshow/{cateId}--------{catePg}---.html"
    },
    {
      "key": "csp_xb_lgyys",
      "name": "蓝光影院(XBiu)",
      "type": 3,
      "api": "csp_XBiu",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext": "https://lgyy.tv/vodshow/{cateId}--------{catePg}---.html"
    },
    {
      "key": "drpy_js_ddys",
      "name": "低端影视(DRPY)",
      "type": 3,
      "api": "http://home.jundie.top:666/JS/dr_py/libs/drpy.min.js",
      "ext": "http://home.jundie.top:666/JS/dr_py/js/ddys.js"
    },
     {
      "key": "drpy_js_akjs",
      "name": "爱看机器人(DRPY)",
      "type": 3,
      "api": "http://home.jundie.top:666/JS/dr_py/libs/drpy.min.js",
      "ext": "http://home.jundie.top:666/JS/dr_py/js/爱看机器人.js"
    },
    {
      "key": "csp_xb_zbk",
      "name": "真不卡(XBiu)",
      "type": 3,
      "api": "csp_XBiu",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext": "https://www.zbkk.net/vodshow/{cateId}--------{catePg}---.html"
    },
    {
      "key": "csp_xb_ysgc",
      "name": "影视工厂(XBiu)",
      "type": 3,
      "api": "csp_XBiu",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext": "https://www.ysgc.fun/vodtype/{cateId}-{catePg}.html"
    },
    {
      "key": "csp_xb_cokemv",
      "name": "cokemv(XBiu)",
      "type": 3,
      "api": "csp_XBiu",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext": "https://cokemv.me/vodshow/{cateId}--------{catePg}---.html"
    },
    {
      "key": "csp_XBPQ_98影院",
      "name": "98影院(XBPQ)",
      "type": 3,
      "api": "csp_XBPQ",
      "searchable": 1,
      "quickSearch": 1,
      "filterable": 0,
      "ext": "{\"免嗅\":\"0\",\"副标题\":\"right\\\">&&</span>\",\"播放标题\":\">&&</a>\",\"播放数组\":\"<ul class=\\\"stui-content__playlist&&</ul>\",\"线路数组\": \"<img src=&&/h3>\",\"线路标题\": \">&&<\",\"分类url\":\"http://www.98ju.com/{cateId}/index{catePg}.html[http://www.98ju.com/{cateId}/index.html]\",\"分类\":\"电影$dianyingpian#电视剧$dianshiju#综艺$zongyi#动漫$dongman\",\"类型\":\"dianyingpian--动作片$dongzuopian#爱情片$aiqingpian#科幻片$kehuanpian#恐怖片$kongbupian#战争片$zhanzhengpian#喜剧片$xijupian#纪录片$jilupian#剧情片$juqingpian||dianshiju--国产剧$guochanju#港台剧$gangtaiju#日韩剧$rihanju#欧美剧$oumeiju]\",\"地区\":\"0\",\"剧情\":\"0\",\"年份\":\"0\",\"排序\":\"0\",\"筛选\":\"1\"}"
    },
    {
      "key": "Gitcafe",
      "name": "小纸条(新)",
      "type": 3,
      "api": "csp_Gitcafe",
      "searchable": 1,
      "playerType": 1,
      "quickSearch": 1,
      "filterable": 1,
      "ext": "token;desc"
    },
    {
      "key": "找资源",
      "name": "找资源",
      "type": 3,
      "api": "csp_Zhaozy",
      "searchable": 1,
      "playerType": 1,
      "quickSearch": 1,
      "filterable": 1
    },
    {
      "key": "upyunsou",
      "name": "Up云搜",
      "type": 3,
      "api": "csp_Upyunso",
      "searchable": 1,
      "quickSearch": 1,
      "playerType": 1,
      "filterable": 0,
      "ext": "token;asc"
    },
    {
      "key": "yisou",
      "name": "宜搜",
      "type": 3,
      "api": "csp_Yisou",
      "searchable": 1,
      "quickSearch": 1,
      "playerType": 1,
      "filterable": 0
    },
    {
      "key": "AliPS",
      "name": "AliPS",
      "type": 3,
      "api": "csp_AliPS",
      "searchable": 1,
      "playerType": 1,
      "quickSearch": 1,
      "filterable": 1
    },
    {
      "key": "push_agent",
      "name": "推送",
      "type": 3,
      "api": "csp_PushAgent",
      "searchable": 1,
      "quickSearch": 1,
      "playerType": 1,
      "filterable": 1,
      "ext": "token;desc"
    }
  ],
  "parses": [
    {
      "name": "Web聚合",
      "type": 3,
      "url": "Web"
    },
    {
      "name": "Json聚合",
      "type": 3,
      "url": "Demo"
    },
    {
      "name": "xmflv",
      "type": 0,
      "url": "https://jx.xmflv.com/?url="
    },
    {
      "name": "freejson",
      "type": 0,
      "url": "https://h5.freejson.xyz/player/?url="
    },
    {
      "name": "365",
      "type": 0,
      "url": "https://chaxun.truechat365.com/?url=",
      "ext": {
        "flag": [
          "qq",
          "腾讯",
          "qiyi",
          "iqiyi",
          "爱奇艺",
          "奇艺",
          "youku",
          "优酷",
          "mgtv",
          "芒果",
          "letv",
          "乐视",
          "pptv",
          "PPTV",
          "sohu",
          "bilibili",
          "哔哩哔哩",
          "哔哩"
        ]
      }
    },
    {
      "name": "parwix稳定",
      "type": 0,
      "url": "https://jx.bozrc.com:4433/player/?url=",
      "ext": {
        "flag": [
          "qq",
          "腾讯",
          "qiyi",
          "iqiyi",
          "爱奇艺",
          "奇艺",
          "youku",
          "优酷",
          "mgtv",
          "芒果",
          "letv",
          "乐视",
          "pptv",
          "PPTV",
          "sohu",
          "bilibili",
          "哔哩哔哩",
          "哔哩"
        ]
      }
    },
    {
      "name": "parwix1",
      "type": 0,
      "url": "https://jx.parwix.com:4433/player/?url=",
      "ext": {
        "flag": [
          "qq",
          "腾讯",
          "qiyi",
          "iqiyi",
          "爱奇艺",
          "奇艺",
          "youku",
          "优酷",
          "mgtv",
          "芒果",
          "letv",
          "乐视",
          "pptv",
          "PPTV",
          "sohu",
          "bilibili",
          "哔哩哔哩",
          "哔哩"
        ]
      }
    },
    {
      "name": "parwix2",
      "type": 0,
      "url": "https://jx.parwix.com:4433/player/analysis.php?v=",
      "ext": {
        "flag": [
          "qq",
          "腾讯",
          "qiyi",
          "iqiyi",
          "爱奇艺",
          "奇艺",
          "youku",
          "优酷",
          "mgtv",
          "芒果",
          "letv",
          "乐视",
          "pptv",
          "PPTV",
          "sohu",
          "bilibili",
          "哔哩哔哩",
          "哔哩"
        ]
      }
    },
    {
      "name": "夜幕",
      "type": 0,
      "url": "https://www.yemu.xyz/?url=",
      "ext": {
        "flag": [
          "qq",
          "腾讯",
          "qiyi",
          "iqiyi",
          "爱奇艺",
          "奇艺",
          "youku",
          "优酷",
          "mgtv",
          "芒果",
          "letv",
          "乐视",
          "pptv",
          "PPTV",
          "sohu",
          "bilibili",
          "哔哩哔哩",
          "哔哩"
        ]
      }
    },
    {
      "name": "8090",
      "url": "https://www.8090g.cn/?url="
    },
    {
      "name": "油果",
      "type": 1,
      "url": "http://json.youguo520.top/fufeng/?url=",
      "ext": {
        "flag": [
          "qq",
          "腾讯",
          "qiyi",
          "iqiyi",
          "爱奇艺",
          "奇艺",
          "youku",
          "优酷",
          "mgtv",
          "芒果",
          "letv",
          "乐视",
          "pptv",
          "PPTV",
          "sohu",
          "bilibili",
          "哔哩哔哩",
          "哔哩"
        ],
        "header": {
          "User-Agent": "Dart/2.14 (dart:io)"
        }
      }
    },
    {
      "name": "懒懒1",
      "type": 1,
      "url": "http://123.57.56.94:9931/lanlan/?url="
    },
    {
      "name": "EXO",
      "type": 0,
      "url": "https://rx.69mj.com/?url=",
      "ext": {
        "flag": [
          "rx",
          "qq",
          "腾讯",
          "qiyi",
          "爱奇艺",
          "奇艺",
          "youku",
          "优酷",
          "mgtv",
          "芒果"
        ]
      }
    },
    {
      "name": "懒懒2",
      "type": 1,
      "url": "http://lanlan.ckflv.cn/?url=",
      "ext": {
        "flag": [
          "qiyi",
          "qq",
          "letv",
          "sohu",
          "youku",
          "mgtv",
          "bilibili",
          "wasu",
          "xigua",
          "1905"
        ]
      }
    },
    {
      "name": "parwix",
      "type": 0,
      "url": "https://jx.parwix.com:4433/player/?url="
    }
  ],
  "flags": [
    "youku",
    "qq",
    "iqiyi",
    "qiyi",
    "letv",
    "sohu",
    "tudou",
    "pptv",
    "mgtv",
    "wasu",
    "bilibili",
    "renrenmi"
  ],
  "wallpaper": "http://www.kf666888.cn/api/tvbox/img"
}
"""#
}
