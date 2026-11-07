import UIKit
import UniformTypeIdentifiers

// 「我的」页的二级页面（R-30~R-47 中对应的设置/管理类界面）。
// 说明：这些页面按架构文档「设置类表单可用 SwiftUI」的口径本可用 SwiftUI，
// 但为保持单一布局体系（设计令牌统一驱动），统一用 UIKit 纯代码实现；
// 每页的尺寸/文案取自 R 系列条目与 strings.xml 实测值。

// MARK: - R-30 配置仓库（多仓管理）

/// R-28 添加仓库弹层：220dp（inputDialogHeight）圆角居中弹窗。
/// 内容 = URL 输入 + 名称输入 + 双按钮行（「本地导入」走文件 App 选配置文件，
/// 「添加并加载」走网络加载），替代原 UIAlertController 文本输入形态。
final class AddStoreDialogViewController: CardDialogViewController, UIDocumentPickerDelegate {

    private let urlField = UITextField()
    private let nameField = UITextField()
    /// 导入/添加完成回调（主线程），宿主据此刷新仓列表。
    var onFinished: (() -> Void)?

    init(prefillURL: String = "") {
        super.init(config: .init(title: "添加仓库",
                                 height: DesignTokens.dp(DesignTokens.Metrics.inputDialogHeight),
                                 anchor: .center))
        urlField.text = prefillURL
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func buildBody(into stack: UIStackView) {
        for (field, placeholder) in [(urlField, "配置地址 https://…/config.json"),
                                     (nameField, "名称（可选）")] {
            field.placeholder = placeholder
            field.textColor = .white
            field.backgroundColor = DesignTokens.Colors.inputBg
            field.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.inputFieldCorner)
            field.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.inputFieldFont))
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.keyboardType = field == urlField ? .URL : .default
            field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
            field.leftViewMode = .always
            field.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.inputFieldHeight).isActive = true
            stack.addArrangedSubview(field)
        }

        let buttonRow = UIStackView.horizontal(spacing: DesignTokens.dp(10))

        let localButton = UIButton(type: .system)
        localButton.setTitle("本地导入", for: .normal)
        localButton.setTitleColor(DesignTokens.Colors.main, for: .normal)
        localButton.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.sheetActionFont))
        localButton.backgroundColor = DesignTokens.Colors.cardWhite
        localButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.dialogConfirmCorner)
        localButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.dialogConfirmHeight).isActive = true
        localButton.addTarget(self, action: #selector(pickLocalFile), for: .touchUpInside)
        buttonRow.addArrangedSubview(localButton)

        let addButton = UIButton(type: .system)
        addButton.setTitle("添加并加载", for: .normal)
        addButton.setTitleColor(.white, for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.sheetActionFont), weight: .medium)
        addButton.backgroundColor = DesignTokens.Colors.main
        addButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.dialogConfirmCorner)
        addButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.dialogConfirmHeight).isActive = true
        addButton.addTarget(self, action: #selector(confirmAdd), for: .touchUpInside)
        buttonRow.addArrangedSubview(addButton)

        localButton.widthAnchor.constraint(equalTo: addButton.widthAnchor, multiplier: 1).isActive = true
        stack.addArrangedSubview(buttonRow)
    }

    @objc private func pickLocalFile() {
        var types: [UTType] = [.json, .plainText, .text]
        types.append(.data)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        // 文件 App 外部选择的安全作用域：读前 start，读后 stop。
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            presentError("无法读取所选文件（非文本配置）")
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let result = LocalConfigImporter.importConfig(text: text, sourceName: "file://\(name)")
        switch result {
        case .success:
            StoreHouseStore.shared.add(ConfigStore(name: name,
                                                   url: "file://\(name)",
                                                   lines: [ConfigLine(name: name, url: "file://\(name)")]))
            let callback = onFinished
            dismiss(animated: true) { callback?() }
        case .failure(let error):
            presentError(error.message)
        }
    }

    @objc private func confirmAdd() {
        guard let url = urlField.text?.trimmingCharacters(in: .whitespaces), !url.isEmpty else {
            urlField.becomeFirstResponder()
            return
        }
        let rawName = nameField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let name = rawName.isEmpty ? "配置\(StoreHouseStore.shared.stores().count + 1)" : rawName
        ConfigRepository.shared.load(urlString: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    StoreHouseStore.shared.add(ConfigStore(name: name, url: url,
                                                            lines: [ConfigLine(name: name, url: url)]))
                    let callback = self.onFinished
                    self.dismiss(animated: true) { callback?() }
                case .failure(let error):
                    self.presentError(error.localizedDescription)
                }
            }
        }
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "导入失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

