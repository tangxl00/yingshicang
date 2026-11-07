import XCTest
@testable import Yingshicang

/// v2.0.50 build 22 范围A播放批次的回归守卫。
///
/// 覆盖（每条都可证伪，缺实现必失败）：
/// 1. R-12/F-10 播放手势 —— 区域判定 / 增量映射 / 锁屏状态矩阵 / 手势只挂画面层不挂返回层
/// 2. R-13 完整按钮条 —— 播放页 8 个功能按钮（倍速/选集/锁定/片头/片尾/音轨/字幕/解析）真实在视图层级
/// 3. R-14 详情页入口 —— 解析/快搜/投屏/下载四入口 + R-11 背景与评分角标载体存在
/// 4. R-18 解析弹窗 —— 三列网格数学 / 条目映射 / 标题计数
/// 5. R-19/F-12 轨道弹层 —— 行数规则（字幕多一条“关闭”）/ 枚举默认项 / 展示名兜底
/// 6. R-24 悬浮播放记录条 —— 显隐规则与内容回填
final class Build22RegressionTests: XCTestCase {

    // MARK: - 1. R-12 播放手势纯逻辑

    /// 区域判定：左右各 40% 为亮度/音量区，中间 20% 为无效区。
    func testGestureZoneRules() {
        let size = CGSize(width: 390, height: 844)
        XCTAssertEqual(PlayerGestureMath.zone(for: CGPoint(x: 0, y: 0), in: size), .brightness)
        // 155/390 ≈ 0.397 < 0.4 → 仍是亮度区
        XCTAssertEqual(PlayerGestureMath.zone(for: CGPoint(x: 155, y: 400), in: size), .brightness)
        XCTAssertEqual(PlayerGestureMath.zone(for: CGPoint(x: 195, y: 400), in: size), .neutral)
        // 234/390 = 0.6，不大于 0.6 → 仍是无效区（边界取开区间）
        XCTAssertEqual(PlayerGestureMath.zone(for: CGPoint(x: 234, y: 400), in: size), .neutral)
        XCTAssertEqual(PlayerGestureMath.zone(for: CGPoint(x: 235, y: 400), in: size), .volume)
        XCTAssertEqual(PlayerGestureMath.zone(for: CGPoint(x: 389, y: 0), in: size), .volume)
        // 非法尺寸必须归 neutral，不得除零或误判
        XCTAssertEqual(PlayerGestureMath.zone(for: CGPoint(x: 10, y: 10), in: .zero), .neutral)
        XCTAssertEqual(PlayerGestureMath.sideFraction, 0.4, "左右分区比例是 40%，改动即布局口径变更")
    }

    /// 增量映射：向上拖增大、向下拖减小、结果夹紧 [0,1]、非法输入安全。
    func testGestureMappedValueClamp() {
        // 向上 100pt、全量程 400pt → +0.25
        XCTAssertEqual(PlayerGestureMath.mappedValue(start: 0.5, translationY: -100, fullTravelHeight: 400),
                       0.75, accuracy: 0.0001)
        // 向下 100pt → -0.25
        XCTAssertEqual(PlayerGestureMath.mappedValue(start: 0.5, translationY: 100, fullTravelHeight: 400),
                       0.25, accuracy: 0.0001)
        // 越界夹紧
        XCTAssertEqual(PlayerGestureMath.mappedValue(start: 0.5, translationY: -4000, fullTravelHeight: 400), 1.0)
        XCTAssertEqual(PlayerGestureMath.mappedValue(start: 0.5, translationY: 4000, fullTravelHeight: 400), 0.0)
        // 全量程非法时返回原值（已夹紧）
        XCTAssertEqual(PlayerGestureMath.mappedValue(start: 0.4, translationY: -100, fullTravelHeight: 0), 0.4)
        // clamp 的非法值兜底
        XCTAssertEqual(PlayerGestureMath.clamp(.nan), 0)
        XCTAssertEqual(PlayerGestureMath.clamp(2.5), 1)
        XCTAssertEqual(PlayerGestureMath.clamp(-0.5), 0)
    }

