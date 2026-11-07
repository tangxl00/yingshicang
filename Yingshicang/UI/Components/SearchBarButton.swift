import UIKit

/// R-02 顶部搜索栏（ActionBarEx 的搜索入口）。
///
/// 布局事实：`layout_height=30dp`，左右外边距由父容器 padding 14dp 提供，
/// 圆角取搜索栏自身的 background 圆角（15dp，等于高度一半 → 胶囊形态）。
/// 文案「搜索影片、电视剧、综艺…」取自 strings.xml 的 search hint。
final class SearchBarButton: UIControl {

    private let iconView = UIImageView()
    private let hintLabel = UILabel.make(text: "搜索影片、电视剧、综艺…",
                                        size: 13,
                                        color: DesignTokens.Colors.text)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DesignTokens.Colors.inputBg
        layer.cornerRadius = DesignTokens.Corner.action
        layer.masksToBounds = true

        iconView.image = UIImage(systemName: "magnifyingglass")
        iconView.tintColor = DesignTokens.Colors.text
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.dp(10)),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: DesignTokens.dp(16)),
            iconView.heightAnchor.constraint(equalToConstant: DesignTokens.dp(16)),
            hintLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: DesignTokens.dp(6)),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -DesignTokens.dp(10)),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
