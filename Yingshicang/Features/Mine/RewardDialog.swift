import UIKit

/// R-33 赞赏弹窗文案与联系信息（独立成纯数据，便于测试与后续运营替换）。
enum RewardContent {
    static let title = "赞赏支持"
    static let body = """
    本应用免费开源，无任何内购与广告。如果它对你有帮助，可以通过下方二维码请作者喝杯咖啡，支持项目持续维护。
    """
    static let contactCopyText = "yingshicang@example.com"

    /// 二维码占位：未内置运营二维码图片时展示的提示文案。
    static let qrPlaceholderHint = "二维码占位（正式包替换为运营素材）"
}

/// R-33 赞赏弹窗：居中卡片，二维码占位 + 赞赏文案 + 复制联系方式。
/// 标题 18sp（shopTitleFont），加载圈 30×30（shopLoadingSize 口径以占位图标呈现）。
final class RewardDialogViewController: CardDialogViewController {
    init() {
        super.init(config: CardDialogViewController.Config(
            title: RewardContent.title,
            height: DesignTokens.dp(400),
            anchor: .center
        ))
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func buildBody(into stack: UIStackView) {
        let body = UILabel.make(text: RewardContent.body,
                                size: 13,
                                color: DesignTokens.Colors.text,
                                lines: 0)
        stack.addArrangedSubview(body)

        let qrHolder = UIView()
        qrHolder.backgroundColor = DesignTokens.Colors.cardWhite
        qrHolder.layer.cornerRadius = DesignTokens.Corner.card
        qrHolder.heightAnchor.constraint(equalToConstant: DesignTokens.dp(130)).isActive = true

        let qrIcon = UIImageView(image: UIImage(systemName: "qrcode"))
        qrIcon.tintColor = .white
        qrIcon.contentMode = .scaleAspectFit
        qrIcon.translatesAutoresizingMaskIntoConstraints = false
        qrHolder.addSubview(qrIcon)
        NSLayoutConstraint.activate([
            qrIcon.centerXAnchor.constraint(equalTo: qrHolder.centerXAnchor),
            qrIcon.centerYAnchor.constraint(equalTo: qrHolder.centerYAnchor, constant: -DesignTokens.dp(8)),
            qrIcon.widthAnchor.constraint(equalToConstant: DesignTokens.Metrics.shopLoadingSize + DesignTokens.dp(34)),
            qrIcon.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.shopLoadingSize + DesignTokens.dp(34))
        ])

        let qrHint = UILabel.make(text: RewardContent.qrPlaceholderHint,
                                  size: 10,
                                  color: DesignTokens.Colors.gray)
        qrHint.translatesAutoresizingMaskIntoConstraints = false
        qrHolder.addSubview(qrHint)
        NSLayoutConstraint.activate([
            qrHint.centerXAnchor.constraint(equalTo: qrHolder.centerXAnchor),
            qrHint.bottomAnchor.constraint(equalTo: qrHolder.bottomAnchor, constant: -DesignTokens.dp(6))
        ])
        stack.addArrangedSubview(qrHolder)

        let copyButton = UIButton.capsule("复制联系邮箱",
                                          size: DesignTokens.Metrics.sheetActionFont,
                                          height: DesignTokens.Metrics.dialogConfirmHeight,
                                          corner: DesignTokens.Metrics.dialogConfirmCorner)
        copyButton.backgroundColor = DesignTokens.Colors.main
        copyButton.addAction(UIAction { _ in
            UIPasteboard.general.string = RewardContent.contactCopyText
        }, for: .touchUpInside)
        stack.addArrangedSubview(copyButton)

        let closeButton = UIButton.capsule("关闭",
                                           size: DesignTokens.Metrics.sheetActionFont,
                                           height: DesignTokens.Metrics.dialogConfirmHeight,
                                           corner: DesignTokens.Metrics.dialogConfirmCorner)
        closeButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        stack.addArrangedSubview(closeButton)
    }
}