    /// 误触阈值与 HUD 百分比文案。
    func testGestureMeaningfulTravelAndPercentText() {
        XCTAssertFalse(PlayerGestureMath.isMeaningful(translationY: 7), "7pt 位移低于 8pt 阈值，视为误触")
        XCTAssertTrue(PlayerGestureMath.isMeaningful(translationY: 8))
        XCTAssertTrue(PlayerGestureMath.isMeaningful(translationY: -8), "向上拖同样计入")
        XCTAssertEqual(PlayerGestureMath.minimumVerticalTravel, 8)

        XCTAssertEqual(PlayerGestureMath.percentText(0.5), "50%")
        XCTAssertEqual(PlayerGestureMath.percentText(1.5), "100%", "越界值必须按 100% 展示")
        XCTAssertEqual(PlayerGestureMath.percentText(-0.2), "0%")
    }

    /// 锁屏状态矩阵：锁屏屏蔽控制层/手势/切集，但保留解锁入口；迷你进度与控制层互斥。
    func testInteractionStateLockMatrix() {
        let locked = PlayerInteractionState(isLocked: true, showsMiniProgress: true)
        XCTAssertFalse(locked.allowsToggleControls, "锁屏时单击不得切出完整控制层")
        XCTAssertFalse(locked.allowsGestureAdjust, "锁屏时不得调音量亮度")
        XCTAssertFalse(locked.allowsEpisodeSwipe, "锁屏时不得左右滑切集")
        XCTAssertTrue(locked.allowsTapToRevealUnlock, "锁屏时必须保留解锁入口，否则用户被锁死")

        let unlocked = PlayerInteractionState(isLocked: false, showsMiniProgress: true)
        XCTAssertTrue(unlocked.allowsToggleControls)
        XCTAssertTrue(unlocked.allowsGestureAdjust)
        XCTAssertTrue(unlocked.allowsEpisodeSwipe)
        XCTAssertFalse(unlocked.allowsTapToRevealUnlock, "未锁屏时点击就是切控制层，不该出现解锁态")

        // 迷你进度 = 控制层隐藏时的替代，两者互斥
        XCTAssertTrue(unlocked.shouldShowMiniProgress(controlsVisible: false))
        XCTAssertFalse(unlocked.shouldShowMiniProgress(controlsVisible: true))
        let noMini = PlayerInteractionState(isLocked: false, showsMiniProgress: false)
        XCTAssertFalse(noMini.shouldShowMiniProgress(controlsVisible: false), "设置关闭迷你进度后不得显示")
    }

    // MARK: - 2. R-12 手势挂载（不得污染左滑返回层）

    /// 竖滑 pan 必须挂在画面层（engineHost），HUD 容器上不得有任何手势——
    /// 否则会与 SwipeBackViewController 基类「恰好 2 个手势」的守卫冲突。
    func testGestureControllerAttachesPanToHostOnly() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let hud = UIView(frame: host.frame)
        let controller = PlayerGestureController(interaction: PlayerInteractionState())
        controller.attach(to: host, hudHost: hud)

        let pans = (host.gestureRecognizers ?? []).compactMap { $0 as? UIPanGestureRecognizer }
        XCTAssertEqual((host.gestureRecognizers ?? []).count, 1, "画面层应有且只有一个竖滑 pan")
        XCTAssertEqual(pans.first?.maximumNumberOfTouches, 1, "单指拖动")

