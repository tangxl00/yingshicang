import UIKit

/// R-23 「我的」页（`mobile_mine_activity`）。
///
/// 布局事实：顶部登录/头像区高 180dp、下方 3 列网格项（项高 80dp、图标 32dp、
/// 名称 13sp、角标 10sp 圆角 10dp）。
/// 网格项对应 AXML 里的功能入口：配置地址、站点管理、播放设置、个性化、
/// WebDAV 备份、本地数据、检查更新、关于、互动交流。
final class MineViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {

    struct Entry {
        var title: String
        var icon: String
        var badge: String = ""
        var action: Action
    }

    enum Action {
        case storeHouse
        case siteManage
        case playerSettings
        case personality
        case webDav
        case localData
        case checkUpdate
        case about
        case interaction
    }

    private let headerView = UIView()
    private let avatar = UIImageView()
    private let titleLabel = UILabel.make(text: "影视仓", size: DesignTokens.Metrics.titleFont,
                                        color: .white, weight: .semibold)
    private let detailLabel = UILabel.make(text: "iOS 客户端 · 2.0.50", size: 12,
                                         color: DesignTokens.Colors.text)
    private var entries: [Entry] = []
    private let collectionView: UICollectionView

    init() {
        let layout = UICollectionViewFlowLayout()
        let columns: CGFloat = CGFloat(DesignTokens.Metrics.myGridColumns)
        let inset = DesignTokens.dp(DesignTokens.Metrics.pageInset)
        let spacing = DesignTokens.dp(DesignTokens.Metrics.gridSpacing)
        let width = floor((UIScreen.main.bounds.width - inset * 2 - spacing * (columns - 1)) / columns)
        layout.itemSize = CGSize(width: width, height: DesignTokens.dp(DesignTokens.Metrics.myItemHeight))
        layout.minimumLineSpacing = spacing
        layout.minimumInteritemSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: DesignTokens.dp(8), left: inset, bottom: inset, right: inset)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        buildEntries()
        setupLayout()
    }

    private func buildEntries() {
        entries = [
            Entry(title: "配置地址", icon: "link", action: .storeHouse),
            Entry(title: "站点管理", icon: "globe", action: .siteManage),
            Entry(title: "播放设置", icon: "play.circle", action: .playerSettings),
            Entry(title: "个性化", icon: "paintpalette", action: .personality),
            Entry(title: "WebDAV 备份", icon: "icloud", action: .webDav),
            Entry(title: "本地数据", icon: "internaldrive", action: .localData),
            Entry(title: "检查更新", icon: "arrow.down.circle", action: .checkUpdate),
            Entry(title: "关于", icon: "info.circle", action: .about),
            Entry(title: "互动交流", icon: "bubble.left.and.bubble.right", action: .interaction)
        ]
    }

    private func setupLayout() {
        view.addSubview(headerView)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .clear

        avatar.image = UIImage(systemName: "person.crop.circle.fill")
        avatar.tintColor = DesignTokens.Colors.main
        avatar.contentMode = .scaleAspectFit

        [avatar, titleLabel, detailLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                           constant: DesignTokens.Metrics.myLoginMarginTop),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.myLoginHeight),

            avatar.leadingAnchor.constraint(equalTo: headerView.leadingAnchor,
                                            constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            avatar.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 64),
            avatar.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: DesignTokens.dp(12)),
            titleLabel.topAnchor.constraint(equalTo: avatar.topAnchor, constant: DesignTokens.dp(8)),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DesignTokens.dp(6))
        ])

        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MineGridCell.self, forCellWithReuseIdentifier: MineGridCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        entries.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MineGridCell.reuseID, for: indexPath) as! MineGridCell
        cell.bind(entries[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        route(entries[indexPath.item].action)
    }

    private func route(_ action: Action) {
        switch action {
        case .storeHouse:
            presentFullScreen(StoreHouseViewController())
        case .siteManage:
            presentFullScreen(SiteManageViewController())
        case .playerSettings:
            presentFullScreen(SettingsListViewController(kind: .player))
        case .personality:
            presentFullScreen(SettingsListViewController(kind: .personality))
        case .webDav:
            presentFullScreen(WebDavViewController())
        case .localData:
            presentFullScreen(LocalDataViewController())
        case .checkUpdate:
            presentFullScreen(UpdateCheckViewController())
        case .about:
            presentFullScreen(AboutViewController())
        case .interaction:
            presentFullScreen(InteractionViewController())
        }
    }

    private func presentFullScreen(_ controller: UIViewController) {
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }
}

final class MineGridCell: UICollectionViewCell {

    static let reuseID = "MineGridCell"
    private let icon = UIImageView()
    private let name = UILabel.make(size: DesignTokens.Metrics.myItemNameFont, color: .white)
    private let badge = UILabel.make(size: DesignTokens.Metrics.myItemBadgeFont, color: .white)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = DesignTokens.Colors.cardWhite
        contentView.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.myGridCorner)
        contentView.layer.masksToBounds = true

        icon.tintColor = DesignTokens.Colors.main
        icon.contentMode = .scaleAspectFit
        name.textAlignment = .center
        badge.backgroundColor = DesignTokens.Colors.accentRed
        badge.textAlignment = .center
        badge.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.myItemBadgeCorner)
        badge.layer.masksToBounds = true
        badge.isHidden = true

        [icon, name, badge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            icon.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DesignTokens.dp(14)),
            icon.widthAnchor.constraint(equalToConstant: DesignTokens.Metrics.myItemIcon),
            icon.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.myItemIcon),

            name.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            name.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            name.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: DesignTokens.dp(8)),

            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            badge.heightAnchor.constraint(equalToConstant: 14),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func bind(_ entry: MineViewController.Entry) {
        icon.image = UIImage(systemName: entry.icon)
        name.text = entry.title
        badge.text = entry.badge.isEmpty ? nil : entry.badge
        badge.isHidden = entry.badge.isEmpty
    }
}
