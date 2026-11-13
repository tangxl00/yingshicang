import CommonCrypto
import Foundation

// MARK: - 配置载荷形态（字节流层识别结果）

/// 一份配置在**字节流层**呈现的形态。识别结果决定后续走哪个解码器。
///
/// 形态清单只收录在真实样本上验证过的类型（证据见 `Docs/CONFIG_FORMATS.md`）：
/// - `.plain`：直接就是 JSON / 带注释的 JSON（绝大多数配置源）；
/// - `.base64Preamble`：任意二进制前导 + `XXXXXXXX**` + base64（真实样本是 JPEG 头，
///   `http://www.饭太硬.cc/tv` 一类「图片伪装」配置）；
/// - `.aes2423`：整串十六进制，以 `2423` 开头，AES-128-CBC 密文，
///   密钥与 IV **内嵌在明文头部**（`$#key#$` + 末 13 位），不需要用户输入口令。
enum ConfigShape: Equatable {
    case plain
    case base64Preamble(marker: String, preambleByteCount: Int)
    case aes2423

    /// 用于错误提示与日志的形态名（**不含密钥**）。
    var displayName: String {
        switch self {
        case .plain: return "JSON 文本"
        case .base64Preamble: return "base64 包装配置（二进制前导 + `**` 标记）"
        case .aes2423: return "AES 加密配置（`2423` 头部）"
        }
    }
}

// MARK: - 传输层解码器

/// 把「拿到的字节」还原成「可交给 JSON 校验的文本」。
///
/// 分层口径（与 FongMi/TV `com.github.catvod.utils.Decoder#verify` 的真实派发顺序一致）：
/// 1. 字节归一：去 UTF-8 BOM 字节、去前导 NUL；
/// 2. base64 包装：**按字节**找 `[A-Za-z0-9]{8}**`，其后全部当作 base64 载荷；
/// 3. AES：明文以 `2423` 开头且为十六进制串；
/// 4. 其余按普通文本交给 `BodyDecoder`（UTF-8 → GB18030 回落）。
///
/// **为什么 base64 必须在字节层判**：真实样本的二进制前导会让严格 UTF-8 解码失败，
/// `BodyDecoder` 回落到 GB18030 时，前导里的 `\x84` 一类字节会按双字节消耗，
/// 把紧随其后的 ASCII 标记吞掉，`**` 标记在字符串里就消失了（实测 marker 为 nil）。
/// 因此标记检索必须发生在解码之前。
enum ConfigTransportDecoder {

    struct Output {
        /// 已还原的文本（plain 形态下就是 `BodyDecoder` 的结果）。
        var text: String
        var shape: ConfigShape
        /// 识别到了形态但还原失败时的真实原因（非 nil 时上层应直接报错）。
        var warning: String?
    }

    static func decode(data: Data, contentType: String) -> Output {
        let bytes = stripPreamble([UInt8](data))
        if let found = marker(in: bytes), let payload = base64Payload(bytes, from: found.end) {
            let text = BodyDecoder.decode(payload, contentType: "application/json")
            let preambleCount = max(0, found.start)
            if text.contains("{") || text.contains("[") {
                return Output(text: text,
                              shape: .base64Preamble(marker: found.marker, preambleByteCount: preambleCount),
                              warning: nil)
            }
        }
        let text = BodyDecoder.decode(Data(bytes), contentType: contentType)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("2423") {
            let result = aes2423Decrypt(trimmed)
            return Output(text: result.text ?? trimmed, shape: .aes2423, warning: result.warning)
        }
        return Output(text: text, shape: .plain, warning: nil)
    }

    // MARK: 字节归一

    private static func stripPreamble(_ bytes: [UInt8]) -> [UInt8] {
        var out = bytes
        // UTF-8 BOM：EF BB BF
        if out.count >= 3, out[0] == 0xEF, out[1] == 0xBB, out[2] == 0xBF { out.removeFirst(3) }
        // 前导 NUL（部分抓取工具会塞 0x00 填充）
        while let first = out.first, first == 0x00 { out.removeFirst() }
        return out
    }