/// 配置仓库页：仓列表 + 「添加」按钮；顶部提示条。
/// 数据走 StoreHouseStore（tpc_stores / tpc_current_line）。
final class StoreHouseViewController: SwipeBackViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let addButton = UIButton(type: .system)
    private let tipLabel = UILabel.make(text: "仓库支持多个配置线路，切换线路后站点列表会整体替换",
                                        size: DesignTokens.Metrics.storeHouseTipFont,
                                        color: DesignTokens.Colors.text, lines: 0)
    private var stores: [ConfigStore] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg

        view.addSubview(tipLabel)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "store")
        view.addSubview(tableView)

        addButton.setTitle("＋ 添加仓库", for: .normal)
        addButton.setTitleColor(DesignTokens.Colors.main, for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.storeHouseAddFont))
        addButton.addTarget(self, action: #selector(addStore), for: .touchUpInside)
        view.addSubview(addButton)

        [tipLabel, tableView, addButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            tipLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.dp(12)),
            tipLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            tipLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.Metrics.actionBarHorizontalPadding),

            tableView.topAnchor.constraint(equalTo: tipLabel.bottomAnchor, constant: DesignTokens.dp(8)),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -DesignTokens.dp(8)),

            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DesignTokens.dp(12)),
            addButton.heightAnchor.constraint(equalToConstant: DesignTokens.dp(44))
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        stores = StoreHouseStore.shared.stores()
        tableView.reloadData()
    }

    @objc private func addStore() {
        // R-28：UIAlertController 输入形态 → 220dp 圆角弹层（含本地文件导入入口）。
        let dialog = AddStoreDialogViewController()
        dialog.onFinished = { [weak self] in
            self?.stores = StoreHouseStore.shared.stores()
            self?.tableView.reloadData()
        }
        present(dialog, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { stores.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "store", for: indexPath)
        let store = stores[indexPath.row]
        let current = StoreHouseStore.shared.currentLine
        let isCurrent = current != nil && store.lines.contains { $0.url == current?.url }
        cell.backgroundColor = .clear
        cell.textLabel?.text = store.name + (isCurrent ? "  ✓" : "")
        cell.textLabel?.textColor = isCurrent ? DesignTokens.Colors.main : .white
        cell.textLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.storeHouseTitleFont))
        cell.detailTextLabel?.text = store.url
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        DesignTokens.dp(DesignTokens.Metrics.storeHouseItemHeight)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let store = stores[indexPath.row]
        guard let line = store.lines.first else { return }
        ConfigRepository.shared.load(urlString: line.url) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    let alert = UIAlertController(title: "切换失败", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "好", style: .default))
                    self?.present(alert, animated: true)
                } else {
                    self?.tableView.reloadData()
                }
            }
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let action = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            guard let self = self else { return }
            StoreHouseStore.shared.remove(storeID: self.stores[indexPath.row].id)
            self.stores = StoreHouseStore.shared.stores()
            self.tableView.reloadData()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }
}

// MARK: - R-31 站点管理（屏蔽源）

final class SiteManageViewController: SwipeBackViewController, UITableViewDataSource, UITableViewDelegate {

    private let searchField = UITextField()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var sites: [SiteConfig] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg

