import UIKit

/// R-52 分类标签全宽浮层：主页 Tab 行右侧 chevron 图标点击后弹出的贴底全宽面板，
/// 列出当前站点的全部分类（顶部 Tab 横滑条的「展开」形态），
/// 点选即切换分类并关闭浮层，当前分类高亮。
final class CategorySheetViewController: CardDialogViewController {

    private let categories: [SiteCategory]
    private let initialSelection: Int
    private var selectedIndex: Int
    private lazy var collectionView: UICollectionView = makeCollectionView()

    /// 点选分类回调（dismiss 后主线程触发），参数为分类下标。
    var onSelect: ((Int) -> Void)?

    init(categories: [SiteCategory], selectedIndex: Int) {
        self.categories = categories
        self.initialSelection = selectedIndex
        self.selectedIndex = selectedIndex
        super.init(config: Config(title: "全部分类",
                                  height: DesignTokens.dp(400),
                                  anchor: .bottom,
                                  showsDragBar: true,
                                  showsCloseButton: false))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 是否与初始选中一致（供回归测试在未点选时断言）。
    var isSelectionUnchanged: Bool { selectedIndex == initialSelection }

    override func buildBody(into stack: UIStackView) {
        // 高度显式给定（弹层 400dp 减去拖拽条/标题/内边距），避免无 intrinsic 尺寸的
        // collection view 在垂直栈里高度歧义。
        stack.addArrangedSubview(collectionView)
        collectionView.heightAnchor.constraint(equalToConstant: DesignTokens.dp(300)).isActive = true
    }

    private func makeCollectionView() -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = DesignTokens.dp(10)
        layout.minimumLineSpacing = DesignTokens.dp(10)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsVerticalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.register(CategoryPillCell.self, forCellWithReuseIdentifier: CategoryPillCell.reuseId)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

extension CategorySheetViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        categories.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CategoryPillCell.reuseId,
                                                      for: indexPath) as! CategoryPillCell
        let selected = indexPath.item == selectedIndex
        cell.configure(title: categories[indexPath.item].name, selected: selected)
        return cell
    }
}

extension CategorySheetViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // 3 列胶囊：宽度均分（去掉两列间距），高度 34dp。
        let columns: CGFloat = 3
        let spacing = DesignTokens.dp(10)
        let width = max(0, (collectionView.bounds.width - spacing * (columns - 1)) / columns)
        return CGSize(width: width, height: DesignTokens.dp(34))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedIndex = indexPath.item
        collectionView.reloadData()
        let callback = onSelect
        let index = indexPath.item
        dismiss(animated: true) {
            DispatchQueue.main.async { callback?(index) }
        }
    }
}

/// 分类胶囊 cell：选中态主色底白字，未选中白 6% 底常规字。
final class CategoryPillCell: UICollectionViewCell {

    static let reuseId = "CategoryPillCell"

    private let titleLabel = UILabel.make(size: DesignTokens.Metrics.cardNameFont,
                                          color: DesignTokens.Colors.text,
                                          weight: .regular,
                                          lines: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor,
                                                constant: DesignTokens.dp(4)),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor,
                                                 constant: -DesignTokens.dp(4))
        ])
        layer.cornerRadius = DesignTokens.dp(8)
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, selected: Bool) {
        titleLabel.text = title
        if selected {
            backgroundColor = DesignTokens.Colors.main
            titleLabel.textColor = .white
        } else {
            backgroundColor = DesignTokens.Colors.cardWhite
            titleLabel.textColor = DesignTokens.Colors.text
        }
    }
}
