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

// MARK: - F-20 真实下载（URLSession 落盘 + 断点续传）

/// 下载路径与可下载性判定（纯逻辑，单测覆盖）。
enum DownloadSupport {

    /// App 文档目录下的 `Downloads/`：用 Documents 而不是 Caches，
    /// 因为这里是用户主动下载的内容，不能被系统在存储吃紧时清掉。
    static var downloadsDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Downloads", isDirectory: true)
    }

    static func ensureDirectory() {
        let dir = downloadsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// 文件名里的非法字符替换成 `_`（`/` 会破坏路径，`:` 在部分接口里是保留符）。
    static func sanitizedName(_ raw: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.newlines)
        let cleaned = raw.components(separatedBy: banned).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "未命名" : String(cleaned.prefix(80))
    }

    /// 落盘文件名：`片名 - 集名.ext`。同一片同一集名重复时不覆盖——
    /// 用任务 id 的稳定哈希做后缀，保证可重复（同一任务重试落同一个文件，能续传）。
    static func fileName(for task: DownloadTask, extension ext: String) -> String {
        let stem = "\(sanitizedName(task.vodName)) - \(sanitizedName(task.episodeName))"
        let normalizedExt = ext.isEmpty ? "mp4" : ext
        return "\(stem)-\(stableHash(task.id)).\(normalizedExt)"
    }

    static func fileURL(forFileName name: String) -> URL {
        downloadsDirectory.appendingPathComponent(name)
    }

    /// 地址可下载性：m3u8 需要分片合成，本版不支持；其余 http(s)
    /// 直链（mp4/m4a/mkv/ts 单文件等）都可以整文件下载。
    enum Downloadability: Equatable {
        case direct(URL)
        case hlsUnsupported
        case invalid
    }

    static func assess(_ episodeURL: String) -> Downloadability {
        let trimmed = episodeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .invalid
        }
        let ext = url.pathExtension.lowercased()
        if ext == "m3u8" || trimmed.lowercased().contains(".m3u8") {
            return .hlsUnsupported
        }
        return .direct(url)
    }

    /// 稳定哈希（不用 `hashValue`：每次进程启动随机种子会变，无法续传同名文件）。
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash % 100000_000, radix: 16)
    }

    /// 已下载文件（用于「文件管理页能看到已下载文件」与本地播放）。
    static func downloadedFileURL(for task: DownloadTask) -> URL? {
        let name = fileName(for: task, extension: URL(string: task.episodeURL)?.pathExtension ?? "")
        let url = fileURL(forFileName: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// F-20 下载服务：`URLSession` 后台配置 + `downloadTask` + 断点续传 + 进度回调。
///
/// 关键取舍：
/// - 用 **background configuration**：App 切后台/被挂起后下载仍由系统守护进程继续，
///   这是 iOS 上「真实落盘」的前提（前台 session 一挂起就断）。
/// - 断点续传走 `cancel(byProducingResumeData:)` 拿到 resume data 落盘，
///   下次 `downloadTask(withResumeData:)` 续；resume data 存在任务本级
///   （key = `resume.<任务id>`），App 重启后仍可用。
/// - 进度写回 `DownloadTaskStore.setStatus`（`setStatus` 由此有了真实生产调用者）。
final class DownloadService: NSObject, URLSessionDownloadDelegate {

    static let shared = DownloadService()

    /// 后台会话标识。`AppDelegate` 需要在
    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
    /// 里以此重建会话，否则系统回调丢失。
    static let backgroundIdentifier = "com.yingshicang.ios.download"

    private let store: DownloadTaskStore
    private let defaults = UserDefaults.standard
    private let resumePrefix = "download.resume."

    /// storeID ↔ URLSession taskID 双向映射（回调里只拿得到 taskID）。
    private var storeIDByTaskID: [Int: String] = [:]
    private var taskIDByStoreID: [String: Int] = [:]
    private var lastProgressWrite: [String: TimeInterval] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        // 单集视频动辄上百 MB，别让默认 60s 超时误杀慢速源。
        config.timeoutIntervalForResource = 60 * 60 * 6
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(store: DownloadTaskStore = .shared) {
        self.store = store
        super.init()
    }

    /// 批量入队（详情页「下载」按钮调这个）。返回真正开始下载的数量。
    @discardableResult
    func start(tasks: [DownloadTask]) -> (started: Int, hls: Int, invalid: Int) {
        DownloadSupport.ensureDirectory()
        var started = 0, hls = 0, invalid = 0
        for task in tasks where task.status == .pending || task.status == .paused {
            switch DownloadSupport.assess(task.episodeURL) {
            case .hlsUnsupported:
                hls += 1
                store.setStatus(id: task.id, status: .failed, message: "m3u8 分片本版不支持")
            case .invalid:
                invalid += 1
                store.setStatus(id: task.id, status: .failed, message: "地址无效（仅支持 http/https）")
            case .direct(let url):
                started += 1
                resume(task: task, url: url)
            }
        }
        return (started, hls, invalid)
    }

    /// 恢复/开始单个任务：有 resume data 就续传，没有就从头下。
    func resume(task: DownloadTask, url: URL? = nil) {
        guard taskIDByStoreID[task.id] == nil else { return } // 已在跑
        let target = url ?? DownloadSupport.assess(task.episodeURL).directURL
        guard let target = target else {
            store.setStatus(id: task.id, status: .failed, message: "地址无效")
            return
        }
        let resumeData = defaults.data(forKey: resumePrefix + task.id)
        let downloadTask: URLSessionDownloadTask
        if let resumeData = resumeData, !resumeData.isEmpty {
            downloadTask = session.downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: target)
            request.setValue("Yingshicang-iOS/2.0.50", forHTTPHeaderField: "User-Agent")
            downloadTask = session.downloadTask(with: request)
        }
        storeIDByTaskID[downloadTask.taskIdentifier] = task.id
        taskIDByStoreID[task.id] = downloadTask.taskIdentifier
        store.setStatus(id: task.id, status: .running, message: "0%")
        downloadTask.resume()
    }

    /// 按系统任务号取回会话里的任务（`allTasks` 是 async 属性，同步路径走 completion 版 getAllTasks）。
    private func sessionTask(with identifier: Int, then: @escaping (URLSessionTask?) -> Void) {
        session.getAllTasks { tasks in
            then(tasks.first { $0.taskIdentifier == identifier })
        }
    }

    /// 暂停并保存 resume data（下次续传）。
    func pause(taskID: String) {
        guard let sessionTaskID = taskIDByStoreID[taskID] else { return }
        sessionTask(with: sessionTaskID) { [weak self] task in
            guard let self = self, let task = task as? URLSessionDownloadTask else { return }
            task.cancel { [weak self] resumeData in
                guard let self = self else { return }
                if let resumeData = resumeData {
                    self.defaults.set(resumeData, forKey: self.resumePrefix + taskID)
                    self.store.setStatus(id: taskID, status: .paused, message: "已暂停（可续传）")
                } else {
                    // 服务端不支持 Range 时拿不到 resume data —— 只能从头下，如实告知。
                    self.store.setStatus(id: taskID, status: .paused, message: "已暂停（该源不支持续传）")
                }
                self.forget(taskID: taskID)
            }
        }
    }

    func cancel(taskID: String) {
        if let sessionTaskID = taskIDByStoreID[taskID] {
            sessionTask(with: sessionTaskID) { task in
                task?.cancel()
            }
        }
        defaults.removeObject(forKey: resumePrefix + taskID)
        forget(taskID: taskID)
        store.setStatus(id: taskID, status: .pending, message: "已取消")
    }

    /// 删除任务同时删本地文件（下载列表左滑删除调用）。
    func removeTaskAndFile(id: String) {
        cancel(taskID: id)
        if let task = store.task(id: id), let file = DownloadSupport.downloadedFileURL(for: task) {
            try? FileManager.default.removeItem(at: file)
        }
        store.remove(id: id)
    }

    private func forget(taskID: String) {
        if let sessionTaskID = taskIDByStoreID[taskID] {
            storeIDByTaskID.removeValue(forKey: sessionTaskID)
        }
        taskIDByStoreID.removeValue(forKey: taskID)
        lastProgressWrite.removeValue(forKey: taskID)
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let storeID = storeIDByTaskID[downloadTask.taskIdentifier] else { return }
        let now = Date().timeIntervalSince1970
        // 进度回调节流到 1s/次：每次写 UserDefaults 都重新序列化整个任务数组，
        // 不节流会在几十 MB 的下载里疯狂写盘。
        if let last = lastProgressWrite[storeID], now - last < 1.0 { return }
        lastProgressWrite[storeID] = now
        let percent = totalBytesExpectedToWrite > 0
            ? Int((Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) * 100)
            : 0
        store.setStatus(id: storeID, status: .running,
                        message: totalBytesExpectedToWrite > 0 ? "\(percent)%" : "下载中")
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let storeID = storeIDByTaskID[downloadTask.taskIdentifier],
              let task = store.task(id: storeID) else { return }
        let name = DownloadSupport.fileName(
            for: task,
            extension: downloadTask.originalRequest?.url?.pathExtension ?? task.episodeURL.pathExtension_()
        )
        let destination = DownloadSupport.fileURL(forFileName: name)
        DownloadSupport.ensureDirectory()
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            defaults.removeObject(forKey: resumePrefix + storeID)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            store.setStatus(id: storeID, status: .completed,
                            message: size > 0 ? Self.sizeText(size) : "已完成")
        } catch {
            store.setStatus(id: storeID, status: .failed, message: "写入失败：\(error.localizedDescription)")
        }
        forget(taskID: storeID)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error = error,
              let storeID = storeIDByTaskID[task.taskIdentifier] else { return }
        let nsError = error as NSError
        // 被 cancel 时也走这里：带 resume data 的属于「主动暂停」，不算失败。
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
           !resumeData.isEmpty {
            defaults.set(resumeData, forKey: resumePrefix + storeID)
            store.setStatus(id: storeID, status: .paused, message: "已暂停（可续传）")
        } else if nsError.code != NSURLErrorCancelled {
            store.setStatus(id: storeID, status: .failed, message: nsError.localizedDescription)
        }
        forget(taskID: storeID)
    }

    /// AppDelegate 暂存的后台完成回调：所有下载事件派发完时必须调用，
    /// 否则系统认为 App 没处理完后台事件，下一次唤醒配额会被扣。
    var onAllEventsDelivered: (() -> Void)?

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.onAllEventsDelivered?()
            self?.onAllEventsDelivered = nil
        }
    }

    static func sizeText(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        return mb >= 1 ? String(format: "已完成 %.1f MB", mb) : String(format: "已完成 %.0f KB", Double(bytes) / 1024)
    }
}

