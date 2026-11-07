import Foundation
import JavaScriptCore

/// JS 引擎错误。所有失败都必须可被上层区分为「装载失败 / 方法缺失 / 抛出异常 / Promise 超时 / Promise 拒绝」，
/// 不允许在 host 层把失败伪装成成功（质检 P1-4 的同类问题在桥层也不应存在）。
enum JSEngineError: Error, LocalizedError, Equatable {
    case spiderMissing
    case methodMissing(String)
    case exception(String)
    case promiseTimeout(TimeInterval)
    case promiseRejected(String)
    case scriptFailed(String)
    case requestBlocked(String)

    var errorDescription: String? {
        switch self {
        case .spiderMissing: return "JS 脚本未产出 __JS_SPIDER__"
        case .methodMissing(let method): return "JS 脚本缺少方法 \(method)"
        case .exception(let message): return "JS 执行抛出异常：\(message)"
        case .promiseTimeout(let seconds): return "JS Promise 在 \(Int(seconds))s 内未完成"
        case .promiseRejected(let reason): return "JS Promise 被拒绝：\(reason)"
        case .scriptFailed(let message): return "JS 脚本求值失败：\(message)"
        case .requestBlocked(let url): return "请求被站点策略拒绝：\(url)"
        }
    }
}

/// JavaScriptCore 宿主桥。
///
/// ## 为什么需要这一层
/// 原 App 用 QuickJS + JNI 跑 drpy2.js 一类站点规则。规则的运行契约（spider.js / http.js）规定：
/// - 规则模块把 `__jsEvalReturn()`（或 default）的结果挂到 `globalThis.__JS_SPIDER__`
/// - 内置 `http` 暴露为全局 `req`，且**必须支持同步语义**：`req(url, {async:false})` 直接返回响应对象，
///   而不是 Promise。规则脚本里有大量 `let html = request(input);` 这种同步写法，
///   一旦返回 Promise，脚本会拿到一个对象而不是字符串，整条解析链立即失效。
///
/// ## 同步语义怎么在 JavaScriptCore 上实现
/// JSC 的 `JSValue` 可以返回由原生 block 构造的对象。原生 block 在调用时**阻塞当前 JS 线程**，
/// 在 block 内起一个 semaphore 等待 `URLSession` 的回调，就能得到「JS 视角的同步调用」。
/// 前提是 JS 执行必须在**专用串行队列**上（见 `executionQueue`），否则阻塞会牵连主线程或造成互锁。
///
/// ## 隔离模型（质检 P1-3）
/// 每个引擎绑定一个站点作用域（`scope`），各自持有独立的 `JSContext` 与独立串行队列：
/// - **同一站点**的调用被串行化（JSC 的 context 不是线程安全的）；
/// - **不同站点**互不共享 `__JS_SPIDER__` / 全局变量 / `local` 存储，
///   因此 8 路并发搜索不会互相覆盖脚本状态。
/// 引擎经 `JSEngineRegistry` 按站点 key 缓存复用（避免每次搜索重复求值 1.5MB 运行库）。
final class JSEngine {

    /// 站点作用域（一般是 `site.key`）。用于 `local` 命名空间隔离与队列标签。
    let scope: String
    /// `req` 的准入策略（协议 + 域白名单 + 内网屏蔽，质检 P1-5）。
    let requestPolicy: JSRequestPolicy
    /// 站点可执行 `local` 存储的命名空间前缀。
    let localNamespace: String

    let context: JSContext
    /// 专用串行队列。所有 JS 执行都必须在这条队列上。
    let executionQueue: DispatchQueue
    /// 脚本装载状态：属于「站点 + 引擎」这一对。
    /// 修复前是每个 `JSSiteProvider` 实例各持一个布尔位，同一站点被复用时会重复求值、
    /// 并把 `__JS_SPIDER__` 反复覆盖（质检 P1-3）。
    private var scriptLoaded = false
    private let loadLock = NSLock()
    /// 同步 HTTP 的超时上限：比单次请求的 timeout 略长，避免 JS 侧永远挂住。
    private let synchronousTimeout: TimeInterval = 40
    /// Promise 收敛的默认超时。
    let promiseTimeout: TimeInterval

