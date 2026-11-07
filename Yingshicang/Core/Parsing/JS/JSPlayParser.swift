import Foundation

/// lazy 规则执行器（F-08 的核心）。
///
/// 文档 4.3 给出三种形态：
/// ① `js:` 脚本 —— 在 JS 引擎里跑，入参 `input`，产出 `{parse,jx,url}`
/// ② `json:` 前缀 —— 先拼 URL 请求接口，取返回 JSON 的 `url`
/// ③ 直接地址 —— 剧集 lists 里已是 m3u8/mp4
final class JSPlayParser {
    static let shared = JSPlayParser()

    /// 执行 lazy。脚本形态在 JS 引擎的一个临时作用域里运行：
    /// 以 `input` 作为入参，跑完后从全局读回 `input` 的最终值。
    func resolve(site: SiteConfig, input: String, completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        let lazy = site.lazy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lazy.isEmpty else {
            completion(.success(PlayResolution(url: input, parseIndex: nil, needSniff: true)))
            return
        }

        // 形态二：`json:` 前缀
        if lazy.lowercased().hasPrefix("json:") {
            resolveJSON(lazy: lazy, input: input, completion: completion)
            return
        }

        // 形态一：`js:` 脚本
        var script = lazy
        if script.lowercased().hasPrefix("js:") {
            script = String(script.dropFirst(3))
        }
        let engine = JSEngine.shared
        let setting = settingJSON(site: site)
        let wrapper = """
        (function(){
          var input = \(jsString(input));
          var rule = \(setting);
          var MY_URL = \(jsString(site.host.isEmpty ? site.api : site.host));
          var HOST = MY_URL;
          \(script)
          return JSON.stringify(input);
        })();
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var output: Any?
            engine.executionQueue.sync {
                if let value = engine.context.evaluateScript(wrapper, withSourceURL: URL(string: "jsc://lazy-\(site.key).js")),
                   let json = value.toString(), !json.isEmpty,
                   let data = json.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) {
                    output = object
                } else if let exception = engine.context.exception {
                    Log.error("[JS] lazy failed: \(exception.toString() ?? "")")
                    engine.context.exception = nil
                }
            }
            if let dict = output as? [String: Any] {
                completion(.success(JSSiteProvider.parsePlay(dict)))
            } else {
                // 脚本没产出结构化结果时，把原地址当直链返回，避免播放页空白。
                completion(.success(PlayResolution(url: input, parseIndex: nil, needSniff: true)))
            }
        }
    }

    /// `json:` 形态：拼接后请求，取 json.url。
    private func resolveJSON(lazy: String, input: String,
                             completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        let prefix = String(lazy.dropFirst("json:".count)).trimmingCharacters(in: .whitespaces)
        let target = prefix + input
        HTTPClient.shared.request(target) { response in
            if let data = response.content.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let url = object["url"] as? String, !url.isEmpty {
                completion(.success(PlayResolution(url: url, parseIndex: nil, needSniff: false)))
            } else {
                completion(.success(PlayResolution(url: input, parseIndex: nil, needSniff: true)))
            }
        }
    }

    /// 把站点配置序列化成 JS 对象字面量（供 lazy 脚本里的 `rule.xxx` 访问）。
    private func settingJSON(site: SiteConfig) -> String {
        var dict: [String: Any] = [
            "key": site.key, "name": site.name, "type": site.type,
            "api": site.api, "ext": site.ext, "jar": site.jar,
            "host": site.host, "url": site.url,
            "searchUrl": site.searchUrl, "detailUrl": site.detailUrl,
            "parse_url": "", "headers": site.headers, "lazy": site.lazy
        ]
        if !site.ext.isEmpty {
            // ext 常是 `?key=xxx` 形式的查询串，规则脚本会拼出完整接口地址。
            dict["parse_url"] = ""
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        // ["value"] → "value"
        return String(text.dropFirst().dropLast())
    }
}
