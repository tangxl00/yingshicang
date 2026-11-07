import Foundation

/// 「二级」详情规则的统一表示。
///
/// 模板.js 给出的二级规则有两种写法：
/// ① JSON 对象：`{"title":"h2&&Text","img":".vodlist_thumb&&data-original","desc":"...","content":"...","tabs":"...","lists":"..."}`
/// ② 分号串：`title;img;desc;content;tabs;lists` 六段（部分老站用这种简写）
/// 两者都要支持，否则相当一部分现有配置无法解析。
struct DetailRule {
    var title: String = ""
    var img: String = ""
    var desc: String = ""
    var content: String = ""
    var tabs: String = ""
    var lists: String = ""
    var score: String = ""
    var year: String = ""
    var area: String = ""
    var type: String = ""

    init(raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 形态一：JSON 对象
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            title = stringValue(object["title"])
            img = stringValue(object["img"])
            desc = stringValue(object["desc"])
            content = stringValue(object["content"])
            tabs = stringValue(object["tabs"])
            lists = stringValue(object["lists"])
            score = stringValue(object["score"])
            year = stringValue(object["year"])
            area = stringValue(object["area"])
            type = stringValue(object["type"])
            // desc 里常混入评分/年份/地区/类型四项，用分号拆开分别兜底。
            if score.isEmpty, let first = HTMLRule.splitFields(desc).first { score = "" }
            if year.isEmpty { year = "" }
            return
        }

        // 形态二：分号六段
        let fields = HTMLRule.splitFields(trimmed)
        title = fields.count > 0 ? fields[0] : ""
        img = fields.count > 1 ? fields[1] : ""
        desc = fields.count > 2 ? fields[2] : ""
        content = fields.count > 3 ? fields[3] : ""
        tabs = fields.count > 4 ? fields[4] : ""
        lists = fields.count > 5 ? fields[5] : ""
    }

    /// JSON 里的值可能是字符串，也可能是数组（多个兜底选择器）。
    private func stringValue(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let list = value as? [String] { return list.joined(separator: ";") }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }
}
