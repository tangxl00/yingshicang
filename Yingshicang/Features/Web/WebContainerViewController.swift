import UIKit
import WebKit

/// R-47 通用 H5 容器（原 APK 的 WebView 复用容器：网盘授权登录页 / H5 说明页等）。
///
/// 与 Android 版对齐的两个职责：
/// 1. **通用承载**：任意 http(s) 页面在容器内打开，导航前过 `JSRequestPolicy`
///    准入（协议白名单 + 内网拦截，与 JS 桥 `req` 同一套策略）；
///    业务容器（如网盘授权）按需传 allowedHosts 放行目标域。
/// 2. **授权回传**：外部授权页最终会 302 到自定义回调（形如
///    `xxx://callback?tok=…` 或带 `token` / `access_token` 参数的页面），
///    容器在导航决策点拦截该跳转、提取令牌、回调宿主并关闭，绝不把令牌留在页面里。
final class WebContainerViewController: SwipeBackViewController, WKNavigationDelegate {

    let webView = WKWebView()
    private let targetURL: URL
    private let pageTitle: String?
    private let policy: JSRequestPolicy

    /// 授权回传：命中令牌后回调（主线程），参数为提取出的令牌。
    var onAuthorizedToken: ((String) -> Void)?

    init(url: URL, title: String? = nil, allowedHosts: Set<String> = []) {
        self.targetURL = url
        self.pageTitle = title
        self.policy = JSRequestPolicy(allowedHosts: allowedHosts)
        super.init(nibName: nil, bundle: nil)
    }

    /// 授权页容器工厂：宿主只需给 URL 与回调。
    static func authorizing(url: URL,
                            allowedHosts: Set<String> = [],
                            onToken: @escaping (String) -> Void) -> WebContainerViewController {
        let controller = WebContainerViewController(url: url, title: "授权登录", allowedHosts: allowedHosts)
        controller.onAuthorizedToken = onToken
        return controller
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 授权回传提取（纯函数，单测覆盖）

    /// 从回调 URL 提取授权令牌。支持三种通行参数名：
    /// `tok` / `token` / `access_token`（大小写不敏感）；无命中返回 nil。
    static func extractToken(from url: URL) -> String? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        let keys = ["tok", "token", "access_token"]
        for key in keys {
            if let item = items.first(where: { $0.name.lowercased() == key }),
               let value = item.value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg

        if let pageTitle = pageTitle {
            let label = UILabel.make(text: pageTitle, size: 16, color: .white, weight: .semibold)
            label.textAlignment = .center
            view.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.dp(12)),
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(14)),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(14))
            ])
            webView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: DesignTokens.dp(8)),
                webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        } else {
            webView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(webView)
            webView.pinEdges(to: view)
        }

        webView.navigationDelegate = self
        let request = URLRequest(url: targetURL)
        webView.load(request)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        // 授权回传拦截：令牌命中即回调宿主并终止导航（令牌不落页面 / 不发第三方请求）。
        if let token = Self.extractToken(from: url) {
            decisionHandler(.cancel)
            let callback = onAuthorizedToken
            dismiss(animated: true) {
                DispatchQueue.main.async { callback?(token) }
            }
            return
        }
        // 导航准入：与 JS 桥同一策略（http/https + 内网拦截 + 域白名单）。
        // 自定义 scheme（授权流程中间跳转 xxx://…）不属于 http 页面导航，
        // 无法加载也没必要拦截——直接放行交给系统处理会失败，这里取消并保持当前页。
        let absolute = url.absoluteString
        if absolute.lowercased().hasPrefix("http://") || absolute.lowercased().hasPrefix("https://") {
            decisionHandler(policy.allows(absolute) ? .allow : .cancel)
        } else {
            decisionHandler(.cancel)
        }
    }
}
