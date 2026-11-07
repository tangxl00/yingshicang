import UIKit

/// R-04 搜索页（全屏 present）。AXML `mobile_search_activity`：
/// 顶部搜索框（高 40dp、圆角 22dp 胶囊）+ 返回；内容区展示
/// ① 搜索历史（含「清空」）② 热门搜索 ③ 搜索结果列表。
final class SearchViewController: SwipeBackViewController, UITextFieldDelegate {

    private let backButton = UIButton(type: .system)
    private let field = UITextField()
    private let historyTitle = UILabel.make(text: "搜索历史", size: DesignTokens.Metrics.hotSearchTitleFont,
                                           color: .white, weight: .semibold)
    private let clearButton = UIButton.text("清空", size: DesignTokens.Metrics.historyClearFont,
                                          color: DesignTokens.Colors.text)
    private let historyWrap = UIView()
    private let resultTable = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel.make(size: 13, color: DesignTokens.Colors.text, lines: 0)

    private var results: [VodItem] = []
    private var searchToken = 0
    private var keyword: String = ""

    private let historyKey = "tpc_search_history"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        setupTopBar()
        setupHistory()
        setupResults()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        field.becomeFirstResponder()
    }

    // MARK: - 布局

    private func setupTopBar() {
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        field.backgroundColor = DesignTokens.Colors.inputBg
        field.layer.cornerRadius = DesignTokens.Corner.action
        field.layer.masksToBounds = true
        field.textColor = .white
        field.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.siteSearchFont))
        field.attributedPlaceholder = NSAttributedString(
            string: "搜索影片、电视剧、综艺…",
            attributes: [.foregroundColor: DesignTokens.Colors.text])
        field.returnKeyType = .search
        field.delegate = self
        field.leftView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        field.leftViewMode = .always
        field.leftView?.tintColor = DesignTokens.Colors.text

        let bar = UIView()
        view.addSubview(bar)
        bar.translatesAutoresizingMaskIntoConstraints = false
        [backButton, field].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview($0)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.siteSearchHeight),

            backButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: DesignTokens.dp(8)),
            backButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: DesignTokens.dp(36)),

            field.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: DesignTokens.dp(4)),
            field.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            field.topAnchor.constraint(equalTo: bar.topAnchor),
            field.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
        ])
        self.topBar = bar
        self.searchField = field
    }

    private var topBar: UIView?
    private var searchField: UITextField?

    private func setupHistory() {
        historyTitle.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearHistory), for: .touchUpInside)
        view.addSubview(historyTitle)
        view.addSubview(clearButton)
        view.addSubview(historyWrap)

        let top: UIView = topBar ?? view!
        NSLayoutConstraint.activate([
            historyTitle.topAnchor.constraint(equalTo: top.bottomAnchor,
                                              constant: DesignTokens.Metrics.hotSearchContainerPaddingTop),
            historyTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                                 constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            clearButton.centerYAnchor.constraint(equalTo: historyTitle.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                                 constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            historyWrap.topAnchor.constraint(equalTo: historyTitle.bottomAnchor, constant: DesignTokens.dp(10)),
            historyWrap.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                                constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            historyWrap.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                                 constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            historyWrap.heightAnchor.constraint(equalToConstant: 40)
        ])
        rebuildHistoryChips()
    }

    private func rebuildHistoryChips() {
        historyWrap.subviews.forEach { $0.removeFromSuperview() }
        let history = searchHistory()
        guard !history.isEmpty else {
            clearButton.isHidden = true
            let tip = UILabel.make(text: "输入关键字后回车搜索，默认同时搜索全部可用站点",
                                  size: 12, color: DesignTokens.Colors.text, lines: 0)
            historyWrap.addSubview(tip)
            tip.pinEdges(to: historyWrap)
            return
        }
        clearButton.isHidden = false
        var x: CGFloat = 0
        let height = DesignTokens.dp(28)
        for word in history.prefix(8) {
            let button = UIButton.capsule(word, size: 12, height: 28,
                                         corner: DesignTokens.Corner.xl)
            button.setTitleColor(DesignTokens.Colors.text, for: .normal)
            button.backgroundColor = DesignTokens.Colors.cardWhite
            let width = (word as NSString).size(withAttributes: [
                .font: UIFont.systemFont(ofSize: DesignTokens.sp(12))
            ]).width + 24
            button.frame = CGRect(x: x, y: 0, width: width, height: height)
            button.addTarget(self, action: #selector(tapHistory(_:)), for: .touchUpInside)
            historyWrap.addSubview(button)
            x += width + 8
            if x > view.bounds.width - 60 { break }
        }
    }

    private func setupResults() {
        resultTable.backgroundColor = .clear
        resultTable.separatorStyle = .none
        resultTable.dataSource = self
        resultTable.delegate = self
        resultTable.register(SearchResultCell.self, forCellReuseIdentifier: SearchResultCell.reuseID)
        resultTable.isHidden = true

        view.addSubview(resultTable)
        statusLabel.textAlignment = .center
        statusLabel.isHidden = true
        view.addSubview(statusLabel)

        let top = historyWrap
        NSLayoutConstraint.activate([
            resultTable.topAnchor.constraint(equalTo: top.bottomAnchor,
                                            constant: DesignTokens.Metrics.historyMarginTop),
            resultTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultTable.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(24)),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(24))
        ])
    }

    // MARK: - 搜索

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        performSearch(textField.text ?? "")
        return true
    }

    @objc private func tapHistory(_ sender: UIButton) {
        field.text = sender.title(for: .normal)
        performSearch(sender.title(for: .normal) ?? "")
    }

    /// 聚合搜索：并行请求所有可搜索站点，按 searchThreadCount 限流。
    /// 站点失败不中断整体（单源失败只影响该源结果），全部失败才提示。
    private func performSearch(_ raw: String) {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        keyword = word
        saveHistory(word)
        rebuildHistoryChips()

        searchToken += 1
        let token = searchToken
        results = []
        resultTable.reloadData()
        resultTable.isHidden = true
        statusLabel.isHidden = false
        statusLabel.text = "搜索中…"

        let sites = ConfigRepository.shared.currentBundle.sites
            .filter { $0.canSearch && !$0.isJarSpider && !SiteBlockStore.shared.isBlocked($0.key) }
        guard !sites.isEmpty else {
            statusLabel.text = "没有可搜索的站点\n若配置中站点均为 jar 爬虫，iOS 无法运行（无 Java 环境）"
            return
        }

        let limit = max(1, min(Settings.shared.searchThreadCount, 8))
        let semaphore = DispatchSemaphore(value: limit)
        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [VodItem] = []
        var failures = 0

        for site in sites {
            semaphore.wait()
            group.enter()
            let provider = SiteProviderFactory.make(site: site)
            provider.search(keyword: word, page: 1) { result in
                lock.lock()
                switch result {
                case .success(let list):
                    collected.append(contentsOf: list.map {
                        VodItem(vodId: $0.vodId, vodName: $0.vodName, vodPic: $0.vodPic,
                                vodRemarks: $0.vodRemarks, siteKey: site.key)
                    })
                case .failure: failures += 1
                }
                lock.unlock()
                semaphore.signal()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.searchToken == token else { return }
            self.results = collected
            self.resultTable.reloadData()
            self.resultTable.isHidden = collected.isEmpty
            if collected.isEmpty {
                self.statusLabel.isHidden = false
                self.statusLabel.text = failures > 0 ? "未找到相关结果（部分站点请求失败）" : "未找到「\(word)」相关结果"
            } else {
                self.statusLabel.isHidden = true
            }
        }
    }

    // MARK: - 历史

    private func searchHistory() -> [String] {
        (UserDefaults.standard.array(forKey: historyKey) as? [String]) ?? []
    }

    private func saveHistory(_ word: String) {
        var list = searchHistory()
        list.removeAll { $0 == word }
        list.insert(word, at: 0)
        UserDefaults.standard.set(Array(list.prefix(20)), forKey: historyKey)
    }

    @objc private func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
        rebuildHistoryChips()
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.reuseID, for: indexPath) as! SearchResultCell
        cell.bind(results[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        DesignTokens.dp(DesignTokens.Metrics.rankCardHeight) / 2
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = results[indexPath.row]
        let controller = DetailViewController(item: item)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }
}

