import UIKit

/// R-06 分类筛选（底部弹层）。
///
/// 数据格式（TVBox 系配置生态的通行格式，字段名 n / v / class / key / name 取自既有配置）：
/// `{"class":[{"key":"class","name":"类型","value":[{"n":"全部","v":""},{"n":"电影","v":"1"}]}]}`
/// 站点 `filter` 字段承载该 JSON；`filterUrl` 里的 `{filter}` 占位由 APISiteProvider 展开，
/// 这里只负责把用户选中值收集成 extend 参数（空值 =「全部」不进请求）。

struct FilterDimension: Equatable {
    let key: String
    let name: String
    let options: [FilterOption]
}

struct FilterOption: Equatable {
    let name: String
    let value: String
}

enum FilterSheetParser {

    /// 解析站点 filter JSON。兼容顶层 `{"class":[...]}` 与直接数组 `[...]` 两种形态；
    /// 解析失败 / 无可选项时返回空（UI 据此不弹筛选入口）。
    static func parse(_ json: String?) -> [FilterDimension] {
        guard let text = json?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let rawList: [[String: Any]]
        if let root = object as? [String: Any], let list = root["class"] as? [[String: Any]] {
            rawList = list
        } else if let list = object as? [[String: Any]] {
            rawList = list
        } else {
            return []
        }
        var out: [FilterDimension] = []
        for entry in rawList {
            guard let key = entry["key"] as? String, !key.isEmpty else { continue }
            let name = (entry["name"] as? String) ?? key
            var options: [FilterOption] = []
            if let values = entry["value"] as? [[String: Any]] {
                for value in values {
                    let n = (value["n"] as? String) ?? ""
                    let v = (value["v"] as? String) ?? ""
                    if !n.isEmpty { options.append(FilterOption(name: n, value: v)) }
                }
            }
            if !options.isEmpty {
                out.append(FilterDimension(key: key, name: name, options: options))
            }
        }
        return out
    }

    /// 选中值 → 分类请求的 extend 参数：值为空（即「全部」）的维度不进请求，
    /// 与原 App「全部 = 不带参数」的请求形态一致。
    static func extend(from selections: [String: String]) -> [String: String] {
        selections.filter { !$0.value.isEmpty }
    }

    /// 初始选中态：每个维度默认选第一项（通行约定第一项即「全部」）。
    static func defaultSelections(dimensions: [FilterDimension]) -> [String: String] {
        var out: [String: String] = [:]
        for dimension in dimensions {
            out[dimension.key] = dimension.options.first?.value ?? ""
        }
        return out
    }
}

/// R-06 筛选底部弹层：470dp（filterSheetHeight）+ 拖拽条 + 逐维度横排选项 + 重置/确定。
final class FilterSheetViewController: CardDialogViewController {

    private let dimensions: [FilterDimension]
    private var selections: [String: String]
    private var dimensionContent: UIStackView?
    /// 应用回调（主线程）：参数为已剔除空值的 extend 请求参数。
    var onApply: (([String: String]) -> Void)?

    init(dimensions: [FilterDimension]) {
        self.dimensions = dimensions
        self.selections = FilterSheetParser.defaultSelections(dimensions: dimensions)
        super.init(config: .init(title: "筛选",
                                 height: DesignTokens.dp(DesignTokens.Metrics.filterSheetHeight),
                                 anchor: .bottom,
                                 showsDragBar: true))
    }

