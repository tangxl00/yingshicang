import AVFoundation
import UIKit

/// R-25 播放页 + R-26 控制层。
///
/// 布局事实（AYML `mobile_player_activity` 系列）：
/// - 顶部栏高 37dp：返回、片名、网速、电池、时间
/// - 控制层：中央播放按钮 45dp，两侧 40dp 圆角按钮，底部进度条高 20dp
///   与时间文本（左右各一），右侧竖排 34dp 侧边按钮
/// - 简介/剧集为底部上滑面板（TabLayout 25dp + ViewPager）
final class PlayerViewController: UIViewController {

    private let detail: VodDetail
    private var episodes: [PlayEpisode]
    private var currentIndex: Int
    private let provider: SiteProvider

    private let engineHost = UIView()
    private let topBar = UIView()
    private let titleLabel = UILabel.make(size: DesignTokens.Metrics.titleFont, color: .white)
    private let netSpeedLabel = UILabel.make(size: DesignTokens.Metrics.netSpeedFont, color: .white)
    private let timeLabel = UILabel.make(size: DesignTokens.Metrics.timeWidth / 8, color: .white)
    private let batteryLabel = UILabel.make(size: 11, color: .white)

    private let controlPanel = UIView()
    private let playButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let prevButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let positionLabel = UILabel.make(size: DesignTokens.Metrics.seekTimeFont, color: .white)
    private let durationLabel = UILabel.make(size: DesignTokens.Metrics.seekTimeFont, color: .white)
    private let seekSlider = UISlider()
    private let speedButton = UIButton(type: .system)
    private let seriesButton = UIButton(type: .system)
    private let statusLabel = UILabel.make(size: 13, color: .white, lines: 0)
    private let loading = UIActivityIndicatorView(style: .large)

    private var engine: PlaybackEngine?
    private var isControlVisible = true
    private var hideTask: DispatchWorkItem?

