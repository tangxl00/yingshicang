import XCTest
@testable import Yingshicang

/// v2.0.50 build 22 范围B批次的回归守卫（R-05/06/28/45/46/47/52/53）。
///
/// 覆盖（每条可证伪，缺实现必失败）：
/// 1. R-05 搜索二次筛选 —— 候选词 2-gram 滑窗 / 全词 AND 过滤 / 屏蔽源收缩结果
/// 2. R-06 筛选弹层 —— filter JSON 两形态解析 / extend 剔空 / 默认选中 / 470dp 贴底几何
/// 3. R-28 添加仓库弹层 —— 本地导入纯链路（好坏 JSON）/ 220dp 居中几何
/// 4. R-45 WebDAV 弹层 —— 连接结果五态分类 / base 归一化 / Basic 头 / 340×310dp 几何
/// 5. R-46 备份弹层 —— 备份包编解码往返 / 450dp 贴底几何
/// 6. R-47 授权回传 —— tok/token/access_token 提取（大小写不敏感）/ 授权容器工厂可实例化
/// 7. R-52 分类浮层 —— 初始选中态 / 400dp 贴底几何
/// 8. R-53 简介弹窗 —— 子串 vs 整词命中 / 高亮计数 / 全文未截断 / 440dp 居中几何
final class Build22Batch2RegressionTests: XCTestCase {

    // MARK: - 1. R-05 搜索结果二次筛选

    /// 候选词：2-gram 滑窗保序去重 + 原词收尾；单字只有原词。
    func testSecondaryFilterTokenGeneration() {
        XCTAssertEqual(SearchResultSecondaryFilter.tokens(from: "斗罗大陆"),
                       ["斗罗", "罗大", "大陆", "斗罗大陆"])
        XCTAssertEqual(SearchResultSecondaryFilter.tokens(from: "三"), ["三"], "单字关键词只有原词")
        XCTAssertEqual(SearchResultSecondaryFilter.tokens(from: "  "), [])
        // 重复 gram 去重：滑窗 gram 与原词相同时只保留首次（原词收尾）
        XCTAssertEqual(SearchResultSecondaryFilter.tokens(from: "aa"), ["aa"])
    }

    /// 过滤语义：结果必须同时包含全部选中词（片名或备注命中均可），大小写不敏感。
    func testSecondaryFilterAllTokenMatch() {
        let items = [
            VodItem(vodId: "1", vodName: "斗罗大陆 第1季", vodPic: "", vodRemarks: "全40集", siteKey: "s1"),
            VodItem(vodId: "2", vodName: "斗罗大陆", vodPic: "", vodRemarks: "HD", siteKey: "s1"),
            VodItem(vodId: "3", vodName: "大陆之恋", vodPic: "", vodRemarks: "更新中", siteKey: "s2")
        ]
        // 单词过滤
        XCTAssertEqual(SearchResultSecondaryFilter.filter(items, selectedTokens: ["斗罗"]).map(\.vodId),
                       ["1", "2"])
        // 双词 AND：必须同时命中「斗罗」和「40」
        XCTAssertEqual(SearchResultSecondaryFilter.filter(items, selectedTokens: ["斗罗", "40"]).map(\.vodId),
                       ["1"], "AND 语义：只含其一的必须被剔除")
        // 空选集原样返回
        XCTAssertEqual(SearchResultSecondaryFilter.filter(items, selectedTokens: []).count, 3)
        // 大小写不敏感（片名与备注拼合检索）
        let mixed = [VodItem(vodId: "9", vodName: "The Matrix", vodPic: "", vodRemarks: "", siteKey: "s")]
        XCTAssertEqual(SearchResultSecondaryFilter.filter(mixed, selectedTokens: ["matrix"]).count, 1)
    }

