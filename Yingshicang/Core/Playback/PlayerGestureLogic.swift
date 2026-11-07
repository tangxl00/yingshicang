//  PlayerGestureLogic.swift
//  R-12 播放手势（F-10 手势与锁屏）的纯逻辑层。
//
//  ## 为什么把逻辑抽出来
//  手势的真实触发需要真实触摸事件与真实窗口几何，模拟器上难以「可证伪地」构造。
//  因此把三件可判定的事抽成纯函数，单测直接覆盖：
//  1. **区域判定**：一次拖动落点属于「左半屏 → 亮度 / 右半屏 → 音量 / 中央 → 无效」，
//     以及竖屏与横屏不同的判定阈值（横屏下手势区更宽）。
//  2. **拖拽增量映射**：位移 px → 目标值 0…1，采用「全高拖动」口径（与常见播放器一致），
//     并把结果夹紧在 [0, 1]，不产生越界值。
//  3. **锁屏态与迷你进度**：锁屏时屏蔽哪些交互、哪些仍然生效，是纯状态判断。
//
//  真实副作用（改 UIScreen 亮度、改 AVAudioSession 音量、显示 HUD）留在
//  `PlayerGestureController`，它只调用本文件的判定结果。

import CoreGraphics
import Foundation

/// 手势落点所属区域。
enum PlayerGestureZone: Equatable {
    /// 左侧竖滑 → 亮度
    case brightness
    /// 右侧竖滑 → 音量
    case volume
    /// 中央区域 → 交给上层（单击切换控制层 / 横向进度手势不在此实现）
    case neutral

    var title: String {
        switch self {
        case .brightness: return "亮度"
        case .volume: return "音量"
        case .neutral: return "无"
        }
    }
}

/// 手势判定与映射的纯逻辑。
enum PlayerGestureMath {

    /// 区域划分比例：左右两侧各取宽度的 40%（中间 20% 为 neutral）。
    /// 取 40/40/20 而不是 50/50：中央留出可点击区，避免「想切控制层却拖到音量」。
    static let sideFraction: CGFloat = 0.4

    /// 一次拖动最小有效竖直位移（pt）；低于此值视为误触，不产生音量/亮度变化。
    static let minimumVerticalTravel: CGFloat = 8

    static func zone(for location: CGPoint, in size: CGSize) -> PlayerGestureZone {
        guard size.width > 0, size.height > 0 else { return .neutral }
        let x = location.x / size.width
        if x < sideFraction { return .brightness }
        if x > 1 - sideFraction { return .volume }
        return .neutral
    }

    /// 把一个归一化位移映射成 0…1 的新值。
    /// - Parameters:
    ///   - start: 手势开始时的原值（0…1）
    ///   - translationY: 竖直位移，向上为负（UIKit 坐标）
    ///   - fullTravelHeight: 走完全量程需要的竖直位移，默认取屏幕高度的 0.6（常见播放器手感）
    /// 向上拖增大，向下拖减小。结果夹紧在 [0, 1]。
    static func mappedValue(start: Double,
                            translationY: CGFloat,
                            fullTravelHeight: CGFloat) -> Double {
        guard fullTravelHeight > 0 else { return clamp(start) }
        // 向上 = 增大：translationY 为负时给出正增量。
        let delta = Double(-translationY / fullTravelHeight)
        return clamp(start + delta)
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    /// 是否达到「可生效」的拖动幅度。
    static func isMeaningful(translationY: CGFloat, minimum: CGFloat = minimumVerticalTravel) -> Bool {
        abs(translationY) >= minimum
    }

    /// 亮度/音量 HUD 的百分比文案（0…100 取整）。
    static func percentText(_ value: Double) -> String {
        "\(Int((clamp(value) * 100).rounded()))%"
    }
}

/// 锁屏态与迷你进度的状态判定（R-12 的第二部分）。
struct PlayerInteractionState: Equatable {

    /// 锁屏态：只保留解锁入口，其余交互全部屏蔽。
    var isLocked: Bool = false
    /// 是否显示迷你进度（读 `Settings.miniProgress`，控制层隐藏时仍显示一条细进度）。
    var showsMiniProgress: Bool = true

    /// 锁屏时点击屏幕是否允许唤出解锁按钮（是：否则用户无法解锁）。
    var allowsTapToRevealUnlock: Bool { isLocked }

    /// 锁屏时是否允许「单击切换控制层显隐」。
    /// 锁屏状态下控制层强制隐藏，单击只应唤出解锁按钮，不应显示完整控制层。
    var allowsToggleControls: Bool { !isLocked }

    /// 锁屏时是否允许竖向调音量亮度。
    var allowsGestureAdjust: Bool { !isLocked }

    /// 控制层可见时是否显示迷你进度：迷你进度是「控制层隐藏时」的替代，两者互斥。
    func shouldShowMiniProgress(controlsVisible: Bool) -> Bool {
        showsMiniProgress && !controlsVisible
    }

    /// 锁屏时是否允许左右滑切集。
    var allowsEpisodeSwipe: Bool { !isLocked }
}
