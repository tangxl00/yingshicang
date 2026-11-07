//  PlayerGestureController.swift
//  R-12 播放手势 + F-10 手势与锁屏的视图层。
//
//  判定逻辑全部走 `PlayerGestureLogic`（纯函数，单测覆盖）；本文件只负责：
//  1. 装手势（竖滑 pan、单击已由播放页自己装，这里不重复）
//  2. 执行真实副作用（`UIScreen.brightness` / 系统音量滑块）
//  3. 显示 HUD（「亮度 45%」）
//  4. 锁屏按钮与迷你进度的显隐
//
//  为什么音量要经 `MPVolumeView`：iOS 没有公开的「设置系统音量」API，
//  唯一可行路径是取出 `MPVolumeView` 内部的 `UISlider` 改 value（业界通行做法）。
//  取不到滑块时（系统版本变动）不做静默失败——HUD 仍展示目标值，
//  同时在 `volumeAdjustable` 上报 false，播放页据此提示用户用实体音量键。

import AVFoundation
import MediaPlayer
import UIKit

/// 播放页的手势/锁屏/迷你进度视图层。
final class PlayerGestureController: NSObject {

    /// 当前手势状态（锁屏、迷你进度开关）。
    private(set) var interaction: PlayerInteractionState

    /// 手势落点所在容器：即播放画面层。
    private weak var host: UIView?
    /// HUD 容器（由播放页提供，保证盖在画面上、控制层之下）。
    private weak var hudHost: UIView?

    /// 当前进度（0…1），由播放页在 onProgress 时回填，供迷你进度条绘制。
    var progress: Double = 0 {
        didSet { miniProgress?.value = progress }
    }

    /// 音量是否真的可以程序化调节（容量判断失败时为 false）。
    private(set) var volumeAdjustable = false

    private var startBrightness: CGFloat = 0
    private var startVolume: Float = 0
    private var activeZone: PlayerGestureZone = .neutral
    private var hud: UILabel?
    private var miniProgress: MiniProgressBar?
    private var lockButton: UIButton?
    private var unlockHint: UILabel?

    private var volumeSlider: UISlider? {
        // MPVolumeView 的滑块在层级里，未布局时可能取不到；每次取最新。
        guard let view = volumeView else { return nil }
        return Self.findSlider(in: view)
    }

