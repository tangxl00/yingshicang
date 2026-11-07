import UIKit

/// 底部 Tab 栏的自绘实现（对应 mobile_home_tab.xml）。
/// 尺寸全部来自布局：栏高 55pt（由外部约束）、paddingTop 5pt、等分、文字 12sp、
/// 图标在文字上方（原布局用 drawableTop），选中态改变图标与文字颜色。
///
/// **v2.0.50 build 21 按用户要求收敛为 3 个 Tab**（主页 / 历史·收藏 / 我的）：
/// 「直播」「短视频」两项连同其页面一并移除，不再出现在此列表里。
final class TabBarView: UIView {

    /// Tab 文案与顺序（3 项；等分由 UIStackView .fillEqually 保证）。
    /// 声明为 `static` 以便单测直接断言条数（`MainTabBarTests`）。
    static let tabTitles = ["主页", "历史·收藏", "我的"]
    /// 图标用 SF Symbols 对齐原图标语义（原图标为位图，iOS 侧使用系统符号保持同一观感）。
    static let tabIcons = ["house.fill", "clock.fill", "person.fill"]

    private var titles: [String] { Self.tabTitles }
    private var icons: [String] { Self.tabIcons }

    private var buttons: [UIButton] = []
    var onSelect: ((Int) -> Void)?
    var selectedIndex: Int = 0 {
        didSet { updateSelection() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = DesignTokens.Colors.mainBg
        // 顶部分隔线：原布局在 Tab 栏上方有一层深色分隔，这里用 0.5pt 细线表达层级。
        let separator = UIView()
        separator.backgroundColor = DesignTokens.Colors.separator
        addSubview(separator)
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        // 布局里的 paddingTop=5dp 落在内容层，这里用容器 insets 表达。
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: DesignTokens.Metrics.tabBarPaddingTop),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        ])

        for (index, title) in titles.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.tabBarFont))
            // 图标上、文字下：iOS 15 起 UIButton.Configuration 支持 vertical 排列。
            var config = UIButton.Configuration.plain()
            config.title = title
            config.image = UIImage(systemName: icons[index])
            config.imagePlacement = .top
            config.imagePadding = 2
            config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)
            config.baseForegroundColor = DesignTokens.Colors.text
            config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.tabBarFont))
            ]))
            button.configuration = config
            button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        updateSelection()
    }

    @objc private func tap(_ sender: UIButton) {
        selectedIndex = sender.tag
        onSelect?(sender.tag)
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            let isSelected = index == selectedIndex
            let color = isSelected ? DesignTokens.Colors.main : DesignTokens.Colors.text
            let title = titles[index]
            var config = button.configuration
            config?.baseForegroundColor = color
            config?.attributedTitle = AttributedString(title, attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.tabBarFont),
                                        weight: isSelected ? .medium : .regular),
                .foregroundColor: color
            ]))
            button.configuration = config
        }
    }
}
