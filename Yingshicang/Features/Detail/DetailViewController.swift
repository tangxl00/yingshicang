import UIKit

/// R-05 详情页（`mobile_detail_activity`）。
///
/// 布局事实（AXML）：
/// - 顶部返回按钮 + 标题条，高 37dp
/// - 顶部信息区：左侧海报 104×140dp（比例 104:140），右侧片名、评分 36sp、
///   简介（最多 4 行）、来源、类型标签（圆角）
/// - 下部 TabLayout（线路切换）+ ViewPager：每页为剧集网格，列数 4
final class DetailViewController: SwipeBackViewController {

    private let item: VodItem
    private let provider: SiteProvider?
    private let scroll = UIScrollView()
    private let contentStack = UIStackView.vertical(spacing: 0)

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel.make(size: DesignTokens.Metrics.titleFont, color: .white)
    private let poster = UIImageView()
    private let nameLabel = UILabel.make(size: DesignTokens.Metrics.previewTitleFont, color: .white, lines: 2)
    private let scoreLabel = UILabel.make(size: DesignTokens.Metrics.previewScoreFont,
                                         color: DesignTokens.Colors.main, weight: .semibold)
    private let descLabel = UILabel.make(size: DesignTokens.Metrics.previewDescFont,
                                        color: DesignTokens.Colors.text, lines: 4)
    private let sourceLabel = UILabel.make(size: DesignTokens.Metrics.introSourceFont,
                                          color: DesignTokens.Colors.text)
    private let typeWrap = UIView()
    private let playButton = UIButton(type: .system)
    private let favButton = UIButton(type: .system)
    private let tabScroll = UIScrollView()
    private let tabStack = UIStackView()
    private let episodeCollection: UICollectionView
    private let statusLabel = UILabel.make(size: 13, color: DesignTokens.Colors.text, lines: 0)

    private var detail: VodDetail?
    private var activeTab = 0
    private var episodes: [PlayEpisode] = []

    init(item: VodItem) {
        self.item = item
        if let site = ConfigRepository.shared.currentBundle.sites.first(where: { $0.key == item.siteKey }) {
            self.provider = SiteProviderFactory.make(site: site)
        } else {
            self.provider = nil
        }
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = DesignTokens.dp(8)
        layout.minimumInteritemSpacing = DesignTokens.dp(8)
        self.episodeCollection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        setupTopBar()
        setupContent()
        loadDetail()
    }

    // MARK: - 布局