        searchField.placeholder = "搜索站点"
        searchField.textColor = .white
        searchField.backgroundColor = DesignTokens.Colors.inputBg
        searchField.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.siteBlockCorner)
        searchField.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.siteSearchFont))
        searchField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        searchField.leftViewMode = .always
        searchField.addTarget(self, action: #selector(refilter), for: .editingChanged)
        view.addSubview(searchField)

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "site")
        view.addSubview(tableView)

        [searchField, tableView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.dp(12)),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            searchField.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.siteSearchHeight),

            tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: DesignTokens.dp(10)),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        refilter()
    }

    @objc private func refilter() {
        let keyword = (searchField.text ?? "").lowercased()
        sites = ConfigRepository.shared.currentBundle.sites.filter {
            keyword.isEmpty || $0.displayName.lowercased().contains(keyword) || $0.key.lowercased().contains(keyword)
        }
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sites.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "site", for: indexPath)
        let site = sites[indexPath.row]
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        var label = site.displayName
        if site.isJarSpider { label += "（jar·iOS 不支持）" }
        cell.textLabel?.text = label
        cell.textLabel?.textColor = SiteBlockStore.shared.isBlocked(site.key) ? DesignTokens.Colors.text : .white
        cell.textLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.siteItemFont))

        let toggle = UISwitch()
        toggle.onTintColor = DesignTokens.Colors.main
        // 开关语义与 Android 对齐：开=参与搜索/展示，关=屏蔽
        toggle.isOn = !SiteBlockStore.shared.isBlocked(site.key)
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(toggleSite(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        DesignTokens.dp(DesignTokens.Metrics.siteItemHeight)
    }

    @objc private func toggleSite(_ sender: UISwitch) {
        guard sites.indices.contains(sender.tag) else { return }
        let site = sites[sender.tag]
        SiteBlockStore.shared.setBlocked(site.key, blocked: !sender.isOn)
    }
}

// MARK: - R-32/R-33 设置列表（播放设置 / 个性化）

final class SettingsListViewController: SwipeBackViewController, UITableViewDataSource, UITableViewDelegate {

    enum Kind { case player, personality }

    struct Row {
        var title: String
        var detail: String
        var action: () -> Void
    }

    private let kind: Kind
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var rows: [Row] = []

    init(kind: Kind) {
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        view.addSubview(tableView)
        tableView.pinEdges(to: view)
        buildRows()
    }

