import UIKit

/// R-02 主页内容区（mobile_home_fragment）。
///
/// 布局事实（AXML）：
/// - 竖向 LinearLayout，`paddingTop=30dip`
/// - ActionBarEx 搜索栏全宽，左右 padding 14dp
/// - 横排容器 `marginLeft=5dip`：TabLayout（weight=1，高 25dp，
///   tabIndicatorHeight=0，tabPaddingStart=8dp、tabPaddingEnd=12dp，tabMode=scrollable）
///   + 24×24dp 的 tabPop 图标（`marginLeft=8`、`marginRight=10`、alpha 0.3、默认 gone）
/// - ViewPager `marginTop=5dip`
final class HomeViewController: UIViewController {

    private let searchBar = SearchBarButton()
    private let tabScroll = UIScrollView()
    private let tabStack = UIStackView()
    private let tabPopButton = UIButton(type: .system)
    private let pager = UIView()
    private var categoryButtons: [UIButton] = []
    private var currentCategoryIndex = 0

    private var categories: [SiteCategory] = []
    private var sites: [SiteConfig] = []
    private var contentController: CategoryContentViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        setupLayout()
        reloadConfig()
    }

    private func setupLayout() {
        let column = UIStackView.vertical(spacing: 0)
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                        constant: DesignTokens.Metrics.homePaddingTop),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 搜索栏：左右 padding 14dp
        let searchContainer = UIView()
        searchContainer.addSubview(searchBar)
        searchBar.pinEdges(to: searchContainer, insets: UIEdgeInsets(top: 0, left: DesignTokens.Metrics.actionBarHorizontalPadding,
                                                                   bottom: 0, right: DesignTokens.Metrics.actionBarHorizontalPadding))
        searchBar.heightAnchor.constraint(equalToConstant: 30).isActive = true
        searchContainer.heightAnchor.constraint(equalToConstant: 30).isActive = true
        searchBar.addTarget(self, action: #selector(openSearch), for: .touchUpInside)
        column.addArrangedSubview(searchContainer)

        // 分类 Tab 行：marginLeft 5dp
        let tabRow = UIView()
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        tabScroll.showsHorizontalScrollIndicator = false
        tabScroll.translatesAutoresizingMaskIntoConstraints = false
        tabStack.axis = .horizontal
        tabStack.spacing = 0
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabScroll.addSubview(tabStack)
        tabRow.addSubview(tabScroll)

        tabPopButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        tabPopButton.tintColor = DesignTokens.Colors.text
        tabPopButton.alpha = 0.3
        tabPopButton.isHidden = true
        // R-52：分类展开浮层入口（categories 非空时在 rebuildCategoryTabs 里显示）。
        tabPopButton.addAction(UIAction { [weak self] _ in
            self?.openCategorySheet()
        }, for: .touchUpInside)
        tabPopButton.translatesAutoresizingMaskIntoConstraints = false
        tabRow.addSubview(tabPopButton)

        NSLayoutConstraint.activate([
            tabScroll.leadingAnchor.constraint(equalTo: tabRow.leadingAnchor,
                                               constant: DesignTokens.Metrics.homePagerMarginTop),
            tabScroll.topAnchor.constraint(equalTo: tabRow.topAnchor),
            tabScroll.bottomAnchor.constraint(equalTo: tabRow.bottomAnchor),
            tabScroll.trailingAnchor.constraint(equalTo: tabPopButton.leadingAnchor, constant: -8),
            tabScroll.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.homeTabHeight),
            tabStack.leadingAnchor.constraint(equalTo: tabScroll.leadingAnchor),
            tabStack.trailingAnchor.constraint(equalTo: tabScroll.trailingAnchor),
            tabStack.topAnchor.constraint(equalTo: tabScroll.topAnchor),
            tabStack.bottomAnchor.constraint(equalTo: tabScroll.bottomAnchor),
            tabStack.heightAnchor.constraint(equalTo: tabScroll.heightAnchor),
            tabPopButton.trailingAnchor.constraint(equalTo: tabRow.trailingAnchor, constant: -10),
            tabPopButton.centerYAnchor.constraint(equalTo: tabRow.centerYAnchor),
            tabPopButton.widthAnchor.constraint(equalToConstant: DesignTokens.Metrics.homeTabPopupSize),
            tabPopButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.homeTabPopupSize),
            tabRow.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.homeTabHeight)
        ])
        column.addArrangedSubview(tabRow)

        // ViewPager：marginTop 5dp
        pager.backgroundColor = .clear
        let pagerContainer = UIView()
        pagerContainer.addSubview(pager)
        pager.pinEdges(to: pagerContainer)
        column.addArrangedSubview(pagerContainer)
        NSLayoutConstraint.activate([
            pagerContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
        ])
        column.setCustomSpacing(DesignTokens.Metrics.homePagerMarginTop, after: tabRow)
    }

    // MARK: - 配置加载

    func reloadConfig() {
        let bundle = ConfigRepository.shared.currentBundle
        sites = bundle.sites.filter { !$0.isJarSpider }
        rebuildCategoryTabs()
        loadCategory(index: 0)
    }

    private func rebuildCategoryTabs() {
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        categoryButtons.removeAll()

        // 首页分类 Tab 来自第一个站点的分类（R-02 数据来源：[CFG] 站点集合 → 分类 Tab）。
        guard let firstSite = sites.first else {
            addCategoryButton(title: "暂无配置", index: 0)
            return
        }
        let provider = SiteProviderFactory.make(site: firstSite)
        provider.categories { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let list):
                    self.categories = list
                    // R-52：有真实分类才显示展开浮层入口。
                    self.tabPopButton.isHidden = list.isEmpty
                    if list.isEmpty {
                        self.addCategoryButton(title: firstSite.displayName, index: 0)
                    } else {
                        for (index, category) in list.enumerated() {
                            self.addCategoryButton(title: category.name, index: index)
                        }
                    }
                case .failure(let error):
                    Log.warn("[Home] categories failed: \(error.localizedDescription)")
                    self.addCategoryButton(title: firstSite.displayName, index: 0)
                }
                self.loadCategory(index: 0)
            }
        }
    }

    private func addCategoryButton(title: String, index: Int) {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(14))
        // tabPaddingStart=8dp / tabPaddingEnd=12dp
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 12)
        button.tag = index
        button.addTarget(self, action: #selector(selectCategory(_:)), for: .touchUpInside)
        tabStack.addArrangedSubview(button)
        categoryButtons.append(button)
    }

    @objc private func selectCategory(_ sender: UIButton) {
        loadCategory(index: sender.tag)
    }

    /// R-52：展开全部分类浮层，点选后走同一条 loadCategory 链路。
    private func openCategorySheet() {
        guard !categories.isEmpty else { return }
        let sheet = CategorySheetViewController(categories: categories,
                                                selectedIndex: currentCategoryIndex)
        sheet.onSelect = { [weak self] index in
            self?.loadCategory(index: index)
        }
        present(sheet, animated: true)
    }

    private func updateCategorySelection() {
        for (index, button) in categoryButtons.enumerated() {
            let selected = index == currentCategoryIndex
            button.setTitleColor(selected ? DesignTokens.Colors.main : DesignTokens.Colors.gray, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(14),
                                                  weight: selected ? .semibold : .regular)
        }
    }

    private func loadCategory(index: Int) {
        currentCategoryIndex = index
        updateCategorySelection()
        guard index < categories.count || !sites.isEmpty else { return }
        let categoryId = index < categories.count ? categories[index].id : ""
        contentController?.willMove(toParent: nil)
        contentController?.view.removeFromSuperview()
        contentController?.removeFromParent()

        let controller = CategoryContentViewController(site: sites.first, categoryId: categoryId)
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        pager.addSubview(controller.view)
        controller.view.pinEdges(to: pager)
        controller.didMove(toParent: self)
        contentController = controller
    }

    @objc private func openSearch() {
        let controller = SearchViewController()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }
}
