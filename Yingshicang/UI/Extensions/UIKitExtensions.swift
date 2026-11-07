import UIKit

extension UIColor {
    /// 由 0xAARRGGBB 构造，资源表里的颜色全部是 ARGB 四字节序。
    convenience init(hex: UInt32, alphaOverride: CGFloat? = nil) {
        let a = alphaOverride ?? CGFloat((hex >> 24) & 0xFF) / 255.0
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

extension UIView {
    /// 便捷固定尺寸（width/height 传入 0 表示不约束）。
    @discardableResult
    func size(_ width: CGFloat, _ height: CGFloat) -> Self {
        translatesAutoresizingMaskIntoConstraints = false
        if width > 0 { widthAnchor.constraint(equalToConstant: width).isActive = true }
        if height > 0 { heightAnchor.constraint(equalToConstant: height).isActive = true }
        return self
    }

    @discardableResult
    func pinEdges(to other: UIView, insets: UIEdgeInsets = .zero) -> Self {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ])
        return self
    }
}

extension UIStackView {
    static func vertical(spacing: CGFloat = 0, alignment: UIStackView.Alignment = .fill) -> UIStackView {
        let s = UIStackView()
        s.axis = .vertical
        s.alignment = alignment
        s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    static func horizontal(spacing: CGFloat = 0, alignment: UIStackView.Alignment = .fill) -> UIStackView {
        let s = UIStackView()
        s.axis = .horizontal
        s.alignment = alignment
        s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }
}

extension UILabel {
    /// 统一入口：字号 (sp) 与颜色来自设计令牌，避免各界面散落硬编码。
    static func make(text: String? = nil,
                     size: CGFloat,
                     color: UIColor = DesignTokens.Colors.text,
                     weight: UIFont.Weight = .regular,
                     lines: Int = 1) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: DesignTokens.sp(size), weight: weight)
        label.textColor = color
        label.numberOfLines = lines
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

extension UIButton {
    static func text(_ title: String,
                     size: CGFloat,
                     color: UIColor,
                     weight: UIFont.Weight = .regular) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(color, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(size), weight: weight)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    /// R-08/R-16/R-35 等处的「灰 20% 底 + 圆角」按钮统一样式。
    static func capsule(_ title: String, size: CGFloat, height: CGFloat, corner: CGFloat) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: DesignTokens.sp(size))
        button.backgroundColor = DesignTokens.Colors.dialog
        button.layer.cornerRadius = DesignTokens.dp(corner)
        button.layer.masksToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: DesignTokens.dp(height)).isActive = true
        return button
    }
}

extension UIImageView {
    /// 异步加载图片。采集站图片普遍为 http 明文，已由 ATS 的 NSAllowsArbitraryLoads 放行。
    func setRemoteImage(_ urlString: String?, placeholder: UIImage? = nil) {
        image = placeholder
        guard let urlString = urlString, let url = URL(string: urlString), !urlString.isEmpty else { return }
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        ImagePipeline.shared.load(request) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let image): self.image = image
            case .failure: self.image = placeholder
            }
        }
    }
}

extension URL {
    /// 拼接采集站的相对路径规则：站点 host + 规则里的 path。
    func appendingRulePath(_ path: String) -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path) ?? self
        }
        var base = self.absoluteString
        if base.hasSuffix("/") && path.hasPrefix("/") {
            base.removeLast()
        }
        if !base.hasSuffix("/") && !path.hasPrefix("/") {
            base += "/"
        }
        return URL(string: base + path) ?? self
    }
}