    init(scope: String,
         requestPolicy: JSRequestPolicy = JSRequestPolicy(),
         promiseTimeout: TimeInterval = 10) {
        self.scope = scope
        self.requestPolicy = requestPolicy
        self.localNamespace = "js.local.\(scope)."
        self.promiseTimeout = promiseTimeout
        self.executionQueue = DispatchQueue(label: "com.yingshicang.jsengine.\(scope)", qos: .userInitiated)
        self.context = JSContext() ?? JSContext(virtualMachine: JSVirtualMachine())!
        context.exceptionHandler = { _, exception in
            Log.error("[JS:\(scope)] exception: \(exception?.toString() ?? "unknown")")
        }
        installHostBridge()
    }

    // MARK: - 宿主桥安装

    private func installHostBridge() {
        let context = self.context

        // console / print / log —— drpy2 全篇用它打日志，缺了会抛 ReferenceError。
        let logBlock: @convention(block) (String) -> Void = { [scope] message in
            Log.debug("[JS:\(scope)] \(message)")
        }
        context.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        context.setObject(logBlock, forKeyedSubscript: "print" as NSString)
        let consoleLog: @convention(block) (String) -> Void = { [scope] message in
            Log.debug("[JS:\(scope) console] \(message)")
        }
        let console = JSValue(newObjectIn: context)
        console?.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        console?.setObject(consoleLog, forKeyedSubscript: "error" as NSString)
        console?.setObject(consoleLog, forKeyedSubscript: "warn" as NSString)
        console?.setObject(consoleLog, forKeyedSubscript: "info" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)

        // req / request —— 同步 + 异步双形态（见类注释），并受站点请求策略约束。
        let reqBlock: @convention(block) (JSValue, JSValue?) -> JSValue = { [weak self] urlValue, optionsValue in
            guard let self = self else { return JSValue(undefinedIn: JSContext.current()) }
            return self.performSynchronousRequest(urlValue: urlValue, optionsValue: optionsValue)
        }
        context.setObject(reqBlock, forKeyedSubscript: "req" as NSString)
        context.setObject(reqBlock, forKeyedSubscript: "request" as NSString)

        // pdfh / pdfa / pd —— 由 SwiftSoup 实现（见 HTMLSelector），
        // drpy2 在模块求值阶段就会读 `pdfh`，因此必须早于 bundle 求值注入。
        let pdfhBlock: @convention(block) (String, String) -> String = { html, rule in
            HTMLSelector.shared.pdfh(html, rule)
        }
        let pdfaBlock: @convention(block) (String, String) -> [String] = { html, rule in
            HTMLSelector.shared.pdfa(html, rule)
        }
        let pdBlock: @convention(block) (String, String) -> [String] = { html, rule in
            HTMLSelector.shared.pd(html, rule)
        }
        context.setObject(pdfhBlock, forKeyedSubscript: "pdfh" as NSString)
        context.setObject(pdfaBlock, forKeyedSubscript: "pdfa" as NSString)
        context.setObject(pdBlock, forKeyedSubscript: "pd" as NSString)
        // drpy2 里还有 pdfh0 / pdfa0 的旧名，一并注入避免老脚本炸。
        context.setObject(pdfhBlock, forKeyedSubscript: "pdfh0" as NSString)
        context.setObject(pdfaBlock, forKeyedSubscript: "pdfa0" as NSString)

        // local 存储桥（对应 Android 的 SharedPreferences），按站点作用域隔离（质检 P1-5）。
        let namespace = localNamespace
        let localGet: @convention(block) (String) -> String = { key in
            UserDefaults.standard.string(forKey: namespace + key) ?? ""
        }
        let localSet: @convention(block) (String, String) -> Void = { key, value in
            UserDefaults.standard.set(value, forKey: namespace + key)
        }
        let localClear: @convention(block) (String) -> Void = { key in
            UserDefaults.standard.removeObject(forKey: namespace + key)
        }
        let local = JSValue(newObjectIn: context)
        local?.setObject(localGet, forKeyedSubscript: "get" as NSString)
        local?.setObject(localSet, forKeyedSubscript: "set" as NSString)
        local?.setObject(localClear, forKeyedSubscript: "delete" as NSString)
        context.setObject(local, forKeyedSubscript: "local" as NSString)

        // getProxy —— 返回本地代理前缀。
        // iOS 端不使用 MITM 代理（App 没有被抓包的需求），返回空串让规则走直连。
        let getProxy: @convention(block) (Bool) -> String = { _ in "" }
        context.setObject(getProxy, forKeyedSubscript: "getProxy" as NSString)

        // sniffer 占位：真嗅探由 PlayResolver/PlaySniffer 完成，JS 侧只保留接口。
        let sniffer: @convention(block) (String) -> Void = { [scope] url in
            Log.debug("[JS:\(scope)] sniffer \(url)")
        }
        context.setObject(sniffer, forKeyedSubscript: "sniffer" as NSString)

        // base64Decode / base64Encode：模板的 lazy 脚本用到了。
        let base64Decode: @convention(block) (String) -> String = { input in
            guard let data = Data(base64Encoded: input, options: .ignoreUnknownCharacters),
                  let text = String(data: data, encoding: .utf8) else { return "" }
            return text
        }
        let base64Encode: @convention(block) (String) -> String = { input in
            Data(input.utf8).base64EncodedString()
        }
        context.setObject(base64Decode, forKeyedSubscript: "base64Decode" as NSString)
        context.setObject(base64Encode, forKeyedSubscript: "base64Encode" as NSString)

        // 运行时元信息：drpy2 会读 VERSION 做分支，缺了会抛 ReferenceError。
        context.setObject("2.0.50", forKeyedSubscript: "VERSION" as NSString)
        context.setObject("", forKeyedSubscript: "RKEY" as NSString)

        // 兜底：把未定义的宿主全局都补成 no-op，
        // 这样即使某个规则脚本引用了我们没有实现的 Android 专有函数，也不会整体崩掉。
        let undefinedStub: @convention(block) (JSValue?) -> JSValue = { _ in
            JSValue(undefinedIn: JSContext.current())
        }
        context.setObject(undefinedStub, forKeyedSubscript: "nativeLog" as NSString)
        context.setObject(undefinedStub, forKeyedSubscript: "toast" as NSString)
    }

