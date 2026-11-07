import UIKit

/// 以下为各 Tab 的最小可编译实现，界面细节在对应文件中逐步补齐。
/// 保留独立文件而非空壳，是为了让「每个 Tab 都有真实控制器」这一结构从一开始就成立。

/// R-21 历史·收藏页：TabLayout 全宽 + ViewPager2，两个 Tab「播放历史 / 我的收藏」。
final class HistoryCollectViewController: UIViewController {
    private let segmented = UISegmentedControl(items: ["播放历史", "我的收藏"])
    private let container = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        // 布局 paddingTop=37dp
        segmented.selectedSegmentIndex = 0
        segmented.addTarget(self, action: #selector(switchTab), for: .valueChanged)
        view.addSubview(segmented)
        view.addSubview(container)
        segmented.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                           constant: DesignTokens.Metrics.historyCollectPaddingTop),
            segmented.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmented.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: segmented.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        switchTab()
    }

    @objc private func switchTab() {
        container.subviews.forEach { $0.removeFromSuperview() }
        let child: UIViewController = segmented.selectedSegmentIndex == 0
            ? HistoryListViewController()
            : FavoriteViewController()
        addChild(child)
        child.view.frame = container.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(child.view)
        child.didMove(toParent: self)
    }
}
