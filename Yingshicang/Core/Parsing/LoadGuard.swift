import Foundation

/// 加载守卫：保证一次加载「一定会结束」且「只回调一次」。
///
/// 存在两类会让界面永久挂起的失效模式，这里一并堵住：
/// 1. **底层永不回调**——站点 Provider 的回调可能因为请求挂起、脚本求值卡住、
///    或闭包持有的实例已释放而永远不触发，UI 的 loading 状态就没有出口。
///    守卫用显式期限收口，超时后交回 `.timeout`，让界面给出真实原因与重试入口。
/// 2. **多重回调**——迟到响应与超时兜底同时到达时，`settle` 只认第一次，
///    后续结果一律丢弃，避免状态机被反复覆盖（例如超时后又被迟到的成功结果翻回去）。
///
/// 这不是「猜一个结果」：超时只表达「本次加载没有在期限内给出结果」，
/// 底层请求是否仍在跑与界面状态无关，用户看到的是可操作的失败态。
final class LoadGuard<Value> {

    /// 站点级加载的默认期限。TVBox 生态里采集站与脚本源通常在数秒内返回，
    /// 20 秒足够覆盖慢网；再长就会让用户误以为卡死。
    static var defaultTimeout: TimeInterval { 20 }

    private let lock = NSLock()
    private var settled = false
    private var timeoutItem: DispatchWorkItem?
    private let timeout: TimeInterval
    private let deliveryQueue: DispatchQueue
    private let completion: (Result<Value, SiteError>) -> Void

    init(timeout: TimeInterval = LoadGuard.defaultTimeout,
         deliveryQueue: DispatchQueue = .main,
         completion: @escaping (Result<Value, SiteError>) -> Void) {
        self.timeout = timeout
        self.deliveryQueue = deliveryQueue
        self.completion = completion
    }

    /// 启动期限计时。必须在调用下层加载之前调用。
    func start() {
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.settle(.failure(.timeout(self.timeout)))
        }
        lock.lock()
        timeoutItem = item
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: item)
    }

    /// 交回结果。只有第一次生效，其余（含超时之后迟到的真实结果）都被丢弃。
    func settle(_ result: Result<Value, SiteError>) {
        lock.lock()
        if settled {
            lock.unlock()
            return
        }
        settled = true
        let item = timeoutItem
        timeoutItem = nil
        lock.unlock()
        item?.cancel()
        deliveryQueue.async { [completion] in completion(result) }
    }

    /// 本次加载是否已经结束（诊断/测试用）。
    var isSettled: Bool {
        lock.lock(); defer { lock.unlock() }
        return settled
    }
}

/// 站点加载的统一入口。
///
/// 所有页面都应经这里调用 `SiteProvider`，而不是直接调 Provider：
/// 只有包一层守卫，才能保证「任何 Provider 行为（含实现缺陷导致的永不回调）
/// 都不会让界面无限转圈」。`operation` 拿到的是守卫的 settle 闭包，
/// Provider 的结果必须交给它，而不是交给页面自己的 completion。
enum SiteLoad {
    static func run<Value>(timeout: TimeInterval = LoadGuard.defaultTimeout,
                           completion: @escaping (Result<Value, SiteError>) -> Void,
                           operation: (@escaping (Result<Value, SiteError>) -> Void) -> Void) {
        let guardBox = LoadGuard<Value>(timeout: timeout, deliveryQueue: .main, completion: completion)
        guardBox.start()
        operation { result in guardBox.settle(result) }
    }
}
