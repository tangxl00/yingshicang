import Foundation

/// 内置 JS 运行库的装载入口。
/// 打包方式：构建期把 drpy2.js 及其 ESM 依赖（cheerio/crypto-js/json5/jinja 等）
/// 用 esbuild 打成一个 IIFE 单文件 `drpy.bundle.js`，随 App 资源一起发布。
/// 原因见架构文档 U-01：JavaScriptCore 没有 `import`，必须先打平。
enum BundledScripts {
    /// 在 bundle 内定位资源文件。
    /// Rules 目录以 folder reference 打包，运行时位于 bundle 根下的 `Rules/`；
    /// 兜底再做一次递归查找，避免不同打包配置下的路径差异。
    /// - Parameter fileName: 文件名，可带扩展名（如 `模板.js`）。
    static func resourcePath(named fileName: String) -> String? {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let exts = ext.isEmpty ? ["js"] : [ext, "js"]
        for e in exts {
            if let url = Bundle.main.url(forResource: base, withExtension: e, subdirectory: "Rules") {
                return url.path
            }
            if let url = Bundle.main.url(forResource: base, withExtension: e) {
                return url.path
            }
        }
        guard let root = Bundle.main.resourceURL else { return nil }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == fileName {
            return url.path
        }
        return nil
    }

    private static func loadScript(_ name: String) -> String {
        if let path = resourcePath(named: "\(name).js"), let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return text
        }
        return ""
    }

    /// 懒加载并缓存，避免每次创建站点源都读 1.5MB 资源。
    static let drpy: String = {
        let text = loadScript("drpy.bundle")
        if text.isEmpty {
            Log.error("[JS] drpy.bundle.js not found in bundle resources")
        }
        return text
    }()

    static let cheerio: String = loadScript("cheerio.bundle")
}
