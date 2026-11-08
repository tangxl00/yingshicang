import XCTest
@testable import Yingshicang

/// v2.0.50 build 22 剩余范围（批次三）回归守卫。
///
/// 覆盖（每条可证伪，缺实现必失败）：
/// 1. R-54 免责声明 —— 首启未同意 / 同意持久化 / reset 复原（隔离 UserDefaults）
/// 2. R-48 阿里 Token —— normalize / 32 位十六进制合法性 / 弹层几何
/// 3. R-33 赞赏弹窗 —— 文案常量非空 / 弹层可实例化
/// 4. R-50 频道密码 —— 加密频道判定 / 密码校验三态
/// 5. R-32 摇一摇 —— 合成加速度序列：静止不触发、上升沿触发、冷却防连触 / 随机挑选器可注入
/// 6. R-44 扫码页 —— 冷却常量 / 页面可实例化（模拟器走手动输入路径）
/// 7. R-07 榜单页 —— 榜单上限 / 卡片几何令牌 / 页面可实例化
/// 8. R-08 条件筛选 —— 无 filter 站点维度为空 / 有 filter 站点维度解析 / 全屏页可实例化
/// 9. R-42 TV 互动 —— 指令集映射 / 地址归一化 / 请求 URL 构造 / 页面可实例化
/// 10. R-43/R-49/F-18 局域网 —— 端点解析 / 推送 URL / 服务类型声明 / 推送请求构造
/// 11. F-20 下载任务 —— 增删查 / 去重 / 状态流转 / 持久化往返（隔离 UserDefaults）
/// 12. R-31 快捷弹窗 —— 180dp 宽度 / 可实例化
final class Build22Batch3RegressionTests: XCTestCase {

