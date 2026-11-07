import UIKit

/// R-08 条件筛选（全屏形态）：从站点筛选维度中选择条件，
/// 应用后由站点分类接口按条件随机抽取一部影片直接打开详情。
///
/// 布局事实（Metrics.randomFilterXXX / confirmButtonXXX）：
/// - 标题 16sp，marginTop 16dp
/// - 维度列表区高 350dp（滚动）
/// - 确定按钮高 45dp 圆角 8dp
final class ConditionFilterViewController: SwipeBackViewController {

    private let site: SiteConfig?
    private let dimensions: [FilterDimension]
    private var selections: [String: String]
    private let statusLabel = UILabel.make(size: 13, color: DesignTokens.Colors.text, lines: 0)
    private let dimensionScroll = UIScrollView()
    private let dimensionStack = UIStackView.vertical(spacing: DesignTokens.dp(12))
    private let activity = UIActivityIndicatorView(style: .medium)

    /// 应用筛选回调（主线程）：参数为剔除空值的 extend。
    var onApply: (([String: String]) -> Void)?

    init(site: SiteConfig?) {
        self.site = site
        self.dimensions = FilterSheetParser.parse(site?.filter)
        self.selections = FilterSheetParser.defaultSelections(dimensions: dimensions)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        title = "条件筛选"

        let column = UIStackView.vertical(spacing: 0)
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.dp(16)),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(14)),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(14)),
            column.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DesignTokens.dp(12))
        ])

        let titleLabel = UILabel.make(text: "按条件随机推荐",
                                      size: 16,
                                      color: .white,
                                      weight: .semibold)
        column.addArrangedSubview(titleLabel)
        column.setCustomSpacing(DesignTokens.dp(16), after: titleLabel)

        dimensionScroll.showsVerticalScrollIndicator = true
        dimensionScroll.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.randomFilterListHeight).isActive = true
        dimensionStack.isLayoutMarginsRelativeArrangement = true
        dimensionScroll.addSubview(dimensionStack)
        dimensionStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dimensionStack.topAnchor.constraint(equalTo: dimensionScroll.contentLayoutGuide.topAnchor),
            dimensionStack.leadingAnchor.constraint(equalTo: dimensionScroll.contentLayoutGuide.leadingAnchor),
            dimensionStack.trailingAnchor.constraint(equalTo: dimensionScroll.contentLayoutGuide.trailingAnchor),
            dimensionStack.bottomAnchor.constraint(equalTo: dimensionScroll.contentLayoutGuide.bottomAnchor),
            dimensionStack.widthAnchor.constraint(equalTo: dimensionScroll.frameLayoutGuide.widthAnchor)
        ])
        column.addArrangedSubview(dimensionScroll)

        if dimensions.isEmpty {
            statusLabel.text = "当前站点未提供筛选维度，无法条件筛选。"
            statusLabel.textAlignment = .center
            column.addArrangedSubview(statusLabel)
        } else {
            rebuildDimensions()
        }

        let confirmButton = UIButton.capsule("确定",
                                              size: 16,
                                              height: DesignTokens.Metrics.confirmButtonHeight,
                                              corner: DesignTokens.Metrics.confirmButtonCorner)
        confirmButton.backgroundColor = DesignTokens.Colors.main
        confirmButton.addAction(UIAction { [weak self] _ in
            self?.confirmTapped()
        }, for: .touchUpInside)
        column.addArrangedSubview(confirmButton)

        activity.hidesWhenStopped = true
        column.addArrangedSubview(activity)
    }

    private func rebuildDimensions() {
        dimensionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for dimension in dimensions {
            let nameLabel = UILabel.make(text: dimension.name, size: 14, color: .white, weight: .medium)
            dimensionStack.addArrangedSubview(nameLabel)

            let optionRow = UIStackView.horizontal(spacing: DesignTokens.dp(6))
            for option in dimension.options {
                let optionButton = UIButton.text(option.name, size: 13, color: .white)
                optionButton.backgroundColor = (selections[dimension.key] == option.value)
                    ? DesignTokens.Colors.main
                    : DesignTokens.Colors.cardWhite
                optionButton.layer.cornerRadius = DesignTokens.Corner.xs
                optionButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
                optionButton.heightAnchor.constraint(equalToConstant: DesignTokens.dp(30)).isActive = true
                optionButton.addAction(UIAction { [weak self] _ in
                    guard let self = self else { return }
                    self.selections[dimension.key] = option.value
                    self.rebuildDimensions()
                }, for: .touchUpInside)
                optionRow.addArrangedSubview(optionButton)
            }
            let scroll = UIScrollView()
            scroll.showsHorizontalScrollIndicator = false
            let rowHolder = UIView()
            rowHolder.addSubview(optionRow)
            optionRow.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                optionRow.topAnchor.constraint(equalTo: rowHolder.topAnchor),
                optionRow.leadingAnchor.constraint(equalTo: rowHolder.leadingAnchor),
                optionRow.bottomAnchor.constraint(equalTo: rowHolder.bottomAnchor),
                optionRow.trailingAnchor.constraint(lessThanOrEqualTo: rowHolder.trailingAnchor)
            ])
            scroll.addSubview(rowHolder)
            rowHolder.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                rowHolder.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                rowHolder.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                rowHolder.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                rowHolder.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                rowHolder.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
            ])
            scroll.heightAnchor.constraint(equalToConstant: DesignTokens.dp(42)).isActive = true
            dimensionStack.addArrangedSubview(scroll)
        }
    }

    private func confirmTapped() {
        let extend = selections.filter { !$0.value.isEmpty }
        onApply?(extend)
        // 自身也具备随机直开能力：宿主未接 onApply 时走内置随机流程。
        if onApply == nil {
            randomPick(extend: extend)
        }
    }

    /// 内置随机推荐：按条件请求分类第 1 页，随机挑一部打开详情。
    func randomPick(extend: [String: String]) {
        guard let site = site else {
            statusLabel.text = "当前无可用站点。"
            return
        }
        activity.startAnimating()
        statusLabel.text = " "
        let provider = SiteProviderFactory.make(site: site)
        provider.category(id: "", page: 1, extend: extend) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activity.stopAnimating()
                switch result {
                case .success(let list):
                    if let picked = ShakeRecommendationPicker.pick(list) {
                        let controller = DetailViewController(item: picked)
                        controller.modalPresentationStyle = .fullScreen
                        self.present(controller, animated: true)
                    } else {
                        self.statusLabel.text = "该条件下没有可推荐的影片"
                    }
                case .failure(let error):
                    self.statusLabel.text = error.localizedDescription
                }
            }
        }
    }
}
