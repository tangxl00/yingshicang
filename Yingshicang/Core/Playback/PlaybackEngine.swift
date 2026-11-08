//  PlaybackEngine.swift
//  双播放内核路由（架构文档 4.4 / 风险 R-08）。
//
//  设计要点：
//  1. AVPlayer 为主内核，覆盖 HLS(m3u8) 与常规 MP4 —— 这是采集站最常见形态。
//  2. VLCKit 作为兜底：当 AVPlayer 无法识别容器/音轨（典型为 mkv、rmvb、FLV、
//     AC3/DTS 音轨）时切到 VLCKit。build 23 起 VLCKit 4.0 以 **官方 SPM
//     binaryTarget** 集成（`project.yml` 的 `packages.VLCKit`，pin 到 tag
//     `4.0.0-a25`），所以这里用 `canImport(VLCKit)` 做编译期探测；
//     `PlaybackRouter` 把「内核选择」抽成可注入的纯逻辑，测试能塞假探测结果。
//  3. 路由判定不依赖扩展名单一条件：先看容器特征串，再看系统 AVAsset 的
//     `isPlayable` 预判，两者任一失败即触发兜底。
//  4. 设备/构建不支持 VLC 时仍走 AVPlayer 尝试一次，失败后由上层**显式报错**，
//     不假装能播（不静默降级）。

import AVFoundation
import UIKit

#if canImport(VLCKit)
import VLCKit
#endif

enum PlaybackEngineKind: String {
    case avplayer
    case vlc
}

/// 播放内核统一接口：上层只关心 play/pause/seek/rate。
protocol PlaybackEngine: AnyObject {
    var onReady: (() -> Void)? { get set }
    var onProgress: ((Double, Double) -> Void)? { get set }   // (position, duration)
    var onError: ((String) -> Void)? { get set }
    var onEnd: (() -> Void)? { get set }

    var kind: PlaybackEngineKind { get }
    var view: UIView { get }

    func load(url: URL, autoplay: Bool)
    func play()
    func pause()
    func seek(to seconds: Double)
    func setRate(_ rate: Double)
    func stop()
}

/// VLCKit 是否可用（**编译期**决定，不是运行时探测）。
/// 未集成 VLCKit 的构建恒为 false，由 UI 明确提示「当前构建未包含 VLC 内核」。
enum PlaybackCapabilities {
    #if canImport(VLCKit)
    static let vlcAvailable = true
    #else
    static let vlcAvailable = false
    #endif

    /// 兼容旧调用点（设置页开关可用性、播放器兜底提示）。
    static func preferredEngine(for url: URL) -> PlaybackEngineKind {
        PlaybackRouter.live.engine(for: url)
    }
}

// MARK: - F-09 路由决策（纯逻辑，可注入）

/// 路由结论（带原因，便于日志与用例断言）。
struct PlaybackRouteDecision: Equatable {
    let engine: PlaybackEngineKind
    let reason: String
}

/// 播放内核路由器。
///
/// 关键点：`vlcAvailable` 与 `avPlayable` 都是**入参**而不是直接读全局/系统，
/// 这样测试可以塞假探测结果，断言「什么样的容器/音轨会走 VLC 分支」，
/// 不依赖 CI 上是否真的装了 VLCKit。
struct PlaybackRouter {

    /// 编译期可用性 + 系统探测（生产环境用这个）。
    var vlcAvailable: Bool = PlaybackCapabilities.vlcAvailable

    static let live = PlaybackRouter()

    /// 已知 AVPlayer 处理不了（或处理得很差的）容器后缀。
    /// 依据：AVFoundation 原生支持的容器是 mp4/mov/m4v/3gp 与 HLS(m3u8)；
    /// mkv/rmvb/rm/flv/avi/wmv/ts/m2ts 需要第三方内核（VLCKit）。
    static let vlcOnlyContainers: Set<String> = [
        "mkv", "rmvb", "rm", "flv", "avi", "wmv", "ts", "m2ts", "ogv", "webm", "divx", "vob"
    ]

    /// 容器判定（只按后缀，不触碰网络）。
    func engine(forContainerExtension ext: String) -> PlaybackRouteDecision {
        let lower = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if Self.vlcOnlyContainers.contains(lower) {
            return vlcAvailable
                ? PlaybackRouteDecision(engine: .vlc, reason: "容器 .\(lower) 不在 AVFoundation 支持范围，走 VLCKit")
                : PlaybackRouteDecision(engine: .avplayer, reason: "容器 .\(lower) 需 VLCKit，但当前构建未集成，先试 AVPlayer")
        }
        return PlaybackRouteDecision(engine: .avplayer, reason: "容器 .\(lower) 由 AVPlayer 直接支持")
    }

