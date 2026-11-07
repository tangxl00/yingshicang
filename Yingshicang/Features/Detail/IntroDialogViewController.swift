import UIKit

/// R-53 简介弹窗内文本检索的纯逻辑（与 UI 解耦，可单测）。
enum IntroTextSearcher {

    /// 在 `text` 中查找 `query` 的命中范围。
    /// - exact=false：子串匹配（大小写不敏感）；
    /// - exact=true：整词匹配（命中的前后必须是词边界——串端或非字母数字字符）；
    /// - 空白 query 返回空数组；结果按位置升序、不重叠。
    static func ranges(of query: String, in text: String, exact: Bool) -> [NSRange] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let ns = text as NSString
        guard trimmed.count <= ns.length else { return [] }
        var result: [NSRange] = []
        var cursor = 0
        while cursor <= ns.length {
            let scope = NSRange(location: cursor, length: ns.length - cursor)
            guard scope.length >= trimmed.count else { break }
            let found = ns.range(of: trimmed,
                                 options: [.caseInsensitive, .literal],
                                 range: scope)
            if found.location == NSNotFound { break }
            if !exact || hasWordBoundary(ns, around: found) {
                result.append(found)
            }
            cursor = found.location + max(found.length, 1)
        }
        return result
    }

    /// 命中片段前后均不为「词字符」（字母/数字）才视作整词匹配；串端视为边界。
    private static func hasWordBoundary(_ ns: NSString, around range: NSRange) -> Bool {
        if range.location > 0, isWordChar(ns.character(at: range.location - 1)) { return false }
        let after = range.location + range.length
        if after < ns.length, isWordChar(ns.character(at: after)) { return false }
        return true
    }

    /// 词边界字符：仅 ASCII 字母/数字构成词边界；中日韩字符间不构成边界
    /// （否则中文关键词在中文简介里永远无法整词命中，精确搜索形同虚设）。
    private static func isWordChar(_ ch: unichar) -> Bool {
        guard ch < 128 else { return false }
        let isDigit = ch >= 0x30 && ch <= 0x39
        let isUpper = ch >= 0x41 && ch <= 0x5A
        let isLower = ch >= 0x61 && ch <= 0x7A
        return isDigit || isUpper || isLower
    }
}

/// R-53 独立视频简介弹窗：完整展示 vodContent（详情页简介区 4 行截断，点击进入本弹窗看全文）。
/// 顶部为搜索栏形态：24dp 搜索图标 + 30dp 高 12sp 输入框 + 40×24dp「精确」按钮；
/// 搜索命中的片段以主色高亮并滚动到首个命中；「精确」切换为整词匹配。
final class IntroDialogViewController: CardDialogViewController {

    private let fullText: String
    private var highlights: [NSRange] = []
    private var highlightIndex = 0

    private let searchField = UITextField()
    private lazy var exactButton: UIButton = UIButton.capsule("精确",
                                                              size: DesignTokens.Metrics.introSearchFont,
                                                              height: DesignTokens.Metrics.introExactHeight,
                                                              corner: 6)
    private let scrollView = UIScrollView()
    private let contentLabel = UILabel.make(size: DesignTokens.Metrics.previewDescFont,
                                            color: DesignTokens.Colors.text,
                                            weight: .regular,
                                            lines: 0)

    init(vodName: String, content: String) {
        self.fullText = content
        super.init(config: Config(title: vodName.isEmpty ? "简介" : vodName,
                                  height: DesignTokens.dp(440),
                                  anchor: .center))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func buildBody(into stack: UIStackView) {
        // 搜索行：图标 24dp + 输入框（高 30dp、12sp）+ 精确按钮（40×24dp）
        let searchRow = UIStackView.horizontal(spacing: DesignTokens.dp(8))
        searchRow.alignment = .center

        let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        searchIcon.tintColor = DesignTokens.Colors.gray
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchIcon.widthAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.introIconSize)),
            searchIcon.heightAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.introIconSize))
        ])

        searchField.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.introSearchFont))
        searchField.textColor = DesignTokens.Colors.text
        searchField.attributedPlaceholder = NSAttributedString(
            string: "搜索简介内容",
            attributes: [.foregroundColor: DesignTokens.Colors.gray])
        searchField.returnKeyType = .search
        searchField.delegate = self
        searchField.backgroundColor = DesignTokens.Colors.cardWhite
        searchField.layer.cornerRadius = DesignTokens.dp(8)
        let fieldWrap = UIView()
        fieldWrap.addSubview(searchField)
        searchField.pinEdges(to: fieldWrap, insets: UIEdgeInsets(top: 0, left: DesignTokens.dp(10),
                                                                bottom: 0, right: DesignTokens.dp(10)))
        searchField.heightAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.introSearchHeight)).isActive = true
        fieldWrap.heightAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.introSearchHeight)).isActive = true

        // exactButton 为 lazy var：首次访问（此处）时按精确按钮规格构建。
        exactButton.widthAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.introExactWidth)).isActive = true
        exactButton.addAction(UIAction { [weak self] _ in
            self?.runSearch(exact: true)
        }, for: .touchUpInside)

        searchRow.addArrangedSubview(searchIcon)
        searchRow.addArrangedSubview(fieldWrap)
        searchRow.addArrangedSubview(exactButton)
        stack.addArrangedSubview(searchRow)

        // 简介全文：可滚动，行数不限
        contentLabel.text = fullText
        scrollView.showsVerticalScrollIndicator = true
        scrollView.addSubview(contentLabel)
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentLabel.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        stack.addArrangedSubview(scrollView)
        scrollView.heightAnchor.constraint(equalToConstant: DesignTokens.dp(320)).isActive = true
    }

    /// 执行搜索：exact=false 子串 / true 整词；命中主色高亮并滚动到首个命中。
    func runSearch(exact: Bool) {
        applySearch(query: searchField.text ?? "", exact: exact)
    }

    /// 搜索主体（拆出便于回归测试直接驱动，不依赖输入框）。
    func applySearch(query: String, exact: Bool) {
        let ranges = IntroTextSearcher.ranges(of: query, in: fullText, exact: exact)
        highlights = ranges
        highlightIndex = 0

        let attributed = NSMutableAttributedString(string: fullText,
                                                    attributes: [.font: UIFont.systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.previewDescFont)),
                                                                 .foregroundColor: DesignTokens.Colors.text])
        for range in ranges {
            attributed.addAttribute(.foregroundColor, value: DesignTokens.Colors.main, range: range)
        }
        contentLabel.attributedText = attributed

        guard let first = ranges.first else { return }
        reveal(range: first)
    }

    /// 当前命中数量与指针（供回归测试断言搜索行为）。
    var highlightCount: Int { highlights.count }
    var currentHighlightIndex: Int { highlightIndex }
    /// 弹窗展示的完整简介文本（供回归断言未截断）。
    var displayedText: String { fullText }

    private func reveal(range: NSRange) {
        let font = UIFont.systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.previewDescFont))
        let prefix = (fullText as NSString).substring(to: range.location) as NSString
        let size = prefix.boundingRect(
            with: CGSize(width: max(scrollView.bounds.width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil)
        let target = max(0, size.height - DesignTokens.dp(40))
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.setContentOffset(CGPoint(x: 0, y: min(target, maxY)), animated: true)
    }
}

extension IntroDialogViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        runSearch(exact: false)
        return true
    }
}