    private func buildRows() {
        let settings = Settings.shared
        switch kind {
        case .player:
            rows = [
                Row(title: "播放内核", detail: settings.playerKernel == .avplayer ? "AVPlayer（系统）" : "VLC") { [weak self] in
                    self?.pickKernel()
                },
                Row(title: "播放倍速", detail: String(format: "%.2fx", settings.rate)) { [weak self] in
                    self?.pickRate()
                },
                Row(title: "历史记录合并", detail: settings.historyMerge ? "开" : "关") { [weak self] in
                    Settings.shared.historyMerge.toggle()
                    self?.buildRows()
                },
                Row(title: "小窗预览", detail: settings.windowPreview ? "开" : "关") { [weak self] in
                    Settings.shared.windowPreview.toggle()
                    self?.buildRows()
                },
                Row(title: "自动横屏", detail: settings.autoLandscape ? "开" : "关") { [weak self] in
                    Settings.shared.autoLandscape.toggle()
                    self?.buildRows()
                },
                Row(title: "片头片尾", detail: "头 \(settings.introSeconds)s / 尾 \(settings.outroSeconds)s") { [weak self] in
                    self?.pickSkip()
                }
            ]
        case .personality:
            rows = [
                Row(title: "海报样式", detail: settings.posterStyle.title) { [weak self] in
                    self?.pickPosterStyle()
                },
                Row(title: "搜索模式", detail: settings.searchMode.title) { [weak self] in
                    self?.pickSearchMode()
                },
                Row(title: "搜索线程数", detail: "\(settings.searchThreadCount)") { [weak self] in
                    self?.pickThreadCount()
                },
                Row(title: "去广告开关", detail: settings.removeAd ? "开" : "关") { [weak self] in
                    Settings.shared.removeAd.toggle()
                    self?.buildRows()
                },
                Row(title: "壁纸模糊", detail: settings.wallpaperBlur ? "开" : "关") { [weak self] in
                    Settings.shared.wallpaperBlur.toggle()
                    self?.buildRows()
                }
            ]
        }
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        let row = rows[indexPath.row]
        cell.backgroundColor = DesignTokens.Colors.cardWhite
        cell.textLabel?.text = row.title
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.settingRowFont))
        cell.detailTextLabel?.text = row.detail
        cell.detailTextLabel?.textColor = DesignTokens.Colors.text
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        DesignTokens.dp(DesignTokens.Metrics.settingRowHeight)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        rows[indexPath.row].action()
    }

    private func pickKernel() {
        let alert = UIAlertController(title: "播放内核", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "AVPlayer（系统）", style: .default) { _ in
            Settings.shared.playerKernel = .avplayer; self.buildRows()
        })
        let vlc = UIAlertAction(title: "VLC（需集成 VLCKit）", style: .default) { _ in
            Settings.shared.playerKernel = .vlc; self.buildRows()
        }
        vlc.isEnabled = PlaybackCapabilities.vlcAvailable
        alert.addAction(vlc)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func pickRate() {
        let alert = UIAlertController(title: "默认倍速", message: nil, preferredStyle: .actionSheet)
        for rate in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            alert.addAction(UIAlertAction(title: String(format: "%.2fx", rate), style: .default) { _ in
                Settings.shared.rate = rate; self.buildRows()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func pickSkip() {
        let alert = UIAlertController(title: "片头/片尾跳过秒数", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "片头秒数"; $0.keyboardType = .numberPad; $0.text = "\(Settings.shared.introSeconds)" }
        alert.addTextField { $0.placeholder = "片尾秒数"; $0.keyboardType = .numberPad; $0.text = "\(Settings.shared.outroSeconds)" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            if let a = alert.textFields?[0].text, let v = Int(a) { Settings.shared.introSeconds = v }
            if let b = alert.textFields?[1].text, let v = Int(b) { Settings.shared.outroSeconds = v }
            self.buildRows()
        })
        present(alert, animated: true)
    }

    private func pickPosterStyle() {
        let alert = UIAlertController(title: "海报样式", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "海报", style: .default) { _ in Settings.shared.posterStyle = .grid; self.buildRows() })
        alert.addAction(UIAlertAction(title: "列表", style: .default) { _ in Settings.shared.posterStyle = .list; self.buildRows() })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func pickSearchMode() {
        let alert = UIAlertController(title: "搜索模式", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "精确匹配", style: .default) { _ in Settings.shared.searchMode = .exact; self.buildRows() })
        alert.addAction(UIAlertAction(title: "模糊匹配", style: .default) { _ in Settings.shared.searchMode = .fuzzy; self.buildRows() })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func pickThreadCount() {
        let alert = UIAlertController(title: "搜索线程数", message: "越大搜索越快，但部分站点会限流", preferredStyle: .alert)
        alert.addTextField { $0.keyboardType = .numberPad; $0.text = "\(Settings.shared.searchThreadCount)" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            if let t = alert.textFields?.first?.text, let v = Int(t) {
                Settings.shared.searchThreadCount = max(1, min(v, 64))
            }
            self.buildRows()
        })
        present(alert, animated: true)
    }
}

// MARK: - R-45 WebDAV 备份

/// R-45 WebDAV 凭据编辑弹层：340dp（webDavWidth）圆角居中弹窗。
/// 三字段 + 「测试连接」（PROPFIND 探测，结果内联回显）+「保存」。
final class WebDavEditDialogViewController: CardDialogViewController {

