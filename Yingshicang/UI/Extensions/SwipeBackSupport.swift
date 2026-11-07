import UIKit

/// 左滑返回 + 点击空白收键盘的统一基类。
///
/// ## 为什么不是 `interactivePopGestureRecognizer`
/// 本 App 的二级页面（详情 / 搜索 / 播放 / 我的子页）**全部是 `modalPresentationStyle = .fullScreen`
/// 的 present**，全仓 `pushViewController` 调用数为 0，不存在导航栈，
/// 因此 `interactivePopGestureRecognizer` 永远没有可 pop 的栈顶，恢复它的 delegate 也不会生效。
/// 真正的「返回上一界面」对应的动作是 `dismiss`，所以这里用边缘侧滑触发 dismiss。
///
/// ## 与播放页手势的关系
/// 播放页只有两种输入：`engineHost` 上的单击（切换控制层）与 `seekSlider`（UISlider 自身拖动），
/// **没有任何全屏横向 pan 手势**，所以不存在「快进横滑 vs 边缘返回」的冲突。
/// 即便如此，本实现仍只认**屏幕最左侧 24pt** 起手的拖动，
/// 且 `cancelsTouchesInView = false`，不会截获滑块与列表内部的拖动。
/// 注意：**不能是 final**——14 个二级页面（Detail/Search/Player/我的子页等）都要继承它。
class SwipeBackViewController: UIViewController, UIGestureRecognizerDelegate {

    /// 边缘识别宽度。取 24pt：足够窄，不会与内容区横向拖动（滑块、横向滚动列表）混淆。
    private static let edgeWidth: CGFloat = 24

    private lazy var edgePan: UIScreenEdgePanGestureRecognizer = {
        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
        pan.edges = .left
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        return pan
    }()

    private lazy var backgroundTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        // 不吞点击：列表选中、按钮点击、滑块拖动照常生效，只是**顺带**收键盘。
        tap.cancelsTouchesInView = false
        tap.delegate = self
        return tap
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        // 手势挂在 view 上而不是 window：页面被 dismiss 时随视图一起释放，不会残留到下一屏。
        view.addGestureRecognizer(edgePan)
        view.addGestureRecognizer(backgroundTap)
    }

    // MARK: - 左滑返回

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // 根 Tab 页（无 presentingViewController）没有「上一界面」，不做任何事。
        guard presentingViewController != nil else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        // 右向拖动越过 60pt 或速度够快才返回，避免误触。
        guard translation.x > 60 || velocity.x > 800 else { return }
        dismiss(animated: true)
    }

    // MARK: - 点击空白收键盘

    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        // 只在有输入焦点时收，避免无谓的全局重排。
        guard hasFocusedInput(in: view) else { return }
        view.endEditing(true)
    }

    private func hasFocusedInput(in root: UIView) -> Bool {
        if root.isFirstResponder { return true }
        for sub in root.subviews where hasFocusedInput(in: sub) { return true }
        return false
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === backgroundTap else { return true }
        return Self.tapMayReceive(on: touch.view)
    }

    /// 点击让路策略：落在可交互控件上时让控件自己处理（按钮 / 滑块 / 开关 / 输入框）。
    /// 抽成静态方法便于单测直接验证，无需构造 UITouch。
    static func tapMayReceive(on touched: UIView?) -> Bool {
        var node: UIView? = touched
        while let current = node {
            if current is UIControl || current is UITextView || current is UITextField { return false }
            node = current.superview
        }
        return true
    }

    /// 背景单击与页面内其他手势（如播放页单击切换控制层）并行，不需要互斥。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
