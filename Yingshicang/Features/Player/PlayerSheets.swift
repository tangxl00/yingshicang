import UIKit

/// R-18 解析弹窗（3 列解析源）与 R-19 轨道选择弹层。
///
/// 两者都是「列表 + 单选」形态，差异只在数据来源与尺寸：
/// - R-18：`parses[]`（配置里已入库的解析源），3 列网格
/// - R-19：音轨 / 字幕轨（`MediaTrackOption`），单列列表 300×250dp

// MARK: - R-18 解析弹层

/// 解析源条目（弹层展示用）。
struct ParseSheetEntry: Equatable {
    var index: Int
    var name: String
    var type: Int

    var listTitle: String {
        name.isEmpty ? "解析源 \(index + 1)" : name
    }

    var typeText: String {
        switch type {
        case 0: return "网页"
        case 1: return "JSON"
        default: return "聚合"
        }
    }
}

enum ParseSheetModel {

    /// 网格列数：与「chooseParse 弹层」的 3 列布局一致。
    static let columns = 3

    /// 由 `parses[]` 构造条目。空名兜底「解析源 N」。
    static func entries(from parses: [ParseConfig]) -> [ParseSheetEntry] {
        parses.enumerated().map { index, parse in
            ParseSheetEntry(index: index, name: parse.name, type: parse.type)
        }
    }

    /// 列宽：内容宽减去列间距后三等分（间距 8dp，向下取整避免累积误差超出容器）。
    static func itemWidth(containerWidth: CGFloat,
                          spacing: CGFloat = 8,
                          columns: Int = ParseSheetModel.columns) -> CGFloat {
        guard columns > 0 else { return 0 }
        let usable = max(0, containerWidth - spacing * CGFloat(columns - 1))
        return floor(usable / CGFloat(columns))
    }

    /// 标题文案：带上解析源总数，便于用户确认配置里确实有解析源。
    static func title(count: Int) -> String { "选择解析源（\(count)）" }
}

/// R-18 解析弹层：3 列解析源 + 首项「自动解析」。
/// 选中后把解析源下标交回播放页，由 `PlayResolver.applySecondaryParse` 执行二次解析。
final class ParseSheetViewController: CardDialogViewController {

    private let entries: [ParseSheetEntry]
    private var selected: Int?
    private var buttons: [UIButton] = []
    private let scroll = UIScrollView()
    private let grid = UIStackView.vertical(spacing: DesignTokens.dp(8))

    /// nil 表示「自动解析」（沿用站点自身规则）。
    var onSelect: ((Int?) -> Void)?

    init(parses: [ParseConfig], currentIndex: Int?) {
        self.entries = ParseSheetModel.entries(from: parses)
        self.selected = currentIndex
        super.init(config: Config(title: ParseSheetModel.title(count: parses.count),
                                  height: DesignTokens.Metrics.inputDialogHeight + 90,
                                  width: DesignTokens.Metrics.choosePlayPopupWidth))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func buildBody(into stack: UIStackView) {
        scroll.showsVerticalScrollIndicator = false
        stack.addArrangedSubview(scroll)
        scroll.addSubview(grid)
        grid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            grid.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            grid.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        rebuildGrid()
    }

    private func rebuildGrid() {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        var rowStack: UIStackView?
        var indexInRow = 0
        var order: [(Int?, String, String)] = [(nil, "自动解析", "站点规则")]
        for entry in entries {
            order.append((entry.index, entry.listTitle, entry.typeText))
        }

        for (selectIndex, title, subtitle) in order {
            if indexInRow == 0 {
                let row = UIStackView.horizontal(spacing: DesignTokens.dp(8))
                row.distribution = .fillEqually
                grid.addArrangedSubview(row)
                rowStack = row
            }
            guard let row = rowStack else { continue }
            let button = makeItem(title: title, subtitle: subtitle, selectIndex: selectIndex)
            row.addArrangedSubview(button)
            buttons.append(button)
            indexInRow += 1
            if indexInRow == ParseSheetModel.columns {
                indexInRow = 0
                rowStack = nil
            }
        }
        // 末行补齐占位，保持列宽一致
        if let row = rowStack, indexInRow > 0 {
            for _ in indexInRow..<ParseSheetModel.columns {
                row.addArrangedSubview(UIView())
            }
        }
    }

    private func makeItem(title: String, subtitle: String, selectIndex: Int?) -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = DesignTokens.Colors.cardWhite
        button.layer.cornerRadius = DesignTokens.Corner.sm
        button.layer.masksToBounds = true
        button.layer.borderWidth = 1
        button.layer.borderColor = (selected == selectIndex ? DesignTokens.Colors.main : UIColor.clear).cgColor
        button.heightAnchor.constraint(equalToConstant: DesignTokens.dp(56)).isActive = true

        let name = UILabel.make(text: title, size: DesignTokens.Metrics.sheetActionFont,
                                color: selectIndex == selected ? DesignTokens.Colors.main : .white, lines: 1)
        name.textAlignment = .center
        let type = UILabel.make(text: subtitle, size: 11, color: DesignTokens.Colors.text, lines: 1)
        type.textAlignment = .center

        let column = UIStackView.vertical(spacing: 2)
        column.addArrangedSubview(name)
        column.addArrangedSubview(type)
        column.isUserInteractionEnabled = false
        button.addSubview(column)
        column.pinEdges(to: button, insets: UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4))

