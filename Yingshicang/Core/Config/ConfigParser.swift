import Foundation

/// 配置文本 → ConfigBundle。
enum ConfigParser {

    /// 解析失败的**真实原因**（不再静默返回空 bundle 让上层误判成「加载成功但没内容」）。
    enum Failure: Error, Equatable {
        /// 文本为空。
        case emptyText
        /// 能当 JSON 读，但顶层结构与配置格式不符（例如是纯数组/字符串）。
        case wrongShape(String)
        /// 结构里有 `sites` 但一个都没解出来（说明站点字段与解码器不匹配）。
        case sitesUndecodable(String)
        /// 既不是合法 JSON，也不是可容错的 JSON。附带首个非法位置的行号与内容片段。
        case invalidJSON(JSONSyntaxError)

        var message: String {
            switch self {
            case .emptyText: return "配置内容为空"
            case .wrongShape(let detail): return "配置顶层结构不符：\(detail)"
            case .sitesUndecodable(let detail): return "站点字段无法解码：\(detail)"
            case .invalidJSON(let syntax): return "不是合法 JSON：\(syntax.display)"
            }
        }
    }

    /// 可诊断的解析入口。`load` 用它，把真实原因透出到界面。
    ///
    /// 顺序：能解码且**解出了内容** → 成功；否则做结构诊断，给出真实原因。
    /// 关键点：`ConfigBundle` 是宽容解码，任何 JSON 对象都能"解码成功"成空 bundle，
    /// 所以不能只看「解码有没有抛错」，必须再看「解出来的东西是不是真的配置」。
    static func parseResult(text: String) -> Result<ConfigBundle, Failure> {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return .failure(.emptyText) }