    private lazy var volumeView: MPVolumeView? = {
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 100, height: 40))
        view.showsRouteButton = false
        hudHost?.addSubview(view)
        return view
    }()

    /// 回调：锁屏态变化（播放页据此隐藏/恢复控制层）。
    var onLockChanged: (() -> Void)?

    init(interaction: PlayerInteractionState) {
        self.interaction = interaction
        super.init()
    }

    // MARK: - 装/卸

    func attach(to host: UIView, hudHost: UIView) {
        self.host = host
        self.hudHost = hudHost

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        host.addGestureRecognizer(pan)

        volumeAdjustable = volumeSlider != nil
        buildLockButton(in: hudHost)
        buildMiniProgress(in: hudHost)
    }

    // MARK: - 竖滑：亮度 / 音量

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let host = host else { return }
        let location = gesture.location(in: host)

        switch gesture.state {
        case .began:
            activeZone = PlayerGestureMath.zone(for: location, in: host.bounds.size)
            startBrightness = UIScreen.main.brightness
            startVolume = volumeSlider?.value ?? 0
            // MPVolumeView 的滑块在未完成布局时可能取不到，每次手势开始时重判
            volumeAdjustable = volumeSlider != nil
            // 锁屏态下不调整亮度/音量，也不显示 HUD。
            guard interaction.allowsGestureAdjust else { activeZone = .neutral; return }
            if activeZone == .neutral { return }
            showHUD(zone: activeZone, value: currentValue(for: activeZone))
        case .changed:
            guard interaction.allowsGestureAdjust, activeZone != .neutral else { return }
            let travel = host.bounds.height * 0.6
            guard PlayerGestureMath.isMeaningful(translationY: gesture.translation(in: host).y) else { return }
            let start = activeZone == .brightness ? Double(startBrightness) : Double(startVolume)
            let value = PlayerGestureMath.mappedValue(start: start,
                                                     translationY: gesture.translation(in: host).y,
                                                     fullTravelHeight: travel)
            apply(value: value, to: activeZone)
            showHUD(zone: activeZone, value: value)
        case .ended, .cancelled, .failed:
            activeZone = .neutral
            hideHUDAfterDelay()
        default:
            break
        }
    }

    private func currentValue(for zone: PlayerGestureZone) -> Double {
        switch zone {
        case .brightness: return Double(UIScreen.main.brightness)
        case .volume: return Double(volumeSlider?.value ?? 0)
        case .neutral: return 0
        }
    }

    private func apply(value: Double, to zone: PlayerGestureZone) {
        switch zone {
        case .brightness:
            UIScreen.main.brightness = CGFloat(PlayerGestureMath.clamp(value))
        case .volume:
            // 取不到滑块时只更新 HUD，不假装已生效（volumeAdjustable 会告诉播放页）。
            volumeSlider?.value = Float(PlayerGestureMath.clamp(value))
        case .neutral:
            break
        }
    }

    // MARK: - HUD

    private func showHUD(zone: PlayerGestureZone, value: Double) {
        guard let hudHost = hudHost else { return }
        if hud == nil {
            let label = UILabel.make(size: DesignTokens.Metrics.miniProgressFont, color: .white, weight: .medium)
            label.textAlignment = .center
            label.backgroundColor = DesignTokens.Colors.black60
            label.layer.cornerRadius = DesignTokens.Corner.sm
            label.layer.masksToBounds = true
            hudHost.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: hudHost.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: hudHost.centerYAnchor),
                label.widthAnchor.constraint(equalToConstant: DesignTokens.dp(120)),
                label.heightAnchor.constraint(equalToConstant: DesignTokens.dp(40))
            ])
            hud = label
        }
        hud?.isHidden = false
        var text = "\(zone.title) \(PlayerGestureMath.percentText(value))"
        if zone == .volume && !volumeAdjustable { text += "\n请用实体音量键" }
        hud?.text = text
        hud?.numberOfLines = 0
    }

    private func hideHUDAfterDelay() {
        guard let hud = hud else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            hud.isHidden = true
        }
    }

    // MARK: - 锁屏

    private func buildLockButton(in host: UIView) {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "lock.open.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = DesignTokens.Colors.black60
        button.layer.cornerRadius = DesignTokens.Metrics.sideButtonCorner
        button.addTarget(self, action: #selector(toggleLock), for: .touchUpInside)
        host.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            button.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: DesignTokens.Metrics.sideButtonSize),
            button.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.sideButtonSize)
        ])
        button.isHidden = true
        lockButton = button

        let hint = UILabel.make(text: "屏幕已锁定，点击锁图标解锁", size: 12,
                                color: DesignTokens.Colors.text, lines: 0)
        hint.textAlignment = .center
        hint.isHidden = true
        host.addSubview(hint)
        hint.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -DesignTokens.dp(24)),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: DesignTokens.dp(24))
        ])
        unlockHint = hint
    }

    /// 锁屏态下点击画面：唤出解锁按钮（不显示完整控制层，避免误触）。
    func revealUnlockIfLocked() -> Bool {
        guard interaction.isLocked else { return false }
        lockButton?.isHidden = false
        unlockHint?.isHidden = false
        scheduleHideUnlock()
        return true
    }

    private func scheduleHideUnlock() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, self.interaction.isLocked else { return }
            self.lockButton?.isHidden = true
            self.unlockHint?.isHidden = true
        }
    }

    @objc private func toggleLock() {
        interaction.isLocked.toggle()
        let icon = interaction.isLocked ? "lock.fill" : "lock.open.fill"
        lockButton?.setImage(UIImage(systemName: icon), for: .normal)
        lockButton?.isHidden = interaction.isLocked
        unlockHint?.isHidden = true
        onLockChanged?()
    }

    /// 由播放页调用：控制层的锁按钮被点击时进入锁屏。
    func lock() {
        guard !interaction.isLocked else { return }
        toggleLock()
    }

    // MARK: - 迷你进度

    private func buildMiniProgress(in host: UIView) {
        let bar = MiniProgressBar()
        bar.backgroundColor = .clear
        host.addSubview(bar)
        bar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: DesignTokens.dp(2))
        ])
        bar.isHidden = true
        miniProgress = bar
    }

    /// 控制层可见性变化时刷新迷你进度显隐（两者互斥）。
    func updateMiniProgressVisibility(controlsVisible: Bool) {
        miniProgress?.isHidden = !interaction.shouldShowMiniProgress(controlsVisible: controlsVisible)
    }

    // MARK: - 工具

    static func findSlider(in view: UIView) -> UISlider? {
        for sub in view.subviews {
            if let slider = sub as? UISlider { return slider }
            if let nested = findSlider(in: sub) { return nested }
        }
        return nil
    }
}

extension PlayerGestureController: UIGestureRecognizerDelegate {
    /// 竖滑与播放页单击、边缘返回手势并行；不吞控件事件。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// 迷你进度条：仅 2pt 高，控制层隐藏时显示当前播放位置。
final class MiniProgressBar: UIView {
    private let track = UIView()
    private let fill = UIView()

    /// 0…1
    var value: Double = 0 {
        didSet {
            let clamped = PlayerGestureMath.clamp(value)
            fillWidth?.constant = bounds.width * CGFloat(clamped)
            setNeedsLayout()
        }
    }

    private var fillWidth: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.backgroundColor = DesignTokens.Colors.white94
        fill.backgroundColor = DesignTokens.Colors.main
        addSubview(track)
        addSubview(fill)
        track.translatesAutoresizingMaskIntoConstraints = false
        fill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.topAnchor.constraint(equalTo: topAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
            fill.leadingAnchor.constraint(equalTo: leadingAnchor),
            fill.topAnchor.constraint(equalTo: topAnchor),
            fill.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        let width = fill.widthAnchor.constraint(equalToConstant: 0)
        width.isActive = true
        fillWidth = width
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
