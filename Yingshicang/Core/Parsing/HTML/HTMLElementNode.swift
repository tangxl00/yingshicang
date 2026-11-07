import Foundation
import SwiftSoup

/// 对 SwiftSoup 元素的轻量包装。
/// 引入包装层的目的：JS 桥需要把结果交给 JavaScriptCore，
/// SwiftSoup 的 Element 不能直接过桥，且需要保留「文本/属性」歧义，
/// 所以统一在这一层收敛为 (元素, 文本, 属性字典) 三件套。
struct HTMLElementNode {
    let element: Element

    var text: String {
        (try? element.text()) ?? ""
    }

    var html: String {
        (try? element.html()) ?? ""
    }

    var outerHtml: String {
        (try? element.outerHtml()) ?? ""
    }

    func attr(_ name: String) -> String {
        (try? element.attr(name)) ?? ""
    }

    /// 取属性的多种常见别名：图片规则里 src / data-src / _src 都会出现。
    func attrAny(_ names: [String]) -> String {
        for name in names {
            let value = attr(name)
            if !value.isEmpty { return value }
        }
        return ""
    }
}