    /// 同步 HTTP：在 JS 线程上阻塞等待网络返回。
    /// 返回值结构对齐 http.js：`{ok,status,content,headers,url}`。
    /// 被站点策略拒绝时返回 `{ok:false,status:403,blocked:true}`，让脚本能感知拒绝而不是拿到空串。
    private func performSynchronousRequest(urlValue: JSValue, optionsValue: JSValue?) -> JSValue {
        guard let ctx = JSContext.current() else { return JSValue(undefinedIn: nil) }
        let urlString = urlValue.toString() ?? ""
        guard !urlString.isEmpty else { return JSValue(undefinedIn: ctx) }

        guard requestPolicy.allows(urlString) else {
            Log.warn("[JS:\(scope)] req blocked: \(urlString)")
            let blocked = JSValue(newObjectIn: ctx)
            blocked?.setObject(false, forKeyedSubscript: "ok" as NSString)
            blocked?.setObject(403, forKeyedSubscript: "status" as NSString)
            blocked?.setObject("", forKeyedSubscript: "content" as NSString)
            blocked?.setObject(urlString, forKeyedSubscript: "url" as NSString)
            blocked?.setObject(true, forKeyedSubscript: "blocked" as NSString)
            if let emptyHeaders = JSValue(object: [String: String](), in: ctx) {
                blocked?.setObject(emptyHeaders, forKeyedSubscript: "headers" as NSString)
            }
            return blocked ?? JSValue(undefinedIn: ctx)
        }

        var options = HTTPOptions()
        if let dict = optionsValue?.toDictionary() as? [String: Any] {
            options = HTTPOptions(jsOptions: dict)
        }

        // JS 线程阻塞等待；URLSession 回调在后台线程 signal。
        let semaphore = DispatchSemaphore(value: 0)
        // 占位值必须也是「真实语义」：同步等待超时时，如实按 NSURLErrorTimedOut 呈现，
        // 不再借旧的默认 status=500 伪造 HTTP 状态码（历史缺陷同 build 20 的 HTTPClient）。
        var response = HTTPResponse.transportFailure(
            urlString,
            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                           userInfo: [NSLocalizedDescriptionKey: "同步请求等待超时（\(synchronousTimeout) 秒）"]))
        DispatchQueue.global(qos: .userInitiated).async {
            HTTPClient.shared.request(urlString, options: options) { result in
                response = result
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + synchronousTimeout)

        // 构造 JS 对象。content 以字符串形式交给脚本，规则代码对它做正则/JSON 解析。
        let result = JSValue(newObjectIn: ctx)
        result?.setObject(response.ok, forKeyedSubscript: "ok" as NSString)
        result?.setObject(response.status, forKeyedSubscript: "status" as NSString)
        result?.setObject(response.content, forKeyedSubscript: "content" as NSString)
        result?.setObject(response.url, forKeyedSubscript: "url" as NSString)
        result?.setObject(false, forKeyedSubscript: "blocked" as NSString)
        if let headers = JSValue(object: response.headers, in: ctx) {
            result?.setObject(headers, forKeyedSubscript: "headers" as NSString)
        }
        return result ?? JSValue(undefinedIn: ctx)
    }