/// 搜索结果行：left 缩略图 + 片名 + 备注 + 源名（源名用于「多源同片」区分）。
final class SearchResultCell: UITableViewCell {

    static let reuseID = "SearchResultCell"

    private let cover = UIImageView()
    private let nameLabel = UILabel.make(size: DesignTokens.Metrics.listNameFont, color: .white, lines: 1)
    private let noteLabel = UILabel.make(size: 11, color: DesignTokens.Colors.text, lines: 1)
    private let siteLabel = UILabel.make(size: 10, color: DesignTokens.Colors.main, lines: 1)

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

        [cover, nameLabel, noteLabel, siteLabel].forEach { contentView.addSubview($0) }
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DesignTokens.dp(6)),
            cover.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DesignTokens.dp(6)),
            cover.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DesignTokens.dp(6)),
            cover.widthAnchor.constraint(equalTo: cover.heightAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: DesignTokens.dp(8)),
            nameLabel.topAnchor.constraint(equalTo: cover.topAnchor),

            noteLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            noteLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: DesignTokens.dp(2)),

            siteLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            siteLabel.bottomAnchor.constraint(equalTo: cover.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func bind(_ item: VodItem) {
        cover.setRemoteImage(item.vodPic)
        nameLabel.text = item.vodName
        noteLabel.text = item.vodRemarks
        siteLabel.text = item.siteKey
    }
}
