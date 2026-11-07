import UIKit

// 「我的」页的二级页面（R-30~R-47 中对应的设置/管理类界面）。
// 说明：这些页面按架构文档「设置类表单可用 SwiftUI」的口径本可用 SwiftUI，
// 但为保持单一布局体系（设计令牌统一驱动），统一用 UIKit 纯代码实现；
// 每页的尺寸/文案取自 R 系列条目与 strings.xml 实测值。

// MARK: - R-30 配置仓库（多仓管理）

/// 配置仓库页：仓列表 + 「添加」按钮；顶部提示条。
/// 数据走 StoreHouseStore（tpc_stores / tpc_current_line）。
final class StoreHouseViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

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
        let alert = UIAlertController(title: "添加配置地址", message: "支持单个 json/txt 地址或多仓聚合地址", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "https://…/config.json" }
        alert.addTextField { $0.placeholder = "名称（可选）" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "添加并加载", style: .default) { [weak self] _ in
            guard let self = self,
                  let url = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !url.isEmpty else { return }
            let rawName = alert.textFields?[1].text?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = rawName.isEmpty ? "配置\(self.stores.count + 1)" : rawName
            self.loadStore(url: url, name: name)
        })
        present(alert, animated: true)
    }

    private func loadStore(url: String, name: String) {
        ConfigRepository.shared.load(urlString: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    StoreHouseStore.shared.add(ConfigStore(name: name, url: url,
                                                            lines: [ConfigLine(name: name, url: url)]))
                    self.stores = StoreHouseStore.shared.stores()
                    self.tableView.reloadData()
                case .failure(let error):
                    let alert = UIAlertController(title: "加载失败", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "好", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
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

final class SiteManageViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

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

final class SettingsListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

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

final class WebDavViewController: UIViewController {

    private let urlField = UITextField()
    private let accountField = UITextField()
    private let passwordField = UITextField()
    private let saveButton = UIButton(type: .system)

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
            column.addArrangedSubview(field)
        }

        saveButton.setTitle("保存", for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.backgroundColor = DesignTokens.Colors.main
        saveButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.dialogConfirmCorner)
        saveButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.dialogConfirmHeight).isActive = true
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        column.addArrangedSubview(saveButton)

        let note = UILabel.make(text: "说明：iOS 版当前仅保存 WebDAV 凭据，备份/恢复的传输逻辑待后续版本接入。",
                                size: 12, color: DesignTokens.Colors.text, lines: 0)
        column.addArrangedSubview(note)
    }

    @objc private func save() {
        Settings.shared.webDavURL = urlField.text ?? ""
        Settings.shared.webDavAccount = accountField.text ?? ""
        Settings.shared.webDavPassword = passwordField.text ?? ""
        let alert = UIAlertController(title: "已保存", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - 其余入口页

/// R-46 本地数据（本地视频扫描）。iOS 侧受沙箱限制，只能访问用户通过
/// 文件 App 放入 App Documents 的视频；提供说明。
final class LocalDataViewController: UIViewController {
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
final class UpdateCheckViewController: UIViewController {
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
final class AboutViewController: UIViewController {
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

/// 互动交流占位（原 APK 为内置 H5 反馈页，依赖其服务端）。
final class InteractionViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        let label = UILabel.make(text: "互动交流\n\n原 APK 的反馈通道依赖其自带服务端，iOS 重写版未接入。",
                                 size: 14, color: DesignTokens.Colors.text, lines: 0)
        label.textAlignment = .center
        view.addSubview(label)
        label.pinEdges(to: view, insets: UIEdgeInsets(top: 80, left: 24, bottom: 24, right: 24))
    }
}