    // MARK: - 执行

    /// 一次性装载脚本（线程安全）。返回 false 表示装载失败。
    /// 供站点 provider 在并发搜索时共用：同一引擎只会求值一次，不同引擎互不影响。
    ///
    /// 若 `__JS_SPIDER__` 已经就位（例如测试或上层预先注入了规则），不再用内置运行库覆盖，
    /// 否则会把已装载的站点规则整体替换成 drpy 模板，表现为「脚本无端丢方法」。
    func loadOnce(script: () -> String?) -> Bool {
        loadLock.lock(); defer { loadLock.unlock() }
        if scriptLoaded { return true }
        // 已有 spider 定义 → 视为已装载，直接复用。
        if hasSpider() {
            scriptLoaded = true
            return true
        }
        guard let body = script(), !body.isEmpty else { return false }
        if let error = evaluate(body, filename: "spider-\(scope).js") {
            Log.error("[JS:\(scope)] script load failed: \(error)")
            return false
        }
        // 装载后仍没有 spider：说明脚本没按契约挂载，明确失败而不是让后续调用报「方法缺失」。
        guard hasSpider() else {
            Log.error("[JS:\(scope)] script did not publish __JS_SPIDER__")
            return false
        }
        scriptLoaded = true
        return true
    }

    /// `globalThis.__JS_SPIDER__` 是否已就位。
    private func hasSpider() -> Bool {
        var present = false
        executionQueue.sync {
            guard let spider = context.objectForKeyedSubscript("__JS_SPIDER__"),
                  !spider.isUndefined, !spider.isNull else {
                present = false
                return
            }
            present = true
        }
        return present
    }

    /// 在 JS 队列上同步求值一段脚本。返回异常信息（成功时 nil）。
    @discardableResult
    func evaluate(_ script: String, filename: String = "inline.js") -> String? {
        var exceptionMessage: String?
        executionQueue.sync {
            guard let value = context.evaluateScript(script, withSourceURL: URL(string: "jsc://\(filename)")) else {
                if let exception = context.exception {
                    exceptionMessage = exception.toString()
                    context.exception = nil
                }
                return
            }
            if context.exception != nil {
                exceptionMessage = context.exception?.toString()
                context.exception = nil
            }
            _ = value
        }
        return exceptionMessage
    }