    /// 屏蔽源链路：走 SearchViewController.performSearch 同款站点过滤（searchableSites），
    /// 验证屏蔽源、jar 爬虫、不可搜站点在搜索管道入口即被剔除——测试不自证（不内联过滤逻辑）。
    func testBlockedSourceShrinksResults() throws {
        SiteBlockStore.shared.setBlocked("s2", blocked: true)
        defer { SiteBlockStore.shared.setBlocked("s2", blocked: false) }
        XCTAssertTrue(SiteBlockStore.shared.isBlocked("s2"))

        // 四个站点：正常 s1 / 被屏蔽 s2 / jar 爬虫 s3 / 不可搜 s4。
        let json = #"""
        [
          {"key":"s1","name":"源一","api":"https://a.example.com/api","searchable":1},
          {"key":"s2","name":"源二","api":"https://b.example.com/api","searchable":1},
          {"key":"s3","name":"jar源","api":"https://c.example.com/spider.jar","searchable":1},
          {"key":"s4","name":"禁搜","api":"https://d.example.com/api","searchable":0}
        ]
        """#
        let sites = try JSONDecoder().decode([SiteConfig].self, from: Data(json.utf8))
        XCTAssertEqual(sites.count, 4)

        let visible = SearchViewController.searchableSites(sites)
        XCTAssertEqual(visible.map(\.key), ["s1"], "屏蔽源、jar 爬虫、禁搜站点都必须从搜索管道消失")

        // 屏蔽解除后 s2 回到可搜集合（同一函数、同一 Store 的可逆性）。
        SiteBlockStore.shared.setBlocked("s2", blocked: false)
        XCTAssertEqual(SearchViewController.searchableSites(sites).map(\.key), ["s1", "s2"],
                       "解除屏蔽后站点必须恢复可搜")
    }

    // MARK: - 2. R-06 分类筛选弹层

    let filterJSON = #"{"class":[{"key":"class","name":"类型","value":[{"n":"全部","v":""},{"n":"电影","v":"1"}]},{"key":"area","name":"地区","value":[{"n":"全部","v":""},{"n":"大陆","v":"cn"}]}]}"#

    /// 解析：顶层 class 形态 / 直接数组形态 / 坏 JSON 与空串都返回空。
    func testFilterSheetParserShapes() {
        let top = FilterSheetParser.parse(filterJSON)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top[0].key, "class")
        XCTAssertEqual(top[0].name, "类型")
        XCTAssertEqual(top[0].options.count, 2)
        XCTAssertEqual(top[0].options[1], FilterOption(name: "电影", value: "1"))

        let array = FilterSheetParser.parse(#"[{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"}]}]"#)
        XCTAssertEqual(array.count, 1, "直接数组形态必须同样支持")
        XCTAssertEqual(array[0].name, "年份")

        XCTAssertTrue(FilterSheetParser.parse("not-json{").isEmpty, "坏 JSON 必须返回空而非崩溃")
        XCTAssertTrue(FilterSheetParser.parse(nil).isEmpty)
        XCTAssertTrue(FilterSheetParser.parse("").isEmpty)
        // 无 value 的维度被丢弃（弹层不出现空维度）
        XCTAssertTrue(FilterSheetParser.parse(#"[{"key":"k","name":"空维度","value":[]}]"#).isEmpty)
    }

    /// extend：值为空（「全部」）的维度不得进请求参数。
    func testFilterExtendDropsEmptyValues() {
        let out = FilterSheetParser.extend(from: ["class": "1", "area": "", "year": "2026"])
        XCTAssertEqual(out, ["class": "1", "year": "2026"], "空值维度必须剔除，与未筛选请求形态一致")
        XCTAssertTrue(FilterSheetParser.extend(from: ["area": ""]).isEmpty)
    }

    /// 默认选中：每个维度取第一项（通行约定第一项即「全部」）。
    func testFilterDefaultSelections() {
        let dimensions = FilterSheetParser.parse(filterJSON)
        let defaults = FilterSheetParser.defaultSelections(dimensions: dimensions)
        XCTAssertEqual(defaults, ["class": "", "area": ""], "默认即全部维度第一项（值为空）")
    }

    /// 筛选弹层几何：470dp 高、贴底、带拖拽条；默认态可判定。
    func testFilterSheetGeometryAndDefaultState() {
        let dimensions = FilterSheetParser.parse(filterJSON)
        let sheet = FilterSheetViewController(dimensions: dimensions)
        sheet.loadViewIfNeeded()
        XCTAssertEqual(sheet.config.height, DesignTokens.dp(470), "filterSheetHeight=470dp 是质检口径")
        XCTAssertEqual(sheet.config.anchor, .bottom)
        XCTAssertNotNil(sheet.dragBar, "贴底弹层必须带 40×4dp 拖拽条")
        XCTAssertTrue(sheet.isDefaultSelection, "初始态必须是默认选中")
    }

    // MARK: - 3. R-28 添加仓库弹层（本地导入）

    /// 本地导入纯链路：合法配置文本导入成功并入库；坏 JSON 返回可读错误。
    func testLocalConfigImporterRoundtrip() {
        let good = #"{"sites":[{"key":"h1","name":"HTML源","type":0,"api":"https://h.example.com"}]}"#
        let result = LocalConfigImporter.importConfig(text: good, sourceName: "本地导入")
        switch result {
        case .success(let bundle):
            XCTAssertEqual(bundle.sites.count, 1)
            XCTAssertEqual(bundle.sites[0].key, "h1")
        case .failure(let error):
            XCTFail("合法配置必须导入成功，实际失败：\(error.message)")
        }

        let bad = LocalConfigImporter.importConfig(text: "{{{", sourceName: "本地导入")
        switch bad {
        case .success:
            XCTFail("坏 JSON 不得导入成功")
        case .failure(let error):
            XCTAssertFalse(error.message.isEmpty, "失败必须给出可读原因")
        }
    }

    /// 添加仓库弹层几何：220dp 居中。
    func testAddStoreDialogGeometry() {
        let dialog = AddStoreDialogViewController()
        dialog.loadViewIfNeeded()
        XCTAssertEqual(dialog.config.height, DesignTokens.dp(220), "inputDialogHeight=220dp")
        XCTAssertEqual(dialog.config.anchor, .center)
    }

    // MARK: - 4. R-45 WebDAV 弹层

    /// 连接结果分类：2xx 成功 / 401·403 未授权 / 404 未找到 / 其余非 WebDAV / 传输失败优先。
    func testWebDavOutcomeClassification() {
        XCTAssertEqual(WebDavConnectionTester.Outcome.classify(status: 207, transport: nil), .ok)
        XCTAssertEqual(WebDavConnectionTester.Outcome.classify(status: 200, transport: nil), .ok)
        XCTAssertEqual(WebDavConnectionTester.Outcome.classify(status: 401, transport: nil), .unauthorized)
        XCTAssertEqual(WebDavConnectionTester.Outcome.classify(status: 403, transport: nil), .unauthorized)
        XCTAssertEqual(WebDavConnectionTester.Outcome.classify(status: 404, transport: nil), .notFound)
        XCTAssertEqual(WebDavConnectionTester.Outcome.classify(status: 500, transport: nil), .notWebDav)
        let failure = TransportFailure(code: -1009, domain: NSURLErrorDomain, message: "offline")
        XCTAssertEqual(WebDavConnectionTester.Outcome.classify(status: 200, transport: failure),
                       .transport("NSURLErrorDomain -1009：offline"),
                       "传输层失败必须优先于状态码，不得伪造成功")
    }

    /// 地址归一化与备份文件拼接：去全部尾斜杠、固定文件名。
    func testWebDavBaseNormalization() {
        XCTAssertEqual(WebDavConnectionTester.normalizedBase("  https://dav.example.com/dav/// "),
                       "https://dav.example.com/dav")
        XCTAssertEqual(WebDavConnectionTester.normalizedBase("https://a.com"), "https://a.com")
        XCTAssertEqual(WebDavConnectionTester.backupFileURL(base: "https://dav.example.com/dav/"),
                       "https://dav.example.com/dav/yingshicang-backup.json")
        XCTAssertEqual(WebDavConnectionTester.backupFileURL(base: ""), "")
    }

    /// Basic 认证头：标准 base64(user:password)。
    func testBasicAuthorizationHeader() {
        XCTAssertEqual(WebDavConnectionTester.basicAuthorization(account: "user", password: "pass"),
                       "Basic " + Data("user:pass".utf8).base64EncodedString())
        XCTAssertTrue(WebDavConnectionTester.basicAuthorization(account: "user", password: "pass").hasPrefix("Basic "))
    }

    /// WebDAV 编辑弹层几何：340dp 宽居中。
    func testWebDavEditDialogGeometry() {
        let dialog = WebDavEditDialogViewController()
        dialog.loadViewIfNeeded()
        XCTAssertEqual(dialog.config.width, DesignTokens.dp(340), "webDavWidth=340dp")
        XCTAssertEqual(dialog.config.anchor, .center)
    }

    // MARK: - 5. R-46 备份弹层

    /// 备份包编解码往返：history + favorites + blockedSites 全量无损。
    func testBackupPayloadEncodeDecodeRoundtrip() {
        let history = HistoryRecord(siteKey: "s1", vodId: "v1", vodName: "斗罗大陆",
                                    vodPic: "", flag: "", playIndex: 0, episodeIndex: 3,
                                    position: 12.5, duration: 2400, updatedAt: 100, finished: false)
        let favorite = FavoriteRecord(siteKey: "s1", vodId: "v1", vodName: "斗罗大陆", vodPic: "", createdAt: 100)
        let payload = BackupPayload(version: 1, exportedAt: 200, history: [history],
                                    favorites: [favorite], blockedSites: ["s2"])
        guard let json = BackupPayload.encodeJSON(payload) else {
            return XCTFail("备份包编码不得失败")
        }
        guard let decoded = BackupPayload.decodeJSON(json) else {
            return XCTFail("备份包解码不得失败")
        }
        XCTAssertEqual(decoded, payload, "编解码往返必须逐字段相等")
        XCTAssertEqual(decoded.blockedSites, ["s2"])
        XCTAssertNil(BackupPayload.decodeJSON("not-json"))
    }

    /// 备份弹层几何：450dp 贴底带拖拽条。
    func testBackupSheetGeometry() {
        let sheet = BackupSheetViewController()
        sheet.loadViewIfNeeded()
        XCTAssertEqual(sheet.config.height, DesignTokens.dp(450), "backupSheetHeight=450dp")
        XCTAssertEqual(sheet.config.anchor, .bottom)
        XCTAssertNotNil(sheet.dragBar)
    }

    // MARK: - 6. R-47 授权回传

    /// 令牌提取：tok/token/access_token 三键、大小写不敏感、无参 URL 返回 nil。
    func testWebContainerTokenExtraction() {
        func url(_ s: String) -> URL { URL(string: s)! }
        XCTAssertEqual(WebContainerViewController.extractToken(from: url("https://ali.example/callback?tok=abc123")),
                       "abc123")
        XCTAssertEqual(WebContainerViewController.extractToken(from: url("https://ali.example/callback?token=xyz")),
                       "xyz")
        XCTAssertEqual(WebContainerViewController.extractToken(from: url("https://ali.example/cb?access_token=t-9")),
                       "t-9")
        XCTAssertEqual(WebContainerViewController.extractToken(from: url("https://ali.example/cb?TOK=up")),
                       "up", "参数名大小写不敏感")
        XCTAssertNil(WebContainerViewController.extractToken(from: url("https://ali.example/callback?code=1")))
        XCTAssertNil(WebContainerViewController.extractToken(from: url("https://ali.example/cb?tok=")),
                     "空令牌视同未授权")
    }

    /// 授权容器工厂可实例化并挂载令牌回调。
    func testWebContainerAuthorizingFactoryBuilds() {
        let container = WebContainerViewController.authorizing(
            url: URL(string: "https://ali.example/callback?tok=abc")!,
            allowedHosts: ["ali.example"]) { _ in }
        container.loadViewIfNeeded()
        XCTAssertNotNil(container.onAuthorizedToken, "授权工厂必须挂载令牌回调")
        XCTAssertEqual(container.webView.superview, container.view, "容器加载后 webView 必须已挂到视图层级")
    }

    // MARK: - 7. R-52 分类全宽浮层

    /// 分类浮层：初始选中保持、400dp 贴底几何。
    func testCategorySheetInitialStateAndGeometry() {
        let categories = [SiteCategory(id: "1", name: "电影"),
                          SiteCategory(id: "2", name: "剧集"),
                          SiteCategory(id: "3", name: "综艺")]
        let sheet = CategorySheetViewController(categories: categories, selectedIndex: 1)
        sheet.loadViewIfNeeded()
        XCTAssertTrue(sheet.isSelectionUnchanged, "未点选前选中态不得漂移")
        XCTAssertEqual(sheet.config.height, DesignTokens.dp(400))
        XCTAssertEqual(sheet.config.anchor, .bottom)
        XCTAssertNotNil(sheet.dragBar)
    }

    // MARK: - 8. R-53 简介弹窗

    let introText = "三体人向地球发射了智子。三体舰队即将抵达。人类面对三体危机组建了面壁计划。"

    /// 检索纯逻辑：子串命中多处 / 整词边界判定（ASCII 词字符才构成边界）/ 空关键词。
    func testIntroTextSearcherRanges() {
        // 子串：三处「三体」
        XCTAssertEqual(IntroTextSearcher.ranges(of: "三体", in: introText, exact: false).count, 3)
        // 中文邻接不构成词边界 → 整词命中同为 3 处
        XCTAssertEqual(IntroTextSearcher.ranges(of: "三体", in: introText, exact: true).count, 3)
        // ASCII 词边界："matrix" 在 MatrixReloaded 里是子串命中但非整词（后跟字母 R）
        let latin = "The Matrix MatrixReloaded"
        XCTAssertEqual(IntroTextSearcher.ranges(of: "matrix", in: latin, exact: false).count, 2)
        XCTAssertEqual(IntroTextSearcher.ranges(of: "matrix", in: latin, exact: true).count, 1)
        // 空关键词
        XCTAssertTrue(IntroTextSearcher.ranges(of: "  ", in: introText, exact: false).isEmpty)
        // 命中范围升序不重叠
        let ranges = IntroTextSearcher.ranges(of: "三体", in: introText, exact: false)
        XCTAssertEqual(ranges, ranges.sorted { $0.location < $1.location })
        for index in 1..<ranges.count {
            XCTAssertLessThanOrEqual(ranges[index - 1].location + ranges[index - 1].length,
                                     ranges[index].location, "命中不得重叠")
        }
    }

    /// 简介弹窗：全文未截断 + 搜索高亮计数（子串 vs 整词）+ 440dp 居中几何。
    func testIntroDialogFullTextAndSearch() {
        let dialog = IntroDialogViewController(vodName: "三体", content: introText)
        dialog.loadViewIfNeeded()
        XCTAssertEqual(dialog.displayedText, introText, "弹窗必须展示完整简介而非 4 行截断")
        XCTAssertEqual(dialog.config.height, DesignTokens.dp(440))
        XCTAssertEqual(dialog.config.anchor, .center)

        dialog.applySearch(query: "三体", exact: false)
        XCTAssertEqual(dialog.highlightCount, 3, "子串模式命中 3 处")
        XCTAssertEqual(dialog.currentHighlightIndex, 0)

        dialog.applySearch(query: "三体", exact: true)
        XCTAssertEqual(dialog.highlightCount, 3, "精确模式：中文邻接不构成边界，整词命中仍为 3 处")

        dialog.applySearch(query: "不存在的词", exact: false)
        XCTAssertEqual(dialog.highlightCount, 0, "无命中时不得残留上一次高亮计数")
    }
}
