import Foundation
import SwiftSoup

/// Android `pdfh` / `pdfa` / `pd` 三个宿主函数的 Swift 等价实现。
///
/// 语义（与 APK 内置 http.js + 模板.js 的用法反证一致，且与 U01Gate 的 cheerio 版对齐）：
/// - pdfh(html, rule)  → 命中的第一个元素的「文本或属性值」，单值字符串
/// - pdfa(html, rule)  → 命中的全部元素的「文本或属性值」，字符串数组
/// - pd(html, rule)    → 末端为属性名时取全部属性值（列表页链接提取），否则取元素完整 HTML
///
/// rule 语法：`A;B;C` 为多字段（从左到右取第一个有结果的字段）；
/// 某字段内 `x&&y&&z` 为逐级下钻；`||` 为**步骤级**并列候选（在每一步内部从左到右取第一个命中的）；
/// `body` / `html` 步骤表示文档根（不作为后代选择器执行，与 U01Gate JS driver 一致）；
/// 字段末段若为纯标识符则按属性名取值（`Text`/`Html` 特判为文本/innerHTML），`:eq(n)` 为 0 基索引。
final class HTMLSelector {

    static let shared = HTMLSelector()

    /// 解析一段 HTML 文本（容错：不完整标签交给 SwiftSoup 自愈）。
    func parse(_ html: String) -> Document? {
        guard !html.isEmpty else { return nil }
        return try? SwiftSoup.parse(html)
    }

    // MARK: - pdfh

    /// 取第一个匹配值。
    func pdfh(_ html: String, _ rule: String) -> String {
        guard let doc = parse(html) else { return "" }
        return pdfh(doc, rule)
    }

    func pdfh(_ doc: Document, _ rule: String) -> String {
        for field in HTMLRule.splitFields(rule) {
            let outcome = runChain(doc, field)
            if outcome.isValueTerminal {
                if let first = outcome.values.first, !first.isEmpty { return first }
                continue
            }
            // 末段是选择器：取第一个元素的文本；链接类元素文本为空时回退 href（drpy 惯例）。
            if let first = outcome.nodes.first {
                let text = first.text
                if !text.isEmpty { return text }
                let href = first.attrAny(attributeAliases("href"))
                if !href.isEmpty { return href }
            }
        }
        return ""
    }

    // MARK: - pdfa

    /// 取全部匹配值。
    func pdfa(_ html: String, _ rule: String) -> [String] {
        guard let doc = parse(html) else { return [] }
        return pdfa(doc, rule)
    }

    func pdfa(_ doc: Document, _ rule: String) -> [String] {
        for field in HTMLRule.splitFields(rule) {
            let outcome = runChain(doc, field)
            if outcome.isValueTerminal {
                let values = outcome.values.filter { !$0.isEmpty }
                if !values.isEmpty { return values }
                continue
            }
            let texts = outcome.nodes.map { $0.text }.filter { !$0.isEmpty }
            if !texts.isEmpty { return texts }
        }
        return []
    }

    // MARK: - pd

    /// 末端为属性名 → 全部属性值；末端为选择器 → 全部元素 HTML。
    func pd(_ html: String, _ rule: String) -> [String] {
        guard let doc = parse(html) else { return [] }
        return pd(doc, rule)
    }

    func pd(_ doc: Document, _ rule: String) -> [String] {
        for field in HTMLRule.splitFields(rule) {
            let outcome = runChain(doc, field)
            if outcome.isValueTerminal {
                let values = outcome.values.filter { !$0.isEmpty }
                if !values.isEmpty { return values }
                continue
            }
            let htmls = outcome.nodes.map { $0.outerHtml.isEmpty ? $0.html : $0.outerHtml }
            if !htmls.isEmpty { return htmls }
        }
        return []
    }

    // MARK: - 内部

    /// 一条链（单个字段）的执行结果。
    private struct ChainOutcome {
        /// 末端是属性名 / Text / Html 时的取值结果。
        var values: [String] = []
        /// 末端是选择器时的最终元素集合。
        var nodes: [HTMLElementNode] = []
        /// 末端是否为「取值」语义。
        var isValueTerminal: Bool = false
    }

