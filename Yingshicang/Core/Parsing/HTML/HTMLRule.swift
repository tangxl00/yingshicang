import Foundation

/// 规则串解析器。
///
/// 采集站规则（模板.js 的「一级/二级/搜索」字段）实际语法是：
///   `选择器1;选择器2;...`
/// 每个选择器内部用 `&&` 逐级下钻，用 `||` 表示并列候选（从左到右取第一个有结果的），
/// 末端可以是属性名（`src` / `href` / `Text` / `Html`），也可以是 `:eq(n)` 索引。
/// 这套语法由 Android 端的 `pdfh` / `pdfa` / `pd` 三个宿主函数实现，本工程必须在 Swift 侧等价实现，
/// 否则既有规则无法复用（见架构文档 4.2 与 6.2 的 JS 桥一致性要求）。
enum HTMLRule {

    /// 把 `a;b;c` 拆成多段。分号出现在属性值或 `:eq()` 里的情况极少，这里只做括号/引号感知的简易切分。
    static func splitFields(_ rule: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for ch in rule {
            if let q = quote {
                current.append(ch)
                if ch == q { quote = nil }
                continue
            }
            switch ch {
            case "'", "\"": quote = ch; current.append(ch)
            case "(", "[": depth += 1; current.append(ch)
            case ")", "]": depth -= 1; current.append(ch)
            case ";":
                if depth == 0 {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            default: current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }

    /// 取出第 index 段（越界回退首段，与 U01Gate JS driver 的 field() 行为一致）。
    static func field(_ rule: String, at index: Int) -> String {
        let parts = splitFields(rule)
        guard index < parts.count else { return parts.first ?? "" }
        return parts[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 单个候选链的解析结果：元素集合，或末端取到的字符串。
    enum Resolution {
        case elements([HTMLElementNode])
        case text(String)
        case none
    }

    /// 把一条链（`a&&b&&src` 这种）拆成步骤。
    static func splitChain(_ chain: String) -> [String] {
        var steps: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        var i = chain.startIndex
        while i < chain.endIndex {
            let ch = chain[i]
            if let q = quote {
                current.append(ch)
                if ch == q { quote = nil }
                i = chain.index(after: i)
                continue
            }
            switch ch {
            case "'", "\"": quote = ch; current.append(ch); i = chain.index(after: i)
            case "(", "[": depth += 1; current.append(ch); i = chain.index(after: i)
            case ")", "]": depth -= 1; current.append(ch); i = chain.index(after: i)
            case "&":
                let next = chain.index(after: i)
                if depth == 0, next < chain.endIndex, chain[next] == "&" {
                    steps.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    i = chain.index(after: next)
                    continue
                }
                current.append(ch); i = next
            default: current.append(ch); i = chain.index(after: i)
            }
        }
        steps.append(current.trimmingCharacters(in: .whitespaces))
        return steps.filter { !$0.isEmpty }
    }

    /// `||` 分隔的并列候选（取第一个非空结果）。
    static func splitAlternatives(_ chain: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var i = chain.startIndex
        while i < chain.endIndex {
            let ch = chain[i]
            if ch == "(" || ch == "[" { depth += 1 }
            if ch == ")" || ch == "]" { depth -= 1 }
            if depth == 0, ch == "|" {
                let next = chain.index(after: i)
                if next < chain.endIndex, chain[next] == "|" {
                    parts.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    i = chain.index(after: next)
                    continue
                }
            }
            current.append(ch)
            i = chain.index(after: i)
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts.filter { !$0.isEmpty }
    }

    /// 末端取值关键字判定：`Text`/`text` 取文本、`Html`/`html` 取 innerHTML、
    /// 其余纯字母标识符（如 `src`、`href`、`data-src`）按属性取值。
    static func isTextToken(_ token: String) -> Bool {
        let lowered = token.lowercased()
        return lowered == "text"
    }

    static func isHtmlToken(_ token: String) -> Bool {
        let lowered = token.lowercased()
        return lowered == "html" || lowered == "outerhtml" || lowered == "allhtml"
    }

    /// 判断某个步骤是不是「取值」而不是「选择器」。
    /// 纯标识符（不含 `.` `#` `[` `:` 空格 `>` `+`）才可能是属性名。
    static func looksLikeAttribute(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let invalid = CharacterSet(charactersIn: ".#[: >+~*()'\"")
        if token.unicodeScalars.contains(where: { invalid.contains($0) }) { return false }
        return true
    }
}
