import UIKit

/// R-27 直播页（`mobile_live_activity`）。
///
/// 布局事实：`paddingTop=37dp`，左侧频道列表（宽 100dp 量级、项高 48dp），
/// 右侧播放区；顶部有「设置」入口（liveSettingWidth/Height）。直播源来自
/// 配置的 `lives` 数组（name + url，url 为包含多个 `频道名$地址` 的文本）。
final class LiveViewController: UIViewController {

    private let channelTable = UITableView(frame: .zero, style: .plain)
    private let playerHost = UIView()
    private let statusLabel = UILabel.make(size: 13, color: DesignTokens.Colors.text, lines: 0)
    private let titleLabel = UILabel.make(size: DesignTokens.Metrics.liveChannelFont,
                                         color: .white, weight: .semibold)
    private let settingButton = UIButton(type: .system)

    private var channels: [LiveChannel] = []
    private var currentChannel: LiveChannel?
    private var engine: AVPlayerEngine?

    struct LiveChannel {
        var name: String
        var url: String
        var sourceName: String
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        setupLayout()
        loadChannels()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        engine?.stop()
    }

    private func setupLayout() {
        titleLabel.text = "直播"
        settingButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        settingButton.tintColor = .white
        settingButton.addTarget(self, action: #selector(openLiveSettings), for: .touchUpInside)

        [titleLabel, settingButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                            constant: DesignTokens.Metrics.livePaddingTop),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                               constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            settingButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            settingButton.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                                   constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            settingButton.widthAnchor.constraint(equalToConstant: 28),
            settingButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        playerHost.backgroundColor = .black
        playerHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerHost)
        NSLayoutConstraint.activate([
            playerHost.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DesignTokens.dp(10)),
            playerHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerHost.heightAnchor.constraint(equalTo: playerHost.widthAnchor, multiplier: 9.0 / 16.0)
        ])

        channelTable.backgroundColor = .clear
        channelTable.separatorStyle = .none
        channelTable.dataSource = self
        channelTable.delegate = self
        channelTable.register(UITableViewCell.self, forCellReuseIdentifier: "ch")
        channelTable.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(channelTable)
        NSLayoutConstraint.activate([
            channelTable.topAnchor.constraint(equalTo: playerHost.bottomAnchor, constant: DesignTokens.dp(8)),
            channelTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            channelTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            channelTable.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        playerHost.addSubview(statusLabel)
        statusLabel.pinEdges(to: playerHost, insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
    }

    // MARK: - 数据

    private func loadChannels() {
        let sources = ConfigRepository.shared.currentBundle.lives
        guard !sources.isEmpty else {
            statusLabel.text = "当前配置未包含直播源\n可在「我的 → 配置地址」更换含 lives 的配置"
            return
        }
        var collected: [LiveChannel] = []
        let group = DispatchGroup()
        let lock = NSLock()

        for source in sources {
            group.enter()
            HTTPClient.shared.request(source.url) { response in
                defer { group.leave() }
                guard response.ok, !response.content.isEmpty else { return }
                let parsed = LiveParser.parse(text: response.content, sourceName: source.name)
                lock.lock()
                collected.append(contentsOf: parsed)
                lock.unlock()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.channels = collected
            self.channelTable.reloadData()
            if collected.isEmpty {
                self.statusLabel.text = "直播源为空（源地址不可用或格式不符）"
            } else {
                self.statusLabel.text = "请在下方选择频道"
                // 上次观看的频道（F-17 记忆上次频道）
                let last = Settings.shared.lastLiveChannel
                if let index = collected.firstIndex(where: { $0.name == last }) {
                    self.play(index: index)
                }
            }
        }
    }

    private func play(index: Int) {
        guard channels.indices.contains(index) else { return }
        let channel = channels[index]
        currentChannel = channel
        Settings.shared.lastLiveChannel = channel.name
        statusLabel.text = "正在打开 \(channel.name)…"
        engine?.stop()
        engine?.view.removeFromSuperview()

        guard let url = URL(string: channel.url) else {
            statusLabel.text = "频道地址无效：\(channel.url)"
            return
        }
        let player = AVPlayerEngine()
        player.onReady = { [weak self] in self?.statusLabel.text = "" }
        player.onError = { [weak self] message in
            self?.statusLabel.text = "播放失败：\(message)"
        }
        engine = player
        player.view.frame = playerHost.bounds
        player.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerHost.addSubview(player.view)
        playerHost.bringSubviewToFront(statusLabel)
        player.load(url: url, autoplay: true)
        titleLabel.text = channel.name
        channelTable.reloadData()
    }

    @objc private func openLiveSettings() {
        let sheet = UIAlertController(title: "直播设置", message: "超时时间（秒）", preferredStyle: .alert)
        sheet.addTextField { field in
            field.keyboardType = .numberPad
            field.text = "\(Settings.shared.liveTimeout)"
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            if let text = sheet.textFields?.first?.text, let value = Int(text) {
                Settings.shared.liveTimeout = value
            }
        })
        present(sheet, animated: true)
    }
}

extension LiveViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { channels.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ch", for: indexPath)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        let channel = channels[indexPath.row]
        let selected = channel.name == currentChannel?.name
        cell.textLabel?.text = "\(channel.name)   \(channel.sourceName)"
        cell.textLabel?.textColor = selected ? DesignTokens.Colors.main : .white
        cell.textLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.liveChannelFont))
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        DesignTokens.dp(48)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        play(index: indexPath.row)
    }
}

/// 直播源解析：配置里的 live url 指向的文本，每行 `频道名$地址`（TVBox 既有格式）。
enum LiveParser {
    static func parse(text: String, sourceName: String) -> [LiveViewController.LiveChannel] {
        var result: [LiveViewController.LiveChannel] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains("$"),
                  !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { continue }
            let parts = trimmed.components(separatedBy: "$")
            guard parts.count >= 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            // 形如 `频道名$线路1$线路2` 时取第一条线路
            let url = parts[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, url.hasPrefix("http") else { continue }
            result.append(LiveViewController.LiveChannel(name: name, url: url, sourceName: sourceName))
        }
        return result
    }
}
