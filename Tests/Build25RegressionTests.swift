import XCTest
@testable import Yingshicang

/// build 25 P0 修复守卫：主页「无限转圈」。
///
/// 真机现象（build 24）：配置加载成功后进主页，只有左上角一个加载圈永远不结束，
/// 无超时、无报错、无兜底，App 完全不可用。
///
/// 已核实的双重根因（本文件逐条固化为可证伪断言）：
/// 1. **站点形态判定错**：jar 声明在配置顶层 `spider`，站点 `api` 只写 jar 内的 Java 类名
///    （`csp_DouDou`）。旧 `isJarSpider` 只看 `.jar` 后缀 → 59 个无 jar 字段的 `csp_*` 站点被放行，
///    工厂还把 `csp_` 前缀按 API 处理 → 默认首站（csp_douban）必然拿不到内容且不回调。
/// 2. **Provider 回调被丢弃**：`JSSiteProvider.invokeRaw` 用 `[weak self] + guard else return`，
///    调用方不持有 provider 时 completion 永不触发（既无成功也无失败）。
/// 3. 全链路没有期限：任何「永挂起」的路径都没有出口。
///
/// 真实验收数据：https://raw.liucn.cc/box/m.json（234 站点 = 168 jar 类 + 51 .js + 15 接口），
/// fixture 直接复用 Build24RegressionTests.lichengJSON（同一份原文，不另造样本）。
final class Build25RegressionTests: XCTestCase {

    private static var bundle: ConfigBundle { ConfigParser.parse(text: Build24RegressionTests.lichengJSON) }

    // MARK: - 1. 站点形态判定（唯一事实源）

    /// 真实配置：jar 类 / 可用站点的规模必须与实测一致（不是「猜」出来的口径）。
    func testRealConfigSiteKindDistribution() {
        let bundle = Self.bundle
        XCTAssertEqual(bundle.sites.count, 234)
        let jar = bundle.sites.filter { $0.spiderKind == .jarClass }
        let js = bundle.sites.filter { $0.spiderKind == .jsScript }
        let api = bundle.sites.filter { $0.spiderKind == .httpAPI }
        XCTAssertEqual(jar.count, 168, "jar 类站点（csp_* 类名 + .jar 后缀）实测 168 个")
        XCTAssertEqual(js.count, 51, ".js 脚本站点实测 51 个")
        XCTAssertEqual(api.count, 15, "http 接口站点实测 15 个")
        XCTAssertEqual(jar.count + js.count + api.count, bundle.sites.count, "三类形态必须全覆盖、无遗漏")
        XCTAssertEqual(bundle.sites.filter { !$0.isPlatformSupported }.count, 168,
                       "iOS 不可用站点必须正好是 jar 类那 168 个")
    }

    /// 旧判定（只看 `.jar` 后缀）会漏掉没有 jar 字段的 `csp_*` 站点——
    /// 这正是首屏选中 csp_douban 的直接原因。此处固化两者的差集规模。
    func testBareClassApiIsJarClassNotAPI() {
        let bundle = Self.bundle
        let csp = bundle.sites.filter { $0.api.hasPrefix("csp_") }
        XCTAssertEqual(csp.count, 165)
        XCTAssertTrue(csp.allSatisfy { $0.spiderKind == .jarClass },
                      "api 为裸 Java 类名的站点一律是 jar 类，不得按 API 处理")
        let legacyPassed = bundle.sites.filter { !$0.isJarSpider }
        XCTAssertEqual(legacyPassed.count, 126, "旧判定放行 126 个站点")
        let legacyWronglyPassed = legacyPassed.filter { !$0.isPlatformSupported }
        XCTAssertEqual(legacyWronglyPassed.count, 61,
                       "旧判定把 61 个 iOS 不可用站点（59 个无 jar 字段的 csp_* + 2 个裸类名 py_*）放进了候选集")
    }