    convenience init(site: SiteConfig?) {
        self.init(dimensions: FilterSheetParser.parse(site?.filter))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 供「重置」使用的初始态判断（可测试）：当前选择与默认态逐维比较。
    var isDefaultSelection: Bool {
        selections == FilterSheetParser.defaultSelections(dimensions: dimensions)
    }

    override func buildBody(into stack: UIStackView) {
        guard let card = stack.superview else { return }

        // 底部操作行：重置（sheetActionFont 16）+ 确定（confirmButtonHeight 45 / Corner 8）。
        let actionsRow = UIStackView.horizontal(spacing: DesignTokens.dp(10))
        actionsRow.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = UIButton(type: .system)
        resetButton.setTitle("重置", for: .normal)
        resetButton.setTitleColor(DesignTokens.Colors.text, for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.sheetActionFont))
        resetButton.backgroundColor = DesignTokens.Colors.cardWhite
        resetButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.confirmButtonCorner)
        resetButton.heightAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.confirmButtonHeight)).isActive = true
        resetButton.addTarget(self, action: #selector(resetSelections), for: .touchUpInside)
        actionsRow.addArrangedSubview(resetButton)

        let applyButton = UIButton(type: .system)
        applyButton.setTitle("确定", for: .normal)
        applyButton.setTitleColor(.white, for: .normal)
        applyButton.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.sheetActionFont), weight: .medium)
        applyButton.backgroundColor = DesignTokens.Colors.main
        applyButton.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.confirmButtonCorner)
        applyButton.heightAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.confirmButtonHeight)).isActive = true
        applyButton.addTarget(self, action: #selector(applySelections), for: .touchUpInside)
        actionsRow.addArrangedSubview(applyButton)

        resetButton.widthAnchor.constraint(equalTo: applyButton.widthAnchor, multiplier: 1).isActive = true
        card.addSubview(actionsRow)
        NSLayoutConstraint.activate([
            actionsRow.leadingAnchor.constraint(equalTo: card.leadingAnchor,
                                               constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            actionsRow.trailingAnchor.constraint(equalTo: card.trailingAnchor,
                                                constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            actionsRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -DesignTokens.dp(16))
        ])

        // 维度滚动区：钉在标题之下、操作行之上（不依赖魔数，高度自动填充剩余空间）。
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: stack.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: actionsRow.topAnchor, constant: -DesignTokens.dp(12))
        ])

        let content = UIStackView.vertical(spacing: DesignTokens.dp(14))
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: DesignTokens.dp(4)),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor,
                                            constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor,
                                             constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -DesignTokens.dp(4)),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor,
                                           constant: -DesignTokens.Metrics.actionBarHorizontalPadding * 2)
        ])

        rebuildDimensionRows(into: content)
        dimensionContent = content
    }

    private func rebuildDimensionRows(into content: UIStackView) {
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for dimension in dimensions {
            content.addArrangedSubview(makeDimensionRow(dimension))
        }
        if dimensions.isEmpty {
            content.addArrangedSubview(UILabel.make(text: "该站点没有可用的筛选项",
                                                    size: 13, color: DesignTokens.Colors.text, lines: 0))
        }
    }

    private func makeDimensionRow(_ dimension: FilterDimension) -> UIView {
        let row = UIStackView.vertical(spacing: DesignTokens.dp(6))
        row.addArrangedSubview(UILabel.make(text: dimension.name, size: 13,
                                            color: DesignTokens.Colors.text, weight: .medium))
        let pillScroll = UIScrollView()
        pillScroll.showsHorizontalScrollIndicator = false
        let pillStack = UIStackView.horizontal(spacing: DesignTokens.dp(8))
        pillStack.translatesAutoresizingMaskIntoConstraints = false
        pillScroll.addSubview(pillStack)
        NSLayoutConstraint.activate([
            pillStack.leadingAnchor.constraint(equalTo: pillScroll.contentLayoutGuide.leadingAnchor),
            pillStack.trailingAnchor.constraint(equalTo: pillScroll.contentLayoutGuide.trailingAnchor),
            pillStack.topAnchor.constraint(equalTo: pillScroll.contentLayoutGuide.topAnchor),
            pillStack.bottomAnchor.constraint(equalTo: pillScroll.contentLayoutGuide.bottomAnchor),
            pillStack.heightAnchor.constraint(equalTo: pillScroll.frameLayoutGuide.heightAnchor)
        ])
        let selected = selections[dimension.key] ?? ""
        for option in dimension.options {
            let button = UIButton.capsule(" \(option.name) ", size: 12, height: 30, corner: DesignTokens.Corner.xl)
            let isSelected = option.value == selected
            button.setTitleColor(isSelected ? .white : DesignTokens.Colors.text, for: .normal)
            button.backgroundColor = isSelected ? DesignTokens.Colors.main : DesignTokens.Colors.cardWhite
            button.addAction(UIAction { [weak self] _ in
                guard let self = self else { return }
                self.selections[dimension.key] = option.value
                self.rebuildAll()
            }, for: .touchUpInside)
            pillStack.addArrangedSubview(button)
        }
        row.addArrangedSubview(pillScroll)
        pillScroll.heightAnchor.constraint(equalToConstant: DesignTokens.dp(30)).isActive = true
        return row
    }

    /// 重建整棵内容树（维度少、行数小，整树重建的代价可忽略，换来选中态零漂移）。
    private func rebuildAll() {
        if let content = dimensionContent {
            rebuildDimensionRows(into: content)
        }
    }

    @objc private func resetSelections() {
        selections = FilterSheetParser.defaultSelections(dimensions: dimensions)
        rebuildAll()
    }

    @objc private func applySelections() {
        let extend = FilterSheetParser.extend(from: selections)
        let callback = onApply
        dismiss(animated: true) {
            DispatchQueue.main.async { callback?(extend) }
        }
    }
}