    // MARK: base64 包装

    /// 找 `XXXXXXXX**`：前 8 字节必须是 ASCII 字母数字，标记后必须有足够载荷。
    private static func marker(in bytes: [UInt8]) -> (marker: String, start: Int, end: Int)? {
        guard bytes.count > 16 else { return nil }
        var index = 0
        while index + 1 < bytes.count {
            if bytes[index] == 0x2A, bytes[index + 1] == 0x2A,
               index >= 8, bytes.count - (index + 2) >= 16,
               isASCIIAlnum(bytes[(index - 8)..<index]) {
                let marker = String(decoding: bytes[(index - 8)..<index], as: UTF8.self)
                return (marker, index - 8, index + 2)
            }
            index += 1
        }
        return nil
    }

    private static func isASCIIAlnum(_ slice: ArraySlice<UInt8>) -> Bool {
        for byte in slice {
            let isDigit = byte >= 0x30 && byte <= 0x39
            let isUpper = byte >= 0x41 && byte <= 0x5A
            let isLower = byte >= 0x61 && byte <= 0x7A
            if !(isDigit || isUpper || isLower) { return false }
        }
        return true
    }

    /// 标记之后取 base64 字母表内的字节，补齐 4 的倍数后解码。
    /// 用「收集合法字符」而不是直接切片，是因为配置尾部常带换行 / 空白 / 误加的 HTML 尾巴。
    private static func base64Payload(_ bytes: [UInt8], from start: Int) -> Data? {
        guard start < bytes.count else { return nil }
        var collected: [UInt8] = []
        collected.reserveCapacity(bytes.count - start)
        for byte in bytes[start...] {
            let isBase64 = (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A)
                || (byte >= 0x30 && byte <= 0x39)
                || byte == 0x2B || byte == 0x2F || byte == 0x3D
            if isBase64 { collected.append(byte) }
        }
        guard collected.count >= 16 else { return nil }
        while collected.count % 4 != 0 { collected.append(0x3D) }
        return Data(base64Encoded: Data(collected))
    }

    // MARK: AES（2423 头部）

    /// FongMi `Decoder#cbc` 的同构实现：
    /// - 整串十六进制 → 字节 → UTF-8 文本 → 小写；
    /// - key = `$#` 与 `#$` 之间的内容，右侧补 `0` 到 16 字节；
    /// - iv = 文本末 13 位，右侧补 `0` 到 16 字节；
    /// - 密文 = 首个 `2324` 之后、截掉末尾 26 位十六进制的部分；
    /// - AES/CBC/PKCS7。
    ///
    /// 密钥是**内嵌**的，不来自用户，因此不需要口令弹窗；也绝不在日志/提示里回显。
    static func aes2423Decrypt(_ text: String) -> (text: String?, warning: String?) {
        guard let raw = hexBytes(text) else {
            return (nil, "AES 配置头部不是合法的十六进制串（长度 \(text.count) 字符），无法解密")
        }
        let header = String(decoding: raw, as: UTF8.self).lowercased()
        guard let keyStart = header.range(of: "$#"), let keyEnd = header.range(of: "#$"),
              keyStart.upperBound <= keyEnd.lowerBound else {
            return (nil, "AES 配置头部缺少 `$#… #$` 密钥段，无法解密")
        }
        let keyRaw = String(header[keyStart.upperBound..<keyEnd.lowerBound])
        guard !keyRaw.isEmpty else {
            return (nil, "AES 配置头部的密钥段为空，无法解密")
        }
        let key = padEnd(keyRaw)
        let iv = padEnd(String(header.suffix(13)))
        guard let cut = text.range(of: "2324") else {
            return (nil, "AES 配置缺少 `2324` 密文分隔标记，无法解密")
        }
        let cipherHex = String(text[cut.upperBound...])
        guard cipherHex.count > 26 else {
            return (nil, "AES 配置密文段不足（剩余 \(cipherHex.count) 字符），无法解密")
        }
        let cipherPart = String(cipherHex.dropLast(26))
        guard let cipher = hexBytes(cipherPart) else {
            return (nil, "AES 配置密文不是合法的十六进制串，无法解密")
        }
        guard cipher.count % 16 == 0, cipher.count >= 16 else {
            return (nil, "AES 配置密文长度 \(cipher.count) 字节，不是 16 的整数倍，无法解密")
        }
        guard let plain = aesCBCDecrypt(cipher: cipher, key: Array(key.utf8), iv: Array(iv.utf8)) else {
            return (nil, "AES 配置解密失败（CBC 解密返回错误，密文可能已损坏）")
        }
        let plainText = String(decoding: plain, as: UTF8.self)
        guard plainText.contains("{") else {
            return (nil, "AES 配置解密结果不是 JSON 文本，密钥派生与密文不匹配")
        }
        return (plainText, nil)
    }

