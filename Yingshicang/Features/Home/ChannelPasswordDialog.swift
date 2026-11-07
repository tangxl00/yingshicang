import UIKit

/// R-50 频道密码校验逻辑（纯函数，可注入测试）。
enum ChannelPasswordRule {
    /// 分类名含「密码」或「加密」视为加密频道，需要先校验密码。
    static func needsPassword(categoryName: String) -> Bool {
        let name = categoryName.replacingOccurrences(of: " ", with: "")
        return name.contains("密码") || name.contains("加密")
    }

    /// 密码校验：trim 后与期望值等值比较；期望值为空表示未设置密码（恒通过）。
    static func validate(_ input: String, expected: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty else { return true }
        guard !trimmed.isEmpty else { return false }
        return trimmed == expected
    }
}

/// R-50 频道密码校验弹层：passwordDialogHeight 180dp 口径，安全输入 + 校验回调。
/// 校验逻辑通过闭包注入（默认走 ChannelPasswordRule.validate），便于测试与站点自定义。
final class ChannelPasswordDialogViewController: CardDialogViewController {
    private let categoryName: String
    private let validator: (String) -> Bool
    private let onUnlocked: () -> Void

    private let textField = UITextField()
    private let errorLabel = UILabel.make(size: DesignTokens.Metrics.inputFieldFont,
                                          color: DesignTokens.Colors.accentRed)

    init(categoryName: String,
         expectedPassword: String?,
         onUnlocked: @escaping () -> Void) {
        self.categoryName = categoryName
        let expected = expectedPassword ?? ""
        self.validator = { input in
            ChannelPasswordRule.validate(input, expected: expected)
        }
        self.onUnlocked = onUnlocked
        super.init(config: CardDialogViewController.Config(
            title: "频道密码",
            height: DesignTokens.dp(DesignTokens.Metrics.passwordDialogHeight),
            anchor: .center
        ))
    }

    init(categoryName: String,
         validator: @escaping (String) -> Bool,
         onUnlocked: @escaping () -> Void) {
        self.categoryName = categoryName
        self.validator = validator
        self.onUnlocked = onUnlocked
        super.init(config: CardDialogViewController.Config(
            title: "频道密码",
            height: DesignTokens.dp(DesignTokens.Metrics.passwordDialogHeight),
            anchor: .center
        ))
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func buildBody(into stack: UIStackView) {
        let hint = UILabel.make(text: "「\(categoryName)」为加密频道，请输入访问密码后继续。",
                                size: DesignTokens.Metrics.inputFieldFont,
                                color: DesignTokens.Colors.text,
                                lines: 0)
        stack.addArrangedSubview(hint)

        textField.isSecureTextEntry = true
        textField.textColor = .white
        textField.backgroundColor = DesignTokens.Colors.inputBg
        textField.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.inputFieldCorner)
        textField.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.inputFieldFont))
        textField.placeholder = "输入频道密码"
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        textField.leftViewMode = .always
        textField.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.inputFieldHeight).isActive = true
        stack.addArrangedSubview(textField)

        errorLabel.text = " "
        stack.addArrangedSubview(errorLabel)

        let confirmButton = UIButton.capsule("确认",
                                             size: DesignTokens.Metrics.sheetActionFont,
                                             height: DesignTokens.Metrics.dialogConfirmHeight,
                                             corner: DesignTokens.Metrics.dialogConfirmCorner)
        confirmButton.backgroundColor = DesignTokens.Colors.main
        confirmButton.addAction(UIAction { [weak self] _ in
            self?.confirmTapped()
        }, for: .touchUpInside)
        stack.addArrangedSubview(confirmButton)
    }

    private func confirmTapped() {
        let input = textField.text ?? ""
        if validator(input) {
            dismiss(animated: true) { [onUnlocked] in
                onUnlocked()
            }
        } else {
            errorLabel.text = "密码不正确，请重试"
        }
    }
}