        let hudGestures = hud.gestureRecognizers ?? []
        XCTAssertTrue(hudGestures.isEmpty, "HUD 容器不得挂手势，否则破坏左滑返回基类的手势守卫，实际: \(hudGestures)")
    }

    /// 锁定与解锁：lock() 进入锁屏并回调；锁屏态 revealUnlockIfLocked 返回 true；未锁屏返回 false。
    func testGestureControllerLockAndReveal() {
        let hud = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = PlayerGestureController(interaction: PlayerInteractionState())
        var lockEvents = 0
        controller.onLockChanged = { lockEvents += 1 }
        controller.attach(to: UIView(frame: hud.frame), hudHost: hud)

        XCTAssertFalse(controller.revealUnlockIfLocked(), "未锁屏时点击不进入解锁流程")
        controller.lock()
        XCTAssertTrue(controller.interaction.isLocked, "lock() 后必须进入锁屏态")
        XCTAssertEqual(lockEvents, 1, "锁屏态变化必须回调播放页（隐藏控制层）")
        controller.lock()
        XCTAssertTrue(controller.interaction.isLocked, "重复 lock() 不得解锁（幂等）")
        XCTAssertEqual(lockEvents, 1, "重复 lock() 不应再次回调")
        XCTAssertTrue(controller.revealUnlockIfLocked(), "锁屏时点击必须能唤出解锁按钮")
    }

    // MARK: - 3. R-18 解析弹窗

    /// 条目映射：下标/名称/类型一一对应，空名兜底，typeText 三分支。
    func testParseSheetEntryMapping() {
        let parses = [
            ParseConfig(name: "Json1", url: "https://a.example/?" , type: 1),
            ParseConfig(name: "", url: "https://b.example/", type: 0),
            ParseConfig(name: "聚合A", url: "https://c.example/", type: 3)
        ]
        let entries = ParseSheetModel.entries(from: parses)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].index, 0)
        XCTAssertEqual(entries[0].name, "Json1")
        XCTAssertEqual(entries[0].typeText, "JSON")
        XCTAssertEqual(entries[1].listTitle, "解析源 2", "空名必须兜底为序号名，不得显示空白")
        XCTAssertEqual(entries[1].typeText, "网页")
        XCTAssertEqual(entries[2].typeText, "聚合", "非 0/1 的 type 统一归聚合")
    }

    /// 三列网格数学：列数固定 3，列宽 = (宽 - 间距×2)/3 向下取整，标题带计数。
    func testParseSheetGridMathAndTitle() {
        XCTAssertEqual(ParseSheetModel.columns, 3, "解析弹窗固定 3 列，列数变化即布局口径变更")
        // (320 - 16) / 3 = 101.33 → 101
        XCTAssertEqual(ParseSheetModel.itemWidth(containerWidth: 320), 101)
        // 5 列自定义：(320 - 32) / 5 = 57.6 → 57
        XCTAssertEqual(ParseSheetModel.itemWidth(containerWidth: 320, spacing: 8, columns: 5), 57)
        // 容器过窄不得返回负数
        XCTAssertEqual(ParseSheetModel.itemWidth(containerWidth: 10), 0)
        XCTAssertEqual(ParseSheetModel.title(count: 7), "选择解析源（7）")
        XCTAssertEqual(ParseSheetModel.title(count: 0), "选择解析源（0）")
    }

    /// 弹窗配置：标题计数与解析源数量一致，尺寸与设计稿一致（350dp 宽）。
    func testParseSheetDialogConfig() {
        let parses = [ParseConfig(name: "A", url: "u", type: 0),
                      ParseConfig(name: "B", url: "u", type: 1)]
        let sheet = ParseSheetViewController(parses: parses, currentIndex: nil)
        XCTAssertEqual(sheet.config.title, "选择解析源（2）", "标题必须带真实解析源计数")
        XCTAssertTrue(sheet.config.width == DesignTokens.Metrics.choosePlayPopupWidth,
                      "解析弹窗宽度必须是 350dp（choosePlayPopupWidth）")
        XCTAssertEqual(sheet.config.height, DesignTokens.Metrics.inputDialogHeight + 90)
        XCTAssertEqual(sheet.config.anchor, .center)
    }

    // MARK: - 4. R-19 轨道弹层

    /// 行数规则：音轨 = 轨道数；字幕 = 轨道数 + 1（关闭项）；无轨道 = 0（走空态文案）。
    func testTrackSheetRowCountRules() {
        func option(_ index: Int, _ kind: MediaTrackKind) -> MediaTrackOption {
            MediaTrackOption(index: index, kind: kind, displayName: "轨\(index)", languageCode: "zh", isDefault: false)
        }
        let audio = TrackSheetViewController(kind: .audio,
                                             options: [option(0, .audio), option(1, .audio), option(2, .audio)],
                                             selectedIndex: nil)
        XCTAssertEqual(audio.rowCount, 3, "音轨没有关闭项")
        XCTAssertEqual(audio.config.title, "音轨")

        let subtitle = TrackSheetViewController(kind: .subtitle,
                                                options: [option(0, .subtitle), option(1, .subtitle), option(2, .subtitle)],
                                                selectedIndex: nil)
        XCTAssertEqual(subtitle.rowCount, 4, "字幕必须多一条「关闭字幕」")
        XCTAssertEqual(subtitle.config.title, "字幕")
        XCTAssertTrue(subtitle.config.width == DesignTokens.Metrics.trackSheetWidth,
                      "轨道弹窗宽度必须是 300dp")
        XCTAssertEqual(subtitle.config.height, DesignTokens.Metrics.trackSheetHeight)

        let emptyAudio = TrackSheetViewController(kind: .audio, options: [], selectedIndex: nil)
        XCTAssertEqual(emptyAudio.rowCount, 0)
        let emptySubtitle = TrackSheetViewController(kind: .subtitle, options: [], selectedIndex: nil)
        XCTAssertEqual(emptySubtitle.rowCount, 0)
    }

    /// 枚举默认项：无显式默认 → 第 0 项；有显式默认 → 仅该条；高亮取值优先级 显式 > 默认 > 第 0。
    func testMediaTrackEnumeratorDefaults() {
        let kind = MediaTrackKind.audio
        // 无显式默认
        let noDefault = MediaTrackEnumerator.options(
            for: [MediaTrackSnapshot(), MediaTrackSnapshot(displayName: "英"), MediaTrackSnapshot(displayName: "粤")],
            kind: kind)
        XCTAssertEqual(noDefault.count, 3)
        XCTAssertTrue(noDefault[0].isDefault, "没有默认标记时第 0 项视为默认（对齐 AVFoundation 语义）")
        XCTAssertFalse(noDefault[1].isDefault)
        XCTAssertFalse(noDefault[2].isDefault)

        // 显式默认在中间
        let explicit = MediaTrackEnumerator.options(
            for: [MediaTrackSnapshot(), MediaTrackSnapshot(displayName: "英", isDefault: true), MediaTrackSnapshot()],
            kind: kind)
        XCTAssertFalse(explicit[0].isDefault, "有显式默认时第 0 项不得再标默认")
        XCTAssertTrue(explicit[1].isDefault)

        // 空输入
        XCTAssertTrue(MediaTrackEnumerator.options(for: [], kind: kind).isEmpty)

        // 高亮优先级
        XCTAssertFalse(MediaTrackEnumerator.allowsOffOption(for: .audio), "音轨没有关闭项")
        XCTAssertTrue(MediaTrackEnumerator.allowsOffOption(for: .subtitle), "字幕有关闭项")
        XCTAssertEqual(MediaTrackEnumerator.highlightedIndex(in: noDefault, selectedIndex: 2), 2, "显式选中优先")
        XCTAssertNil(MediaTrackEnumerator.highlightedIndex(in: noDefault, selectedIndex: 99), "越界选中不得崩、不得误高亮")
        XCTAssertEqual(MediaTrackEnumerator.highlightedIndex(in: explicit, selectedIndex: nil), 1, "无显式选中回默认项")
        XCTAssertNil(MediaTrackEnumerator.highlightedIndex(in: [], selectedIndex: 0), "空轨道返回 nil（UI 显示空态）")
    }

    /// 展示名三级兜底：本地化名 > 语言码 > 「音轨 N / 字幕 N」。
    func testMediaTrackOptionListTitleFallback() {
        XCTAssertEqual(MediaTrackOption(index: 0, kind: .audio, displayName: "国语", languageCode: "zh", isDefault: true).listTitle, "国语")
        XCTAssertEqual(MediaTrackOption(index: 0, kind: .audio, displayName: "", languageCode: "zh", isDefault: true).listTitle, "zh")
        XCTAssertEqual(MediaTrackOption(index: 0, kind: .audio, displayName: "", languageCode: "", isDefault: true).listTitle, "音轨 1")
        XCTAssertEqual(MediaTrackOption(index: 1, kind: .subtitle, displayName: "", languageCode: "", isDefault: false).listTitle, "字幕 2")
    }

    /// 引擎侧轨道 API 的空守卫：无 currentItem 时不得崩、返回空。
    func testAVPlayerEngineTrackAPIsGuardEmptyItem() {
        let engine = AVPlayerEngine()
        XCTAssertTrue(engine.mediaSnapshots(kind: .audio).isEmpty, "无媒体项时音轨快照应为空")
        XCTAssertTrue(engine.mediaSnapshots(kind: .subtitle).isEmpty, "无媒体项时字幕快照应为空")
        XCTAssertNil(engine.selectedTrackIndex(kind: .audio))
        XCTAssertNil(engine.selectedTrackIndex(kind: .subtitle))
        // 越界/空选不抛错不崩
        engine.selectTrack(kind: .audio, index: 0)
        engine.disableTrack(kind: .subtitle)
    }

    // MARK: - 5. R-13 播放页按钮条 + R-14 详情页入口

    /// 递归收集视图树里的全部按钮标题。
    private func allButtonTitles(in view: UIView) -> [String] {
        var titles: [String] = []
        for sub in view.subviews {
            if let button = sub as? UIButton {
                titles.append(button.title(for: .normal) ?? "")
            }
            titles.append(contentsOf: allButtonTitles(in: sub))
        }
        return titles
    }

    /// 剥掉 Mirror 取值里的嵌套 Optional（Any 包 Optional 再包 Any 的形态）。
    private func unwrapOptional(_ value: Any?) -> Any? {
        guard let value = value else { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        guard let child = mirror.children.first else { return nil }
        return unwrapOptional(child.value)
    }

    /// R-13：播放页控制层必须同时有 8 个功能按钮，缺任何一个即失败。
    func testPlayerButtonBarHasEightActions() throws {
        let site = try JSONDecoder().decode(SiteConfig.self, from: Data("{}".utf8))
        let provider = SiteProviderFactory.make(site: site)
        let detail = VodDetail(vodId: "b22", vodName: "回归测试", vodPic: "", vodContent: "",
                               vodScore: "", vodYear: "", vodArea: "", vodType: "", vodRemarks: "",
                               siteKey: site.key, tabs: ["线路1"],
                               lists: [[PlayEpisode(name: "01", url: "https://example.com/v.m3u8")]],
                               quality: [])
        let player = PlayerViewController(detail: detail,
                                          episodes: detail.lists[0],
                                          startIndex: 0,
                                          provider: provider,
                                          initialParseIndex: 2)
        player.loadViewIfNeeded()

        let titles = allButtonTitles(in: player.view)
        for required in ["倍速", "选集", "锁定", "片头", "片尾", "音轨", "字幕", "解析"] {
            XCTAssertTrue(titles.contains(required), "播放页缺少「\(required)」按钮，实际按钮: \(titles)")
        }

        // R-12：手势控制器必须完成挂载
        let mirror = Mirror(reflecting: player)
        let controller = unwrapOptional(mirror.children.first { $0.label == "gestureController" }?.value)
        XCTAssertNotNil(controller, "播放页 setupLayout 后 gestureController 必须非空（R-12 手势未接线）")
        // R-18：详情页指定的初始解析源必须被带到播放页
        let forced = unwrapOptional(mirror.children.first { $0.label == "forcedParseIndex" }?.value)
        XCTAssertEqual(forced as? Int, 2, "initialParseIndex=2 必须存入 forcedParseIndex")
    }

    /// R-11 + R-14：详情页必须有背景层、评分角标载体和四个入口按钮。
    func testDetailPageBackdropBadgeAndEntries() {
        let item = VodItem(vodId: "b22", vodName: "回归测试", vodPic: "", vodRemarks: "", siteKey: "no-such-site")
        let detail = DetailViewController(item: item)
        detail.loadViewIfNeeded()

        let titles = allButtonTitles(in: detail.view)
        for required in ["解析", "快搜", "投屏", "下载"] {
            XCTAssertTrue(titles.contains(required), "详情页缺少「\(required)」入口（R-14），实际按钮: \(titles)")
        }

        let mirror = Mirror(reflecting: detail)
        let backdrop = mirror.children.first { $0.label == "backdrop" }?.value
        XCTAssertTrue(backdrop is UIImageView, "R-11 模糊背景层（backdrop）必须存在")
        let badge = mirror.children.first { $0.label == "posterBadge" }?.value
        XCTAssertTrue(badge is UILabel, "R-11 评分角标（posterBadge）必须存在")
        if let badgeLabel = badge as? UILabel, let poster = mirror.children.first(where: { $0.label == "poster" })?.value as? UIImageView {
            XCTAssertEqual(badgeLabel.superview, poster, "评分角标必须叠在海报上（R-11）")
        }
    }

    // MARK: - 6. R-24 悬浮播放记录条

    /// 显隐与内容：有关闭开关设置、无记录、有记录三种情形。
    func testFloatHistoryBarVisibilityAndContent() {
        let original = Settings.shared.showFloatHistory
        defer {
            Settings.shared.showFloatHistory = original
        }

        let bar = FloatHistoryBar(frame: CGRect(x: 0, y: 0, width: 350, height: FloatHistoryBar.barHeight))
        XCTAssertEqual(FloatHistoryBar.barHeight, DesignTokens.Metrics.floatBarHeight, "悬浮条高度对齐 50dp")

        // 无记录 → 不显示
        Settings.shared.showFloatHistory = true
        let noRecordVisible = bar.reload()
        if HistoryStore.shared.latest() == nil {
            XCTAssertFalse(noRecordVisible, "无播放记录时悬浮条不得显示")
            XCTAssertNil(bar.currentRecord)
        }

        // 写入一条记录 → 显示且内容回填
        let record = HistoryRecord(siteKey: "b22-float-test", vodId: "v1", vodName: "悬浮条测试片",
                                   vodPic: "", flag: "", playIndex: 0, episodeIndex: 2,
                                   position: 100, duration: 600)
        HistoryStore.shared.upsert(record: record)
        defer {
            if let saved = HistoryStore.shared.resume(siteKey: record.siteKey, vodId: record.vodId), let id = saved.id {
                HistoryStore.shared.remove(id: id)
            }
        }
        XCTAssertTrue(bar.reload(), "有记录且开关开启时必须显示")
        XCTAssertEqual(bar.currentRecord?.vodName, "悬浮条测试片")
        let mirror = Mirror(reflecting: bar)
        let nameText = mirror.children.first { $0.label == "nameLabel" }?.value as? UILabel
        XCTAssertEqual(nameText?.text, "悬浮条测试片", "悬浮条标题必须回填最近记录片名")

        // 开关关闭 → 不显示
        Settings.shared.showFloatHistory = false
        XCTAssertFalse(bar.reload(), "设置关闭悬浮播放记录后必须隐藏")
        XCTAssertNil(bar.currentRecord)
    }
}
