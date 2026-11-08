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

        // 搜索栏：左右 padding 14dp；右侧为 R-07 榜单入口与 R-31 添加快捷入口。
        let searchContainer = UIView()
        searchContainer.addSubview(searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.topAnchor.constraint(equalTo: searchContainer.topAnchor).isActive = true
        searchBar.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor).isActive = true
        searchBar.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor,
                                           constant: DesignTokens.Metrics.actionBarHorizontalPadding).isActive = true
        searchBar.heightAnchor.constraint(equalToConstant: 30).isActive = true
        searchContainer.heightAnchor.constraint(equalToConstant: 30).isActive = true
        searchBar.addTarget(self, action: #selector(openSearch), for: .touchUpInside)

        let rankButton = UIButton(type: .system)
        rankButton.setImage(UIImage(systemName: "list.number"), for: .normal)
        rankButton.tintColor = DesignTokens.Colors.text
        rankButton.addAction(UIAction { [weak self] _ in
            self?.openRank()
        }, for: .touchUpInside)
        rankButton.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(rankButton)

        // R-31 添加快捷弹窗入口（扫码 / 条件筛选）。
        let quickAddButton = UIButton(type: .system)
        quickAddButton.setImage(UIImage(systemName: "plus"), for: .normal)
        quickAddButton.tintColor = DesignTokens.Colors.text
        quickAddButton.addAction(UIAction { [weak self] _ in
            self?.openQuickAddPopup()
        }, for: .touchUpInside)
        quickAddButton.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(quickAddButton)

        NSLayoutConstraint.activate([
            rankButton.leadingAnchor.constraint(equalTo: searchBar.trailingAnchor, constant: DesignTokens.dp(8)),
            rankButton.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            rankButton.widthAnchor.constraint(equalToConstant: 28),
            rankButton.heightAnchor.constraint(equalToConstant: 30),
            quickAddButton.leadingAnchor.constraint(equalTo: rankButton.trailingAnchor, constant: DesignTokens.dp(4)),
            quickAddButton.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor,
                                                     constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            quickAddButton.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            quickAddButton.widthAnchor.constraint(equalToConstant: 28),
            quickAddButton.heightAnchor.constraint(equalToConstant: 30)
        ])
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
        // R-50：加密频道（分类名含「密码/加密」）先弹密码校验层，通过后才展示内容。
        if index < categories.count,
           ChannelPasswordRule.needsPassword(categoryName: categories[index].name) {
            present(ChannelPasswordDialogViewController(
                categoryName: categories[index].name,
                expectedPassword: nil) { [weak self] in
                    self?.showCategoryContent(categoryId: categoryId)
            }, animated: true)
            return
        }
        showCategoryContent(categoryId: categoryId)
    }

    private func showCategoryContent(categoryId: String) {
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

    // MARK: - R-07 榜单 / R-31 快捷入口

    /// R-07 榜单入口：当前首站点的推荐数据榜单。
    private func openRank() {
        let controller = RankListViewController(site: sites.first)
        present(controller, animated: true)
    }

    /// R-31 添加快捷弹窗：宽 180dp、项高 30dp、paddingTop 10dp（Metrics.addPopupXXX）。
    /// 项：① 扫码添加配置（R-44/R-31）② 条件筛选（R-08）。
    private func openQuickAddPopup() {
        let popup = QuickAddPopupViewController()
        popup.onScanCode = { [weak self] in
            guard let self = self else { return }
            let scanner = ScanCodeViewController { [weak self] value in
                DispatchQueue.main.async {
                    self?.addScannedConfig(urlString: value)
                }
            }
            self.present(scanner, animated: true)
        }
        popup.onConditionFilter = { [weak self] in
            guard let self = self else { return }
            let controller = ConditionFilterViewController(site: self.sites.first)
            self.present(controller, animated: true)
        }
        present(popup, animated: true)
    }

    /// R-44/R-31 扫码结果 → 走与手动添加一致的网络加载链路。
    private func addScannedConfig(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 二维码内容不可信：只接受 http/https + 非空 host 才进加载链路（质检 P2-4）。
        guard ConfigRepository.acceptableConfigURL(from: trimmed) != nil else {
            let alert = UIAlertController(title: "地址不可用",
                                          message: "仅支持 http/https 且需包含有效域名或 IP：\(trimmed)",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }
        ConfigRepository.shared.load(urlString: trimmed) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    StoreHouseStore.shared.add(ConfigStore(
                        name: "扫码导入",
                        url: trimmed,
                        lines: [ConfigLine(name: "扫码导入", url: trimmed)]))
                case .failure(let error):
                    Log.warn("[Home] scanned config load failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

/// R-31 添加快捷弹窗：180dp 窄弹窗，列表两项（项高 30dp，paddingTop 10dp）。
final class QuickAddPopupViewController: CardDialogViewController {
    var onScanCode: (() -> Void)?
    var onConditionFilter: (() -> Void)?

    init() {
        super.init(config: CardDialogViewController.Config(
            title: "添加",
            height: DesignTokens.dp(150),
            width: DesignTokens.dp(DesignTokens.Metrics.addPopupWidth),
            anchor: .center,
            showsCloseButton: false
        ))
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func buildBody(into stack: UIStackView) {
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: DesignTokens.dp(DesignTokens.Metrics.sheetContentPaddingTop - 5),
                                           left: 0, bottom: 0, right: 0)

        let scanItem = UIButton.text("扫码添加配置", size: 14, color: .white)
        scanItem.contentHorizontalAlignment = .left
        scanItem.addAction(UIAction { [weak self] _ in
            let callback = self?.onScanCode
            self?.dismiss(animated: true) { callback?() }
        }, for: .touchUpInside)
        stack.addArrangedSubview(scanItem)

        let filterItem = UIButton.text("条件筛选", size: 14, color: .white)
        filterItem.contentHorizontalAlignment = .left
        filterItem.addAction(UIAction { [weak self] _ in
            let callback = self?.onConditionFilter
            self?.dismiss(animated: true) { callback?() }
        }, for: .touchUpInside)
        stack.addArrangedSubview(filterItem)

        for item in [scanItem, filterItem] {
            item.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.addPopupItemHeight).isActive = true
        }
    }
}
