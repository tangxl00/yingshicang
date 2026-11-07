import UIKit

/// R-01 主壳 + 底部 Tab 栏。
///
/// 布局事实（mobile_home_activity.xml / mobile_home_tab.xml，AXML 直接读取）：
/// - 根 FrameLayout 全屏；ViewPager2 全屏，但 `layout_marginBottom=58dip` 给底栏留位
/// - 底部 include 高 `55dip`，内部 FrameLayout 撑满 + LinearLayout 横排
/// - LinearLayout `paddingTop=5dip`（同时有 paddingBottom，对称留白）
/// - 等宽 ShapeTextView，textSize `12dip`
///
/// **Tab 数量变更（v2.0.50 build 21，按用户真机验收要求）**：
/// 原版 5 个（主页/直播/短视频/历史·收藏/我的）→ 现为 3 个（主页/历史·收藏/我的）。
/// 「直播」与「短视频」两个模块连同其入口、解析与播放链路一并删除，
/// 原因见 KNOWN_DIFFERENCES「按用户要求移除的功能」一节。
///
/// iOS 侧用 UITabBarController 实现同等结构：自定义 tabBar 高度 55pt、
/// 图标上、文字下、等分，选中色取主色（文档 5.1 标注选中色待确认，
/// 本工程取 `main_color #00C64E` 并在默认取值清单中声明）。
final class MainTabBarController: UITabBarController {

    private let customTabBar = TabBarView()
    /// R-24 底部悬浮播放记录条（悬在 Tab 栏上方）。
    private let floatBar = FloatHistoryBar()

    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = makeTabs()
        setupCustomTabBar()
        setupFloatBar()
        // 冷启动落在「主页」（R-01 验收口径），不回记上次 Tab——
        // 文档 R-01 的 [SP] 虽提到记录上次停留 Tab，但验收口径明确要求冷启动落在主页，
        // 以验收口径为准（列入默认取值清单）。
        selectedIndex = 0
        customTabBar.selectedIndex = 0
        tabBar.isHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 播放页 fullScreen 关闭后回到主壳，这里刷新悬浮条（记录可能已更新）
        refreshFloatBar()
    }

    override var childForStatusBarStyle: UIViewController? { selectedViewController }

    private func makeTabs() -> [UIViewController] {
        let home = UINavigationController(rootViewController: HomeViewController())
        let history = UINavigationController(rootViewController: HistoryCollectViewController())
        let mine = UINavigationController(rootViewController: MineViewController())

        for nav in [home, history, mine] {
            nav.setNavigationBarHidden(true, animated: false)
        }
        // 说明：本 App 的二级页面全部是 fullScreen present（Detail/Search/Player/我的子页），
        // 导航栈从不 push，所以「左滑返回」不是靠 interactivePopGestureRecognizer 生效的，
        // 而是由 SwipeBackViewController（UI/Extensions/SwipeBackSupport.swift）在边缘侧滑时 dismiss。
        // 三个 Tab 根页没有可返回的上一屏，因此不装该手势。
        return [home, history, mine]
    }

    private func setupCustomTabBar() {
        view.addSubview(customTabBar)
        customTabBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            customTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customTabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            customTabBar.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.tabBarHeight)
        ])
        customTabBar.onSelect = { [weak self] index in
            guard let self = self else { return }
            self.selectedIndex = index
            Settings.shared.lastTabIndex = index
        }
    }

    private func setupFloatBar() {
        view.addSubview(floatBar)
        floatBar.translatesAutoresizingMaskIntoConstraints = false
        floatBar.isHidden = true
        NSLayoutConstraint.activate([
            floatBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(12)),
            floatBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(12)),
            floatBar.bottomAnchor.constraint(equalTo: customTabBar.topAnchor, constant: -DesignTokens.dp(8)),
            floatBar.heightAnchor.constraint(equalToConstant: FloatHistoryBar.barHeight)
        ])
        floatBar.onTap = { [weak self] record in
            guard let self = self else { return }
            let item = VodItem(vodId: record.vodId, vodName: record.vodName, vodPic: record.vodPic,
                               vodRemarks: "", siteKey: record.siteKey)
            let controller = DetailViewController(item: item)
            controller.modalPresentationStyle = .fullScreen
            self.present(controller, animated: true)
        }
        refreshFloatBar()
    }

    private func refreshFloatBar() {
        floatBar.isHidden = !floatBar.reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(customTabBar)
        view.bringSubviewToFront(floatBar)
    }
}