    /// 求值并把结果按 JSON 反序列化成 Foundation 对象。
    /// 供 lazy 脚本这类「脚本自己 `return JSON.stringify(...)`」的场景使用。
    func evaluateJSON(_ script: String, filename: String = "inline.js") -> Result<Any, JSEngineError> {
        var outcome: Result<Any, JSEngineError> = .failure(.scriptFailed("未执行"))
        executionQueue.sync {
            guard let value = context.evaluateScript(script, withSourceURL: URL(string: "jsc://\(filename)")),
                  value.isUndefined == false, value.isNull == false else {
                let message = context.exception?.toString() ?? "脚本无返回值"
                context.exception = nil
                outcome = .failure(.scriptFailed(message))
                return
            }
            if let exception = context.exception {
                context.exception = nil
                outcome = .failure(.exception(exception.toString() ?? ""))
                return
            }
            let text = value.toString() ?? ""
            // `.fragmentsAllowed` 是必需的：lazy 脚本常用 `return JSON.stringify(input)`，
            // 其结果是**裸字符串**这一 JSON 片段，不带该选项时 JSONSerialization 直接判失败，
            // 表现为「懒解析永远返回不了地址」。
            guard !text.isEmpty, let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                outcome = .failure(.scriptFailed("脚本返回值不是合法 JSON"))
                return
            }
            outcome = .success(object)
        }
        return outcome
    }

    /// 调用 `globalThis.__JS_SPIDER__` 上的一个方法，并把 Promise 形态的返回值真正收敛为同步结果。
    ///
    /// Promise 收敛机制（质检 P1-2）：
    /// 1. 原生侧建一个状态盒（`PromiseBox`）；
    /// 2. 调 `promise.then(resolveBlock, rejectBlock)`，两个 block 各自写状态盒；
    /// 3. 在当前 JS 队列上反复空转 `evaluateScript("0")`（JSC 在每次 API 调用后抽 microtask queue），
    ///    直到状态盒完成或到达 `promiseTimeout`；
    /// 4. 超时 → `.promiseTimeout`，拒绝 → `.promiseRejected`，两者都是失败，不返回原值。
    func callSpider(_ method: String, arguments: [Any]) -> Result<Any?, JSEngineError> {
        var outcome: Result<Any?, JSEngineError> = .failure(.spiderMissing)
        executionQueue.sync {
            guard let spider = context.objectForKeyedSubscript("__JS_SPIDER__"),
                  !spider.isUndefined, !spider.isNull else {
                Log.warn("[JS:\(scope)] __JS_SPIDER__ not present")
                outcome = .failure(.spiderMissing)
                return
            }
            guard let function = spider.objectForKeyedSubscript(method), function.isUndefined == false else {
                Log.warn("[JS:\(scope)] spider.\(method) missing")
                outcome = .failure(.methodMissing(method))
                return
            }
            let jsArguments = arguments.map { JSValue(object: $0, in: context) ?? JSValue(undefinedIn: context) }
            guard let result = function.call(withArguments: jsArguments) else {
                let message = context.exception?.toString() ?? "调用无返回值"
                context.exception = nil
                outcome = .failure(.exception(message))
                return
            }
            if let exception = context.exception {
                context.exception = nil
                Log.error("[JS:\(scope)] \(method) threw: \(exception.toString() ?? "")")
                outcome = .failure(.exception(exception.toString() ?? ""))
                return
            }
            // 普通（非 Promise）返回：直接取值。
            guard let thenValue = result.objectForKeyedSubscript("then"),
                  thenValue.isUndefined == false, thenValue.isNull == false else {
                outcome = .success(result.toObject())
                return
            }
            outcome = self.settlePromise(result, thenValue: thenValue, method: method)
        }
        return outcome
    }

    /// Promise 收敛实现：见 `callSpider` 注释。
    private func settlePromise(_ promise: JSValue, thenValue: JSValue, method: String) -> Result<Any?, JSEngineError> {
        let box = PromiseBox()
        let resolveBlock: @convention(block) (JSValue?) -> Void = { value in
            box.done = true
            box.value = value?.toObject()
        }
        let rejectBlock: @convention(block) (JSValue?) -> Void = { reason in
            box.done = true
            box.error = reason?.toString() ?? "promise rejected"
        }
        guard let resolveJS = JSValue(object: resolveBlock, in: context),
              let rejectJS = JSValue(object: rejectBlock, in: context) else {
            return .failure(.exception("无法构造 Promise 回调"))
        }
        _ = thenValue.call(withArguments: [resolveJS, rejectJS])
        if let exception = context.exception {
            context.exception = nil
            return .failure(.exception(exception.toString() ?? ""))
        }

        let deadline = Date().addingTimeInterval(promiseTimeout)
        while !box.done {
            if Date() > deadline {
                Log.warn("[JS:\(scope)] \(method) promise timeout after \(promiseTimeout)s")
                return .failure(.promiseTimeout(promiseTimeout))
            }
            // 推进 JSC 的 microtask 队列：每次 API 调用后会抽取一次待执行任务。
            _ = context.evaluateScript("0")
            if context.exception != nil {
                let message = context.exception?.toString() ?? ""
                context.exception = nil
                return .failure(.exception(message))
            }
            if box.done { break }
            // 让出极短时间片，避免纯空转把 CPU 打满；状态盒在同一队列上，不需要锁。
            Thread.sleep(forTimeInterval: 0.005)
        }
        if let error = box.error {
            return .failure(.promiseRejected(error))
        }
        return .success(box.value)
    }
}