    /// 完整判定：容器后缀 → (可选) AVAsset 可播性实测。
    /// - Parameter avPlayable: `nil` 表示还没做实测（只按容器定），
    ///   `false` 表示 AVAsset 明确说不可播（例如 mp4 封装里只有 DTS/AC3 音轨）→ 触发兜底。
    func engine(for url: URL, avPlayable: Bool? = nil) -> PlaybackEngineKind {
        decision(for: url, avPlayable: avPlayable).engine
    }

    func decision(for url: URL, avPlayable: Bool? = nil) -> PlaybackRouteDecision {
        // m3u8 是 HLS 清单，AVPlayer 的原生强项，永远优先它。
        let ext = url.pathExtension
        if ext.lowercased() == "m3u8" {
            return PlaybackRouteDecision(engine: .avplayer, reason: "HLS 清单由 AVPlayer 直接支持")
        }
        let byContainer = engine(forContainerExtension: ext)
        if byContainer.engine == .vlc { return byContainer }

        guard let avPlayable = avPlayable else { return byContainer }
        if !avPlayable {
            return vlcAvailable
                ? PlaybackRouteDecision(engine: .vlc, reason: "AVAsset 判定不可播（音轨/封装不被支持），回退 VLCKit")
                : PlaybackRouteDecision(engine: .avplayer, reason: "AVAsset 判定不可播，但当前构建未集成 VLCKit")
        }
        return PlaybackRouteDecision(engine: .avplayer, reason: "AVAsset 判定可播")
    }
}

/// AVPlayer 内核。
final class AVPlayerEngine: NSObject, PlaybackEngine {

    let kind: PlaybackEngineKind = .avplayer
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var failedObservation: NSKeyValueObservation?

    var onReady: (() -> Void)?
    var onProgress: ((Double, Double) -> Void)?
    var onError: ((String) -> Void)?
    var onEnd: (() -> Void)?

    var view: UIView { container }

    private let container = UIView()

    override init() {
        super.init()
        container.backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        container.layer.addSublayer(playerLayer)

        // 0.5s 粒度的进度回调：既要给进度条用，也要给「记忆播放位置」用。
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let position = CMTimeGetSeconds(time)
            let duration = CMTimeGetSeconds(self.player.currentItem?.duration ?? .zero)
            guard position.isFinite else { return }
            self.onProgress?(position, duration.isFinite ? duration : 0)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleEnd),
                                              name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    deinit {
        if let token = timeObserver { player.removeTimeObserver(token) }
        NotificationCenter.default.removeObserver(self)
    }

    func load(url: URL, autoplay: Bool) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self = self else { return }
            switch item.status {
            case .readyToPlay:
                self.onReady?()
                if autoplay { self.play() }
            case .failed:
                self.onError?(item.error?.localizedDescription ?? "AVPlayer 无法解码该视频")
            default: break
            }
        }
        failedObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { _, _ in }
    }

    func play() {
        player.play()
        // 倍速必须在 play 之后设置，否则部分 HLS 清单会把速率重置为 1.0
        player.rate = Float(Settings.shared.rate)
    }

    func pause() { player.pause() }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setRate(_ rate: Double) {
        if player.timeControlStatus == .playing { player.rate = Float(rate) }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    @objc private func handleEnd() { onEnd?() }

    // MARK: - R-19 轨道枚举与选择（媒体选择组：音轨 .audible / 内嵌字幕 .legible）
    // 逻辑层在 MediaTrackModels（MediaTrackEnumerator / MediaTrackProbe），这里只做引擎侧执行。

    func mediaSnapshots(kind: MediaTrackKind) -> [MediaTrackSnapshot] {
        guard let item = player.currentItem else { return [] }
        return MediaTrackProbe.snapshots(for: item.asset, kind: kind)
    }

    func selectedTrackIndex(kind: MediaTrackKind) -> Int? {
        guard let item = player.currentItem else { return nil }
        return MediaTrackProbe.selectedIndex(for: item, kind: kind)
    }

    func selectTrack(kind: MediaTrackKind, index: Int) {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: Self.characteristic(for: kind)),
              group.options.indices.contains(index) else { return }
        item.select(group.options[index], in: group)
    }

    func disableTrack(kind: MediaTrackKind) {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: Self.characteristic(for: kind)) else { return }
        item.select(nil, in: group)
    }

    private static func characteristic(for kind: MediaTrackKind) -> AVMediaCharacteristic {
        kind == .audio ? .audible : .legible
    }

    /// PlayerLayer 需要随容器尺寸变化，容器自身不带约束体系统筹，这里手工同步。
    func layout(in bounds: CGRect) {
        playerLayer.frame = bounds
    }
}

// MARK: - F-09 VLCKit 内核

