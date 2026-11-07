import CoreMotion
import Foundation
import UIKit

/// R-32 摇一摇：加速度样本与判定阈值（纯数据，便于测试）。
struct ShakeSample {
    var x: Double
    var y: Double
    var z: Double
    var timestamp: TimeInterval

    var magnitudeDeltaFromRest: Double {
        // 静止时合力约等于重力 g(9.8)；偏离量 = |sqrt(x²+y²+z²) - g|
        let magnitude = (x * x + y * y + z * z).squareRoot()
        return abs(magnitude - ShakeDetector.gravity)
    }
}

/// R-32 摇一摇判定器（纯逻辑，不依赖 CoreMotion 实例，可用合成样本序列测试）。
final class ShakeDetector {
    static let gravity: Double = 9.8
    /// 触发阈值：偏离静止合力 2.2g 视为一次有效甩动。
    static let triggerThreshold: Double = 2.2
    /// 防连触间隔（秒）。
    static let cooldown: TimeInterval = 1.5

    private(set) var lastTriggeredAt: TimeInterval?
    private var lastMagnitudeDelta: Double = 0

    /// 输入一帧加速度样本；返回该帧是否触发摇一摇。
    func ingest(_ sample: ShakeSample) -> Bool {
        let delta = sample.magnitudeDeltaFromRest
        defer { lastMagnitudeDelta = delta }

        // 上升沿触发：上一帧低于阈值、本帧超过阈值，且已过冷却时间。
        guard lastMagnitudeDelta < ShakeDetector.triggerThreshold,
              delta >= ShakeDetector.triggerThreshold else { return false }
        if let last = lastTriggeredAt,
           sample.timestamp - last < ShakeDetector.cooldown { return false }
        lastTriggeredAt = sample.timestamp
        return true
    }

    func reset() {
        lastTriggeredAt = nil
        lastMagnitudeDelta = 0
    }
}

/// R-32 运动数据源抽象：生产走 CoreMotion，测试可注入合成序列。
protocol MotionSource {
    func start(handler: @escaping (ShakeSample) -> Void)
    func stop()
}

/// R-32 CoreMotion 实现：加速度计 30Hz 采样。
final class CoreMotionShakeSource: MotionSource {
    private let manager = CMMotionManager()
    private var handler: ((ShakeSample) -> Void)?

    func start(handler: @escaping (ShakeSample) -> Void) {
        self.handler = handler
        guard manager.isAccelerometerAvailable else { return }
        manager.accelerometerUpdateInterval = 1.0 / 30.0
        manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            let a = data.acceleration
            self.handler?(ShakeSample(
                x: a.x * CoreMotionShakeSource.gScale,
                y: a.y * CoreMotionShakeSource.gScale,
                z: a.z * CoreMotionShakeSource.gScale,
                timestamp: data.timestamp
            ))
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
        handler = nil
    }

    /// CMAcceleration 以 g 为单位，ShakeSample 以 m/s² 为单位。
    static let gScale: Double = 9.8
}

/// R-32 摇一摇控制器：组合数据源与判定器，触发时回调（主线程）。
final class ShakeGestureController {
    private let source: MotionSource
    private let detector = ShakeDetector()
    private let onShake: () -> Void
    private(set) var isActive = false

    init(source: MotionSource = CoreMotionShakeSource(), onShake: @escaping () -> Void) {
        self.source = source
        self.onShake = onShake
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        detector.reset()
        source.start { [weak self] sample in
            guard let self = self, self.detector.ingest(sample) else { return }
            self.onShake()
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        source.stop()
    }
}

/// R-32 随机推荐挑选器：从候选片单中随机挑一部（RNG 可注入，测试可复现）。
enum ShakeRecommendationPicker {
    static func pick<V: RandomNumberGenerator>(_ items: [VodItem], using rng: inout V) -> VodItem? {
        guard !items.isEmpty else { return nil }
        return items[Int(rng.next() % UInt64(items.count))]
    }

    static func pick(_ items: [VodItem]) -> VodItem? {
        var rng = SystemRandomNumberGenerator()
        return pick(items, using: &rng)
    }
}
