import Foundation
import SwiftSoup

/// Android `pdfh` / `pdfa` / `pd` 三个宿主函数的 Swift 等价实现。
///
/// 语义（与 APK 内置 http.js + 模板.js 的用法反证一致）：
/// - pdfh(html, rule)  → 命中的第一个元素的「文本或属性值」，单值字符串
/// - pdfa(html, rule)  → 命中的全部元素的「文本或属性值」，字符串数组
/// - pd(html, rule)    → 取完整元素 HTML（`&&` 下钻中间层用）
///
/// rule 语法：`A;B;C` 为多字段；某字段内 `x&&y` 为逐级下钻；`x||y` 为并列候选。
/// 字段末段若形如 `:eq(n)` 则取第 n 个；若为 `Text`/`Html` 则取文本/HTML；否则按属性名取值。
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
        for chain in HTMLRule.splitChain(rule) {
            for candidate in HTMLRule.splitAlternatives(chain) {
                if let value = resolve(doc, candidate), !value.isEmpty { return value }
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
        let steps = HTMLRule.splitChain(rule)
        guard !steps.isEmpty else { return [] }

        var nodes = rootNodes(doc)
        let containerSteps = steps.count > 1 ? Array(steps.dropLast()) : []
        for step in containerSteps {
            nodes = selectAll(step, in: nodes)
            if nodes.isEmpty { return [] }
        }

        let last = steps.last ?? ""

        // 末段是属性名 → 对每个元素取该属性。
        if HTMLRule.looksLikeAttribute(last) {
            if HTMLRule.isTextToken(last) {
                return nodes.map { $0.text }.filter { !$0.isEmpty }
            }
            if HTMLRule.isHtmlToken(last) {
                return nodes.map { $0.html }.filter { !$0.isEmpty }
            }
            let attrNames = attributeAliases(last)
            return nodes.map { $0.attrAny(attrNames) }.filter { !$0.isEmpty }
        }

        // 末段是选择器 → 在其内部再选，取当选元素的文本。
        let children = selectAll(last, in: nodes)
        return children.map { $0.text }.filter { !$0.isEmpty }
    }

    // MARK: - pd

    /// 取元素 HTML（多段规则时取最深一层）。
    func pd(_ html: String, _ rule: String) -> [String] {
        guard let doc = parse(html) else { return [] }
        return pd(doc, rule)
    }

    func pd(_ doc: Document, _ rule: String) -> [String] {
        for chain in HTMLRule.splitChain(rule) {
            for candidate in HTMLRule.splitAlternatives(chain) {
                let steps = HTMLRule.splitChain(candidate)
                var nodes = rootNodes(doc)
                for (index, step) in steps.enumerated() {
                    // 末段若为属性名，不参与选择，直接返回上一步元素的 HTML。
                    if index == steps.count - 1, HTMLRule.looksLikeAttribute(step) { break }
                    nodes = selectAll(step, in: nodes)
                    if nodes.isEmpty { break }
                }
                if !nodes.isEmpty {
                    return nodes.map { $0.outerHtml.isEmpty ? $0.html : $0.outerHtml }
                }
            }
        }
        return []
    }

    // MARK: - 内部

    /// 单个候选链求值，返回字符串。
    private func resolve(_ doc: Document, _ candidate: String) -> String? {
        let steps = HTMLRule.splitChain(candidate)
        guard !steps.isEmpty else { return nil }
        var nodes = rootNodes(doc)
        for (index, step) in steps.enumerated() {
            let isLast = index == steps.count - 1
            if isLast, HTMLRule.looksLikeAttribute(step) {
                guard let first = nodes.first else { return nil }
                if HTMLRule.isTextToken(step) { return first.text }
                if HTMLRule.isHtmlToken(step) { return first.html }
                let value = first.attrAny(attributeAliases(step))
                return value.isEmpty ? nil : value
            }
            nodes = selectAll(step, in: nodes)
            if nodes.isEmpty { return nil }
            if isLast {
                guard let first = nodes.first else { return nil }
                return first.text.isEmpty ? first.attr("href") : first.text
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