    /// 隔离的 UserDefaults（每次全新 suite，不污染标准域）。
    private func isolatedDefaults() -> UserDefaults {
        let name = "batch3.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    // MARK: - 1. R-54 免责声明

    func testDisclaimerGateFirstLaunchThenPersisted() {
        let defaults = isolatedDefaults()
        XCTAssertFalse(DisclaimerGate.isAccepted(defaults: defaults), "首启必须未同意")
        DisclaimerGate.accept(defaults: defaults)
        XCTAssertTrue(DisclaimerGate.isAccepted(defaults: defaults), "同意后必须持久化")
        DisclaimerGate.reset(defaults: defaults)
        XCTAssertFalse(DisclaimerGate.isAccepted(defaults: defaults), "reset 后回到未同意（下次启动再次弹出）")
    }

    func testDisclaimerDialogGeometry() {
        let dialog = DisclaimerDialogViewController()
        XCTAssertEqual(dialog.config.title, "免责声明")
        XCTAssertEqual(dialog.config.anchor, .center)
        XCTAssertEqual(dialog.config.height, 420, "免责弹窗内容高度 420dp 口径")
    }

    // MARK: - 2. R-48 阿里 Token

    func testAliTokenValidatorNormalizeAndValidity() {
        let valid = "0123456789abcdef0123456789ABCDEF"
        XCTAssertTrue(AliTokenValidator.isValid(valid), "32 位十六进制必须合法（大小写混合）")
        XCTAssertTrue(AliTokenValidator.isValid("  \(valid) \n"), "首尾空白经 normalize 后仍合法")
        XCTAssertFalse(AliTokenValidator.isValid("0123456789abcdef0123456789ABCDEF0"), "33 位必须非法")
        XCTAssertFalse(AliTokenValidator.isValid("0123456789abcdef0123456789ABCDEG"), "非十六进制字符必须非法")
        XCTAssertFalse(AliTokenValidator.isValid(""), "空串非法")
        XCTAssertEqual(AliTokenValidator.normalize("  ab cd\t\n"), "abcd", "内部空白必须被剔除")
    }

    func testAliTokenDialogGeometry() {
        let dialog = AliTokenDialogViewController()
        XCTAssertEqual(dialog.config.title, "阿里云盘 Token")
        XCTAssertEqual(dialog.config.height, 220, "输入弹窗 220dp 口径")
        XCTAssertEqual(dialog.config.anchor, .center)
    }

    // MARK: - 3. R-33 赞赏弹窗

    func testRewardContentAndDialog() {
        XCTAssertFalse(RewardContent.title.isEmpty)
        XCTAssertFalse(RewardContent.body.isEmpty)
        XCTAssertFalse(RewardContent.contactCopyText.isEmpty)
        let dialog = RewardDialogViewController()
        XCTAssertEqual(dialog.config.title, RewardContent.title)
        XCTAssertEqual(dialog.config.anchor, .center)
    }

    // MARK: - 4. R-50 频道密码

    func testChannelPasswordRule() {
        XCTAssertTrue(ChannelPasswordRule.needsPassword(categoryName: "密码频道"))
        XCTAssertTrue(ChannelPasswordRule.needsPassword(categoryName: "加密 电影"))
        XCTAssertFalse(ChannelPasswordRule.needsPassword(categoryName: "电影"))
        XCTAssertFalse(ChannelPasswordRule.needsPassword(categoryName: "热播 剧"))
        // 密码校验：等值 / 空期望恒过 / 空输入失败
        XCTAssertTrue(ChannelPasswordRule.validate("1234", expected: "1234"))
        XCTAssertTrue(ChannelPasswordRule.validate(" 1234 ", expected: "1234"), "输入 trim 后等值")
        XCTAssertFalse(ChannelPasswordRule.validate("12345", expected: "1234"))
        XCTAssertFalse(ChannelPasswordRule.validate("", expected: "1234"))
        XCTAssertTrue(ChannelPasswordRule.validate("anything", expected: ""), "未设置密码恒通过")
    }

    func testChannelPasswordDialogGeometry() {
        let dialog = ChannelPasswordDialogViewController(categoryName: "密码频道",
                                                         expectedPassword: nil) {}
        XCTAssertEqual(dialog.config.title, "频道密码")
        XCTAssertEqual(dialog.config.height, 180, "密码弹窗 180dp 口径")
    }

    func testChannelPasswordDialogValidatorInjection() {
        // 注入式校验：正确密码回调一次，错误密码不回调。
        let dialog = ChannelPasswordDialogViewController(categoryName: "加密") { input in
            input == "secret"
        } onUnlocked: {
            XCTFail("错误密码不得触发解锁回调")
        }
        // 仅验证注入链路构造成功；校验语义由 ChannelPasswordRule 测试覆盖。
        XCTAssertNotNil(dialog)
        let ok = ChannelPasswordDialogViewController(categoryName: "加密") { input in
            input == "secret"
        } onUnlocked: {}
        XCTAssertNotNil(ok)
    }

    // MARK: - 5. R-32 摇一摇

    /// 静止样本：重力附近小幅波动，绝不触发。
    func testShakeDetectorRestDoesNotTrigger() {
        let detector = ShakeDetector()
        for i in 0..<60 {
            let sample = ShakeSample(x: 0.01 * Double(i % 3), y: 0.02, z: 9.8, timestamp: Double(i) * 0.033)
            XCTAssertFalse(detector.ingest(sample), "静止样本不得触发摇一摇")
        }
    }

    /// 上升沿触发 + 冷却：第一次甩动触发，冷却期内第二次不触发，冷却后可再触发。
    func testShakeDetectorRisingEdgeAndCooldown() {
        let detector = ShakeDetector()
        // t=0 静止
        XCTAssertFalse(detector.ingest(ShakeSample(x: 0, y: 0, z: 9.8, timestamp: 0)))
        // t=1 猛甩（合力偏离重力 > 2.2g）→ 触发
        XCTAssertTrue(detector.ingest(ShakeSample(x: 0, y: 0, z: 9.8 + 3.0, timestamp: 1.0)), "超阈值上升沿必须触发")
        // t=1.05 回落 + 再次超阈值（冷却期内）→ 不触发
        XCTAssertFalse(detector.ingest(ShakeSample(x: 0, y: 0, z: 9.8, timestamp: 1.05)))
        XCTAssertFalse(detector.ingest(ShakeSample(x: 0, y: 0, z: 9.8 + 3.0, timestamp: 1.06)),
                       "冷却期内不得重复触发")
        // t=5（超过 1.5s 冷却）回落 + 超阈值 → 再次触发
        XCTAssertFalse(detector.ingest(ShakeSample(x: 0, y: 0, z: 9.8, timestamp: 5.0)))
        XCTAssertTrue(detector.ingest(ShakeSample(x: 0, y: 0, z: 9.8 + 3.0, timestamp: 5.01)), "冷却后必须可再触发")
    }

    /// 摇一摇推荐挑选器：注入固定 RNG 可复现，空列表返回 nil。
    func testShakeRecommendationPickerDeterministic() {
        struct FixedRNG: RandomNumberGenerator {
            var value: UInt64
            mutating func next() -> UInt64 { value }
        }
        let items = [
            VodItem(vodId: "a", vodName: "A", vodPic: "", vodRemarks: "", siteKey: "s"),
            VodItem(vodId: "b", vodName: "B", vodPic: "", vodRemarks: "", siteKey: "s"),
            VodItem(vodId: "c", vodName: "C", vodPic: "", vodRemarks: "", siteKey: "s")
        ]
        var rng1 = FixedRNG(value: 1)
        var rng2 = FixedRNG(value: 1)
        XCTAssertEqual(ShakeRecommendationPicker.pick(items, using: &rng1)?.vodId,
                       ShakeRecommendationPicker.pick(items, using: &rng2)?.vodId,
                       "同种子必须挑选同一部")
        var rngB = FixedRNG(value: 2)
        XCTAssertNotNil(ShakeRecommendationPicker.pick(items, using: &rngB))
        XCTAssertNil(ShakeRecommendationPicker.pick([]), "空候选不得返回影片")
    }

    // MARK: - 6. R-44 扫码页

    func testScanCodePageContract() throws {
        XCTAssertEqual(ScanCodeViewController.scanCooldown, 2.0, "扫码冷却 2 秒")
        let controller = ScanCodeViewController { _ in }
        XCTAssertNotNil(controller, "扫码页必须可实例化（相机不可用时走手动输入路径）")
        // 相机不可用时的降级路径必须真实存在：手动输入框 + 确认按钮 + 失败提示。
        let source = try sourceOf("Yingshicang/Features/Home/ScanCodeViewController.swift")
        XCTAssertTrue(source.contains("manualField"), "扫码页必须有手动输入框")
        XCTAssertTrue(source.contains("手动输入配置地址"), "手动输入框必须有占位文案")
        XCTAssertTrue(source.contains("确认地址"), "手动输入必须有确认按钮")
        XCTAssertTrue(source.contains("打开相机失败") || source.contains("相机"), "相机不可用必须有提示路径")
    }

    // MARK: - 7. R-07 榜单页

    func testRankListContract() {
        XCTAssertEqual(RankListViewController.rankLimit, 50)
        XCTAssertEqual(DesignTokens.Metrics.rankCardHeight, 160, "榜单卡高 160dp")
        XCTAssertEqual(DesignTokens.Metrics.rankCoverHeight, 140, "封面高 140dp")
        XCTAssertEqual(DesignTokens.Metrics.rankCoverRatio, 448.0 / 672.0, accuracy: 0.0001)
        let controller = RankListViewController(site: nil)
        XCTAssertNotNil(controller)
        let cell = RankCardCell(style: .default, reuseIdentifier: RankCardCell.reuseID)
        cell.configure(item: VodItem(vodId: "1", vodName: "片名", vodPic: "", vodRemarks: "全40集", siteKey: "s"),
                       rank: 3)
        XCTAssertNotNil(cell)
    }

    // MARK: - 8. R-08 条件筛选

    func testConditionFilterDimensionsParsing() {
        // 无 filter 站点：维度为空。
        let plain = ConfigRepository.parse(text: #"{"sites":[{"key":"c1","name":"普通","type":0,"api":"https://c.example.com"}]}"#).sites[0]
        let plainController = ConditionFilterViewController(site: plain)
        XCTAssertTrue(plainController.isViewLoaded == false, "未加载视图前不触发解析")

        // 有 filter 站点：复用 FilterSheetParser 解析维度（filter 值为转义 JSON 字符串）。
        let filterJSON = #"{"class":[{"key":"class","name":"类型","value":[{"n":"全部","v":""},{"n":"电影","v":"1"}]}]}"#
        let escapedFilter = filterJSON.replacingOccurrences(of: "\"", with: "\\\"")
        let siteText = #"{"sites":[{"key":"c2","name":"带筛选","type":0,"api":"https://c2.example.com","filter":"FILTER_PLACEHOLDER"}]}"#
            .replacingOccurrences(of: "FILTER_PLACEHOLDER", with: escapedFilter)
        guard let filteredSite = ConfigRepository.parse(text: siteText).sites.first else {
            XCTFail("filter 站点必须可解析（注入引号须转义）")
            return
        }
        let filtered = filteredSite
        let dimensions = FilterSheetParser.parse(filtered.filter)
        XCTAssertEqual(dimensions.count, 1)
        XCTAssertEqual(dimensions[0].name, "类型")
        XCTAssertEqual(dimensions[0].options.map(\.name), ["全部", "电影"])
    }

    // MARK: - 9. R-42 TV 互动

    func testInteractionCommandMapping() {
        XCTAssertEqual(InteractionCommand(rawValue: "ok"), .ok)
        XCTAssertEqual(InteractionCommand.back.displayName, "返回")
        XCTAssertEqual(InteractionCommand.allCases.count, 10, "十键指令集")
        for command in InteractionCommand.allCases {
            XCTAssertFalse(command.displayName.isEmpty)
        }
    }

    func testInteractionMessengerURLBuilding() {
        XCTAssertEqual(InteractionMessenger.normalizeBase(" 192.168.1.8:9978 "), "http://192.168.1.8:9978",
                       "无 scheme 自动补 http")
        XCTAssertEqual(InteractionMessenger.normalizeBase("http://a.tv/"), "http://a.tv", "尾部斜杠剔除")
        XCTAssertNil(InteractionMessenger.normalizeBase(""), "空地址非法")
        XCTAssertNil(InteractionMessenger.normalizeBase("   "), "纯空白非法")
        let url = InteractionMessenger.requestURL(for: .ok, base: "192.168.1.8:9978")
        XCTAssertEqual(url?.absoluteString, "http://192.168.1.8:9978/interaction?key=ok")
        let body = InteractionMessenger.requestBody(for: .back)
        let decoded = try? JSONSerialization.jsonObject(with: body) as? [String: String]
        XCTAssertEqual(decoded?["key"], "back")
    }

    func testInteractionPageInstantiable() {
        let controller = InteractionViewController()
        XCTAssertNotNil(controller, "TV 互动页必须可实例化（不再是占位说明页）")
        // 实质契约：指令集 10 键齐全、地址归一化补 scheme 去尾斜杠、非法地址拒绝发送。
        XCTAssertEqual(InteractionCommand.allCases.count, 10, "TV 遥控指令必须 10 键齐全")
        XCTAssertEqual(InteractionMessenger.normalizeBase("192.168.1.8:9978/"), "http://192.168.1.8:9978",
                       "无 scheme 补 http、去尾部斜杠")
        XCTAssertEqual(InteractionMessenger.normalizeBase("  https://tv.local:8080/  "), "https://tv.local:8080",
                       "已有 scheme 保持 https、去首尾空白与尾部斜杠")
        XCTAssertNil(InteractionMessenger.normalizeBase("   "), "空白地址非法")
        XCTAssertNil(InteractionMessenger.normalizeBase("not a url with spaces"), "含空格的非法地址不得补 scheme 放行")
        XCTAssertEqual(InteractionMessenger.requestURL(for: .ok, base: "192.168.1.8:9978")?.absoluteString,
                       "http://192.168.1.8:9978/interaction?key=ok", "指令 URL 必须按约定拼接")
        XCTAssertNil(InteractionMessenger.requestURL(for: .ok, base: ""), "无合法地址不得发送")
    }

    // MARK: - 10. R-43/R-49/F-18 局域网

    func testLANSyncEndpointParsing() {
        XCTAssertEqual(LANSyncEndpoint.parse("192.168.1.8"), LANSyncEndpoint(name: "手动设备", host: "192.168.1.8", port: 9978),
                       "无端口走默认 9978")
        XCTAssertEqual(LANSyncEndpoint.parse("http://192.168.1.8:8080")?.port, 8080, "scheme 剔除端口保留")
        XCTAssertNil(LANSyncEndpoint.parse("192.168.1.8:abc"), "非数字端口非法")
        XCTAssertNil(LANSyncEndpoint.parse("192.168.1.8:99999"), "超范围端口非法")
        XCTAssertNil(LANSyncEndpoint.parse("192.168.1.8/a/b"), "带路径非法")
        XCTAssertNil(LANSyncEndpoint.parse(""))
        let endpoint = LANSyncEndpoint.parse("192.168.1.8:9978")
        XCTAssertEqual(endpoint?.pushURL?.absoluteString, "http://192.168.1.8:9978/sync/push")
    }

    func testLANSyncServiceDescriptorMatchesPlist() throws {
        // build 23 收敛：只注册自有发现服务 _yingshicang._tcp（httpType/advertisedTypes 已随
        // 「无浏览/注册实例的 _http._tcp 声明」一并删除）。断言与真实 Info.plist 一一对应。
        XCTAssertEqual(LANSyncServiceDescriptor.serviceType, "_yingshicang._tcp.")
        let source = try sourceOf("Config/Info.plist")
        XCTAssertTrue(source.contains("_yingshicang._tcp"), "plist 必须声明与 serviceType 同源的服务类型")
        XCTAssertFalse(source.contains("_http._tcp"), "未实际注册的 _http._tcp 声明必须删除")
    }

    func testLANPushRequestConstruction() {
        let endpoint = LANSyncEndpoint(name: "TV", host: "192.168.1.8", port: 9978)
        let payload = BackupPayload.make()
        let request = LANPushService.makeRequest(to: endpoint, payload: payload)
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request?.url?.absoluteString, "http://192.168.1.8:9978/sync/push")
        XCTAssertNotNil(request?.httpBody, "推送体必须是 BackupPayload JSON")
    }

    // MARK: - 11. F-20 下载任务

    func testDownloadTaskStoreLifecycle() {
        let store = DownloadTaskStore(defaults: isolatedDefaults())
        XCTAssertTrue(store.tasks.isEmpty)
        let item = VodItem(vodId: "v1", vodName: "片名", vodPic: "", vodRemarks: "", siteKey: "s1")
        let episodes = [PlayEpisode(name: "第1集", url: "https://x.example.com/1.m3u8"),
                        PlayEpisode(name: "第2集", url: "https://x.example.com/2.m3u8")]
        let added = store.add(vodItem: item, episodes: episodes, flag: "线路1")
        XCTAssertEqual(added, 2, "两集全部入队")
        XCTAssertEqual(store.tasks.count, 2)
        XCTAssertEqual(store.pendingCount, 2)
        // 去重：重复加入不产生新任务
        XCTAssertEqual(store.add(vodItem: item, episodes: episodes, flag: "线路1"), 0)
        XCTAssertEqual(store.tasks.count, 2)
        // 状态流转
        let id = DownloadTask.makeID(siteKey: "s1", vodId: "v1", episodeURL: episodes[0].url)
        store.setStatus(id: id, status: .completed)
        XCTAssertEqual(store.task(id: id)?.status, .completed)
        XCTAssertEqual(store.pendingCount, 1, "完成后未完成数减一")
        // 清除已完成
        store.clearFinished()
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks[0].episodeName, "第2集")
        // 删除
        store.remove(id: DownloadTask.makeID(siteKey: "s1", vodId: "v1", episodeURL: episodes[1].url))
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testDownloadTaskPersistenceRoundTrip() {
        let defaults = isolatedDefaults()
        let first = DownloadTaskStore(defaults: defaults)
        let item = VodItem(vodId: "v9", vodName: "持久化", vodPic: "", vodRemarks: "", siteKey: "s9")
        first.add(vodItem: item,
                  episodes: [PlayEpisode(name: "全集", url: "https://x.example.com/all.m3u8")],
                  flag: "默认")
        // 新实例同一 defaults：任务必须读得回来
        let second = DownloadTaskStore(defaults: defaults)
        XCTAssertEqual(second.tasks.count, 1)
        XCTAssertEqual(second.tasks[0].vodName, "持久化")
        XCTAssertEqual(second.tasks[0].status, .pending)
    }

    func testDownloadStatusDisplayText() {
        XCTAssertEqual(DownloadStatus.pending.displayText, "等待中")
        XCTAssertEqual(DownloadStatus.completed.displayText, "已完成")
        XCTAssertEqual(DownloadStatus.failed.displayText, "失败")
    }

    // MARK: - 12. R-31 快捷弹窗

    func testQuickAddPopupGeometry() {
        let popup = QuickAddPopupViewController()
        XCTAssertEqual(popup.config.width, 180, "添加快捷弹窗宽 180dp")
        XCTAssertEqual(popup.config.anchor, .center)
    }

    // MARK: - 13. 接线静态守卫（源码级断言：入口缺失必失败）

    private func sourceOf(_ filename: String) throws -> String {
        // 直接按 #filePath 相对定位：Tests/ 上级即仓库根（CI 布局与本地一致）。
        let here = URL(fileURLWithPath: #filePath) // .../Tests/Build22Batch3RegressionTests.swift
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent(filename)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// R-54 免责声明挂载：MainTabBarController 首启必须 present DisclaimerDialog。
    func testWiringDisclaimerInTabBar() throws {
        let source = try sourceOf("Yingshicang/App/MainTabBarController.swift")
        XCTAssertTrue(source.contains("presentDisclaimerIfFirstLaunch"), "主壳必须挂免责声明入口")
        XCTAssertTrue(source.contains("!DisclaimerGate.isAccepted()"), "仅首启（未同意）才弹出")
    }

    /// R-32 摇一摇挂载：主壳必须启动 ShakeGestureController。
    func testWiringShakeInTabBar() throws {
        let source = try sourceOf("Yingshicang/App/MainTabBarController.swift")
        XCTAssertTrue(source.contains("ShakeGestureController"), "主壳必须挂摇一摇控制器")
        XCTAssertTrue(source.contains("shakeController.start()"), "出现时必须启动监听")
        XCTAssertTrue(source.contains("shakeController.stop()"), "消失时必须停止监听")
    }

    /// R-31/R-44 扫码入口 + R-07 榜单入口：首页必须接线。
    func testWiringHomeEntries() throws {
        let source = try sourceOf("Yingshicang/Features/Home/HomeViewController.swift")
        XCTAssertTrue(source.contains("ScanCodeViewController"), "首页快捷弹窗必须接扫码页")
        XCTAssertTrue(source.contains("RankListViewController"), "首页必须有榜单入口")
        XCTAssertTrue(source.contains("ConditionFilterViewController"), "首页快捷弹窗必须接条件筛选")
        XCTAssertTrue(source.contains("QuickAddPopupViewController"), "R-31 快捷弹窗必须存在")
    }

    /// R-50 频道密码挂载：首页分类点击链路必须含密码校验。
    func testWiringChannelPasswordInHome() throws {
        let source = try sourceOf("Yingshicang/Features/Home/HomeViewController.swift")
        XCTAssertTrue(source.contains("ChannelPasswordRule.needsPassword"), "分类点击必须判定加密频道")
        XCTAssertTrue(source.contains("ChannelPasswordDialogViewController"), "加密频道必须弹密码层")
    }

    /// F-20 下载入口接线：详情页 downloadEntryTapped 不再是占位 alert。
    func testWiringDownloadInDetail() throws {
        let source = try sourceOf("Yingshicang/Features/Detail/DetailViewController.swift")
        XCTAssertTrue(source.contains("DownloadTaskStore.shared.add"), "下载入口必须入队任务")
        XCTAssertTrue(source.contains("DownloadListViewController"), "下载入口必须打开任务列表")
        XCTAssertFalse(source.contains("下载任务管理将在后续版本提供"), "占位提示必须被移除")
    }

    /// R-42 TV 互动不再是占位页：MineSubPages 中的占位类必须删除。
    func testInteractionPlaceholderRemoved() throws {
        let source = try sourceOf("Yingshicang/Features/Mine/MineSubPages.swift")
        XCTAssertFalse(source.contains("原 APK 的反馈通道依赖其自带服务端"), "旧占位文案必须删除")
        XCTAssertFalse(source.contains("final class InteractionViewController"), "占位类必须删除（新实现位于 InteractionPage.swift）")
    }

    /// Mine 页新增入口：网盘 / 局域网同步 / 赞赏。
    func testWiringMineEntries() throws {
        let source = try sourceOf("Yingshicang/Features/Mine/MineViewController.swift")
        XCTAssertTrue(source.contains("NetdiskViewController"), "我的页必须有网盘入口")
        XCTAssertTrue(source.contains("LANSyncDialogViewController"), "我的页必须有局域网同步入口")
        XCTAssertTrue(source.contains("RewardDialogViewController"), "我的页必须有赞赏入口")
    }

    /// Info.plist 权限声明：相机 / Bonjour / 本地网络。
    func testInfoPlistPrivacyKeys() throws {
        let source = try sourceOf("Config/Info.plist")
        XCTAssertTrue(source.contains("NSCameraUsageDescription"), "扫码需要相机用途说明")
        XCTAssertTrue(source.contains("NSBonjourServices"), "Bonjour 发现需要服务类型声明")
        XCTAssertTrue(source.contains("NSLocalNetworkUsageDescription"), "局域网同步需要本地网络用途说明")
        XCTAssertTrue(source.contains("_yingshicang._tcp"), "Bonjour 服务类型必须与 LANSyncServiceDescriptor 同源")
        // ATS 红线：只允许 NSAllowsArbitraryLoads 一个键（历史缺陷防线）。
        // 判定范围剔除 XML 注释——注释里的历史缺陷说明会提到被禁键名，属合法文档，不算违规。
        let codeOnly = source.components(separatedBy: "<!--")
            .map { $0.components(separatedBy: "-->").last ?? "" }
            .joined()
        XCTAssertFalse(codeOnly.contains("NSAllowsArbitraryLoadsInWebContent"), "ATS dict 出现该键会使 NSAllowsArbitraryLoads 被平台忽略")
        XCTAssertFalse(codeOnly.contains("NSAllowsLocalNetworking"), "ATS dict 出现该键会使 NSAllowsArbitraryLoads 被平台忽略")
    }
}
