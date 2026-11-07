import Foundation
import JavaScriptCore

/// U-01 探针核心：在 JavaScriptCore 中加载 cheerio.bundle.js（esbuild 单文件版，
/// 暴露 `globalThis.cheerio`），并提供带/不带 Node 全局垫片两种装载模式，
/// 供门禁判定 A（直接可跑）/ C（差 Node 全局，垫片后可跑）/ B（不可跑，降级宿主实现）。
public enum U01Probe {

    public enum LoadResult {
        case ok
        case failed(String)
    }

    /// 装载 cheerio。
    /// - Parameter shimmed: true 时先注入最小 Node 全局垫片（只补类型与编码，
    ///   不补任何 DOM 能力）——对应判定分支 C 的重跑条件。
    public static func load(shimmed: Bool) -> (JSContext, LoadResult) {
        let context = JSContext()!
        context.exceptionHandler = { _, value in
            // 异常记录到 lastError，由调用方读取；不在此抛出，
            // 让每个断言自行判定。
            context.setObject(value?.toString() ?? "unknown JS exception",
                              forKeyedSubscript: "__lastError" as NSString)
        }

        if shimmed {
            // 分支 C 垫片：仅类型与编码层面的 Node 全局，不含任何 DOM。
            context.evaluateScript("""
            var global = globalThis;
            var process = { env: {}, version: 'v18.0.0', nextTick: function (f) { f(); },
                            browser: false, platform: 'darwin' };
            function Buffer(input, encoding) {
                this._s = (input === undefined || input === null) ? '' : String(input);
                this.length = this._s.length;
                this.toString = function (enc) { return this._s; };
            }
            Buffer.from = function (input, encoding) { return new Buffer(input, encoding); };
            Buffer.isBuffer = function (x) { return x instanceof Buffer; };
            Buffer.alloc = function (n) { return new Buffer(' '); };
            globalThis.Buffer = Buffer;
            globalThis.process = process;
            globalThis.global = globalThis;
            """)
        }

        guard let bundleURL = resourceURL(named: "cheerio.bundle.js") else {
            return (context, .failed("cheerio.bundle.js 资源缺失（U01Gate/Resources）"))
        }
        guard let source = try? String(contentsOf: bundleURL, encoding: .utf8) else {
            return (context, .failed("cheerio.bundle.js 读取失败"))
        }
        let before = context.objectForKeyedSubscript("__lastError")
        _ = context.evaluateScript(source, withSourceURL: bundleURL)
        let after = context.objectForKeyedSubscript("__lastError")
        if let err = after, !err.isUndefined, err.toString() != before?.toString() {
            return (context, .failed("求值抛异常: \(err.toString() ?? "unknown")"))
        }
        // 装载成功的判据：globalThis.cheerio 存在且可调用 load
        let probe = context.evaluateScript(
            "(typeof cheerio !== 'undefined' && typeof cheerio.load === 'function')")
        if probe?.toBool() == true {
            return (context, .ok)
        }
        let errText = context.objectForKeyedSubscript("__lastError")?.toString() ?? "no exception recorded"
        return (context, .failed("cheerio 未正确暴露（typeof cheerio 检查失败）: \(errText)"))
    }

    static func resourceURL(named name: String) -> URL? {
        // SPM 资源在自动生成的 Bundle.module 中；.copy("Resources") 目录
        // 落在 bundle 的 Resources/ 下，另配递归兜底以防布局差异。
        let bundle = Bundle.module
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("Resources/\(name)"),
            bundle.resourceURL?.appendingPathComponent(name)
        ]
        if let hit = candidates.compactMap({ $0 })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return hit
        }
        guard let root = bundle.resourceURL else { return nil }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            return url
        }
        return nil
    }

    /// 注入 pdfh/pdfa/pd 驱动脚本（C-5 探针依赖，资源属 U01Gate 模块）。
    public static func installPdfhDriver(_ context: JSContext) -> Bool {
        guard let url = resourceURL(named: "pdfh.driver.js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return false }
        _ = context.evaluateScript(source)
        let ok = context.evaluateScript("(typeof pdfh === 'function' && typeof pd === 'function')")
        return ok?.toBool() == true
    }

    /// 取最近一次 JS 异常文本（用于诊断信息，不作为断言依据）。
    public static func lastError(of context: JSContext) -> String {
        context.objectForKeyedSubscript("__lastError")?.toString() ?? ""
    }
}

