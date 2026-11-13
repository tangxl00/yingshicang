import Foundation

/// 文本解码：优先按 Content-Type 声明的 charset，其次按 HTML meta 声明，最后回落 GB18030。
/// 国内采集站大量使用 GBK/GB2312 页面，直接按 UTF-8 解码会得到满屏乱码。
///
/// **build 24 修正（配置源加载）**：`metaCharset` 只对 HTML 生效。
/// 原实现不看 content-type，对任何响应都在前 4KB 里找 `charset=`，
/// 而 JSON 配置文件正文里随时可能出现 `"charset"` 字样（爬虫规则、ext 配置里都可能带），
/// 一旦命中就会把整份 UTF-8 配置按 GBK 解码 —— 中文全乱、JSON 结构被破坏，
/// 最终表现为「配置格式无法解析」。JSON 是结构性文本，编码只认 content-type。
enum BodyDecoder {
    static func decode(_ data: Data, contentType: String) -> String {
        if data.isEmpty { return "" }
        let isHTML = contentTypeLooksHTML(contentType) || looksLikeHTML(data)
        let declared = charsetName(in: contentType) ?? (isHTML ? metaCharset(in: data) : nil)
        if let declared = declared, let encoding = encoding(for: declared),
           let text = String(data: data, encoding: encoding) {
            return text
        }
        // UTF-8 优先：JSON / TXT 配置几乎都是 UTF-8，且 UTF-8 解码失败时才有必要回退。
        if let text = String(data: data, encoding: .utf8) { return text }
        // GBK / GB18030 回退：TVBox 圈子里不少配置文件是 Windows 记事本另存的 GBK。
        if let encoding = encoding(for: "gb18030"), let text = String(data: data, encoding: encoding) {
            return text
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    private static func contentTypeLooksHTML(_ contentType: String) -> Bool {
        let lowered = contentType.lowercased()
        return lowered.contains("text/html") || lowered.contains("application/xhtml")
    }

    /// content-type 缺失或为 octet-stream 时的兜底判据：看正文开头像不像 HTML。
    private static func looksLikeHTML(_ data: Data) -> Bool {
        let head = data.prefix(512)
        guard let text = String(data: head, encoding: .isoLatin1) else { return false }
        let lowered = text.lowercased()
        return lowered.contains("<!doctype html") || lowered.contains("<html")
    }

    private static func charsetName(in contentType: String) -> String? {
        guard let range = contentType.range(of: "charset=", options: .caseInsensitive) else { return nil }
        var value = String(contentType[range.upperBound...])
        if let semicolon = value.firstIndex(of: ";") { value = String(value[value.startIndex..<semicolon]) }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        return value.isEmpty ? nil : value.lowercased()
    }

    private static func metaCharset(in data: Data) -> String? {
        // 只看前 4KB，避免整页扫描。
        let head = data.prefix(4096)
        guard let text = String(data: head, encoding: .isoLatin1) else { return nil }
        let lowered = text.lowercased()
        guard let range = lowered.range(of: "charset=") else { return nil }
        let tail = text[range.upperBound...]
        var value = ""
        for ch in tail.prefix(24) {
            if ch == "\"" || ch == "'" || ch == ">" || ch == " " || ch == ";" { break }
            value.append(ch)
        }
        return value.isEmpty ? nil : value.lowercased()
    }

    private static func encoding(for charset: String) -> String.Encoding? {
        switch charset {
        case "utf-8", "utf8": return .utf8
        case "gbk", "gb2312", "gb18030", "x-gbk", "gb_2312-80": return gb18030
        case "big5": return big5
        case "iso-8859-1", "latin1": return .isoLatin1
        default: return nil
        }
    }

    /// CFString 编码表里的 GB18030（扩展到 0x0632）。
    private static let gb18030: String.Encoding = {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }()

    private static let big5: String.Encoding = {
        let cfEncoding = CFStringEncoding(CFStringEncodings.big5.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }()
}