    private func setupTopBar() {
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        titleLabel.text = item.vodName

        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        [backButton, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview($0)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.playTopBarHeight),

            backButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: DesignTokens.dp(8)),
            backButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: DesignTokens.Metrics.backButtonSize),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: DesignTokens.dp(4)),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            titleLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])
        self.topBar = bar
    }

    private var topBar: UIView?

    private func setupContent() {
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)
        scroll.addSubview(contentStack)
        let bar: UIView = topBar ?? view!
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // 顶部信息区
        let infoRow = UIStackView.horizontal(spacing: DesignTokens.dp(12), alignment: .top)
        infoRow.isLayoutMarginsRelativeArrangement = true
        infoRow.layoutMargins = UIEdgeInsets(top: DesignTokens.dp(4), left: DesignTokens.Metrics.actionBarHorizontalPadding,
                                            bottom: DesignTokens.dp(8), right: DesignTokens.Metrics.actionBarHorizontalPadding)

        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.cardCorner)
        poster.setRemoteImage(item.vodPic)
        poster.widthAnchor.constraint(equalToConstant: DesignTokens.Metrics.introPosterWidth).isActive = true
        poster.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.introPosterHeight).isActive = true

        let infoColumn = UIStackView.vertical(spacing: DesignTokens.dp(6))
        let nameRow = UIStackView.horizontal(spacing: DesignTokens.dp(8), alignment: .firstBaseline)
        nameRow.addArrangedSubview(nameLabel)
        nameRow.addArrangedSubview(scoreLabel)
        infoColumn.addArrangedSubview(nameRow)
        infoColumn.addArrangedSubview(descLabel)
        infoColumn.addArrangedSubview(sourceLabel)
        typeWrap.translatesAutoresizingMaskIntoConstraints = false
        infoColumn.addArrangedSubview(typeWrap)

        infoRow.addArrangedSubview(poster)
        infoRow.addArrangedSubview(infoColumn)
        contentStack.addArrangedSubview(infoRow)

        // 播放 / 收藏按钮
        let actionRow = UIStackView.horizontal(spacing: DesignTokens.dp(10))
        actionRow.isLayoutMarginsRelativeArrangement = true
        actionRow.layoutMargins = UIEdgeInsets(top: 0, left: DesignTokens.Metrics.actionBarHorizontalPadding,
                                              bottom: DesignTokens.dp(8), right: DesignTokens.Metrics.actionBarHorizontalPadding)
        playButton.setTitle("立即播放", for: .normal)
        playButton.setTitleColor(.white, for: .normal)
        playButton.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(14), weight: .medium)
        playButton.backgroundColor = DesignTokens.Colors.main
        playButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.previewPlayCorner)
        playButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.previewPlayHeight).isActive = true
        playButton.addTarget(self, action: #selector(playFirst), for: .touchUpInside)

        favButton.setTitle("收藏", for: .normal)
        favButton.setTitleColor(.white, for: .normal)
        favButton.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(14))
        favButton.backgroundColor = DesignTokens.Colors.dialog
        favButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.previewPlayCorner)
        favButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.previewFavHeight).isActive = true
        favButton.widthAnchor.constraint(equalToConstant: DesignTokens.dp(84)).isActive = true
        favButton.addTarget(self, action: #selector(toggleFavorite), for: .touchUpInside)

        actionRow.addArrangedSubview(playButton)
        actionRow.addArrangedSubview(favButton)
        contentStack.addArrangedSubview(actionRow)
        updateFavoriteButton()

        // 线路 Tab
        tabScroll.showsHorizontalScrollIndicator = false
        tabStack.axis = .horizontal
        tabStack.spacing = DesignTokens.dp(8)
        tabScroll.addSubview(tabStack)
        let tabRow = UIView()
        tabRow.addSubview(tabScroll)
        tabScroll.translatesAutoresizingMaskIntoConstraints = false
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabRow.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.playSeriesTabHeight).isActive = true
        NSLayoutConstraint.activate([
            tabScroll.leadingAnchor.constraint(equalTo: tabRow.leadingAnchor,
                                              constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            tabScroll.trailingAnchor.constraint(equalTo: tabRow.trailingAnchor,
                                                constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            tabScroll.topAnchor.constraint(equalTo: tabRow.topAnchor),
            tabScroll.bottomAnchor.constraint(equalTo: tabRow.bottomAnchor),
            tabStack.leadingAnchor.constraint(equalTo: tabScroll.leadingAnchor),
            tabStack.trailingAnchor.constraint(equalTo: tabScroll.trailingAnchor),
            tabStack.topAnchor.constraint(equalTo: tabScroll.topAnchor),
            tabStack.bottomAnchor.constraint(equalTo: tabScroll.bottomAnchor),
            tabStack.heightAnchor.constraint(equalTo: tabScroll.heightAnchor)
        ])
        contentStack.addArrangedSubview(tabRow)
        contentStack.setCustomSpacing(DesignTokens.Metrics.playPagerMarginTop, after: tabRow)

        // 剧集网格
        episodeCollection.backgroundColor = .clear
        episodeCollection.dataSource = self
        episodeCollection.delegate = self
        episodeCollection.register(EpisodeCell.self, forCellWithReuseIdentifier: EpisodeCell.reuseID)
        episodeCollection.heightAnchor.constraint(equalToConstant: DesignTokens.dp(240)).isActive = true
        contentStack.addArrangedSubview(episodeCollection)

        statusLabel.textAlignment = .center
        statusLabel.isHidden = true
        view.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(24)),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(24))
        ])
    }

    // MARK: - 数据

    private func loadDetail() {
        guard let provider = provider else {
            statusLabel.text = "找不到站点「\(item.siteKey)」的配置，请检查配置源"
            statusLabel.isHidden = false
            return
        }
        statusLabel.text = "加载中…"
        statusLabel.isHidden = false
        provider.detail(id: item.vodId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let detail):
                    self.statusLabel.isHidden = true
                    self.apply(detail)
                case .failure(let error):
                    self.statusLabel.text = error.localizedDescription ?? "详情加载失败"
                    self.statusLabel.isHidden = false
                }
            }
        }
    }

    private func apply(_ detail: VodDetail) {
        self.detail = detail
        titleLabel.text = detail.vodName.isEmpty ? item.vodName : detail.vodName
        nameLabel.text = detail.vodName
        scoreLabel.text = detail.vodScore.isEmpty ? "" : detail.vodScore
        descLabel.text = detail.vodContent
        sourceLabel.text = "来源：" + item.siteKey
        if !detail.vodPic.isEmpty { poster.setRemoteImage(detail.vodPic) }

        // 类型标签（圆角 22dp，对应 introTypeCorner）
        typeWrap.subviews.forEach { $0.removeFromSuperview() }
        let types = [detail.vodYear, detail.vodArea, detail.vodType].filter { !$0.isEmpty }
        let wrapStack = UIStackView.horizontal(spacing: DesignTokens.dp(6))
        for text in types {
            let label = UILabel.make(text: " \(text) ", size: DesignTokens.Metrics.introTypeFont,
                                     color: DesignTokens.Colors.text)
            label.backgroundColor = DesignTokens.Colors.cardWhite
            label.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.introTypeCorner)
            label.layer.masksToBounds = true
            wrapStack.addArrangedSubview(label)
        }
        typeWrap.addSubview(wrapStack)
        wrapStack.pinEdges(to: typeWrap)

        rebuildTabRow(tabs: detail.tabs.isEmpty ? ["默认线路"] : detail.tabs)
        switchTab(index: 0)
    }

    private func rebuildTabRow(tabs: [String]) {
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, name) in tabs.enumerated() {
            let button = UIButton(type: .custom)
            button.setTitle(name, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(13),
                                                  weight: index == activeTab ? .semibold : .regular)
            button.setTitleColor(index == activeTab ? DesignTokens.Colors.main : DesignTokens.Colors.text, for: .normal)
            button.tag = index
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabStack.addArrangedSubview(button)
        }
    }

    @objc private func tabTapped(_ sender: UIButton) {
        switchTab(index: sender.tag)
    }

    private func switchTab(index: Int) {
        activeTab = index
        guard let detail = detail else { return }
        if detail.lists.indices.contains(index) {
            episodes = detail.lists[index]
        } else {
            episodes = detail.lists.first ?? []
        }
        rebuildTabRow(tabs: detail.tabs.isEmpty ? ["默认线路"] : detail.tabs)
        episodeCollection.reloadData()
    }

    private func updateFavoriteButton() {
        let fav = FavoriteStore.shared.isFavorite(siteKey: item.siteKey, vodId: item.vodId)
        favButton.setTitle(fav ? "已收藏" : "收藏", for: .normal)
        favButton.setTitleColor(fav ? DesignTokens.Colors.main : .white, for: .normal)
    }

    // MARK: - 交互

    @objc private func playFirst() {
        guard let first = episodes.first else {
            statusLabel.text = "该影片暂无可用剧集"
            statusLabel.isHidden = false
            return
        }
        openPlayer(first, index: 0)
    }

    private func openPlayer(_ episode: PlayEpisode, index: Int) {
        guard let provider = provider, let detail = detail else { return }
        let controller = PlayerViewController(detail: detail, episodes: episodes,
                                            startIndex: index, provider: provider)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    @objc private func toggleFavorite() {
        _ = FavoriteStore.shared.toggle(siteKey: item.siteKey, vodId: item.vodId,
                                        vodName: item.vodName, vodPic: item.vodPic)
        updateFavoriteButton()
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

extension DetailViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        episodes.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EpisodeCell.reuseID, for: indexPath) as! EpisodeCell
        cell.bind(episodes[indexPath.item].name, selected: false)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        openPlayer(episodes[indexPath.item], index: indexPath.item)
    }
}

/// 剧集项：`seriesColumns=4` 列，圆角 8dp，高 40dp，名称最多 2 行。
final class EpisodeCell: UICollectionViewCell {

    static let reuseID = "EpisodeCell"
    private let label = UILabel.make(size: DesignTokens.Metrics.seriesFont,
                                    color: .white, lines: 2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = DesignTokens.Colors.cardWhite
        contentView.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.seriesCorner)
        contentView.layer.masksToBounds = true
        label.textAlignment = .center
        contentView.addSubview(label)
        label.pinEdges(to: contentView, insets: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func bind(_ name: String, selected: Bool) {
        label.text = name
        contentView.backgroundColor = selected ? DesignTokens.Colors.main : DesignTokens.Colors.cardWhite
    }
}