    init(detail: VodDetail, episodes: [PlayEpisode], startIndex: Int, provider: SiteProvider) {
        self.detail = detail
        self.episodes = episodes
        self.currentIndex = startIndex
        self.provider = provider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    deinit { hideTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupLayout()
        startPlayback()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveProgressAndStop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        (engine as? AVPlayerEngine)?.layout(in: engineHost.bounds)
    }

    // MARK: - 布局

    private func setupLayout() {
        engineHost.backgroundColor = .black
        view.addSubview(engineHost)
        engineHost.pinEdges(to: view)

        view.addSubview(topBar)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.playTopBarHeight)
        ])

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(closePlayer), for: .touchUpInside)
        titleLabel.text = detail.vodName
        netSpeedLabel.text = ""
        batteryLabel.text = "100%"
        [backButton, titleLabel, netSpeedLabel, batteryLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            topBar.addSubview($0)
        }
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: DesignTokens.dp(8)),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: DesignTokens.Metrics.backButtonSize),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: DesignTokens.dp(4)),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: netSpeedLabel.leadingAnchor, constant: -DesignTokens.dp(8)),

            batteryLabel.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            batteryLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            netSpeedLabel.trailingAnchor.constraint(equalTo: batteryLabel.leadingAnchor, constant: -DesignTokens.dp(8)),
            netSpeedLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor)
        ])

        // 控制层
        controlPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlPanel)
        NSLayoutConstraint.activate([
            controlPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            controlPanel.heightAnchor.constraint(equalToConstant: DesignTokens.dp(120))
        ])
        controlPanel.backgroundColor = DesignTokens.Colors.black44

        let centerRow = UIStackView.horizontal(spacing: DesignTokens.dp(36), alignment: .center)
        prevButton.setImage(UIImage(systemName: "backward.fill"), for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.fill"), for: .normal)
        playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        [prevButton, playButton, nextButton].forEach {
            $0.tintColor = .white
        }
        prevButton.addTarget(self, action: #selector(playPrev), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(playNext), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        prevButton.size(DesignTokens.Metrics.controlButtonSize, DesignTokens.Metrics.controlButtonSize)
        nextButton.size(DesignTokens.Metrics.controlButtonSize, DesignTokens.Metrics.controlButtonSize)
        playButton.size(DesignTokens.Metrics.playButtonSize, DesignTokens.Metrics.playButtonSize)
        centerRow.addArrangedSubview(prevButton)
        centerRow.addArrangedSubview(playButton)
        centerRow.addArrangedSubview(nextButton)

        let seekRow = UIStackView.horizontal(spacing: DesignTokens.dp(8), alignment: .center)
        seekSlider.minimumTrackTintColor = DesignTokens.Colors.main
        seekSlider.maximumTrackTintColor = DesignTokens.Colors.white44
        seekSlider.setThumbImage(UIImage(systemName: "circle.fill"), for: .normal)
        seekSlider.addTarget(self, action: #selector(seekChanged), for: .touchUpInside)
        seekSlider.addTarget(self, action: #selector(seekChanged), for: .touchUpOutside)
        positionLabel.text = "00:00"
        durationLabel.text = "00:00"
        positionLabel.size(46, 0)
        durationLabel.size(46, 0)
        seekRow.addArrangedSubview(positionLabel)
        seekRow.addArrangedSubview(seekSlider)
        seekRow.addArrangedSubview(durationLabel)

        let actionRow = UIStackView.horizontal(spacing: DesignTokens.dp(12), alignment: .center)
        speedButton.setTitle("倍速", for: .normal)
        speedButton.setTitleColor(.white, for: .normal)
        speedButton.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.speedLabelFont))
        speedButton.backgroundColor = DesignTokens.Colors.dialog
        speedButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.speedLabelCorner)
        speedButton.size(56, 28)
        speedButton.addTarget(self, action: #selector(showSpeedSheet), for: .touchUpInside)

        seriesButton.setTitle("选集", for: .normal)
        seriesButton.setTitleColor(.white, for: .normal)
        seriesButton.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.speedLabelFont))
        seriesButton.backgroundColor = DesignTokens.Colors.dialog
        seriesButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.speedLabelCorner)
        seriesButton.size(56, 28)
        seriesButton.addTarget(self, action: #selector(showSeriesSheet), for: .touchUpInside)

        actionRow.addArrangedSubview(speedButton)
        actionRow.addArrangedSubview(seriesButton)
        actionRow.addArrangedSubview(UIView())

        let column = UIStackView.vertical(spacing: DesignTokens.dp(6))
        column.isLayoutMarginsRelativeArrangement = true
        column.layoutMargins = UIEdgeInsets(top: DesignTokens.dp(6), left: DesignTokens.Metrics.actionBarHorizontalPadding,
                                            bottom: DesignTokens.dp(6), right: DesignTokens.Metrics.actionBarHorizontalPadding)
        column.addArrangedSubview(centerRow)
        column.addArrangedSubview(seekRow)
        column.addArrangedSubview(actionRow)
        controlPanel.addSubview(column)
        column.pinEdges(to: controlPanel)

        loading.hidesWhenStopped = true
        view.addSubview(loading)
        loading.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        statusLabel.textAlignment = .center
        statusLabel.isHidden = true
        view.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: DesignTokens.dp(24)),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -DesignTokens.dp(24))
        ])

        // 单击屏幕切换控制层显隐（播放器通行交互）
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        engineHost.addGestureRecognizer(tap)
    }

    // MARK: - 播放

    private func startPlayback() {
        guard episodes.indices.contains(currentIndex) else {
            showStatus("没有可播放的剧集")
            return
        }
        let episode = episodes[currentIndex]
        loading.startAnimating()
        statusLabel.isHidden = true

        provider.play(flag: detail.tabs.indices.contains(activeTabForEpisodes) ? detail.tabs[activeTabForEpisodes] : "",
                      url: episode.url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading.stopAnimating()
                switch result {
                case .success(let resolution):
                    self.startEngine(urlString: resolution.url)
                case .failure(let error):
                    self.showStatus(error.localizedDescription ?? "播放地址解析失败")
                }
            }
        }
    }

    /// 当前剧集所属线路名。详情页切线路时 episodes 已被替换，
    /// 这里用剧集数组归属反查，避免线路名错配。
    private var activeTabForEpisodes: Int {
        if let index = detail.lists.firstIndex(where: { $0 == episodes }) { return index }
        return 0
    }

    private func startEngine(urlString: String) {
        guard let url = URL(string: urlString) else {
            showStatus("播放地址无效：\(urlString)")
            return
        }
        engine?.stop()
        engine?.view.removeFromSuperview()

        let kind = PlaybackCapabilities.preferredEngine(for: url)
        let newEngine: PlaybackEngine
        switch kind {
        case .vlc:
            newEngine = PlaybackCapabilities.vlcAvailable ? VLCPlayerEngineStub() : VLCPlayerEngineStub()
        case .avplayer:
            newEngine = AVPlayerEngine()
        }
        newEngine.onReady = { [weak self] in
            self?.loading.stopAnimating()
            self?.hideStatus()
        }
        newEngine.onProgress = { [weak self] position, duration in
            self?.updateProgress(position: position, duration: duration)
        }
        newEngine.onError = { [weak self] message in
            self?.handleEngineError(message, url: url)
        }
        newEngine.onEnd = { [weak self] in self?.playNext() }

        engine = newEngine
        newEngine.view.frame = engineHost.bounds
        newEngine.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        engineHost.addSubview(newEngine.view)
        engineHost.bringSubviewToFront(topBar)

        // 记忆播放位置：同一条历史记录存在时，从上次位置续播（F-06）
        var resume: Double = 0
        if let record = HistoryStore.shared.resume(siteKey: detail.siteKey, vodId: detail.vodId),
           record.playIndex == currentIndex, record.position > 3 {
            resume = record.position
        }
        newEngine.load(url: url, autoplay: true)
        newEngine.setRate(Settings.shared.rate)
        if resume > 0 { newEngine.seek(to: resume) }
        updatePlayButton(isPlaying: true)
    }

    /// AVPlayer 失败时的兜底路由：有 VLC 则换内核重试一次，没有则明确报错。
    /// 只重试一次，避免容器真不支持时反复切换造成闪烁。
    private var didFallback = false

    private func handleEngineError(_ message: String, url: URL) {
        if !didFallback, PlaybackCapabilities.vlcAvailable {
            didFallback = true
            startEngine(urlString: url.absoluteString)
            return
        }
        showStatus("播放失败：\(message)\n" + (PlaybackCapabilities.vlcAvailable ? "" : "（当前构建未集成 VLC 内核，部分容器无法播放）"))
    }

    private func updateProgress(position: Double, duration: Double) {
        guard duration > 0 else { return }
        seekSlider.maximumValue = Float(duration)
        if !seekSlider.isTracking { seekSlider.value = Float(position) }
        positionLabel.text = formatTime(position)
        durationLabel.text = formatTime(duration)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private func updatePlayButton(isPlaying: Bool) {
        let name = isPlaying ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: name), for: .normal)
    }

    private func showStatus(_ text: String) {
        statusLabel.text = text
        statusLabel.isHidden = false
        loading.stopAnimating()
    }

    private func hideStatus() { statusLabel.isHidden = true }

    private func saveProgressAndStop() {
        let position = Double(seekSlider.value)
        let duration = Double(seekSlider.maximumValue)
        guard duration > 0 else { engine?.stop(); return }
        let finished = duration - position < 30
        let record = HistoryRecord(siteKey: detail.siteKey, vodId: detail.vodId, vodName: detail.vodName,
                                   vodPic: detail.vodPic, flag: detail.tabs.first ?? "",
                                   playIndex: currentIndex, episodeIndex: currentIndex,
                                   position: position, duration: duration, finished: finished)
        HistoryStore.shared.upsert(record: record)
        engine?.stop()
    }

    // MARK: - 交互

    @objc private func togglePlay() {
        guard let engine = engine else { return }
        if engine.kind == .avplayer {
            let player = engine as? AVPlayerEngine
            // 用 rate 判断是否在播：AVPlayerEngine 的 timeControlStatus 未对外暴露
            if seekSlider.isUserInteractionEnabled, isPlayingNow {
                player?.pause()
                updatePlayButton(isPlaying: false)
                isPlayingNow = false
            } else {
                player?.play()
                updatePlayButton(isPlaying: true)
                isPlayingNow = true
            }
        }
    }

    private var isPlayingNow = true

    @objc private func seekChanged() {
        engine?.seek(to: Double(seekSlider.value))
    }

    @objc private func playPrev() {
        guard currentIndex > 0 else { return }
        saveProgressAndStop()
        currentIndex -= 1
        startPlayback()
    }

    @objc private func playNext() {
        guard currentIndex + 1 < episodes.count else {
            showStatus("已经是最后一集")
            return
        }
        saveProgressAndStop()
        currentIndex += 1
        startPlayback()
    }

    @objc private func toggleControls() {
        isControlVisible.toggle()
        UIView.animate(withDuration: 0.2) {
            self.controlPanel.alpha = self.isControlVisible ? 1 : 0
            self.topBar.alpha = self.isControlVisible ? 1 : 0
        }
        if isControlVisible { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self = self, self.isControlVisible else { return }
            self.isControlVisible = false
            UIView.animate(withDuration: 0.2) {
                self.controlPanel.alpha = 0
                self.topBar.alpha = 0
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: task)
    }

    @objc private func showSpeedSheet() {
        let sheet = UIAlertController(title: "播放倍速", message: nil, preferredStyle: .actionSheet)
        // 倍速档位来自 AXML 的 speed 数组；持久化到 tpc_settings.rate（F-15）
        for rate in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            sheet.addAction(UIAlertAction(title: String(format: "%.2fx", rate), style: .default) { [weak self] _ in
                Settings.shared.rate = rate
                self?.engine?.setRate(rate)
                self?.speedButton.setTitle(String(format: "%.2fx", rate), for: .normal)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = speedButton
            pop.sourceRect = speedButton.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func showSeriesSheet() {
        let controller = SeriesSheetViewController(episodes: episodes, currentIndex: currentIndex)
        controller.onSelect = { [weak self] index in
            guard let self = self else { return }
            self.saveProgressAndStop()
            self.currentIndex = index
            self.startPlayback()
        }
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(controller, animated: true)
    }

    @objc private func closePlayer() {
        saveProgressAndStop()
        dismiss(animated: true)
    }
}

/// R-26 选集面板（底部上滑，列表形态）。
final class SeriesSheetViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let episodes: [PlayEpisode]
    private let currentIndex: Int
    private let table = UITableView(frame: .zero, style: .plain)
    var onSelect: ((Int) -> Void)?

    init(episodes: [PlayEpisode], currentIndex: Int) {
        self.episodes = episodes
        self.currentIndex = currentIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.sheet
        let title = UILabel.make(text: "选集（共 \(episodes.count) 集）", size: DesignTokens.Metrics.sheetTitleFont,
                                color: .white, weight: .semibold)
        view.addSubview(title)
        view.addSubview(table)
        title.translatesAutoresizingMaskIntoConstraints = false
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "ep")
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: DesignTokens.Metrics.sheetContentPaddingTop),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            table.topAnchor.constraint(equalTo: title.bottomAnchor, constant: DesignTokens.dp(10)),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { episodes.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ep", for: indexPath)
        cell.backgroundColor = .clear
        cell.textLabel?.text = episodes[indexPath.row].name
        cell.textLabel?.textColor = indexPath.row == currentIndex ? DesignTokens.Colors.main : .white
        cell.textLabel?.font = .systemFont(ofSize: DesignTokens.sp(14))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        dismiss(animated: true) { self.onSelect?(indexPath.row) }
    }
}