        // 用 title 记录选择下标：nil 无法放 tag，故把「自动解析」记为 -1。
        button.tag = selectIndex ?? -1
        button.addTarget(self, action: #selector(tapItem(_:)), for: .touchUpInside)
        return button
    }

    @objc private func tapItem(_ sender: UIButton) {
        selected = sender.tag == -1 ? nil : sender.tag
        onSelect?(selected)
        handleClose()
    }
}

// MARK: - R-19 轨道选择弹层

/// 轨道弹层：音轨 / 字幕轨单选。字幕额外提供「关闭字幕」项。
final class TrackSheetViewController: CardDialogViewController, UITableViewDataSource, UITableViewDelegate {

    private let kind: MediaTrackKind
    private let options: [MediaTrackOption]
    private var selected: Int?
    private let table = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel.make(size: DesignTokens.Metrics.trackItemFont,
                                          color: DesignTokens.Colors.text, lines: 0)

    /// - Parameter selectedIndex: 传入 `nil` 表示「当前无显式选中」，按默认项高亮。
    var onSelect: ((Int?) -> Void)?

    init(kind: MediaTrackKind, options: [MediaTrackOption], selectedIndex: Int?) {
        self.kind = kind
        self.options = options
        self.selected = MediaTrackEnumerator.highlightedIndex(in: options, selectedIndex: selectedIndex)
        super.init(config: Config(title: kind.title,
                                  height: DesignTokens.Metrics.trackSheetHeight,
                                  width: DesignTokens.Metrics.trackSheetWidth))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 列表项数量：字幕多一条「关闭字幕」；无轨道时为 0（展示空态文案）。
    var rowCount: Int {
        guard !options.isEmpty else { return 0 }
        return options.count + (MediaTrackEnumerator.allowsOffOption(for: kind) ? 1 : 0)
    }

    override func buildBody(into stack: UIStackView) {
        stack.addArrangedSubview(table)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "track")

        emptyLabel.textAlignment = .center
        emptyLabel.text = "当前视频没有可切换的\(kind.title)"
        emptyLabel.isHidden = rowCount > 0
        stack.addArrangedSubview(emptyLabel)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rowCount }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "track", for: indexPath)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        if indexPath.row < options.count {
            let option = options[indexPath.row]
            cell.textLabel?.text = option.listTitle
            cell.textLabel?.textColor = option.index == selected ? DesignTokens.Colors.main : .white
        } else {
            cell.textLabel?.text = "关闭\(kind.title)"
            cell.textLabel?.textColor = DesignTokens.Colors.text
        }
        cell.textLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.trackItemFont))
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        DesignTokens.dp(DesignTokens.Metrics.trackItemHeight)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row < options.count {
            selected = options[indexPath.row].index
            onSelect?(selected)
        } else {
            // 「关闭字幕」→ 传 nil，由引擎取消选择 legible 轨道
            selected = nil
            onSelect?(nil)
        }
        handleClose()
    }
}
