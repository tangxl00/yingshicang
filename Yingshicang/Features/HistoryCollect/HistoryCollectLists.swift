import UIKit

/// R-21 历史列表（`mobile_history_activity` 的「播放历史」Tab）。
/// 布局：搜索入口（高 36dp、圆角历史搜索样式）+ 列表；列表项左侧 3:4 封面，
/// 右侧片名 + 「看到第 N 集 第 MM:SS」+ 右侧删除按钮。
final class HistoryListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let table = UITableView(frame: .zero, style: .plain)
    private let clearButton = UIButton.text("清空", size: DesignTokens.Metrics.historyClearFont,
                                          color: DesignTokens.Colors.text)
    private let statusLabel = UILabel.make(size: 13, color: DesignTokens.Colors.text, lines: 0)
    private var items: [HistoryRecord] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        clearButton.addTarget(self, action: #selector(clearAll), for: .touchUpInside)
        view.addSubview(clearButton)
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.register(HistoryCell.self, forCellReuseIdentifier: HistoryCell.reuseID)
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        view.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            clearButton.topAnchor.constraint(equalTo: view.topAnchor, constant: DesignTokens.Metrics.historyMarginTop),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                                 constant: -DesignTokens.Metrics.actionBarHorizontalPadding),

            table.topAnchor.constraint(equalTo: clearButton.bottomAnchor, constant: DesignTokens.Metrics.historyListMarginTop),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(24)),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(24))
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    func reload() {
        items = HistoryStore.shared.all()
        table.reloadData()
        statusLabel.text = items.isEmpty ? "暂无播放历史\n在播放页观看后会自动记录进度" : ""
        clearButton.isHidden = items.isEmpty
    }

    @objc private func clearAll() {
        let alert = UIAlertController(title: "清空播放历史", message: "此操作不可恢复", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            HistoryStore.shared.removeAll()
            self?.reload()
        })
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: HistoryCell.reuseID, for: indexPath) as! HistoryCell
        cell.bind(items[indexPath.row])
        cell.onDelete = { [weak self] in
            guard let self = self, let id = self.items[indexPath.row].id else { return }
            HistoryStore.shared.remove(id: id)
            self.reload()
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        DesignTokens.dp(96)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = items[indexPath.row]
        let item = VodItem(vodId: record.vodId, vodName: record.vodName, vodPic: record.vodPic,
                           vodRemarks: "", siteKey: record.siteKey)
        let controller = DetailViewController(item: item)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }
}

final class HistoryCell: UITableViewCell {

    static let reuseID = "HistoryCell"
    private let cover = UIImageView()
    private let nameLabel = UILabel.make(size: DesignTokens.Metrics.listNameFont, color: .white, lines: 1)
    private let progressLabel = UILabel.make(size: 11, color: DesignTokens.Colors.text, lines: 1)
    private let deleteButton = UIButton(type: .system)
    var onDelete: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        contentView.backgroundColor = DesignTokens.Colors.cardWhite
        contentView.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.cardCorner)
        contentView.layer.masksToBounds = true

        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.cardCorner)
        cover.translatesAutoresizingMaskIntoConstraints = false

        deleteButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        deleteButton.tintColor = DesignTokens.Colors.text
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        [cover, nameLabel, progressLabel, deleteButton].forEach { contentView.addSubview($0) }
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DesignTokens.dp(8)),
            cover.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            cover.heightAnchor.constraint(equalTo: contentView.heightAnchor, constant: -DesignTokens.dp(16)),
            cover.widthAnchor.constraint(equalTo: cover.heightAnchor, multiplier: 3.0 / 4.0),

            nameLabel.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: DesignTokens.dp(10)),
            nameLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -DesignTokens.dp(8)),
            nameLabel.topAnchor.constraint(equalTo: cover.topAnchor, constant: DesignTokens.dp(4)),

            progressLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            progressLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: DesignTokens.dp(6)),

            deleteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DesignTokens.dp(8)),
            deleteButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 28),
            deleteButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func bind(_ record: HistoryRecord) {
        cover.setRemoteImage(record.vodPic)
        nameLabel.text = record.vodName
        let minutes = Int(record.position) / 60
        let seconds = Int(record.position) % 60
        let ep = record.flag.isEmpty ? "第 \(record.playIndex + 1) 集" : "\(record.flag) 第 \(record.playIndex + 1) 集"
        progressLabel.text = String(format: "看到 %@ %02d:%02d", ep, minutes, seconds)
    }

    @objc private func deleteTapped() { onDelete?() }
}

/// R-22 收藏列表：3 列海报网格（与主页一致），长按/角标删除。
final class FavoriteViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {

    private let collectionView: UICollectionView
    private let statusLabel = UILabel.make(size: 13, color: DesignTokens.Colors.text, lines: 0)
    private var items: [FavoriteRecord] = []

    init() {
        let layout = UICollectionViewFlowLayout()
        let columns: CGFloat = 3
        let inset = DesignTokens.dp(DesignTokens.Metrics.pageInset)
        let spacing = DesignTokens.dp(DesignTokens.Metrics.gridSpacing)
        let width = floor((UIScreen.main.bounds.width - inset * 2 - spacing * (columns - 1)) / columns)
        layout.itemSize = CGSize(width: width, height: width / DesignTokens.Metrics.posterRatio + DesignTokens.dp(34))
        layout.minimumLineSpacing = spacing
        layout.minimumInteritemSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: DesignTokens.dp(8), left: inset, bottom: inset, right: inset)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
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
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        view.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor, constant: DesignTokens.Metrics.historyMarginTop),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(24)),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(24))
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        items = FavoriteStore.shared.all()
        collectionView.reloadData()
        statusLabel.text = items.isEmpty ? "暂无收藏\n在详情页点击「收藏」即可加入" : ""
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PosterCardCell.reuseID, for: indexPath) as! PosterCardCell
        let record = items[indexPath.item]
        cell.bind(VodItem(vodId: record.vodId, vodName: record.vodName, vodPic: record.vodPic,
                          vodRemarks: "", siteKey: record.siteKey))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let record = items[indexPath.item]
        let controller = DetailViewController(item: VodItem(vodId: record.vodId, vodName: record.vodName,
                                                           vodPic: record.vodPic, vodRemarks: "",
                                                           siteKey: record.siteKey))
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    /// 悬浮删除（R-22：卡片右上角删除钮，点击后 confirm）。
    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(title: "", children: [
                UIAction(title: "取消收藏", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    guard let self = self else { return }
                    let record = self.items[indexPath.item]
                    FavoriteStore.shared.remove(siteKey: record.siteKey, vodId: record.vodId)
                    self.reload()
                }
            ])
        }
    }
}
