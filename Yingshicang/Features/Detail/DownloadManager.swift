import Foundation
import UIKit

/// F-20 下载任务状态机。
enum DownloadStatus: String, Codable, Equatable {
    case pending
    case running
    case paused
    case completed
    case failed

    var displayText: String {
        switch self {
        case .pending: return "等待中"
        case .running: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}

/// F-20 下载任务：记录影片/剧集来源与状态，元数据持久化到 UserDefaults。
struct DownloadTask: Codable, Equatable, Identifiable {
    var id: String
    var vodId: String
    var vodName: String
    var vodPic: String
    var siteKey: String
    var episodeName: String
    var episodeURL: String
    var flag: String
    var status: DownloadStatus
    var createdAt: Double
    var message: String

    /// 任务唯一键：站点 + 影片 + 集地址（同一集不重复建任务）。
    static func makeID(siteKey: String, vodId: String, episodeURL: String) -> String {
        "\(siteKey)|\(vodId)|\(episodeURL)"
    }
}

/// F-20 下载任务仓库：增删查 + 状态流转 + UserDefaults 持久化（纯逻辑，可测试）。
final class DownloadTaskStore {
    static let shared = DownloadTaskStore()
    static let storageKey = "download.tasks.v1"

    private let defaults: UserDefaults
    private(set) var tasks: [DownloadTask] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: DownloadTaskStore.storageKey),
           let saved = try? JSONDecoder().decode([DownloadTask].self, from: data) {
            tasks = saved
        }
    }

    // MARK: - 任务管理

    /// 加入任务（去重：同 id 已存在则不重复加入）。返回是否真的加入。
    @discardableResult
    func add(_ task: DownloadTask) -> Bool {
        guard !tasks.contains(where: { $0.id == task.id }) else { return false }
        tasks.insert(task, at: 0)
        persist()
        return true
    }

    @discardableResult
    func add(vodItem: VodItem, episodes: [PlayEpisode], flag: String) -> Int {
        var added = 0
        for episode in episodes {
            let id = DownloadTask.makeID(siteKey: vodItem.siteKey, vodId: vodItem.vodId, episodeURL: episode.url)
            let task = DownloadTask(
                id: id, vodId: vodItem.vodId, vodName: vodItem.vodName, vodPic: vodItem.vodPic,
                siteKey: vodItem.siteKey, episodeName: episode.name, episodeURL: episode.url,
                flag: flag, status: .pending, createdAt: Date().timeIntervalSince1970, message: "")
            if add(task) { added += 1 }
        }
        return added
    }

    func remove(id: String) {
        tasks.removeAll { $0.id == id }
        persist()
    }

    func clearFinished() {
        tasks.removeAll { $0.status == .completed || $0.status == .failed }
        persist()
    }

    func setStatus(id: String, status: DownloadStatus, message: String = "") {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = status
        tasks[index].message = message
        persist()
    }

    func task(id: String) -> DownloadTask? {
        tasks.first { $0.id == id }
    }

    var pendingCount: Int {
        tasks.filter { $0.status == .pending || $0.status == .running }.count
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: DownloadTaskStore.storageKey)
        }
    }
}

/// F-20 下载列表页：任务列表 + 状态 + 删除 + 清除已完成。
final class DownloadListViewController: SwipeBackViewController,
                                        UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel.make(size: 13, color: DesignTokens.Colors.text, lines: 0)

    private let store: DownloadTaskStore

    init(store: DownloadTaskStore = .shared) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        title = "下载任务"

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DownloadTaskCell.self, forCellReuseIdentifier: DownloadTaskCell.reuseID)
        tableView.rowHeight = DesignTokens.dp(64)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)

        // present 无导航栏，清除入口放页面顶部。
        let clearButton = UIButton.text("清除已完成", size: 13, color: DesignTokens.Colors.gray)
        clearButton.contentHorizontalAlignment = .right
        clearButton.addAction(UIAction { [weak self] _ in
            self?.store.clearFinished()
            self?.refresh()
        }, for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clearButton)

        NSLayoutConstraint.activate([
            clearButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.dp(8)),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(14)),
            clearButton.heightAnchor.constraint(equalToConstant: DesignTokens.dp(28)),
            tableView.topAnchor.constraint(equalTo: clearButton.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(24)),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(24))
        ])

        refresh()
    }

    private func refresh() {
        statusLabel.isHidden = !store.tasks.isEmpty
        statusLabel.text = "暂无下载任务。\n在影片详情页点「下载」即可把全部剧集加入任务列表。"
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource / Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.tasks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DownloadTaskCell.reuseID, for: indexPath)
        if let taskCell = cell as? DownloadTaskCell {
            taskCell.configure(task: store.tasks[indexPath.row])
        }
        return cell
    }

    func tableView(_ tableView: UITableView,
                   commit editingStyle: UITableViewCell.EditingStyle,
                   forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        store.remove(id: store.tasks[indexPath.row].id)
        refresh()
    }
}

/// F-20 任务行：片名 + 集名 + 状态。
final class DownloadTaskCell: UITableViewCell {
    static let reuseID = "DownloadTaskCell"

    private let titleLabel = UILabel.make(size: 14, color: .white)
    private let statusLabel = UILabel.make(size: 11, color: DesignTokens.Colors.text)
    private let episodeLabel = UILabel.make(size: 11, color: DesignTokens.Colors.gray)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        titleLabel.numberOfLines = 1
        statusLabel.textAlignment = .right
        episodeLabel.numberOfLines = 1

        for label in [titleLabel, episodeLabel, statusLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DesignTokens.dp(10)),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DesignTokens.dp(14)),
            titleLabel.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -DesignTokens.dp(8)),
            episodeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            episodeLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            episodeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DesignTokens.dp(4)),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DesignTokens.dp(14)),
            statusLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func configure(task: DownloadTask) {
        titleLabel.text = task.vodName
        episodeLabel.text = task.episodeName
        statusLabel.text = task.message.isEmpty ? task.status.displayText : "\(task.status.displayText) · \(task.message)"
        statusLabel.textColor = task.status == .completed
            ? DesignTokens.Colors.main
            : (task.status == .failed ? DesignTokens.Colors.accentRed : DesignTokens.Colors.text)
    }
}