    private let urlField = UITextField()
    private let accountField = UITextField()
    private let passwordField = UITextField()
    private let resultLabel = UILabel.make(size: 12, color: DesignTokens.Colors.text, lines: 0)
    private let testButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    override init(config: Config) {
        super.init(config: config)
    }

    convenience init() {
        self.init(config: .init(title: "WebDAV 服务器",
                                height: DesignTokens.dp(310),
                                width: DesignTokens.dp(DesignTokens.Metrics.webDavWidth),
                                anchor: .center))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func buildBody(into stack: UIStackView) {
        for (field, placeholder, value) in [
            (urlField, "服务器地址 https://…", Settings.shared.webDavURL),
            (accountField, "账号", Settings.shared.webDavAccount),
            (passwordField, "密码", Settings.shared.webDavPassword)
        ] {
            field.placeholder = placeholder
            field.text = value
            field.textColor = .white
            field.backgroundColor = DesignTokens.Colors.inputBg
            field.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.inputFieldCorner)
            field.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.inputFieldFont))
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.isSecureTextEntry = field == passwordField
            field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
            field.leftViewMode = .always
            field.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.inputFieldHeight).isActive = true
            stack.addArrangedSubview(field)
        }

        resultLabel.isHidden = true
        stack.addArrangedSubview(resultLabel)

        let buttonRow = UIStackView.horizontal(spacing: DesignTokens.dp(10))
        testButton.setTitle("测试连接", for: .normal)
        testButton.setTitleColor(DesignTokens.Colors.main, for: .normal)
        testButton.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.sheetActionFont))
        testButton.backgroundColor = DesignTokens.Colors.cardWhite
        testButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.dialogConfirmCorner)
        testButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.dialogConfirmHeight).isActive = true
        testButton.addTarget(self, action: #selector(testConnection), for: .touchUpInside)
        buttonRow.addArrangedSubview(testButton)

        saveButton.setTitle("保存", for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.sheetActionFont), weight: .medium)
        saveButton.backgroundColor = DesignTokens.Colors.main
        saveButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.dialogConfirmCorner)
        saveButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.dialogConfirmHeight).isActive = true
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        buttonRow.addArrangedSubview(saveButton)

        testButton.widthAnchor.constraint(equalTo: saveButton.widthAnchor, multiplier: 1).isActive = true
        stack.addArrangedSubview(buttonRow)
    }

    @objc private func testConnection() {
        resultLabel.isHidden = false
        resultLabel.text = "正在连接…"
        testButton.isEnabled = false
        WebDavConnectionTester.testConnection(base: urlField.text ?? "",
                                              account: accountField.text ?? "",
                                              password: passwordField.text ?? "") { [weak self] outcome in
            guard let self = self else { return }
            self.testButton.isEnabled = true
            self.resultLabel.text = outcome.displayText
        }
    }

    @objc private func save() {
        Settings.shared.webDavURL = urlField.text ?? ""
        Settings.shared.webDavAccount = accountField.text ?? ""
        Settings.shared.webDavPassword = passwordField.text ?? ""
        dismiss(animated: true)
    }
}

/// R-46 备份底部弹层：450dp（backupSheetHeight）双栏。
/// 左栏 weight 1.3：backupIconSize 80 图标 + 说明；右栏 weight 2.0：上传备份 /
/// 下载并恢复操作 + 结果状态。
final class BackupSheetViewController: CardDialogViewController {

    private let statusLabel = UILabel.make(size: 12, color: DesignTokens.Colors.text, lines: 0)

    // 显式 override designated init：子类定义了 required init?(coder:)（本身是
    // designated）后不再自动继承父类的 init(config:)，convenience init() 的
    // self.init(config:) 委托必须有这个显式实现才可解析。
    override init(config: Config) {
        super.init(config: config)
    }

