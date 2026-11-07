import Foundation

/// R-05 搜索结果二次筛选：把关键词切成候选词，用户点选后对聚合结果做「全词命中」过滤。
///
/// 原行为（AXML search_activity）：搜索结果顶部出现关键词的候选词横条，
/// 点选后列表只保留片名/备注包含**全部**所选候选词的结果。中文无空格分词，
/// 原实现即按 2 字滑窗生成候选词，这里保持同一策略：
/// 「斗罗大陆」→ ["斗罗", "罗大", "大陆"]，另加关键词本身（去重）便于长词精确过滤。
enum SearchResultSecondaryFilter {

    /// 候选词：2-gram 滑窗（保序去重）+ 原词本身；单字关键词只有原词。
    static func tokens(from keyword: String) -> [String] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let chars = Array(trimmed)
        guard chars.count >= 2 else { return [trimmed] }

        var out: [String] = []
        var seen: Set<String> = [trimmed]
        var index = 0
        while index + 1 < chars.count {
            let gram = String(chars[index...index + 1])
            if seen.insert(gram).inserted {
                out.append(gram)
            }
            index += 1
        }
        out.append(trimmed)
        return out
    }

    /// 过滤：结果必须**同时包含全部**选中词（片名或备注任一字段命中即可），
    /// 大小写不敏感。未选词（空）时原样返回。
    static func filter(_ items: [VodItem], selectedTokens: [String]) -> [VodItem] {
        guard !selectedTokens.isEmpty else { return items }
        let tokens = selectedTokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return items }
        return items.filter { item in
            let haystack = item.vodName + " " + item.vodRemarks
            return tokens.allSatisfy { token in
                haystack.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}
