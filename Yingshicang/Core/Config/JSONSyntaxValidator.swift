import Foundation

/// JSON 语法错误的可诊断描述：行号 + 列号 + 该行内容片段。
///
/// 存在的理由：`JSONSerialization` 的错误对象只给一句 "The data is not in the correct format."
/// 和凑整的 "around character 1234"（指向的是字节偏移，中文/emoji 场景下与实际位置对不上），
/// 用户完全无法据此定位配置里的哪一行坏了。这里做一次**自实现的最小 RFC 8259 校验**，
/// 只为了给出「第几行、这一行长什么样」，不参与正常解析路径。
struct JSONSyntaxError: Equatable {
    var message: String
    /// 1 基行号；0 表示无法确定。
    var line: Int
    /// 该行内容片段（已截断）。
    var snippet: String

    static func line(_ message: String, _ line: Int, _ snippet: String) -> JSONSyntaxError {
        JSONSyntaxError(message: message, line: line, snippet: snippet)
    }

    var display: String {
        if line > 0 {
            return "第 \(line) 行附近（\(message)）：\(snippet.isEmpty ? "<空>" : snippet)"
        }
        return message
    }
}

/// 最小 RFC 8259 校验器，只负责定位第一处语法错误。
enum JSONSyntaxValidator {

    static func firstError(in text: String) -> JSONSyntaxError {
        let scalars = Array(text.unicodeScalars)
        var index = 0
        var state = State(scalars: scalars, text: text)
        defer { _ = state }
        do {
            try parseValue(&state, &index)
            try skipWhitespace(&state, &index)
            if index < scalars.count {
                throw Fault.unexpected("JSON 结束后还有多余内容", index)
            }
            return JSONSyntaxError(message: "无法解析为 JSON", line: 0, snippet: "")
        } catch let fault as Fault {
            switch fault {
            case .unexpected(let message, let at):
                return describe(text: text, at: at, message: message)
            }
        } catch {
            return JSONSyntaxError(message: "无法解析为 JSON", line: 0, snippet: "")
        }
    }

    // MARK: - 内部

    private struct State {
        let scalars: [Unicode.Scalar]
        let text: String
        var inString = false
        var escaped = false
    }

    private enum Fault: Error {
        case unexpected(String, Int)
    }

    private static func skipWhitespace(_ state: inout State, _ index: inout Int) throws {
        while index < state.scalars.count {
            let v = state.scalars[index].value
            guard v == 0x20 || v == 0x09 || v == 0x0A || v == 0x0D else { return }
            index += 1
        }
    }

    private static func parseValue(_ state: inout State, _ index: inout Int) throws {
        try skipWhitespace(&state, &index)
        guard index < state.scalars.count else {
            throw Fault.unexpected("内容意外结束", index)
        }
        let scalar = state.scalars[index]
        switch scalar {
        case "{":
            try parseObject(&state, &index)
        case "[":
            try parseArray(&state, &index)
        case "\"":
            try parseString(&state, &index)
        case "t", "f", "n":
            try parseLiteral(&state, &index)
        case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            try parseNumber(&state, &index)
        default:
            throw Fault.unexpected("非法值起始字符「\(scalar)」", index)
        }
    }

    private static func parseLiteral(_ state: inout State, _ index: inout Int) throws {
        let remaining = state.scalars[index...].map { String($0) }.joined()
        for literal in ["true", "false", "null"] where remaining.hasPrefix(literal) {
            index += literal.unicodeScalars.count
            return
        }
        throw Fault.unexpected("非法字面量", index)
    }

    private static func parseNumber(_ state: inout State, _ index: inout Int) throws {
        let start = index
        if index < state.scalars.count, state.scalars[index] == "-" { index += 1 }
        guard index < state.scalars.count else {
            throw Fault.unexpected("数字不完整", start)
        }
        if state.scalars[index] == "0" {
            index += 1
        } else if state.scalars[index].value >= 0x31 && state.scalars[index].value <= 0x39 {
            while index < state.scalars.count, isDigit(state.scalars[index]) { index += 1 }
        } else {
            throw Fault.unexpected("数字格式非法", start)
        }
        if index < state.scalars.count, state.scalars[index] == "." {
            index += 1
            guard index < state.scalars.count, isDigit(state.scalars[index]) else {
                throw Fault.unexpected("小数点后缺少数字", index)
            }
            while index < state.scalars.count, isDigit(state.scalars[index]) { index += 1 }
        }
        if index < state.scalars.count, state.scalars[index] == "e" || state.scalars[index] == "E" {
            index += 1
            if index < state.scalars.count, state.scalars[index] == "+" || state.scalars[index] == "-" {
                index += 1
            }
            guard index < state.scalars.count, isDigit(state.scalars[index]) else {
                throw Fault.unexpected("指数部分缺少数字", index)
            }
            while index < state.scalars.count, isDigit(state.scalars[index]) { index += 1 }
        }
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x30 && scalar.value <= 0x39
    }

