import Foundation
import UIKit

/// R-43/R-49/F-18 局域网同步：端点模型与地址归一（纯逻辑，可测试）。
struct LANSyncEndpoint: Equatable {
    var name: String
    var host: String
    var port: Int

    /// 手动输入的地址（host 或 host:port）→ 端点；非法返回 nil。
    static func parse(_ raw: String, defaultPort: Int = 9978, name: String = "手动设备") -> LANSyncEndpoint? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        for prefix in ["http://", "https://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        guard !text.isEmpty else { return nil }
        var host = text
        var port = defaultPort
        if let colon = text.firstIndex(of: ":") {
            let hostPart = String(text[text.startIndex..<colon])
            let portPart = String(text[text.index(after: colon)...])
            guard let parsed = Int(portPart), (1...65535).contains(parsed), !hostPart.isEmpty else { return nil }
            host = hostPart
            port = parsed
        }
        guard host.rangeOfCharacter(from: CharacterSet(charactersIn: "/ ").union(.whitespaces)) == nil else { return nil }
        return LANSyncEndpoint(name: name, host: host, port: port)
    }

    /// 推送端点 URL：http://{host}:{port}/sync/push
    var pushURL: URL? {
        URL(string: "http://\(host):\(port)/sync/push")
    }

    var displayText: String {
        "\(name)（\(host):\(port)）"
    }
}

/// F-18 服务发现描述（纯逻辑）：影视仓设备在局域网内注册的 Bonjour 服务。
enum LANSyncServiceDescriptor {
    /// Bonjour 服务类型（Info.plist 的 NSBonjourServices 与此处同源）。
    static let serviceType = "_yingshicang._tcp."
    /// 通用 HTTP 服务（TV 盒子普遍只注册 _http._tcp）。
    static let httpType = "_http._tcp."

    static let advertisedTypes: [String] = [serviceType, httpType]
}

/// F-18 局域网设备发现：NetServiceBrowser 封装，发现/移除通过回调上报（主线程）。
final class BonjourDeviceFinder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private(set) var endpoints: [LANSyncEndpoint] = []
    private var onUpdate: (([LANSyncEndpoint]) -> Void)?

    func startSearch(onUpdate: @escaping ([LANSyncEndpoint]) -> Void) {
        stopSearch()
        self.onUpdate = onUpdate
        browser.delegate = self
        browser.searchForServices(ofType: LANSyncServiceDescriptor.serviceType, inDomain: "local.")
    }

    func stopSearch() {
        browser.stop()
        services.removeAll()
        endpoints.removeAll()
        browser.delegate = nil
        onUpdate = nil
    }

    // MARK: - NetServiceBrowserDelegate

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didFind service: NetService,
                           moreComing: Bool) {
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didRemove service: NetService,
                           moreComing: Bool) {
        if let index = services.firstIndex(where: { $0 == service }) {
            services.remove(at: index)
        }
        endpoints.removeAll { $0.name == service.name }
        publishIfReady()
    }

    // MARK: - NetServiceDelegate

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName else { return }
        let endpoint = LANSyncEndpoint(name: sender.name, host: host, port: sender.port)
        endpoints.removeAll { $0.name == endpoint.name }
        endpoints.append(endpoint)
        publishIfReady()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        if let index = services.firstIndex(where: { $0 == sender }) {
            services.remove(at: index)
        }
    }

    private func publishIfReady() {
        let snapshot = endpoints
        let callback = onUpdate
        DispatchQueue.main.async {
            callback?(snapshot)
        }
    }
}

/// R-49 局域网推送：把本机配置（BackupPayload JSON）推送到局域网设备。
enum LANPushService {
    struct PushOutcome: Equatable {
        var success: Bool
        var httpStatus: Int
        var message: String
    }

    /// 构造推送请求（纯函数，可测试）。
    static func makeRequest(to endpoint: LANSyncEndpoint, payload: BackupPayload) -> URLRequest? {
        guard let url = endpoint.pushURL,
              let json = BackupPayload.encodeJSON(payload),
              let body = json.data(using: .utf8) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        return request
    }

    /// 执行推送（网络面；真机复测口径）。
    static func push(to endpoint: LANSyncEndpoint,
                     completion: @escaping (PushOutcome) -> Void) {
        let payload = BackupPayload.make()
        guard let request = makeRequest(to: endpoint, payload: payload) else {
            completion(PushOutcome(success: false, httpStatus: 0, message: "推送数据构造失败"))
            return
        }
        URLSession.shared.dataTask(with: request) { _, response, error in
            let outcome: PushOutcome
            if let error = error {
                outcome = PushOutcome(success: false, httpStatus: 0, message: error.localizedDescription)
            } else if let http = response as? HTTPURLResponse {
                let ok = (200...299).contains(http.statusCode)
                outcome = PushOutcome(success: ok,
                                      httpStatus: http.statusCode,
                                      message: ok ? "推送成功" : "对端返回 HTTP \(http.statusCode)")
            } else {
                outcome = PushOutcome(success: false, httpStatus: 0, message: "未知响应")
            }
            DispatchQueue.main.async { completion(outcome) }
        }.resume()
    }
}