    /// 执行单个字段（`x&&y&&z` 一条完整下钻链）。
    ///
    /// 层级：字段 → 步骤（`&&`）→ 步骤内候选（`||`）。
    /// `body`/`html` 步骤映射到文档根；末端纯标识符按属性取值。
    private func runChain(_ doc: Document, _ field: String) -> ChainOutcome {
        let steps = HTMLRule.splitChain(field)
        guard !steps.isEmpty else { return ChainOutcome() }

        var nodes = rootNodes(doc)
        for (index, step) in steps.enumerated() {
            let isLast = index == steps.count - 1
            let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)

            // `body`/`html` 步骤 = 文档根（U01Gate JS driver 同款语义），
            // 不作为后代选择器执行——SwiftSoup 的 select 是后代语义，直接选 body 会落空。
            if !isLast, trimmed == "body" || trimmed == "html" {
                nodes = rootNodes(doc)
                continue
            }

            // 末端取值：属性名 / Text / Html（含步骤级 `||` 候选，如 `href||data-href`）。
            if isLast, HTMLRule.looksLikeAttribute(trimmed) {
                let alternatives = HTMLRule.splitAlternatives(trimmed)
                var values: [String] = []
                for node in nodes {
                    if let value = terminalValue(for: node, alternatives: alternatives) {
                        values.append(value)
                    }
                }
                var outcome = ChainOutcome()
                outcome.values = values
                outcome.nodes = nodes
                outcome.isValueTerminal = true
                return outcome
            }

            // 下钻步骤：步骤内 `||` 候选从左到右取第一个命中的。
            let alternatives = HTMLRule.splitAlternatives(trimmed)
            var matched: [HTMLElementNode] = []
            for alt in alternatives {
                let selected = selectAll(alt, in: nodes)
                if !selected.isEmpty {
                    matched = selected
                    break
                }
            }
            if matched.isEmpty { return ChainOutcome() }
            nodes = matched
        }

        var outcome = ChainOutcome()
        outcome.nodes = nodes
        return outcome
    }

    /// 末端取值：对单个元素依次尝试候选（Text / Html / 属性名），返回第一个非空值。
    private func terminalValue(for node: HTMLElementNode, alternatives: [String]) -> String? {
        for alt in alternatives {
            if HTMLRule.isTextToken(alt) {
                let text = node.text
                if !text.isEmpty { return text }
            } else if HTMLRule.isHtmlToken(alt) {
                let html = node.html
                if !html.isEmpty { return html }
            } else {
                let value = node.attrAny(attributeAliases(alt))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private func rootNodes(_ doc: Document) -> [HTMLElementNode] {
        guard let body = doc.body() else { return [] }
        return [HTMLElementNode(element: body)]
    }

    /// 在一组元素上应用一条选择器步骤。
    /// 支持：普通选择器、`:eq(n)` 伪类（0 基，取全局第 n 个）。
    private func selectAll(_ step: String, in nodes: [HTMLElementNode]) -> [HTMLElementNode] {
        var working = step.trimmingCharacters(in: .whitespaces)
        guard !working.isEmpty else { return nodes }

        var eqIndex: Int?
        if let range = working.range(of: ":eq(", options: .backwards), working.hasSuffix(")") {
            let inner = working[range.upperBound..<working.index(before: working.endIndex)]
            if let n = Int(inner.trimmingCharacters(in: .whitespaces)) {
                eqIndex = n
                working = String(working[working.startIndex..<range.lowerBound])
            }
        }

        // SwiftSoup 的 Element.select 是「本元素的后代」语义，与 Android Jsoup 一致，
        // 所以可以逐个容器 select 后拼接结果。
        var results: [HTMLElementNode] = []
        for node in nodes {
            guard let matched = try? node.element.select(working) else { continue }
            for element in matched.array() {
                results.append(HTMLElementNode(element: element))
            }
        }

        if let index = eqIndex {
            return index < results.count ? [results[index]] : []
        }
        return results
    }

    /// 属性名别名：采集站规则里 `src` 实际常取 `data-src` / `data-original`。
    private func attributeAliases(_ name: String) -> [String] {
        switch name.lowercased() {
        case "src": return ["src", "data-src", "data-original", "data-echo"]
        case "href": return ["href", "data-href"]
        case "pic": return ["pic", "src", "data-src"]
        default: return [name]
        }
    }
}