    convenience init() {
        self.init(config: .init(title: "备份与恢复",
                                height: DesignTokens.dp(DesignTokens.Metrics.backupSheetHeight),
                                anchor: .bottom,
                                showsDragBar: true))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func buildBody(into stack: UIStackView) {
        let columns = UIStackView.horizontal(spacing: DesignTokens.dp(16))

        // 左栏（weight 1.3）：图标 + 说明。
        let left = UIStackView.vertical(spacing: DesignTokens.dp(10))
        left.alignment = .center
        let icon = UIImageView(image: UIImage(systemName: "externaldrive.badge.icloud"))
        icon.tintColor = DesignTokens.Colors.main
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        left.addArrangedSubview(icon)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.backupIconSize)),
            icon.heightAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.backupIconSize))
        ])
        left.addArrangedSubview(UILabel.make(text: "本地数据整体备份\n历史 / 收藏 / 屏蔽源",
                                             size: 12, color: DesignTokens.Colors.text, lines: 0))
        columns.addArrangedSubview(left)

        // 右栏（weight 2.0）：备份操作。
        let right = UIStackView.vertical(spacing: DesignTokens.dp(10))
        let uploadButton = UIButton.text("上传备份到 WebDAV", size: 14, color: .white)
        uploadButton.backgroundColor = DesignTokens.Colors.main
        uploadButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.confirmButtonCorner)
        uploadButton.heightAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.confirmButtonHeight)).isActive = true
        uploadButton.addTarget(self, action: #selector(uploadBackup), for: .touchUpInside)
        right.addArrangedSubview(uploadButton)

        let downloadButton = UIButton.text("从 WebDAV 下载并恢复", size: 14, color: DesignTokens.Colors.main)
        downloadButton.backgroundColor = DesignTokens.Colors.cardWhite
        downloadButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.confirmButtonCorner)
        downloadButton.heightAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.confirmButtonHeight)).isActive = true
        downloadButton.addTarget(self, action: #selector(downloadBackup), for: .touchUpInside)
        right.addArrangedSubview(downloadButton)

        statusLabel.isHidden = true
        right.addArrangedSubview(statusLabel)
        columns.addArrangedSubview(right)

        // 双栏权重 1.3 : 2.0（storeHouseLeftWeight / storeHouseRightWeight）。
        left.widthAnchor.constraint(equalTo: right.widthAnchor,
                                    multiplier: DesignTokens.Metrics.storeHouseLeftWeight / DesignTokens.Metrics.storeHouseRightWeight).isActive = true
        stack.addArrangedSubview(columns)
    }

    @objc private func uploadBackup() {
        statusLabel.isHidden = false
        statusLabel.text = "正在上传备份…"
        BackupTransfer.upload { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.statusLabel.text = "备份已上传"
            case .failure(let error):
                self.statusLabel.text = error.displayText
            }
        }
    }

    @objc private func downloadBackup() {
        statusLabel.isHidden = false
        statusLabel.text = "正在下载备份…"
        BackupTransfer.downloadAndRestore { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let payload):
                self.statusLabel.text = "已恢复：历史 \(payload.history.count) 条 / 收藏 \(payload.favorites.count) 条"
            case .failure(let error):
                self.statusLabel.text = error.displayText
            }
        }
    }
}

/// R-45/R-46 WebDAV 备份页：凭据状态 + 编辑入口（340dp 弹层）+ 备份入口（450dp 双栏弹层）。
final class WebDavViewController: SwipeBackViewController {

    private let statusCard = UILabel.make(size: 13, color: .white, lines: 0)
    private let editButton = UIButton(type: .system)
    private let backupButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg

        let column = UIStackView.vertical(spacing: DesignTokens.dp(14))
        column.isLayoutMarginsRelativeArrangement = true
        column.layoutMargins = UIEdgeInsets(top: 24, left: DesignTokens.Metrics.actionBarHorizontalPadding,
                                            bottom: 24, right: DesignTokens.Metrics.actionBarHorizontalPadding)
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let title = UILabel.make(text: "WebDAV 备份", size: DesignTokens.Metrics.webDavTitleFont,
                                 color: .white, weight: .semibold)
        column.addArrangedSubview(title)

        statusCard.numberOfLines = 0
        column.addArrangedSubview(statusCard)

