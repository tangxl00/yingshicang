import UIKit

/// R-07 榜单页：以当前首站点的首页推荐数据生成榜单（按序号排行的横条卡列表）。
///
/// 布局事实（Metrics.rankXXX，来自 AXML）：
/// - 卡高 160dp，封面高 140dp、宽高比 448:672
/// - 序号角标 9sp，标题 15sp，元信息 10sp，描述 5 行
/// - 列表 paddingTop 10dp（rankPaddingTop）
final class RankListViewController: SwipeBackViewController,
                                    UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel.make(size: 13, color: DesignTokens.Colors.text, lines: 0)
    private let activity = UIActivityIndicatorView(style: .medium)

    private let site: SiteConfig?
    private var provider: SiteProvider? {
        guard let site = site else { return nil }
        return SiteProviderFactory.make(site: site)
    }

    private var items: [VodItem] = []

    /// 榜单取前 50 名（首页推荐 + 分页补足时上限）。
    static let rankLimit = 50

    init(site: SiteConfig?) {
        self.site = site
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        title = "榜单"

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(RankCardCell.self, forCellReuseIdentifier: RankCardCell.reuseID)
        tableView.rowHeight = DesignTokens.Metrics.rankCardHeight
        tableView.contentInset = UIEdgeInsets(top: DesignTokens.Metrics.rankPaddingTop, left: 0, bottom: 0, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        statusLabel.textAlignment = .center
        statusLabel.isHidden = true
        statusLabel.text = "榜单加载中…"
        view.addSubview(statusLabel)

        activity.hidesWhenStopped = true
        view.addSubview(activity)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(24)),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(24)),
            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        loadRank()
    }

    private func loadRank() {
        activity.startAnimating()
        statusLabel.isHidden = false
        guard let provider = provider else {
            activity.stopAnimating()
            statusLabel.text = "当前没有可用站点，无法加载榜单"
            return
        }
        SiteLoad.run { [weak self] result in
            guard let self = self else { return }
            self.activity.stopAnimating()
            switch result {
            case .success(let list):
                self.items = Array(list.prefix(RankListViewController.rankLimit))
                self.statusLabel.isHidden = !self.items.isEmpty
                if self.items.isEmpty { self.statusLabel.text = "该站点没有可展示的榜单数据" }
                self.tableView.reloadData()
            case .failure(let error):
                self.statusLabel.isHidden = false
                self.statusLabel.text = error.localizedDescription
            }
        } operation: { settle in
            provider.home { settle($0) }
        }
    }

    // MARK: - UITableViewDataSource / Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RankCardCell.reuseID, for: indexPath)
        if let rankCell = cell as? RankCardCell {
            rankCell.configure(item: items[indexPath.row], rank: indexPath.row + 1)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let controller = DetailViewController(item: items[indexPath.row])
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }
}

/// R-07 榜单卡：封面 + 序号角标 + 标题 + 元信息 + 描述。
final class RankCardCell: UITableViewCell {
    static let reuseID = "RankCardCell"

    private let coverView = UIImageView()
    private let rankBadge = UILabel.make(size: DesignTokens.Metrics.rankBadgeFont, color: .white)
    private let titleLabel = UILabel.make(size: DesignTokens.Metrics.rankTitleFont, color: .white, weight: .medium)
    private let metaLabel = UILabel.make(size: DesignTokens.Metrics.rankMetaFont, color: DesignTokens.Colors.text)
    private let descLabel = UILabel.make(size: DesignTokens.Metrics.rankMetaFont,
                                         color: DesignTokens.Colors.text, lines: 5)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        let coverWidth = DesignTokens.Metrics.rankCoverHeight * DesignTokens.Metrics.rankCoverRatio

        coverView.contentMode = .scaleAspectFill
        coverView.layer.cornerRadius = DesignTokens.Corner.xs
        coverView.layer.masksToBounds = true
        coverView.backgroundColor = DesignTokens.Colors.black60
        contentView.addSubview(coverView)
        coverView.translatesAutoresizingMaskIntoConstraints = false

        rankBadge.backgroundColor = DesignTokens.Colors.accentRed
        rankBadge.textAlignment = .center
        rankBadge.layer.cornerRadius = DesignTokens.dp(6)
        rankBadge.layer.masksToBounds = true
        contentView.addSubview(rankBadge)
        rankBadge.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.numberOfLines = 1
        contentView.addSubview(metaLabel)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        descLabel.numberOfLines = 5
        contentView.addSubview(descLabel)
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // 垂直居中（卡高 160 - 封面 140 = 上下各 10dp）。
            coverView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DesignTokens.dp(10)),
            coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DesignTokens.dp(12)),
            coverView.widthAnchor.constraint(equalToConstant: coverWidth),
            coverView.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.rankCoverHeight),

            rankBadge.leadingAnchor.constraint(equalTo: coverView.leadingAnchor, constant: DesignTokens.dp(4)),
            rankBadge.topAnchor.constraint(equalTo: coverView.topAnchor, constant: DesignTokens.dp(4)),
            rankBadge.widthAnchor.constraint(equalToConstant: DesignTokens.dp(18)),
            rankBadge.heightAnchor.constraint(equalToConstant: DesignTokens.dp(14)),

            titleLabel.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: DesignTokens.dp(10)),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DesignTokens.dp(12)),
            titleLabel.topAnchor.constraint(equalTo: coverView.topAnchor),

            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DesignTokens.dp(4)),

            descLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            descLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: DesignTokens.dp(4)),
            descLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -DesignTokens.dp(8))
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func configure(item: VodItem, rank: Int) {
        coverView.setRemoteImage(item.vodPic)
        rankBadge.text = "\(rank)"
        titleLabel.text = item.vodName
        metaLabel.text = item.vodRemarks.isEmpty ? "—" : item.vodRemarks
        // 榜单描述：VodItem 无独立简介字段时以备注呈现，避免编造内容。
        descLabel.text = item.vodRemarks
    }
}
