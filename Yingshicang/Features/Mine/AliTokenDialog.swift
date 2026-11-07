import UIKit

/// R-48 阿里 Token 校验：normalize 去首尾与内部空白；合法 = 32 位十六进制字符。
enum AliTokenValidator {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }

    static func isValid(_ raw: String) -> Bool {
        let token = normalize(raw)
        guard token.count == 32 else { return false }
        return token.allSatisfy { c in c.isHexDigit }
    }
}

/// R-48 阿里 Token 弹层：居中弹窗（inputDialogHeight 220dp 口径），输入 32 位 Token，
/// 校验通过后写入 Settings.aliToken。
final class AliTokenDialogViewController: CardDialogViewController {
    private let textField = UITextField()
    private let errorLabel = UILabel.make(size: DesignTokens.Metrics.inputFieldFont,
                                          color: DesignTokens.Colors.accentRed,
                                          lines: 0)
    private let onSaved: (() -> Void)?

    init(onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
        super.init(config: CardDialogViewController.Config(
            title: "阿里云盘 Token",
            height: DesignTokens.dp(DesignTokens.Metrics.inputDialogHeight),
            anchor: .center
        ))
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        textField.text = Settings.shared.aliToken
    }

    override func buildBody(into stack: UIStackView) {
        let hint = UILabel.make(
            text: "用于网盘类站点的阿里云盘直链解析。Token 为 32 位十六进制字符串，保存后立即对网盘站点生效。",
            size: DesignTokens.Metrics.inputFieldFont,
            color: DesignTokens.Colors.text,
            lines: 0
        )
        stack.addArrangedSubview(hint)

        textField.textColor = .white
        textField.backgroundColor = DesignTokens.Colors.inputBg
        textField.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.inputFieldCorner)
        textField.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.inputFieldFont))
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.placeholder = "粘贴 32 位 Token"
        textField.clearButtonMode = .whileEditing
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        textField.leftViewMode = .always
        textField.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.inputFieldHeight).isActive = true
        stack.addArrangedSubview(textField)

        errorLabel.text = " "
        stack.addArrangedSubview(errorLabel)

        let saveButton = UIButton.capsule("保存",
                                          size: DesignTokens.Metrics.sheetActionFont,
                                          height: DesignTokens.Metrics.dialogConfirmHeight,
                                          corner: DesignTokens.Metrics.dialogConfirmCorner)
        saveButton.backgroundColor = DesignTokens.Colors.main
        saveButton.addAction(UIAction { [weak self] _ in
            self?.saveTapped()
        }, for: .touchUpInside)
        stack.addArrangedSubview(saveButton)

        let clearButton = UIButton.text("清除 Token",
                                        size: DesignTokens.Metrics.sheetActionFont,
                                        color: DesignTokens.Colors.gray)
        clearButton.addAction(UIAction { [weak self] _ in
            Settings.shared.aliToken = ""
            self?.textField.text = nil
            self?.errorLabel.text = " "
            self?.onSaved?()
        }, for: .touchUpInside)
        stack.addArrangedSubview(clearButton)
    }

    private func saveTapped() {
        let raw = textField.text ?? ""
        guard AliTokenValidator.isValid(raw) else {
            let token = AliTokenValidator.normalize(raw)
            errorLabel.text = token.isEmpty
                ? "Token 不能为空"
                : "格式不正确：需要 32 位十六进制字符，当前 \(token.count) 位"
            return
        }
        Settings.shared.aliToken = AliTokenValidator.normalize(raw)
        errorLabel.text = " "
        dismiss(animated: true)
        onSaved?()
    }
}

/// R-39 网盘页（best-effort）：展示阿里 Token 配置状态与说明，提供 Token 弹层入口。
final class NetdiskViewController: SwipeBackViewController {
    private let statusLabel = UILabel.make(size: DesignTokens.Metrics.settingRowFont,
                                           color: .white,
                                           lines: 0)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        title = "网盘"

        let stack = UIStackView.vertical(spacing: DesignTokens.dp(14))
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: DesignTokens.dp(16), left: DesignTokens.dp(14),
            bottom: DesignTokens.dp(16), right: DesignTokens.dp(14)
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.dp(12)),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let intro = UILabel.make(
            text: "网盘能力说明：阿里云盘直链解析依赖站点脚本与 Token 授权。配置 Token 后，支持阿里网盘的站点可解析直链播放；未配置时网盘类内容可能无法播放。",
            size: 13,
            color: DesignTokens.Colors.text,
            lines: 0
        )
        stack.addArrangedSubview(intro)

        stack.addArrangedSubview(statusLabel)

        let configButton = UIButton.capsule("配置阿里云盘 Token",
                                            size: DesignTokens.Metrics.sheetActionFont,
                                            height: DesignTokens.Metrics.dialogConfirmHeight,
                                            corner: DesignTokens.Metrics.dialogConfirmCorner)
        configButton.backgroundColor = DesignTokens.Colors.main
        configButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.present(AliTokenDialogViewController { [weak self] in
                self?.refreshStatus()
            }, animated: true)
        }, for: .touchUpInside)
        stack.addArrangedSubview(configButton)

        let closeHint = UILabel.make(text: "左滑屏幕边缘可返回",
                                     size: 11,
                                     color: DesignTokens.Colors.gray)
        stack.addArrangedSubview(closeHint)

        refreshStatus()
    }

    private func refreshStatus() {
        let token = Settings.shared.aliToken
        if AliTokenValidator.isValid(token) {
            statusLabel.text = "当前状态：已配置（尾号 \(token.suffix(4))）"
        } else {
            statusLabel.text = "当前状态：未配置"
        }
    }
}
