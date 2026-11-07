//  MediaTrackModels.swift
//  R-19 字幕/音轨选择弹层的模型与枚举（F-12 画质与音轨、字幕）。
//
//  设计要点：
//  1. 枚举逻辑拆成两层：`MediaTrackEnumerator` 是**纯函数**，输入是轨道快照，
//     与 AVFoundation 完全解耦，单测不需要真实视频文件即可覆盖「枚举 / 默认项 /
//     序号映射 / 选中态」四类行为。
//  2. `MediaTrackProbe` 负责把 `AVMediaSelectionGroup` / `AVAssetTrack` 映射成快照，
//     是唯一触碰 AVFoundation 的地方。AVPlayer 内核对内部/字幕轨的支持依赖
//     media selection group（音轨 authoritative，字幕走 legible 特性）。
//  3. 外挂字幕（.srt/.ass 文件）不在本层做转换：AVPlayer 无公开的外挂字幕挂载 API，
//     该能力随 VLC 内核集成提供（见 VLCKitIntegration.swift 与 IMPLEMENTATION_STATUS F-12）。

import AVFoundation
import Foundation

enum MediaTrackKind: String, Codable, Equatable {
    case audio
    case subtitle

    var title: String {
        switch self {
        case .audio: return "音轨"
        case .subtitle: return "字幕"
        }
    }
}

/// 一条可选项。`index` 是该类轨道在组内的序号，用于「选中态」回填与跨重启的稳定标识。
struct MediaTrackOption: Codable, Equatable, Identifiable {
    var index: Int
    var kind: MediaTrackKind
    var displayName: String
    var languageCode: String
    var isDefault: Bool

    var id: String { "\(kind.rawValue)-\(index)" }

    /// 列表展示文案：优先本地化名，其次语言码，最后兜底「音轨 N / 字幕 N」。
    var listTitle: String {
        if !displayName.isEmpty { return displayName }
        if !languageCode.isEmpty { return languageCode }
        return "\(kind.title) \(index + 1)"
    }
}

/// 与 AVFoundation 解耦的轨道快照。
struct MediaTrackSnapshot: Equatable {
    var displayName: String
    var languageCode: String
    var isDefault: Bool

    init(displayName: String = "", languageCode: String = "", isDefault: Bool = false) {
        self.displayName = displayName
        self.languageCode = languageCode
        self.isDefault = isDefault
    }
}

/// 纯枚举逻辑（可单测）。
enum MediaTrackEnumerator {

    /// 由快照列表构造选项列表。默认项最多一条：第一个 `isDefault` 为真者；
    /// 若没有任何默认标记，则第 0 项视为默认（与 AVFoundation 的 defaultOption 语义对齐）。
    static func options(for snapshots: [MediaTrackSnapshot], kind: MediaTrackKind) -> [MediaTrackOption] {
        guard !snapshots.isEmpty else { return [] }
        let hasExplicitDefault = snapshots.contains { $0.isDefault }
        return snapshots.enumerated().map { offset, snapshot in
            let isDefault = hasExplicitDefault ? snapshot.isDefault : (offset == 0)
            return MediaTrackOption(index: offset,
                                    kind: kind,
                                    displayName: snapshot.displayName,
                                    languageCode: snapshot.languageCode,
                                    isDefault: isDefault)
        }
    }

    /// 当前应高亮的序号：显式选中优先，其次默认项，最后第 0 项。
    /// 返回 nil 表示该类轨道为空（UI 应展示「无可用轨道」而不是空弹层）。
    static func highlightedIndex(in options: [MediaTrackOption], selectedIndex: Int?) -> Int? {
        guard !options.isEmpty else { return nil }
        if let selected = selectedIndex {
            // 越界选中属于异常状态：不得崩、也不得误高亮（与「无选中」的默认项兜底区分开）。
            return options.indices.contains(selected) ? selected : nil
        }
        if let fallback = options.first(where: { $0.isDefault }) { return fallback.index }
        return options.first?.index
    }

    /// 「关闭字幕」是字幕弹层里的合法选项，音轨弹层没有这一项。
    static func allowsOffOption(for kind: MediaTrackKind) -> Bool {
        kind == .subtitle
    }
}

/// AVFoundation 探针：把真实资产映射成快照。
enum MediaTrackProbe {

    /// 音轨。优先用 media selection group（支持 AVAudioMix 切换），
    /// 组不存在时回退到 `asset.tracks(withMediaType: .audio)`（部分封装没有 group）。
    static func audioSnapshots(for asset: AVAsset) -> [MediaTrackSnapshot] {
        if let group = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            return group.options.map { option in
                MediaTrackSnapshot(displayName: option.displayName,
                                   languageCode: option.extendedLanguageTag ?? option.locale?.languageCode ?? "",
                                   isDefault: group.defaultOption == option)
            }
        }
        return asset.tracks(withMediaType: .audio).map { track in
            MediaTrackSnapshot(displayName: track.trackID > 0 ? "音轨 \(track.trackID)" : "",
                               languageCode: track.languageCode ?? "",
                               isDefault: false)
        }
    }

    /// 字幕。只认 legible 特性组（内嵌字幕）；外挂字幕不在 AVPlayer 公开能力范围内。
    static func subtitleSnapshots(for asset: AVAsset) -> [MediaTrackSnapshot] {
        guard let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return [] }
        return group.options.map { option in
            MediaTrackSnapshot(displayName: option.displayName,
                               languageCode: option.extendedLanguageTag ?? option.locale?.languageCode ?? "",
                               isDefault: group.defaultOption == option)
        }
    }

    static func snapshots(for asset: AVAsset, kind: MediaTrackKind) -> [MediaTrackSnapshot] {
        switch kind {
        case .audio: return audioSnapshots(for: asset)
        case .subtitle: return subtitleSnapshots(for: asset)
        }
    }

    /// 当前已选中的序号（回填弹层高亮用）。
    static func selectedIndex(for item: AVPlayerItem, kind: MediaTrackKind) -> Int? {
        let characteristic: AVMediaCharacteristic = kind == .audio ? .audible : .legible
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic),
              let selected = item.currentMediaSelection.selectedMediaOption(in: group),
              let index = group.options.firstIndex(of: selected) else { return nil }
        return index
    }
}
