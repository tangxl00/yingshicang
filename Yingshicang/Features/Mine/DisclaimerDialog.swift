import UIKit

/// R-54 免责声明：仅首次启动弹出一次，同意结果持久化到 UserDefaults。
enum DisclaimerGate {
    static let storageKey = "disclaimer.accepted.v22050"

    static func isAccepted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: storageKey)
    }

    static func accept(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: storageKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}

/// R-54 免责声明弹窗：居中卡片，正文 + 「我已阅读并同意」按钮。
/// 点击同意 → 写持久化标记 → 关闭弹窗；暂不同意 → 仅关闭（下次启动再次弹出）。
final class DisclaimerDialogViewController: CardDialogViewController {
    private let onAgree: (() -> Void)?

    init(onAgree: (() -> Void)? = nil) {
        self.onAgree = onAgree
        super.init(config: CardDialogViewController.Config(
            title: "免责声明",
            height: DesignTokens.dp(420),
            anchor: .center
        ))
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func buildBody(into stack: UIStackView) {
        let label = UILabel.make(
            text: """
            本应用为开源影视聚合壳（iOS 重写版），自身不提供、不存储、不上传任何视频、音频或图文内容，所有内容均来自用户自行配置的第三方站点。

            1. 内容责任：站内呈现的一切资源及其版权合规性由对应站点负责，与本应用无关；请通过合法渠道观看正版内容。
            2. 使用限制：本应用仅供个人学习与技术交流，禁止用于任何商业用途或传播违法违规内容。
            3. 数据安全：配置、历史与设置仅保存在本机；WebDAV / 局域网同步功能仅在你主动配置后与指定设备通信。
            4. 网络行为：播放与加载产生的流量消耗由用户自行承担；部分站点可能包含广告或第三方脚本，请自行甄别。
            """,
            size: DesignTokens.Metrics.warningBodyFont,
            color: DesignTokens.Colors.text,
            lines: 0
        )
        stack.addArrangedSubview(label)

        let agreeButton = UIButton.capsule("我已阅读并同意",
                                           size: DesignTokens.Metrics.sheetActionFont,
                                           height: DesignTokens.Metrics.dialogConfirmHeight,
                                           corner: DesignTokens.Metrics.dialogConfirmCorner)
        agreeButton.backgroundColor = DesignTokens.Colors.main
        agreeButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            DisclaimerGate.accept()
            self.dismiss(animated: true)
            self.onAgree?()
        }, for: .touchUpInside)
        stack.addArrangedSubview(agreeButton)

        let laterButton = UIButton.capsule("暂不同意",
                                           size: DesignTokens.Metrics.sheetActionFont,
                                           height: DesignTokens.Metrics.dialogConfirmHeight,
                                           corner: DesignTokens.Metrics.dialogConfirmCorner)
        laterButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        stack.addArrangedSubview(laterButton)
    }
}
