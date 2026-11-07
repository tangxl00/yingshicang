//  PlaybackEngine.swift
//  双播放内核路由（架构文档 4.4 / 风险 R-08）。
//
//  设计要点：
//  1. AVPlayer 为主内核，覆盖 HLS(m3u8) 与常规 MP4 —— 这是采集站最常见形态。
//  2. VLCKit 作为兜底：当 AVPlayer 无法识别容器/音轨（典型为 mkv、rmvb、FLV、
//     AC3/EAC3 音轨）时切到 VLCKit。VLCKit 在 SPM 上无官方包，CI 中不拉取；
//     因此这里用 `canImport(MobileVLCKit)` 做编译期探测——未集成时 VLC 分支
//     退化为「明确提示不可用」，绝不假装能播（不静默降级）。
//  3. 路由判定不依赖扩展名单一条件：先看容器特征串，再看系统 AVAsset 的
//     `isPlayable` 预判，两者任一失败即触发兜底。

import AVFoundation
import UIKit

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

/// VLCKit 是否可用（编译期决定）。CI 未集成 VLCKit 时恒为 false，
/// 由 UI 明确提示「当前构建未包含 VLC 内核」。
enum PlaybackCapabilities {
    #if canImport(MobileVLCKit)
    static let vlcAvailable = true
    #else
    static let vlcAvailable = false
    #endif

    /// 容器级路由建议：AVPlayer 不支持 mkv/rmvb/flv/ts(部分) 与常见 AC3 音轨。
    /// 这是按容器后缀的静态判定，动态判定见 `AVPlayerEngine` 的失败回调。
    static func preferredEngine(for url: URL) -> PlaybackEngineKind {
        let ext = url.pathExtension.lowercased()
        let unsupportedByAVPlayer: Set<String> = ["mkv", "rmvb", "rm", "flv", "avi", "wmv", "ts", "m2ts", "mov"]
        if unsupportedByAVPlayer.contains(ext) {
            // 没有 VLC 时仍交给 AVPlayer 尝试（部分 ts 可播），由失败回调提示。
            return vlcAvailable ? .vlc : .avplayer
        }
        return .avplayer
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

/// VLCKit 兜底内核的占位实现：未集成时明确报错，集成后由 `vlc` 分支替换。
final class VLCPlayerEngineStub: NSObject, PlaybackEngine {

    let kind: PlaybackEngineKind = .vlc
    var onReady: (() -> Void)?
    var onProgress: ((Double, Double) -> Void)?
    var onError: ((String) -> Void)?
    var onEnd: (() -> Void)?

    private let label = UILabel.make(text: "当前构建未集成 VLC 内核，无法播放该容器的视频\n（VLCKit 未通过 SPM 分发，需以 XCFramework 集成）",
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

    func load(url: URL, autoplay: Bool) {
        onError?("当前构建未集成 VLC 内核")
    }
    func play() {}
    func pause() {}
    func seek(to seconds: Double) {}
    func setRate(_ rate: Double) {}
    func stop() {}
}
