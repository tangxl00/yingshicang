import UIKit

/// R-01 主壳 + 底部 Tab 栏。
///
/// 布局事实（mobile_home_activity.xml / mobile_home_tab.xml，AXML 直接读取）：
/// - 根 FrameLayout 全屏；ViewPager2 全屏，但 `layout_marginBottom=58dip` 给底栏留位
/// - 底部 include 高 `55dip`，内部 FrameLayout 撑满 + LinearLayout 横排
/// - LinearLayout `paddingTop=5dip`（同时有 paddingBottom，对称留白）
/// - 5 个等宽 ShapeTextView，textSize `12dip`，顺序「主页/直播/短视频/历史·收藏/我的」
///
/// iOS 侧用 UITabBarController 实现同等结构：自定义 tabBar 高度 55pt、
/// 图标上、文字下、5 等分，选中色取主色（文档 5.1 标注选中色待确认，
/// 本工程取 `main_color #00C64E` 并在默认取值清单中声明）。
final class MainTabBarController: UITabBarController {

    private let customTabBar = TabBarView()

    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = makeTabs()
        setupCustomTabBar()
        // 冷启动落在「主页」（R-01 验收口径），不回记上次 Tab——
        // 文档 R-01 的 [SP] 虽提到记录上次停留 Tab，但验收口径明确要求冷启动落在主页，
        // 以验收口径为准（列入默认取值清单）。
        selectedIndex = 0
        customTabBar.selectedIndex = 0
        tabBar.isHidden = true
    }

    override var childForStatusBarStyle: UIViewController? { selectedViewController }

    private func makeTabs() -> [UIViewController] {
        let home = UINavigationController(rootViewController: HomeViewController())
        let live = UINavigationController(rootViewController: LiveViewController())
        let shortVideo = UINavigationController(rootViewController: ShortVideoViewController())
        let history = UINavigationController(rootViewController: HistoryCollectViewController())
        let mine = UINavigationController(rootViewController: MineViewController())

        for nav in [home, live, shortVideo, history, mine] {
            nav.setNavigationBarHidden(true, animated: false)
            nav.interactivePopGestureRecognizer?.isEnabled = true
        }
        return [home, live, shortVideo, history, mine]
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(customTabBar)
    }
}