#if canImport(VLCKit)
/// VLCKit 兜底内核（build 23 起的真实实现）。
///
/// 与 `AVPlayerEngine` 的接口完全一致（`PlaybackEngine`），上层不需要分支判断。
/// 契约细节都按 VLCKit 4.0 头文件核对过：
/// - `VLCMediaPlayerDelegate` 全部 `@optional`，只实现需要的四个回调；
/// - `mediaPlayerTimeChanged` 收 `Notification`，时间要从 `player.time.value`（**毫秒**）取；
/// - `mediaPlayerLengthChanged` 给的是毫秒 `int64_t`，`VLCMedia.length` 是 `VLCTime`；
/// - `drawable` 接受任意 `UIView`，所以直接把容器塞进去即可，无需 VLCVideoView。
final class VLCPlayerEngine: NSObject, PlaybackEngine, VLCMediaPlayerDelegate {

    let kind: PlaybackEngineKind = .vlc

    var onReady: (() -> Void)?
    var onProgress: ((Double, Double) -> Void)?
    var onError: ((String) -> Void)?
    var onEnd: (() -> Void)?

    private let player = VLCMediaPlayer()
    private let container = UIView()
    private var durationMs: Int64 = 0
    private var didSignalReady = false
    private var didSignalEnd = false
    private var pendingRate: Double = 1.0
    private var pendingSeek: Double?

    var view: UIView { container }

    override init() {
        super.init()
        container.backgroundColor = .black
        container.clipsToBounds = true
        player.delegate = self
        player.drawable = container
    }

    deinit {
        player.delegate = nil
        player.stop()
    }

    func load(url: URL, autoplay: Bool) {
        didSignalReady = false
        didSignalEnd = false
        durationMs = 0
        guard let media = VLCMedia(url: url) else {
            onError?("VLCKit 无法构造媒体对象：\(url.absoluteString)")
            return
        }
        // 网络流给一点缓冲余量，避免采集站的慢速源一上来就判定失败。
        media.addOption(":network-caching=1500")
        media.addOption(":clock-jitter=0")
        media.addOption(":clock-synchro=0")
        player.media = media
        if autoplay { player.play() }
    }

    func play() { player.play() }

    func pause() { player.pause() }

    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        // 媒体还没到 Playing 时 seek 会被丢弃，先记下来等 ready 后补做。
        if player.state != .playing, !didSignalReady {
            pendingSeek = seconds
            return
        }
        player.time = VLCTime(number: NSNumber(value: seconds * 1000))
    }

    func setRate(_ rate: Double) {
        pendingRate = rate
        // VLC 的 rate 只在播放中生效，暂停态设置会被忽略。
        if player.isPlaying { player.rate = Float(rate) }
    }

    func stop() {
        player.stop()
    }

    // MARK: - VLCMediaPlayerDelegate（全部 @optional）

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        switch newState {
        case .playing:
            if !didSignalReady {
                didSignalReady = true
                onReady?()
            }
            player.rate = Float(pendingRate)
            if let target = pendingSeek {
                pendingSeek = nil
                player.time = VLCTime(number: NSNumber(value: target * 1000))
            }
        case .error:
            onError?("VLCKit 无法解码该视频（容器或音轨不被支持）")
        case .stopped, .stopping:
            // 用户主动 stop 也会到这里；只有「播到结尾」才回 onEnd，
            // 用 position 接近 1 且非 Error 状态做区分，避免暂停被误判成播完。
            if !didSignalEnd, didSignalReady, durationMs > 0, player.position > 0.98 {
                didSignalEnd = true
                onEnd?()
            }
        default:
            break
        }
    }

    func mediaPlayerLengthChanged(_ length: Int64) {
        durationMs = length
        emitProgress()
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        emitProgress()
    }

    private func emitProgress() {
        let positionMs = (player.time.value?.doubleValue) ?? 0
        var duration = Double(durationMs)
        if duration <= 0, let length = player.media?.length.value?.doubleValue, length > 0 {
            duration = length
        }
        // VLCTime 是毫秒，上层契约是秒。
        let position = max(0, positionMs / 1000)
        onProgress?(position, duration > 0 ? duration / 1000 : 0)
    }
}
#else
/// 未集成 VLCKit 的构建（理论上不会出现：`project.yml` 已固定依赖）。
/// 保留同签名的显式失败实现，确保「不假装能播」——宁可报错也不静默降级。
final class VLCPlayerEngine: NSObject, PlaybackEngine {

    let kind: PlaybackEngineKind = .vlc
    var onReady: (() -> Void)?
    var onProgress: ((Double, Double) -> Void)?
    var onError: ((String) -> Void)?
    var onEnd: (() -> Void)?

    private let label = UILabel.make(text: "当前构建未集成 VLC 内核，无法播放该容器的视频",
                                     size: 13, color: .white, lines: 0)
    var view: UIView { container }
    private let container = UIView()

    override init() {
        super.init()
        container.backgroundColor = .black
        label.textAlignment = .center
        container.addSubview(label)
        label.pinEdges(to: container, insets: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24))
    }

    func load(url: URL, autoplay: Bool) { onError?("当前构建未集成 VLC 内核") }
    func play() {}
    func pause() {}
    func seek(to seconds: Double) {}
    func setRate(_ rate: Double) {}
    func stop() {}
}
#endif