    private static func parseString(_ state: inout State, _ index: inout Int) throws {
        guard index < state.scalars.count, state.scalars[index] == "\"" else {
            throw Fault.unexpected("此处应为字符串", index)
        }
        index += 1
        var escaped = false
        while index < state.scalars.count {
            let scalar = state.scalars[index]
            if escaped {
                escaped = false
                index += 1
                continue
            }
            if scalar == "\\" {
                escaped = true
                index += 1
                continue
            }
            if scalar == "\"" {
                index += 1
                return
            }
            if scalar.value < 0x20 {
                throw Fault.unexpected("字符串内出现未转义的控制字符", index)
            }
            index += 1
        }
        throw Fault.unexpected("字符串未闭合", index)
    }

    private static func parseObject(_ state: inout State, _ index: inout Int) throws {
        index += 1                                    // 跳过 {
        try skipWhitespace(&state, &index)
        if index < state.scalars.count, state.scalars[index] == "}" { index += 1; return }
        while true {
            try skipWhitespace(&state, &index)
            guard index < state.scalars.count, state.scalars[index] == "\"" else {
                throw Fault.unexpected("对象键必须是双引号字符串", index)
            }
            try parseString(&state, &index)
            try skipWhitespace(&state, &index)
            guard index < state.scalars.count, state.scalars[index] == ":" else {
                throw Fault.unexpected("键后缺少冒号", index)
            }
            index += 1
            try parseValue(&state, &index)
            try skipWhitespace(&state, &index)
            guard index < state.scalars.count else {
                throw Fault.unexpected("对象未闭合", index)
            }
            if state.scalars[index] == "," {
                index += 1
                try skipWhitespace(&state, &index)
                continue
            }
            if state.scalars[index] == "}" {
                index += 1
                return
            }
            throw Fault.unexpected("对象成员之间缺少逗号或多出内容", index)
        }
    }

    private static func parseArray(_ state: inout State, _ index: inout Int) throws {
        index += 1                                    // 跳过 [
        try skipWhitespace(&state, &index)
        if index < state.scalars.count, state.scalars[index] == "]" { index += 1; return }
        while true {
            try parseValue(&state, &index)
            try skipWhitespace(&state, &index)
            guard index < state.scalars.count else {
                throw Fault.unexpected("数组未闭合", index)
            }
            if state.scalars[index] == "," {
                index += 1
                continue
            }
            if state.scalars[index] == "]" {
                index += 1
                return
            }
            throw Fault.unexpected("数组元素之间缺少逗号或多出内容", index)
        }
    }

    /// 把标量偏移换算成行号 + 该行内容片段。
    private static func describe(text: String, at scalarIndex: Int, message: String) -> JSONSyntaxError {
        // 用标量偏移在标量数组上换行计数，避免 Character/grapheme 与偏移不一致。
        let scalars = Array(text.unicodeScalars)
        var line = 1
        var lineStart = 0
        var i = 0
        while i < min(scalarIndex, scalars.count) {
            if scalars[i] == "\n" {
                line += 1
                lineStart = i + 1
            }
            i += 1
        }
        var lineEnd = lineStart
        while lineEnd < scalars.count, scalars[lineEnd] != "\n" { lineEnd += 1 }
        var view = String.UnicodeScalarView()
        for k in lineStart..<lineEnd { view.append(scalars[k]) }
        var snippet = String(view).trimmingCharacters(in: .whitespaces)
        if snippet.count > 80 {
            snippet = String(snippet.prefix(80)) + "…"
        }
        return JSONSyntaxError(message: message, line: line, snippet: snippet)
    }
}