        editButton.setTitle("编辑服务器", for: .normal)
        editButton.setTitleColor(.white, for: .normal)
        editButton.backgroundColor = DesignTokens.Colors.main
        editButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.dialogConfirmCorner)
        editButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.dialogConfirmHeight).isActive = true
        editButton.addTarget(self, action: #selector(openEdit), for: .touchUpInside)
        column.addArrangedSubview(editButton)

        backupButton.setTitle("备份与恢复", for: .normal)
        backupButton.setTitleColor(DesignTokens.Colors.main, for: .normal)
        backupButton.backgroundColor = DesignTokens.Colors.cardWhite
        backupButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.dialogConfirmCorner)
        backupButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.dialogConfirmHeight).isActive = true
        backupButton.addTarget(self, action: #selector(openBackup), for: .touchUpInside)
        column.addArrangedSubview(backupButton)

        let note = UILabel.make(text: "备份内容：播放历史、收藏、屏蔽源。备份文件为 yingshicang-backup.json，存放在 WebDAV 服务器根目录。",
                                size: 12, color: DesignTokens.Colors.text, lines: 0)
        column.addArrangedSubview(note)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshStatus()
    }

    private func refreshStatus() {
        let base = WebDavConnectionTester.normalizedBase(Settings.shared.webDavURL)
        if base.isEmpty {
            statusCard.text = "尚未配置 WebDAV 服务器。\n配置后可将本地数据备份到自己的网盘。"
        } else {
            let account = Settings.shared.webDavAccount
            statusCard.text = "服务器：\(base)\n账号：\(account.isEmpty ? "（未填写）" : account)"
        }
    }

    @objc private func openEdit() {
        present(WebDavEditDialogViewController(), animated: true)
    }

    @objc private func openBackup() {
        present(BackupSheetViewController(), animated: true)
    }
}

// MARK: - 其余入口页

/// R-46 本地数据（本地视频扫描）。iOS 侧受沙箱限制，只能访问用户通过
/// 文件 App 放入 App Documents 的视频；提供说明。
final class LocalDataViewController: SwipeBackViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        let label = UILabel.make(text: "本地视频\n\n通过系统「文件」App 将视频放入「我的 iPhone → 影视仓」目录后，此处会列出可播放文件。",
                                 size: 14, color: DesignTokens.Colors.text, lines: 0)
        label.textAlignment = .center
        view.addSubview(label)
        label.pinEdges(to: view, insets: UIEdgeInsets(top: 80, left: 24, bottom: 24, right: 24))
    }
}

/// R-47 检查更新：iOS 侧无自更新通道（App Store / 自签分发均不由 App 内控制）。
final class UpdateCheckViewController: SwipeBackViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        let column = UIStackView.vertical(spacing: DesignTokens.dp(12))
        column.alignment = .center
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        column.addArrangedSubview(UILabel.make(text: "当前版本 2.0.50", size: 18, color: .white, weight: .semibold))
        column.addArrangedSubview(UILabel.make(text: "iOS 版通过 GitHub Actions 出包，更新以仓库为准；\nApp 内自更新在 iOS 平台不可用（系统限制）。",
                                               size: 13, color: DesignTokens.Colors.text, lines: 0))
    }
}

/// 关于页。
final class AboutViewController: SwipeBackViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        let column = UIStackView.vertical(spacing: DesignTokens.dp(10))
        column.alignment = .center
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        column.addArrangedSubview(UILabel.make(text: "影视仓", size: 24, color: .white, weight: .semibold))
        column.addArrangedSubview(UILabel.make(text: "iOS 原生重写版 · 2.0.50", size: 13, color: DesignTokens.Colors.text))
        column.addArrangedSubview(UILabel.make(text: "本项目为学习用途的界面与功能还原实现；\n内容源由用户自行配置，App 不内置任何内容。",
                                               size: 12, color: DesignTokens.Colors.text, lines: 0))
    }
}