/// Promise 收敛过程中的原生状态盒（block 内写、轮询侧读，都在同一 JS 队列上，无需加锁）。
private final class PromiseBox {
    var done = false
    var value: Any?
    var error: String?
}

/// 引擎注册表：按站点作用域缓存 `JSEngine`，保证「同站点串行、跨站点隔离」。
/// 质检 P1-3 的修复点：不再存在单一全局 `JSEngine.shared`。
final class JSEngineRegistry {
    static let shared = JSEngineRegistry()
    private var engines: [String: JSEngine] = [:]
    private let lock = NSLock()

    /// 允许测试构造独立注册表，避免用例之间共享引擎状态。
    init() {}

    /// 取站点引擎。`scope` 一般传 `site.key`；lazy 脚本用 `lazy:<key>` 独立作用域，
    /// 避免 lazy 脚本定义的全局变量污染 spider 运行库。
    func engine(scope: String, requestPolicy: JSRequestPolicy) -> JSEngine {
        lock.lock(); defer { lock.unlock() }
        if let existing = engines[scope] {
            return existing
        }
        let engine = JSEngine(scope: scope, requestPolicy: requestPolicy)
        engines[scope] = engine
        return engine
    }

    func engine(for site: SiteConfig) -> JSEngine {
        engine(scope: "site:\(site.key)", requestPolicy: JSRequestPolicy(allowedHosts: JSRequestPolicy.allowedHosts(for: site)))
    }

    func lazyEngine(for site: SiteConfig) -> JSEngine {
        engine(scope: "lazy:\(site.key)", requestPolicy: JSRequestPolicy(allowedHosts: JSRequestPolicy.allowedHosts(for: site)))
    }

    /// 配置切换/重置时整体丢弃（避免旧脚本状态与新配置串味）。
    func reset() {
        lock.lock(); engines.removeAll(); lock.unlock()
    }

    /// 当前已缓存的引擎作用域（诊断/测试用）。
    func scopes() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(engines.keys).sorted()
    }
}
