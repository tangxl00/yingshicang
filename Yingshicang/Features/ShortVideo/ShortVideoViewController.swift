import UIKit
import WebKit

/// R-28 短视频页。APK 的短视频为独立的 WebView/H5 壳（`mobile_shortvideo`），
/// 依赖安卓 WebView 与站点 H5 页面。iOS 侧按架构文档的风险处置给出等价实现：
/// 用 WKWebView 承载同一 H5 地址，并明确标注这是 H5 壳形态（非原生重写）。
final class ShortVideoViewController: UIViewController {

    private let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private let statusLabel = UILabel.make(size: 13, color: DesignTokens.Colors.text, lines: 0)
    private let titleLabel = UILabel.make(text: "短视频", size: DesignTokens.Metrics.titleFont,
                                        color: .white, weight: .semibold)

    /// 短视频地址来自配置的 `spider` 旁的 flag，或站点 ext 中的 shortvideo 键。
    /// 未配置时展示说明，而不是空白页。
    private var address: String? {
        let bundle = ConfigRepository.shared.currentBundle
        // ext 是配置里的原始字符串（通常是 JSON 文本），这里按 key 探测
        for site in bundle.sites where site.ext.contains("shortvideo") {
            if let range = site.ext.range(of: "shortvideo") {
                let tail = site.ext[range.upperBound...]
                if let urlStart = tail.range(of: "http") {
                    let rest = tail[urlStart.lowerBound...]
                    let end = rest.firstIndex { $0 == "\"" || $0 == "," || $0 == "}" || $0 == " " || $0 == "\\" }
                    let raw = end == nil ? String(rest) : String(rest[..<end!])
                    if !raw.isEmpty { return raw }
                }
            }
        }
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        view.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                            constant: DesignTokens.Metrics.homePaddingTop),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                               constant: DesignTokens.Metrics.actionBarHorizontalPadding)
        ])

        webView.backgroundColor = DesignTokens.Colors.mainBg
        webView.isOpaque = false
        webView.scrollView.backgroundColor = DesignTokens.Colors.mainBg
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DesignTokens.dp(10)),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        view.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(24)),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(24))
        ])

        if let address = address, let url = URL(string: address) {
            statusLabel.isHidden = true
            webView.load(URLRequest(url: url))
        } else {
            // 短视频依赖配置里提供的 H5 地址；原生 APK 也是 WebView 壳，
            // 未配置时按实际情况提示（不静默空白）。
            statusLabel.text = "短视频为 H5 形态，需配置项 ext 内提供 shortvideo 地址。\n当前配置未提供，功能暂不可用。"
        }
    }
}