        // TVBox 系配置普遍带 `//` 行注释（常见于文件首行说明、站点之间分隔），
        // 严格解析器会直接判「不是合法 JSON」。这里先按行级口径剥注释，再解析。
        let cleaned = stripJSONNoise(normalized)
        // 1) 原文；2) 去注释 / BOM / 尾逗号后的文本。原文优先，避免对本来就合法的
        //    配置做任何改写（例如字符串值里真的含 `//` 的行）。
        for candidate in [normalized, cleaned] {
            guard let bundle = decode(candidate) else { continue }
            if !bundle.sites.isEmpty || !bundle.parses.isEmpty { return .success(bundle) }
            // 解出来是空的：要么真是空仓，要么这份文本根本不是配置 —— 交给结构诊断判定。
            if let failure = analyze(cleaned) { return .failure(failure) }
            return .success(bundle)
        }
        return .failure(analyze(cleaned) ?? .invalidJSON(JSONSyntaxError.line("无法解析为 JSON", 0, "")))
    }

    /// 兼容旧签名：解析不出内容时返回空 bundle（仅测试与非关键路径使用）。
    static func parse(text: String) -> ConfigBundle {
        if case .success(let bundle) = parseResult(text: text) { return bundle }
        return .init()
    }

    /// 统一入口前的文本归一：去 UTF-8 BOM、去首尾空白。
    /// BOM 在 Windows 记事本另存的配置里很常见，`JSONSerialization` 见到它会直接拒。
    static func normalize(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        t = t.replacingOccurrences(of: "\u{0000}", with: "")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(_ text: String) -> ConfigBundle? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ConfigBundle.self, from: data)
    }

    /// 结构诊断：返回 nil 表示「确实是一份合法的空配置」，返回 Failure 表示真实原因。
    private static func analyze(_ cleaned: String) -> Failure? {
        guard let data = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return .invalidJSON(JSONSyntaxValidator.firstError(in: cleaned))
        }
        guard let root = object as? [String: Any] else {
            return .wrongShape("顶层是 JSON 数组或标量，不是配置对象")
        }
        if let rawSites = root["sites"] ?? root["api_site"] {
            if let list = rawSites as? [Any], !list.isEmpty {
                return .sitesUndecodable("sites 有 \(list.count) 项，但没有任何一项满足站点字段约束")
            }
            return nil                    // sites 是空数组 / null：合法的空仓
        }
        if root["urls"] != nil || root["stores"] != nil {
            return .wrongShape("这是多仓索引文件（urls/stores），不是单仓配置文件")
        }
        if root["parses"] != nil || root["flags"] != nil
            || root["wallpaper"] != nil || root["spider"] != nil {
            return nil                    // 有配置字段但没有 sites：合法的空仓
        }
        return .wrongShape("JSON 对象缺少 sites/parses 等配置字段")
    }

    /// 解析多仓索引文件（R-29 的仓列表来源）。
    /// 兼容两种形态：
    ///   [ { "name": "...", "url": "...", "lines": [ ... ] } ]
    ///   { "urls": [ { "url": "...", "name": "..." } ] }   （TVBox 多仓入口）
    static func parseStoreIndex(text: String) -> [ConfigStore] {
        let trimmed = stripJSONNoise(normalize(text))
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [] }

        if let list = object as? [[String: Any]] {
            return list.compactMap { storeFromDictionary($0) }
        }
        if let root = object as? [String: Any] {
            // TVBox 多仓入口：`{"urls":["...","..."]}` 纯字符串数组，
            // 每个 URL 就是一条线路，整体作为一个仓返回。
            if let urls = root["urls"] as? [String] {
                let lines: [ConfigLine] = urls.enumerated().compactMap { pair -> ConfigLine? in
                    let url = pair.element.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !url.isEmpty else { return nil }
                    return ConfigLine(name: "线路\(pair.offset + 1)", url: url)
                }
                guard !lines.isEmpty else { return [] }
                return [ConfigStore(name: "默认仓", url: lines[0].url, lines: lines)]
            }
            if let urls = root["urls"] as? [[String: Any]] {
                return urls.compactMap { storeFromDictionary($0) }
            }
            if let stores = root["stores"] as? [[String: Any]] {
                return stores.compactMap { storeFromDictionary($0) }
            }
        }
        return []
    }

    private static func storeFromDictionary(_ dict: [String: Any]) -> ConfigStore? {
        let name = (dict["name"] as? String) ?? (dict["title"] as? String) ?? ""
        let url = (dict["url"] as? String) ?? ""
        guard !url.isEmpty else { return nil }
        var lines: [ConfigLine] = []
        if let rawLines = dict["lines"] as? [[String: Any]] {
            for item in rawLines {
                let lineName = (item["name"] as? String) ?? (item["title"] as? String) ?? ""
                let lineURL = (item["url"] as? String) ?? ""
                if !lineURL.isEmpty {
                    lines.append(ConfigLine(name: lineName, url: lineURL))
                }
            }
        }
        if lines.isEmpty { lines = [ConfigLine(name: name, url: url)] }
        return ConfigStore(name: name.isEmpty ? url : name, url: url, lines: lines)
    }

    /// 去掉 `//` 行注释、`/* */` 块注释、尾逗号。
    ///
    /// **注释剥离口径（build 24）**：整行以 `//` 开头（允许行首空白）的行按注释整行丢弃。
    /// 这是 TVBox 圈配置的通行形态，也是唯一能保证「不误伤字符串值」的口径 ——
    /// 字符串里出现 `https://…` 这类内容极为常见，按字符扫描判断「是否在字符串内」
    /// 一旦状态出错，就会把 URL 当注释截断（build 23 的真实故障即由此产生，详见
    /// `JSONSyntaxValidator` 上方注释）。行级口径不依赖字符串状态机，天然安全。
    ///
    /// 块注释与行尾注释仍按字符扫描处理，但**按 Unicode.Scalar 粒度**推进，
    /// 不能用 `Character`（字素簇）——`"` + 变体选择符会被合成为一个 Character，
    /// `ch == "\""` 判等随之失效。
    static func stripJSONNoise(_ text: String) -> String {
        let withoutBOM = normalize(text)
        var lines: [String] = []
        lines.reserveCapacity(64)
        for line in withoutBOM.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("//") { continue }
            lines.append(line)
        }
        let joined = lines.joined(separator: "\n")
        let stripped = stripBlockComments(joined)
        return removeTrailingCommas(stripped)
    }

    /// 块注释 `/* … */` 剥离，按 Unicode.Scalar 粒度推进，并跳过字符串内部。
    private static func stripBlockComments(_ text: String) -> String {
        guard text.contains("/*") else { return text }
        var output = String.UnicodeScalarView()
        output.reserveCapacity(text.unicodeScalars.count)
        let scalars = Array(text.unicodeScalars)
        var index = 0
        var inString = false
        var escaped = false
        while index < scalars.count {
            let scalar = scalars[index]
            if inString {
                output.append(scalar)
                if escaped { escaped = false }
                else if scalar == "\\" { escaped = true }
                else if scalar == "\"" { inString = false }
                index += 1
                continue
            }
            if scalar == "\"" {
                inString = true
                output.append(scalar)
                index += 1
                continue
            }
            if scalar == "/", index + 1 < scalars.count, scalars[index + 1] == "*" {
                index += 2
                while index + 1 < scalars.count, !(scalars[index] == "*" && scalars[index + 1] == "/") {
                    index += 1
                }
                index = min(index + 2, scalars.count)
                // 注释整体被抹掉后可能留下空行，保持一个换行以免两个 token 粘连。
                output.append("\n")
                continue
            }
            output.append(scalar)
            index += 1
        }
        return String(output)
    }

    /// 尾逗号 `,}` / `,]` 去掉（TVBox 配置里常见）。
    private static func removeTrailingCommas(_ text: String) -> String {
        guard text.contains(",") else { return text }
        var output = String.UnicodeScalarView()
        let scalars = Array(text.unicodeScalars)
        var index = 0
        var inString = false
        var escaped = false
        while index < scalars.count {
            let scalar = scalars[index]
            if inString {
                output.append(scalar)
                if escaped { escaped = false }
                else if scalar == "\\" { escaped = true }
                else if scalar == "\"" { inString = false }
                index += 1
                continue
            }
            if scalar == "\"" {
                inString = true
                output.append(scalar)
                index += 1
                continue
            }
            if scalar == "," {
                // 向前看空白，若是 `}` 或 `]` 则丢弃这个逗号。
                var probe = index + 1
                while probe < scalars.count, scalars[probe].value == 0x20 || scalars[probe].value == 0x09
                        || scalars[probe].value == 0x0A || scalars[probe].value == 0x0D {
                    probe += 1
                }
                if probe < scalars.count, scalars[probe] == "}" || scalars[probe] == "]" {
                    index += 1
                    continue
                }
            }
            output.append(scalar)
            index += 1
        }
        return String(output)
    }
}
