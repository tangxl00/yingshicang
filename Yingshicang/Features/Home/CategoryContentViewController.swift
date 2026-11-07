import UIKit

/// R-02 主页 ViewPager 的分类内容页（海报墙），对应 AXML 的 home 分类 fragment。
///
/// 实现要点：
/// - 3 列海报网格（`gridColumns`），间距 8dp，页面内缩 12dp（令牌来自 gridSpacing/pageInset）
/// - 触底追加下一页（分类接口的 page 参数，取值 1 基，与 APK 一致）
/// - 站点返回 unsupportedJar / 网络错误时展示明确文案，不静默显示空列表
final class CategoryContentViewController: SwipeBackViewController {

    private let collectionView: UICollectionView
    private let statusLabel = UILabel.make(size: 13, color: DesignTokens.Colors.text, lines: 0)
    private let activity = UIActivityIndicatorView(style: .medium)

    private let site: SiteConfig?
    private let categoryId: String
    private var provider: SiteProvider? {
        guard let site = site else { return nil }
        return SiteProviderFactory.make(site: site)
    }

    private var items: [VodItem] = []
    private var page = 0
    private var isLoading = false
    private var reachedEnd = false

    init(site: SiteConfig?, categoryId: String) {
        self.site = site
        self.categoryId = categoryId
        let layout = UICollectionViewFlowLayout()
        let columns = CGFloat(DesignTokens.Metrics.gridColumns)
        let inset = DesignTokens.dp(DesignTokens.Metrics.pageInset)
        let spacing = DesignTokens.dp(DesignTokens.Metrics.gridSpacing)
        let usable = UIScreen.main.bounds.width - inset * 2 - spacing * (columns - 1)
        let itemWidth = floor(usable / columns)
        layout.itemSize = CGSize(width: itemWidth,
                                 height: itemWidth / DesignTokens.Metrics.posterRatio + DesignTokens.dp(34))
        layout.minimumLineSpacing = spacing
        layout.minimumInteritemSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: DesignTokens.dp(8), left: inset, bottom: inset, right: inset)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PosterCardCell.self, forCellWithReuseIdentifier: PosterCardCell.reuseID)
        collectionView.register(PosterListCell.self, forCellWithReuseIdentifier: PosterListCell.reuseID)
        collectionView.showsVerticalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        statusLabel.textAlignment = .center
        statusLabel.isHidden = true
        view.addSubview(statusLabel)

        activity.hidesWhenStopped = true
        view.addSubview(activity)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(24)),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(24)),
            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        loadNextPage()
    }

    // MARK: - 数据

    private func loadNextPage() {
        guard !isLoading, !reachedEnd, let provider = provider else {
            if provider == nil { showStatus("尚未加载配置\n请在「我的 → 配置地址」中添加配置") }
            return
        }
        isLoading = true
        if items.isEmpty { activity.startAnimating() }

        let nextPage = page + 1
        provider.category(id: categoryId, page: nextPage, extend: [:]) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                self.activity.stopAnimating()
                switch result {
                case .success(let list):
                    self.page = nextPage
                    if list.isEmpty { self.reachedEnd = true }
                    self.items.append(contentsOf: list)
                    self.collectionView.reloadData()
                    if self.items.isEmpty { self.showStatus("暂无内容") }
                case .failure(let error):
                    if self.items.isEmpty {
                        self.showStatus(error.localizedDescription ?? "加载失败")
                    } else {
                        self.reachedEnd = true
                    }
                }
            }
        }
    }

    private func showStatus(_ text: String) {
        statusLabel.text = text
        statusLabel.isHidden = false
    }

    private func openDetail(_ item: VodItem) {
        let controller = DetailViewController(item: item)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }
}

extension CategoryContentViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let item = items[indexPath.item]
        if Settings.shared.posterStyle == .list {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PosterListCell.reuseID, for: indexPath) as! PosterListCell
            cell.bind(item)
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PosterCardCell.reuseID, for: indexPath) as! PosterCardCell
        cell.bind(item)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        openDetail(items[indexPath.item])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offset = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let height = scrollView.bounds.height
        // 触底前 200pt 预加载下一页，避免用户看到空白
        if contentHeight > 0, offset + height > contentHeight - 200 {
            loadNextPage()
        }
    }
}