    private static func padEnd(_ value: String) -> String {
        if value.count >= 16 { return String(value.prefix(16)) }
        let padding = "0000000000000000"
        return value + padding.prefix(16 - value.count)
    }

    private static func hexBytes(_ text: String) -> [UInt8]? {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count % 2 == 0, !scalars.isEmpty else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(scalars.count / 2)
        var index = 0
        while index < scalars.count {
            guard let high = hexValue(scalars[index]), let low = hexValue(scalars[index + 1]) else { return nil }
            out.append(high << 4 | low)
            index += 2
        }
        return out
    }

    private static func hexValue(_ scalar: Unicode.Scalar) -> UInt8? {
        switch scalar.value {
        case 0x30...0x39: return UInt8(scalar.value - 0x30)
        case 0x61...0x66: return UInt8(scalar.value - 0x61 + 10)
        case 0x41...0x46: return UInt8(scalar.value - 0x41 + 10)
        default: return nil
        }
    }

    private static func aesCBCDecrypt(cipher: [UInt8], key: [UInt8], iv: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: cipher.count + 16)
        var outLength = 0
        let status = CCCrypt(CCOperation(kCCDecrypt),
                             CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionPKCS7Padding),
                             key, key.count,
                             iv,
                             cipher, cipher.count,
                             &out, out.count,
                             &outLength)
        guard status == kCCSuccess, outLength > 0 else { return nil }
        return Array(out.prefix(outLength))
    }
}

// MARK: - JSON5 / JS 对象字面量归一

/// 把生态里真实存在的「JS 对象字面量 / 类 JSON5」配置转成标准 JSON 文本。
///
/// 真实样本：`https://raw.githubusercontent.com/gsdlj/TVBox/main/4.txt`
/// （12,586 字节，`{spider:'…',sites:[{key:'t4public',…}]}` —— 未加引号的键 + 单引号字符串），
/// 严格 JSON 在 `line 1 column 2` 就失败；归一后是 77 个站点的合法配置。
///
/// 只做三件事，做不到就返回 nil（宁可明确报错，不做半吊子改写）：
/// 1. 单引号字符串 → 双引号字符串（转义内部双引号）；
/// 2. 后面跟 `:` 的裸标识符 → 加引号的键；
/// 3. 去掉 `,}` / `,]` 尾逗号。
enum JSON5Lite {

    /// 归一失败的原因（用于错误提示）。
    enum Unsupported: String, Error {
        case templateLiteral = "含模板字符串（反引号），属于 JS 表达式而非配置字面量"
        case unterminatedString = "字符串引号未闭合"
    }

