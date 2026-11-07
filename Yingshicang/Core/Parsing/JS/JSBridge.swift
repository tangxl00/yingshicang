import Foundation
import JavaScriptCore

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
/// ## 线程模型
/// - 每个 `JSContext` 绑定一个固定队列（JSContext 不是线程安全的，同一 context 不能被多线程并发使用）。
/// - 网络回调在 URLSession 的后台线程完成，通过 semaphore 交回 JS 队列。
/// - 所有对 JSContext 的访问都必须 `executionQueue.sync`，UI 层调用前不需要关心线程。
final class JSEngine {

    /// 单例：站点规则脚本体量大（drpy bundle ≈ 1.5MB），重复创建 context 会显著拖慢首屏。
    static let shared = JSEngine()

    let context: JSContext
    /// 专用串行队列。所有 JS 执行都必须在这条队列上。
    let executionQueue = DispatchQueue(label: "com.yingshicang.jsengine", qos: .userInitiated)
    /// 同步 HTTP 的超时上限：比单次请求的 timeout 略长，避免 JS 侧永远挂住。
    private let synchronousTimeout: TimeInterval = 40

    private init() {
        context = JSContext() ?? JSContext(virtualMachine: JSVirtualMachine())!
        context.exceptionHandler = { _, exception in
            Log.error("[JS] exception: \(exception?.toString() ?? "unknown")")
        }
        installHostBridge()
    }

    // MARK: - 宿主桥安装

    private func installHostBridge() {
        let context = self.context

        // console / print / log —— drpy2 全篇用它打日志，缺了会抛 ReferenceError。
        let logBlock: @convention(block) (String) -> Void = { message in
            Log.debug("[JS] \(message)")
        }
        context.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        context.setObject(logBlock, forKeyedSubscript: "print" as NSString)
        let consoleLog: @convention(block) (String) -> Void = { message in
            Log.debug("[JS console] \(message)")
        }
        let console = JSValue(newObjectIn: context)
        console?.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        console?.setObject(consoleLog, forKeyedSubscript: "error" as NSString)
        console?.setObject(consoleLog, forKeyedSubscript: "warn" as NSString)
        console?.setObject(consoleLog, forKeyedSubscript: "info" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)

        // req / request —— 同步 + 异步双形态（见类注释）。
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

        // local 存储桥（对应 Android 的 SharedPreferences）。
        let localGet: @convention(block) (String) -> String = { key in
            UserDefaults.standard.string(forKey: "js.local.\(key)") ?? ""
        }
        let localSet: @convention(block) (String, String) -> Void = { key, value in
            UserDefaults.standard.set(value, forKey: "js.local.\(key)")
        }
        let local = JSValue(newObjectIn: context)
        local?.setObject(localGet, forKeyedSubscript: "get" as NSString)
        local?.setObject(localSet, forKeyedSubscript: "set" as NSString)
        context.setObject(local, forKeyedSubscript: "local" as NSString)

        // getProxy —— 返回本地代理前缀。
        // iOS 端不使用 MITM 代理（App 没有被抓包的需求），返回空串让规则走直连。
        let getProxy: @convention(block) (Bool) -> String = { _ in "" }
        context.setObject(getProxy, forKeyedSubscript: "getProxy" as NSString)

        // sniffer 占位：真嗅探由原生播放内核完成，JS 侧只保留接口。
        let sniffer: @convention(block) (String) -> Void = { url in Log.debug("[JS] sniffer \(url)") }
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
    private func performSynchronousRequest(urlValue: JSValue, optionsValue: JSValue?) -> JSValue {
        guard let ctx = JSContext.current() else { return JSValue(undefinedIn: nil) }
        let urlString = urlValue.toString() ?? ""
        guard !urlString.isEmpty else { return JSValue(undefinedIn: ctx) }

        var options = HTTPOptions()
        if let dict = optionsValue?.toDictionary() as? [String: Any] {
            options = HTTPOptions(jsOptions: dict)
        }

        // JS 线程阻塞等待；URLSession 回调在后台线程 signal。
        let semaphore = DispatchSemaphore(value: 0)
        var response = HTTPResponse.failure(urlString)
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
        if let headers = JSValue(object: response.headers, in: ctx) {
            result?.setObject(headers, forKeyedSubscript: "headers" as NSString)
        }
        return result ?? JSValue(undefinedIn: ctx)
    }

    // MARK: - 执行

    /// 在 JS 队列上同步求值一段脚本。返回异常信息（成功时 nil）。
    @discardableResult
    func evaluate(_ script: String, filename: String = "inline.js") -> String? {
        var exceptionMessage: String?
        executionQueue.sync {
            guard let value = context.evaluateScript(script, withSourceURL: URL(string: "jsc://\(filename)")) else {
                if let exception = context.exception {
                    exceptionMessage = exception.toString()
                }
                return
            }
            if context.exception != nil {
                exceptionMessage = context.exception?.toString()
            }
            _ = value
        }
        return exceptionMessage
    }

    /// 调用 `globalThis.__JS_SPIDER__` 上的一个方法。
    /// 参数按 JSON 可序列化的形式传入（字典/数组/字符串/数字）。
    func callSpider(_ method: String, arguments: [Any]) -> Any? {
        var output: Any?
        executionQueue.sync {
            guard let spider = context.objectForKeyedSubscript("__JS_SPIDER__"),
                  !spider.isUndefined, !spider.isNull else {
                Log.warn("[JS] __JS_SPIDER__ not present")
                return
            }
            guard let function = spider.objectForKeyedSubscript(method), function.isUndefined == false else {
                Log.warn("[JS] spider.\(method) missing")
                return
            }
            let jsArguments = arguments.map { JSValue(object: $0, in: context) ?? JSValue(undefinedIn: context) }
            guard let result = function.call(withArguments: jsArguments) else { return }
            if let exception = context.exception {
                Log.error("[JS] \(method) threw: \(exception.toString() ?? "")")
                context.exception = nil
                return
            }
            output = result.toObject()
        }
        return output
    }
}