private extension String {
    /// `episodeURL` 是字符串，取后缀时别重复造 URL。
    func pathExtension_() -> String {
        (URL(string: self)?.pathExtension) ?? ""
    }
}

private extension DownloadSupport.Downloadability {
    var directURL: URL? {
        if case .direct(let url) = self { return url }
        return nil
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

    /// 后台下载会话会异步回写状态（进度/完成/失败），每次回到前台都重刷。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 上一轮暂停/失败的任务，回到页面时尝试续传/重试，避免「登记了永远不动」。
        let restorable = store.tasks.filter { $0.status == .pending }
        if !restorable.isEmpty {
            DownloadService.shared.start(tasks: restorable)
        }
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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let task = store.tasks[indexPath.row]
        switch task.status {
        case .completed:
            // 已完成 → 播本地文件（文件管理语义：下载列表就是文件入口）。
            if let file = DownloadSupport.downloadedFileURL(for: task) {
                let player = LocalFilePlayerViewController(fileURL: file, title: task.vodName)
                present(player, animated: true)
            } else {
                // 文件被系统/用户清掉但状态还是已完成：回退为失败，如实告知。
                store.setStatus(id: task.id, status: .failed, message: "本地文件已丢失，请重新下载")
                refresh()
            }
        case .paused:
            DownloadService.shared.resume(task: task)
            refresh()
        case .failed:
            // 失败重试：置回 pending 再走一次准入判定。
            store.setStatus(id: task.id, status: .pending, message: "")
            DownloadService.shared.start(tasks: [task])
            refresh()
        case .pending, .running:
            break
        }
    }

