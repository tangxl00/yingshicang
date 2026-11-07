import UIKit

/// R-24 底部悬浮播放记录条。
///
/// 布局事实（mobile_float_play_bar.xml，AXML 直接读取）：
/// - 背景 50dp，封面 55×55dp（超出背景高度、上下居中悬浮），播放键 35dp
/// - 片名 + 集数/进度两行文字
///
/// 显隐规则：`Settings.showFloatHistory` 开启且有播放记录时显示；
/// 点击任意区域进入该片的详情页（续播定位由详情页/播放页的既有逻辑完成）。
final class FloatHistoryBar: UIView {

    static let barHeight: CGFloat = DesignTokens.Metrics.floatBarHeight

    private let cover = UIImageView()
    private let nameLabel = UILabel.make(size: 14, color: .white, weight: .medium)
    private let episodeLabel = UILabel.make(size: 11, color: DesignTokens.Colors.text)
    private let playButton = UIButton(type: .system)
    private(set) var currentRecord: HistoryRecord?

    /// 点击回调：携带最近一条播放记录。
    var onTap: ((HistoryRecord) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DesignTokens.Colors.sheet
        layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.speedLabelCorner)
        layer.masksToBounds = false

        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.seriesCorner)
        cover.widthAnchor.constraint(equalToConstant: DesignTokens.Metrics.floatCover).isActive = true
        cover.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.floatCover).isActive = true

        nameLabel.numberOfLines = 1
        episodeLabel.numberOfLines = 1

        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.tintColor = DesignTokens.Colors.main
        playButton.widthAnchor.constraint(equalToConstant: DesignTokens.Metrics.floatPlayWidth).isActive = true
        playButton.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.floatPlayWidth).isActive = true

        let textColumn = UIStackView.vertical(spacing: DesignTokens.dp(2))
        textColumn.addArrangedSubview(nameLabel)
        textColumn.addArrangedSubview(episodeLabel)

        let row = UIStackView.horizontal(spacing: DesignTokens.dp(10), alignment: .center)
        [cover, textColumn, playButton].forEach { row.addArrangedSubview($0) }
        row.isLayoutMarginsRelativeArrangement = true
        // 左侧多留白，避免悬浮封面被圆角裁掉
        row.layoutMargins = UIEdgeInsets(top: 0, left: DesignTokens.dp(2), bottom: 0, right: DesignTokens.dp(10))
        addSubview(row)
        row.pinEdges(to: self)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 重新读取最近一条播放记录并刷新内容。
    /// 返回值 = 本次刷新后是否应该显示。
    @discardableResult
    func reload() -> Bool {
        guard Settings.shared.showFloatHistory, let record = HistoryStore.shared.latest() else {
            currentRecord = nil
            return false
        }
        currentRecord = record
        cover.setRemoteImage(record.vodPic)
        nameLabel.text = record.vodName
        episodeLabel.text = "看到第 \(record.episodeIndex + 1) 集"
        return true
    }

    @objc private func handleTap() {
        guard let record = currentRecord else { return }
        onTap?(record)
    }
}