/// R-43 局域网同步弹窗：syncSheetHeight 470dp 贴底弹层。
/// 内容 = 设备发现列表（自动搜索 Bonjour）+ 手动地址输入 + 「推送配置」按钮。
final class LANSyncDialogViewController: CardDialogViewController {
    private let finder = BonjourDeviceFinder()
    private let statusLabel = UILabel.make(size: DesignTokens.Metrics.syncFieldFont,
                                           color: DesignTokens.Colors.text, lines: 0)
    private let manualField = UITextField()
    private let deviceStack = UIStackView.vertical(spacing: DesignTokens.dp(6))
    private var selectedEndpoint: LANSyncEndpoint?
    private var devices: [LANSyncEndpoint] = []

    var onFinished: (() -> Void)?

    init() {
        super.init(config: CardDialogViewController.Config(
            title: "局域网同步",
            height: DesignTokens.dp(DesignTokens.Metrics.syncSheetHeight),
            anchor: .bottom,
            showsDragBar: true
        ))
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        finder.startSearch { [weak self] endpoints in
            self?.renderDevices(endpoints)
        }
    }

    deinit {
        finder.stopSearch()
    }

    override func buildBody(into stack: UIStackView) {
        statusLabel.text = "正在搜索局域网内的影视仓设备…"
        stack.addArrangedSubview(statusLabel)

        deviceStack.axis = .vertical
        stack.addArrangedSubview(deviceStack)

        manualField.textColor = .white
        manualField.backgroundColor = DesignTokens.Colors.inputBg
        manualField.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.inputFieldCorner)
        manualField.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.syncFieldFont))
        manualField.autocorrectionType = .no
        manualField.autocapitalizationType = .none
        manualField.keyboardType = .URL
        manualField.placeholder = "手动输入设备地址（IP:端口）"
        manualField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        manualField.leftViewMode = .always
        manualField.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.syncFieldHeight).isActive = true
        stack.addArrangedSubview(manualField)

        let pushButton = UIButton.capsule("推送配置到设备",
                                          size: DesignTokens.Metrics.sheetActionFont,
                                          height: DesignTokens.Metrics.dialogConfirmHeight,
                                          corner: DesignTokens.Metrics.syncButtonCorner)
        pushButton.backgroundColor = DesignTokens.Colors.main
        pushButton.addAction(UIAction { [weak self] _ in
            self?.pushTapped()
        }, for: .touchUpInside)
        stack.addArrangedSubview(pushButton)

        let refreshButton = UIButton.text("重新搜索",
                                          size: DesignTokens.Metrics.syncFieldFont,
                                          color: DesignTokens.Colors.gray)
        refreshButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.statusLabel.text = "正在搜索局域网内的影视仓设备…"
            self.finder.startSearch { [weak self] endpoints in
                self?.renderDevices(endpoints)
            }
        }, for: .touchUpInside)
        stack.addArrangedSubview(refreshButton)
    }

    private func renderDevices(_ endpoints: [LANSyncEndpoint]) {
        devices = endpoints
        deviceStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if endpoints.isEmpty {
            statusLabel.text = "未发现设备。可稍后点「重新搜索」，或手动输入地址（默认端口 9978）。"
            selectedEndpoint = nil
            return
        }
        statusLabel.text = "发现 \(endpoints.count) 台设备，点击选中后推送："
        for endpoint in endpoints {
            let row = UIButton.text(endpoint.displayText,
                                     size: DesignTokens.Metrics.syncFieldFont,
                                     color: .white)
            row.contentHorizontalAlignment = .left
            row.backgroundColor = (endpoint == selectedEndpoint)
                ? DesignTokens.Colors.mainBg44
                : DesignTokens.Colors.cardWhite
            row.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.syncButtonCorner)
            row.addAction(UIAction { [weak self] _ in
                self?.selectedEndpoint = endpoint
                self?.renderDevices(self?.devices ?? [])
            }, for: .touchUpInside)
            row.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.syncFieldHeight).isActive = true
            deviceStack.addArrangedSubview(row)
        }
    }

    private func pushTapped() {
        var endpoint = selectedEndpoint
        if endpoint == nil, let raw = manualField.text, !raw.isEmpty {
            endpoint = LANSyncEndpoint.parse(raw)
        }
        guard let target = endpoint else {
            statusLabel.text = "请先选中一台设备，或在输入框填写地址（IP:端口）。"
            return
        }
        statusLabel.text = "正在推送到 \(target.displayText) …"
        LANPushService.push(to: target) { [weak self] outcome in
            guard let self = self else { return }
            self.statusLabel.text = outcome.message
            if outcome.success {
                self.dismiss(animated: true) { [onFinished] in
                    onFinished?()
                }
            }
        }
    }
}
