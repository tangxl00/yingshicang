import Foundation

/// 内置 JS 运行库的装载入口。
/// 打包方式：构建期把 drpy2.js 及其 ESM 依赖（cheerio/crypto-js/json5/jinja 等）
/// 用 esbuild 打成一个 IIFE 单文件 `drpy.bundle.js`，随 App 资源一起发布。
/// 原因见架构文档 U-01：JavaScriptCore 没有 `import`，必须先打平。
enum BundledScripts {
    /// 懒加载并缓存，避免每次创建站点源都读 1.5MB 资源。
    static let drpy: String = {
        if let path = Bundle.main.path(forResource: "drpy.bundle", ofType: "js", inDirectory: "Rules"),
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return text
        }
        // folder reference 打包时可能不带 inDirectory 前缀。
        if let path = Bundle.main.path(forResource: "drpy.bundle.js"), let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return text
        }
        Log.error("[JS] drpy.bundle.js not found in bundle resources")
        return ""
    }()

    static let cheerio: String = {
        if let path = Bundle.main.path(forResource: "cheerio.bundle", ofType: "js", inDirectory: "Rules"),
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return text
        }
        if let path = Bundle.main.path(forResource: "cheerio.bundle.js"), let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return text
        }
        return ""
    }()
}