    func tableView(_ tableView: UITableView,
                   commit editingStyle: UITableViewCell.EditingStyle,
                   forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        // 删除 = 取消任务 + 删本地文件 + 移除记录，三步一起做（DownloadService 负责）。
        DownloadService.shared.removeTaskAndFile(id: store.tasks[indexPath.row].id)
        refresh()
    }
}

// MARK: - F-20 本地文件播放页

/// 播放 `Documents/Downloads/` 里的已下载文件。
///
/// 不复用 `PlayerViewController`：那套走站点解析链（provider → PlayResolver → 网络地址），
/// 本地文件没有 provider 上下文。这里直接用 `PlaybackRouter` + `PlaybackEngine`：
/// mp4 走 AVPlayer，mkv/rmvb 等走 VLCKit——与在线播放同一套路由规则。
final class LocalFilePlayerViewController: SwipeBackViewController {

    private let fileURL: URL
    private let titleText: String
    private var engine: PlaybackEngine?
    private let host = UIView()
    private let titleLabel = UILabel.make(size: 15, color: .white, weight: .semibold)
    private let playButton = UIButton(type: .system)
    private let slider = UISlider()
    private let positionLabel = UILabel.make(size: 11, color: .white)
    private let durationLabel = UILabel.make(size: 11, color: .white)
    private let hintLabel = UILabel.make(size: 12, color: .white, lines: 0)
    private var isPlaying = false