    static func toJSON(_ text: String) -> Result<String, Unsupported> {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(text.unicodeScalars.count)
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            switch scalar {
            case "`":
                return .failure(.templateLiteral)
            case "\"":
                index = copyDoubleQuoted(scalars, from: index, into: &out)
                if index < 0 { return .failure(.unterminatedString) }
            case "'":
                let converted = convertSingleQuoted(scalars, from: index)
                guard let result = converted else { return .failure(.unterminatedString) }
                out.append(contentsOf: result.scalars)
                index = result.next
            default:
                if isWordStart(scalar) {
                    var end = index
                    while end < scalars.count, isWordBody(scalars[end]) { end += 1 }
                    let word = String(String.UnicodeScalarView(scalars[index..<end]))
                    var probe = end
                    while probe < scalars.count, isWhitespace(scalars[probe]) { probe += 1 }
                    let isKey = probe < scalars.count && scalars[probe] == ":" && !isLiteral(word)
                    if isKey {
                        out.append("\"")
                        out.append(contentsOf: word.unicodeScalars)
                        out.append("\"")
                    } else {
                        out.append(contentsOf: word.unicodeScalars)
                    }
                    index = end
                } else {
                    out.append(scalar)
                    index += 1
                }
            }
        }
        return .success(removeTrailingCommas(String(out)))
    }

    private static func copyDoubleQuoted(_ scalars: [Unicode.Scalar], from start: Int,
                                         into out: inout String.UnicodeScalarView) -> Int {
        var index = start
        out.append("\"")
        index += 1
        while index < scalars.count {
            let scalar = scalars[index]
            out.append(scalar)
            if scalar == "\\" {
                if index + 1 < scalars.count { out.append(scalars[index + 1]) }
                index += 2
                continue
            }
            if scalar == "\"" { return index + 1 }
            index += 1
        }
        return -1
    }

    private static func convertSingleQuoted(_ scalars: [Unicode.Scalar], from start: Int)
        -> (scalars: String.UnicodeScalarView, next: Int)? {
        var out = String.UnicodeScalarView()
        out.append("\"")
        var index = start + 1
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\\" {
                if index + 1 < scalars.count {
                    let next = scalars[index + 1]
                    out.append("\\")
                    out.append(next)
                    index += 2
                    continue
                }
                return nil
            }
            if scalar == "'" {
                out.append("\"")
                return (out, index + 1)
            }
            if scalar == "\"" {
                out.append("\\")
                out.append("\"")
                index += 1
                continue
            }
            out.append(scalar)
            index += 1
        }
        return nil
    }

    private static func isWordStart(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        let isDigit = value >= 0x30 && value <= 0x39
        let isUpper = value >= 0x41 && value <= 0x5A
        let isLower = value >= 0x61 && value <= 0x7A
        return isUpper || isLower || scalar == "_" || scalar == "$" || isDigit
    }

    private static func isWordBody(_ scalar: Unicode.Scalar) -> Bool {
        isWordStart(scalar)
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
    }

    private static func isLiteral(_ word: String) -> Bool {
        ["true", "false", "null", "undefined", "function"].contains(word)
    }

    private static func removeTrailingCommas(_ text: String) -> String {
        guard text.contains(",") else { return text }
        var out = String.UnicodeScalarView()
        let scalars = Array(text.unicodeScalars)
        var index = 0
        var inString = false
        var escaped = false
        while index < scalars.count {
            let scalar = scalars[index]
            if inString {
                out.append(scalar)
                if escaped { escaped = false }
                else if scalar == "\\" { escaped = true }
                else if scalar == "\"" { inString = false }
                index += 1
                continue
            }
            if scalar == "\"" {
                inString = true
                out.append(scalar)
                index += 1
                continue
            }
            if scalar == "," {
                var probe = index + 1
                while probe < scalars.count, isWhitespace(scalars[probe]) { probe += 1 }
                if probe < scalars.count, scalars[probe] == "}" || scalars[probe] == "]" {
                    index += 1
                    continue
                }
            }
            out.append(scalar)
            index += 1
        }
        return String(out)
    }
}
