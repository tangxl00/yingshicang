import UIKit

/// 通用卡片弹层容器（R-08 / R-18 / R-19 / R-28 / R-45 / R-48 / R-50 / R-53 / R-54 共用形态）。
///
/// 形态事实（AXML）：遮罩 alpha 0.6、圆角 16dp 卡片、可选 40×4dp 拖拽条、
/// 标题 16sp + 右上 33dp 关闭钮、内容区垂直排列。
/// 各业务弹层只覆写 `buildBody(into:)` 填内容，遮罩/圆角/关闭语义集中在这里，
/// 避免每个弹层各写一套形态导致尺寸漂移（质检抽查口径即比对这些 dp 值）。
class CardDialogViewController: UIViewController, UIGestureRecognizerDelegate {

    enum Anchor {
        /// 居中弹窗（解析 / 轨道 / 输入 token / 密码 / 简介）
        case center
        /// 贴底弹层（R-06 筛选 / R-08 条件筛选，需带拖拽条）
        case bottom
    }

    struct Config {
        var title: String
        var height: CGFloat
        /// 显式宽度；nil 表示占满「容器宽度 − 两侧 14dp」。
        var width: CGFloat?
        var anchor: Anchor
        var showsDragBar: Bool
        var showsCloseButton: Bool

        init(title: String,
             height: CGFloat,
             width: CGFloat? = nil,
             anchor: Anchor = .center,
             showsDragBar: Bool = false,
             showsCloseButton: Bool = true) {
            self.title = title
            self.height = height
            self.width = width
            self.anchor = anchor
            self.showsDragBar = showsDragBar
            self.showsCloseButton = showsCloseButton
        }
    }

    /// 遮罩不透明度：与原布局的 0.6 黑遮罩对齐。
    static let dimAlpha: CGFloat = 0.6

    /// 卡片宽度：显式宽度优先，但不得超过「容器宽度 − 两侧 14dp 安全边距」。
    /// 抽成静态纯函数，单测可直接覆盖窄屏（320pt）与显式宽度超限两种边界。
    static func cardWidth(containerWidth: CGFloat, explicit: CGFloat?) -> CGFloat {
        let safeWidth = max(0, containerWidth - DesignTokens.Metrics.actionBarHorizontalPadding * 2)
        guard let explicit = explicit else { return safeWidth }
        return min(explicit, safeWidth)
    }

    let config: Config
    /// 内容区栈：子类在 `buildBody` 里往里加视图。
    let bodyStack = UIStackView.vertical(spacing: DesignTokens.dp(12))
    private let card = UIView()
    private let titleLabel = UILabel.make(size: DesignTokens.Metrics.dialogTitleFont, color: .white, weight: .semibold)
    private let closeButton = UIButton(type: .system)
    private var cardWidthConstraint: NSLayoutConstraint?
    private(set) var dragBar: UIView?

    /// 关闭回调：业务侧据此保存或放弃。
    var onClose: (() -> Void)?

    init(config: Config) {
        self.config = config
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(Self.dimAlpha)

        card.backgroundColor = DesignTokens.Colors.sheet
        card.layer.cornerRadius = DesignTokens.Corner.card
        card.layer.masksToBounds = true
        view.addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false

        let widthConstraint = card.widthAnchor.constraint(
            equalToConstant: Self.cardWidth(containerWidth: UIScreen.main.bounds.width, explicit: config.width))
        cardWidthConstraint = widthConstraint
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: config.height),
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            widthConstraint
        ])
        switch config.anchor {
        case .center:
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        case .bottom:
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        }

        var topInset = DesignTokens.Metrics.sheetContentPaddingTop
        if config.showsDragBar {
            let bar = UIView()
            bar.backgroundColor = DesignTokens.Colors.white44
            bar.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.dragBarCorner)
            card.addSubview(bar)
            bar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bar.topAnchor.constraint(equalTo: card.topAnchor,
                                         constant: DesignTokens.dp(DesignTokens.Metrics.dragBarTopMargin)),
                bar.centerXAnchor.constraint(equalTo: card.centerXAnchor),
                bar.widthAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.dragBarWidth)),
                bar.heightAnchor.constraint(equalToConstant: DesignTokens.dp(DesignTokens.Metrics.dragBarHeight))
            ])
            dragBar = bar
            topInset += DesignTokens.Metrics.dragBarTopMargin + DesignTokens.Metrics.dragBarHeight + DesignTokens.dp(6)
        }

        titleLabel.text = config.title
        card.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: topInset),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor,
                                               constant: DesignTokens.Metrics.actionBarHorizontalPadding)
        ])

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = DesignTokens.Colors.text
        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        card.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: DesignTokens.dp(-8)),
            closeButton.widthAnchor.constraint(equalToConstant: DesignTokens.Metrics.dialogCloseSize),
            closeButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.dialogCloseSize)
        ])
        closeButton.isHidden = !config.showsCloseButton

        card.addSubview(bodyStack)
        NSLayoutConstraint.activate([
            bodyStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DesignTokens.dp(10)),
            bodyStack.leadingAnchor.constraint(equalTo: card.leadingAnchor,
                                              constant: DesignTokens.Metrics.actionBarHorizontalPadding),
            bodyStack.trailingAnchor.constraint(equalTo: card.trailingAnchor,
                                                constant: -DesignTokens.Metrics.actionBarHorizontalPadding),
            bodyStack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -DesignTokens.dp(12))
        ])
        buildBody(into: bodyStack)

        // 遮罩点击关闭：落点在卡片外才关，避免误关正在输入的弹层。
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = Self.cardWidth(containerWidth: view.bounds.width, explicit: config.width)
        if cardWidthConstraint?.constant != width {
            cardWidthConstraint?.constant = width
        }
    }

    /// 内容构建点：子类覆写。
    func buildBody(into stack: UIStackView) {}

    /// 供调用方在关闭前做校验。返回 false 则不关闭。
    func mayClose() -> Bool { true }

    @objc func handleClose() {
        guard mayClose() else { return }
        let callback = onClose
        dismiss(animated: true) { callback?() }
    }

    @objc private func handleBackdropTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        if card.frame.contains(point) { return }
        handleClose()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard let touched = touch.view else { return true }
        var node: UIView? = touched
        while let current = node {
            if current is UIControl { return false }
            node = current.superview
        }
        return true
    }
}