    init(fileURL: URL, title: String) {
        self.fileURL = fileURL
        self.titleText = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = titleText
        titleLabel.text = titleText
        titleLabel.textAlignment = .center

        host.backgroundColor = .black
        view.addSubview(host)

        playButton.setTitle("暂停", for: .normal)
        playButton.setTitleColor(.white, for: .normal)
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)

        slider.minimumTrackTintColor = DesignTokens.Colors.main
        slider.addTarget(self, action: #selector(seekChanged), for: .valueChanged)

        let bottomBar = UIStackView.horizontal(spacing: DesignTokens.dp(10))
        positionLabel.text = "00:00"
        durationLabel.text = "00:00"
        for v in [playButton, positionLabel, slider, durationLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addArrangedSubview(v)
        }
        view.addSubview(bottomBar)
        hintLabel.textAlignment = .center
        view.addSubview(hintLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.dp(10)),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(14)),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(14)),
            host.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DesignTokens.dp(8)),
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -DesignTokens.dp(8)),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(14)),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(14)),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DesignTokens.dp(10)),
            bottomBar.heightAnchor.constraint(equalToConstant: DesignTokens.dp(30)),
            hintLabel.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(24)),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(24))
        ])

        start()
    }

    private func start() {
        let route = PlaybackRouter.live.decision(for: fileURL)
        Log.info("[Download] local play route: \(route.engine.rawValue) — \(route.reason)")
        let newEngine: PlaybackEngine = route.engine == .vlc ? VLCPlayerEngine() : AVPlayerEngine()
        newEngine.onReady = { [weak self] in self?.hintLabel.isHidden = true }
        newEngine.onProgress = { [weak self] position, duration in
            guard let self = self else { return }
            self.positionLabel.text = self.format(position)
            if duration > 0, !self.slider.isTracking {
                self.slider.maximumValue = Float(duration)
                self.slider.value = Float(position)
                self.durationLabel.text = self.format(duration)
            }
        }
        newEngine.onError = { [weak self] message in
            self?.hintLabel.text = "播放失败：\(message)"
            self?.hintLabel.isHidden = false
        }
        engine = newEngine
        newEngine.view.frame = host.bounds
        newEngine.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(newEngine.view)
        newEngine.load(url: fileURL, autoplay: true)
        isPlaying = true
    }

    @objc private func togglePlay() {
        guard let engine = engine else { return }
        if isPlaying {
            engine.pause()
            playButton.setTitle("播放", for: .normal)
        } else {
            engine.play()
            playButton.setTitle("暂停", for: .normal)
        }
        isPlaying.toggle()
    }

    @objc private func seekChanged() {
        engine?.seek(to: Double(slider.value))
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
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
