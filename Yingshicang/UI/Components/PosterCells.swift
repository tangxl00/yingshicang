import UIKit

/// R-03 海报卡（列表/网格共用）。布局事实：
/// - 封面比例 220:280（AXML item 宽高与 ImageView 固定尺寸推算）
/// - 右上角标 12sp、圆角 4dp、黑 44% 底（备注/集数）
/// - 左下角标 11sp、圆角 4dp
/// - 片名 13sp、最多 4 行、灰色
final class PosterCardCell: UICollectionViewCell {

    static let reuseID = "PosterCardCell"

    private let cover = UIImageView()
    private let flagLabel = UILabel.make(size: DesignTokens.Metrics.cardFlagFont, color: .white)
    private let noteLabel = UILabel.make(size: DesignTokens.Metrics.cardNoteFont, color: .white)
    private let nameLabel = UILabel.make(size: DesignTokens.Metrics.cardNameFont,
                                       color: DesignTokens.Colors.text, lines: 4)
    private var coverHeightConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear

        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.backgroundColor = DesignTokens.Colors.cardWhite
        cover.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.cardCorner)
        cover.layer.masksToBounds = true
        cover.translatesAutoresizingMaskIntoConstraints = false

        flagLabel.backgroundColor = DesignTokens.Colors.black44
        flagLabel.textAlignment = .center
        flagLabel.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.cardCorner)
        flagLabel.layer.masksToBounds = true
        flagLabel.isHidden = true

        noteLabel.backgroundColor = DesignTokens.Colors.black44
        noteLabel.textAlignment = .center
        noteLabel.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.cardCorner)
        noteLabel.layer.masksToBounds = true
        noteLabel.isHidden = true

        nameLabel.textAlignment = .left

        contentView.addSubview(cover)
        contentView.addSubview(flagLabel)
        contentView.addSubview(noteLabel)
        contentView.addSubview(nameLabel)

        let height = cover.heightAnchor.constraint(equalTo: cover.widthAnchor,
                                                   multiplier: 1.0 / DesignTokens.Metrics.posterRatio)
        coverHeightConstraint = height

        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: contentView.topAnchor),
            cover.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            height,

            flagLabel.topAnchor.constraint(equalTo: cover.topAnchor, constant: DesignTokens.dp(4)),
            flagLabel.trailingAnchor.constraint(equalTo: cover.trailingAnchor, constant: -DesignTokens.dp(4)),
            flagLabel.heightAnchor.constraint(equalToConstant: DesignTokens.dp(18)),
            flagLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: DesignTokens.dp(30)),

            noteLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor, constant: DesignTokens.dp(4)),
            noteLabel.bottomAnchor.constraint(equalTo: cover.bottomAnchor, constant: -DesignTokens.dp(4)),
            noteLabel.trailingAnchor.constraint(lessThanOrEqualTo: cover.trailingAnchor, constant: -DesignTokens.dp(4)),
            noteLabel.heightAnchor.constraint(equalToConstant: DesignTokens.dp(16)),

            nameLabel.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: DesignTokens.dp(4)),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func bind(_ item: VodItem) {
        cover.setRemoteImage(item.vodPic)
        nameLabel.text = item.vodName
        noteLabel.text = item.vodRemarks
        noteLabel.isHidden = item.vodRemarks.isEmpty
        flagLabel.isHidden = true
    }

    /// 列表模式（60×60 缩略图 + 名称 14sp 3 行）由 PosterListCell 承载，
    /// 这里保留接口以便统一切换，避免两套 cell 各自绑定逻辑。
    func applyListStyle() {
        coverHeightConstraint?.isActive = false
    }
}

/// R-03 列表形态：60×60 缩略图 + 名称 14sp（最多 3 行）。
final class PosterListCell: UICollectionViewCell {

    static let reuseID = "PosterListCell"

    private let cover = UIImageView()
    private let nameLabel = UILabel.make(size: DesignTokens.Metrics.listNameFont,
                                       color: .white, lines: 3)
    private let noteLabel = UILabel.make(size: DesignTokens.Metrics.cardNoteFont,
                                        color: DesignTokens.Colors.text, lines: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = DesignTokens.Colors.cardWhite
        contentView.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.cardCorner)
        contentView.layer.masksToBounds = true

        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.cardCorner)
        cover.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(cover)
        contentView.addSubview(nameLabel)
        contentView.addSubview(noteLabel)

        let side = DesignTokens.dp(DesignTokens.Metrics.listThumb)
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DesignTokens.dp(6)),
            cover.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            cover.widthAnchor.constraint(equalToConstant: side),
            cover.heightAnchor.constraint(equalToConstant: side),

            nameLabel.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: DesignTokens.dp(8)),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DesignTokens.dp(8)),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DesignTokens.dp(8)),

            noteLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            noteLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            noteLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: DesignTokens.dp(4))
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func bind(_ item: VodItem) {
        cover.setRemoteImage(item.vodPic)
        nameLabel.text = item.vodName
        noteLabel.text = item.vodRemarks
    }
}
