import UIKit

/// 站点切换弹层（P0「主页无限转圈」修复配套入口）。
///
/// 为什么需要它：真实配置（234 个站点）里有 168 个是 jar 类站点，iOS 无 Java 运行时，
/// 这些站点永远给不出内容。只提示「不支持」而不给切换入口，等于把用户留在死页面；
/// 只给切换入口而不标识可用性，用户就要逐个点 168 次才知道哪个能用。
/// 因此这里两件事一起做：**可用站点可选**、**不可用站点灰显并标注「不支持」**。
final class SiteSwitchSheetViewController: CardDialogViewController {

    private let sites: [SiteConfig]
    private let currentKey: String
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var rows: [SiteConfig] = []

    /// 选中站点回调（弹层关闭后主线程触发）。
    var onSelect: ((SiteConfig) -> Void)?

    init(sites: [SiteConfig], currentKey: String) {
        self.sites = sites
        self.currentKey = currentKey
        super.init(config: Config(title: "切换站点",
                                  height: DesignTokens.dp(420),
                                  anchor: .bottom,
                                  showsDragBar: true,
                                  showsCloseButton: false))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 排序口径：可用站点全部排在不可用站点之前，同组内保持配置原顺序。
    /// 抽成静态纯函数，便于单测在真实 m.json fixture 上验证「可用在前」。
    static func orderedRows(_ sites: [SiteConfig]) -> [SiteConfig] {
        let usable = sites.filter { $0.isPlatformSupported }
        let unusable = sites.filter { !$0.isPlatformSupported }
        return usable + unusable
    }

    /// 行文案：不可用站点必须带显式标识，不能只靠颜色（色弱与截图沟通都会失真）。
    static func rowTitle(for site: SiteConfig) -> String {
        let base = site.displayName
        return site.isPlatformSupported ? base : "\(base)（jar 插件·iOS 不支持）"
    }

    override func buildBody(into stack: UIStackView) {
        let hint = UILabel.make(text: "共 \(sites.count) 个站点，其中 \(sites.filter { $0.isPlatformSupported }.count) 个在 iOS 可用",
                                size: 12, color: DesignTokens.Colors.gray, lines: 2)
        hint.textAlignment = .center
        stack.addArrangedSubview(hint)

        rows = Self.orderedRows(sites)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "siteSwitch")
        stack.addArrangedSubview(tableView)
        tableView.heightAnchor.constraint(equalToConstant: DesignTokens.dp(330)).isActive = true
    }
}

extension SiteSwitchSheetViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "siteSwitch", for: indexPath)
        let site = rows[indexPath.row]
        let usable = site.isPlatformSupported
        cell.backgroundColor = .clear
        cell.textLabel?.text = Self.rowTitle(for: site)
        cell.textLabel?.font = .systemFont(ofSize: DesignTokens.sp(14))
        // 不可用站点灰显；可用站点白色，当前站点绿色。
        if !usable {
            cell.textLabel?.textColor = DesignTokens.Colors.gray
        } else if site.key == currentKey {
            cell.textLabel?.textColor = DesignTokens.Colors.main
        } else {
            cell.textLabel?.textColor = .white
        }
        // 不可用站点不给选中态：点它只会重复「不支持」提示，没有信息增量。
        cell.selectionStyle = usable ? .default : .none
        cell.accessoryType = site.key == currentKey ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        DesignTokens.dp(DesignTokens.Metrics.siteItemHeight)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let site = rows[indexPath.row]
        guard site.isPlatformSupported else { return }
        let callback = onSelect
        dismiss(animated: true) { callback?(site) }
    }
}