    /// 默认首站必须是可用站点，不能是 csp_douban（jar 类）。
    func testDefaultSiteSkipsJarSite() {
        let bundle = Self.bundle
        XCTAssertEqual(bundle.sites.first?.key, "csp_douban", "配置第一个站点确实是 jar 站（故障触发点）")
        XCTAssertFalse(bundle.sites.first?.isPlatformSupported ?? true,
                       "故障前提：配置首个站点在 iOS 不可用")
        guard let picked = HomeViewController.defaultSite(in: bundle.sites) else {
            return XCTFail("配置里有 66 个可用站点，默认选择不得为空")
        }
        XCTAssertEqual(picked.key, "直播转点播", "默认必须跳到第一个可用站点")
        XCTAssertEqual(picked.api, "./libs/tv/zb.min.js")
        XCTAssertTrue(picked.isPlatformSupported)
        XCTAssertNotEqual(picked.key, "csp_douban", "默认站点绝不能停在 jar 站")
    }

    /// 全不可用时默认选择返回 nil（主页据此显示说明而不是空转）。
    func testDefaultSiteNilWhenAllUnusable() {
        let json = #"""
        [{"key":"a","name":"A","type":3,"api":"csp_A"},
         {"key":"b","name":"B","type":3,"api":"py_B","jar":"./libs/jar/b.jar"}]
        """#
        let sites = (try? JSONDecoder().decode([SiteConfig].self, from: Data(json.utf8))) ?? []
        XCTAssertEqual(sites.count, 2)
        XCTAssertTrue(sites.allSatisfy { !$0.isPlatformSupported })
        XCTAssertNil(HomeViewController.defaultSite(in: sites), "全不可用时必须没有默认站点")
    }

    // MARK: - 2. jar 站点立即终止（不挂起）

    /// jar 站点的主页/分类/搜索/详情/播放都必须**同步立即**返回 unsupportedJar，
    /// 而不是留在 pending 等一个永远不会来的回调。
    func testJarSiteReturnsUnsupportedImmediately() {
        let jarSite = SiteConfig.fixture(key: "csp_douban", name: "🌕┃豆瓣┃热播",
                                         type: 3, api: "csp_DouDou")
        let provider = SiteProviderFactory.make(site: jarSite)
        XCTAssertTrue(provider is UnsupportedSiteProvider, "jar 站点必须路由到显式不支持实现")

        var results: [Result<[VodItem], SiteError>] = []
        provider.home { results.append($0) }
        provider.category(id: "1", page: 1, extend: [:]) { results.append($0) }
        provider.search(keyword: "三体", page: 1) { results.append($0) }
        XCTAssertEqual(results.count, 3, "三个入口必须全部同步回调（同步返回即不存在挂起窗口）")
        for result in results {
            guard case .failure(let error) = result else { return XCTFail("jar 站点不得返回成功") }
            XCTAssertEqual(error, .unsupportedJar("🌕┃豆瓣┃热播"))
        }

        var detailResult: Result<VodDetail, SiteError>?
        provider.detail(id: "1") { detailResult = $0 }
        guard case .failure(let error) = detailResult else {
            return XCTFail("jar 站点详情必须立即失败")
        }
        XCTAssertEqual(error, .unsupportedJar("🌕┃豆瓣┃热播"))

        var playResult: Result<PlayResolution, SiteError>?
        provider.play(flag: "1", url: "http://x") { playResult = $0 }
        guard case .failure(let error) = playResult else {
            return XCTFail("jar 站点播放必须立即失败")
        }
        XCTAssertEqual(error, .unsupportedJar("🌕┃豆瓣┃热播"))
    }

    /// 真实配置里的默认首站必须走「不支持」而不是 API/JS provider——
    /// 旧实现把 `csp_` 前缀路由给 APISiteProvider，这才是首屏挂起的机制。
    func testRealDefaultSiteDoesNotEnterAPIProvider() {
        let bundle = Self.bundle
        guard let first = bundle.sites.first else { return XCTFail("配置必须有站点") }
        XCTAssertFalse(SiteProviderFactory.make(site: first) is APISiteProvider,
                       "csp_douban 不得进 APISiteProvider（旧实现的错路由）")
        XCTAssertFalse(SiteProviderFactory.make(site: first) is JSSiteProvider,
                       "csp_douban 不得进 JSSiteProvider")
        XCTAssertTrue(SiteProviderFactory.make(site: first) is UnsupportedSiteProvider)
    }

    /// UI 层的错误分类：只有 unsupportedJar 是「终态，给切换站点」，
    /// 其余错误必须给「重试」，否则用户拿不到正确出口。
    func testUnsupportedClassificationDrivesExits() {
        XCTAssertTrue(CategoryContentViewController.isUnsupported(.unsupportedJar("X")))
        XCTAssertFalse(CategoryContentViewController.isUnsupported(.timeout(20)))
        XCTAssertFalse(CategoryContentViewController.isUnsupported(.network(404)))
        XCTAssertFalse(CategoryContentViewController.isUnsupported(.parse("x")))
    }

    // MARK: - 3. 超时兜底（永不回调的 Provider 也必须落地）

    /// 模拟「永不回调」的 Provider：SiteLoad 必须在期限内交回 .timeout。
    func testNeverCallingProviderSettlesByTimeout() {
        let expectation = expectation(description: "timeout fallback")
        let started = Date()
        var settled: Result<[VodItem], SiteError>?
        SiteLoad.run(timeout: 0.5) { result in
            settled = result
            expectation.fulfill()
        } operation: { _ in
            // 故意什么都不做：模拟脚本卡死 / 请求挂起 / 实例已释放导致 completion 丢失。
        }
        wait(for: [expectation], timeout: 3)

        guard case .failure(.timeout(let seconds)) = settled else {
            return XCTFail("永不回调必须以 .timeout 收口，实际: \(String(describing: settled))")
        }
        XCTAssertEqual(seconds, 0.5, "超时时长必须如实反映给用户")
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "必须在期限内结束，不能无限等待")
        XCTAssertTrue(SiteError.timeout(0.5).errorDescription?.contains("加载超时") ?? false)
        XCTAssertTrue(SiteError.timeout(0.5).errorDescription?.contains("重试") ?? false,
                      "超时文案必须给出可操作的下一步")
    }

    /// 迟到结果不能覆盖已落地的状态（否则界面会被翻回「加载中」）。
    func testLateResultCannotOverwriteFirstSettle() {
        let expectation = expectation(description: "first settle wins")
        var delivered: [Result<[VodItem], SiteError>] = []
        let guarded = LoadGuard<[VodItem]>(timeout: 0.2) { result in
            delivered.append(result)
            expectation.fulfill()
        }
        guarded.start()
        // 立刻给出真实结果：应当落地为成功。
        guarded.settle(.success([VodItem.fixtureStub()]))
        wait(for: [expectation], timeout: 2)
        // 再补一次迟到结果，必须被丢弃。
        guarded.settle(.failure(.timeout(0.2)))
        XCTAssertEqual(delivered.count, 1, "只允许第一次 settle 生效")
        guard case .success(let items) = delivered.first, items.count == 1 else {
            return XCTFail("先到的成功结果必须保留，实际: \(String(describing: delivered.first))")
        }
        XCTAssertTrue(guarded.isSettled, "已 settle 的守卫必须自报已结束")
    }

    /// 正常返回的 Provider 不被超时干扰（守卫不是「无条件超时」）。
    func testRealResultPassesThroughGuard() {
        let expectation = expectation(description: "passthrough")
        var settled: Result<[VodItem], SiteError>?
        SiteLoad.run(timeout: 2) { result in
            settled = result
            expectation.fulfill()
        } operation: { settle in
            settle(.success([VodItem.fixtureStub()]))
        }
        wait(for: [expectation], timeout: 4)
        guard case .success(let items) = settled else {
            return XCTFail("正常结果必须原样透出，实际: \(String(describing: settled))")
        }
        XCTAssertEqual(items.count, 1)
    }

    // MARK: - 4. 站点切换列表：可用性标识与排序

    /// 站点切换列表的顺序与文案：可用站点在前，不可用带显式标识（色弱/截图沟通都不能只靠颜色）。
    func testSiteSwitchOrderingAndLabel() {
        let sites = [
            SiteConfig.fixture(key: "j1", name: "🌕┃豆瓣┃热播", type: 3, api: "csp_DouDou"),
            SiteConfig.fixture(key: "ok1", name: "📺︎┃电视┃点播", type: 3, api: "./libs/tv/zb.min.js"),
            SiteConfig.fixture(key: "j2", name: "🐼┃绿豆┃影视", type: 3, api: "csp_Lvdou"),
            SiteConfig.fixture(key: "ok2", name: "接口站", type: 1, api: "https://a.example.com/api")
        ]
        let ordered = SiteSwitchSheetViewController.orderedRows(sites)
        XCTAssertEqual(ordered.map(\.key), ["ok1", "ok2", "j1", "j2"], "可用站点必须排在不可用之前")
        XCTAssertEqual(SiteSwitchSheetViewController.rowTitle(for: sites[0]),
                       "🌕┃豆瓣┃热播（jar 插件·iOS 不支持）")
        XCTAssertEqual(SiteSwitchSheetViewController.rowTitle(for: sites[1]), "📺︎┃电视┃点播",
                       "可用站点标题不加任何后缀")
        XCTAssertEqual(ordered.filter { $0.isPlatformSupported }.count, 2)
    }

    /// 真实配置上验证切换列表口径：168 个带标识、66 个可选，且首行就是可用站点。
    func testSiteSwitchOnRealConfig() {
        let bundle = Self.bundle
        let ordered = SiteSwitchSheetViewController.orderedRows(bundle.sites)
        XCTAssertEqual(ordered.count, 234, "切换列表必须是全量站点，不能只列可用站点")
        XCTAssertEqual(ordered.first?.key, "直播转点播", "列表首行必须是第一个可用站点")
        XCTAssertEqual(ordered.filter { $0.isPlatformSupported }.count, 66)
        XCTAssertEqual(ordered.filter { !$0.isPlatformSupported }.count, 168)
        XCTAssertTrue(ordered.suffix(168).allSatisfy { !$0.isPlatformSupported },
                      "尾部 168 行必须全是不可用站点")
    }

    // MARK: - 5. 搜索与主页候选集口径一致

    /// 搜索管道同样跳过 jar 类站点（否则每轮搜索都会白等 168 个死站点）。
    func testSearchPipelineSkipsJarSites() {
        let bundle = Self.bundle
        let searchable = SearchViewController.searchableSites(bundle.sites)
        XCTAssertTrue(searchable.allSatisfy { $0.isPlatformSupported },
                      "可搜集合不得包含 jar 类站点")
        XCTAssertLessThanOrEqual(searchable.count, 66)
        XCTAssertFalse(searchable.contains { $0.key == "csp_douban" })
    }

    /// 首屏链路必须只剩可用站点作为候选（主页候选集的过滤口径）。
    func testHomeCandidateSetExcludesUnsupported() {
        let bundle = Self.bundle
        let candidates = bundle.sites.filter { $0.isPlatformSupported }
        XCTAssertEqual(candidates.count, 66)
        XCTAssertEqual(candidates.first?.key, "直播转点播")
        XCTAssertFalse(candidates.contains { $0.spiderKind == .jarClass })
        XCTAssertEqual(bundle.sites.filter { $0.isJarSpider }.count, 108,
                       "旧口径只识别 108 个（仅带 jar 字段的站点），保留该事实以说明差集来源")
    }
}

// MARK: - 测试夹具

extension SiteConfig {
    /// 构造最小站点（不改生产代码的 Codable 行为，测试内直接走 JSON 解码路径）。
    static func fixture(key: String, name: String, type: Int, api: String, jar: String = "") -> SiteConfig {
        let dict: [String: Any] = ["key": key, "name": name, "type": type, "api": api, "jar": jar]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(SiteConfig.self, from: data)
    }
}

extension VodItem {
    static func fixtureStub() -> VodItem {
        VodItem(vodId: "1", vodName: "测试影片", vodPic: "", vodRemarks: "", siteKey: "test")
    }
}
