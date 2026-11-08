import UIKit

/// R-42 TV 互动指令集：手机端遥控 TV 版影视仓的按键语义。
enum InteractionCommand: String, CaseIterable {
    case up = "up"
    case down = "down"
    case left = "left"
    case right = "right"
    case ok = "ok"
    case back = "back"
    case home = "home"
    case menu = "menu"
    case play = "play"
    case pause = "pause"

    var displayName: String {
        switch self {
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        case .ok: return "确认"
        case .back: return "返回"
        case .home: return "主页"
        case .menu: return "菜单"
        case .play: return "播放"
        case .pause: return "暂停"
        }
    }
}

/// R-42 TV 互动指令编码（纯函数，可测试）。
enum InteractionMessenger {
    /// 目标地址归一化：补 scheme、去尾部斜杠；非法输入返回 nil。
    static func normalizeBase(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.hasPrefix("http://") && !text.hasPrefix("https://") {
            text = "http://" + text
        }
        while text.count > 1 && text.hasSuffix("/") { text.removeLast() }
        guard URL(string: text) != nil, text.hasPrefix("http") else { return nil }
        return text
    }

    /// 指令 → 请求 URL：{base}/interaction?key={command.rawValue}
    static func requestURL(for command: InteractionCommand, base: String) -> URL? {
        guard let normalized = normalizeBase(base) else { return nil }
        return URL(string: "\(normalized)/interaction?key=\(command.rawValue)")
    }

    /// 指令 → 请求体（TV 端 HTTP 端点约定的 JSON）。
    static func requestBody(for command: InteractionCommand) -> Data {
        let payload: [String: String] = ["key": command.rawValue]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }
}

/// R-42 TV 互动页：向同局域网的 TV 端（影视仓 TV 版）发送遥控指令。
/// 布局按 Metrics.interactionXXX：标题 paddingTop 30dp 16sp、提示条 25dp 圆角 12dp、
/// 方向按钮高 80dp 圆角 12dp、发送按钮 40dp 高圆角 20dp。
final class InteractionViewController: SwipeBackViewController {
    private let baseField = UITextField()
    private let tipLabel = UILabel.make(size: 12, color: DesignTokens.Colors.text, lines: 0)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        title = "TV 互动"

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.pinEdges(to: view)

        let stack = UIStackView.vertical(spacing: DesignTokens.dp(12))
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: DesignTokens.Metrics.interactionTopPadding, left: DesignTokens.dp(14),
            bottom: DesignTokens.dp(20), right: DesignTokens.dp(14)
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        let titleLabel = UILabel.make(text: "TV 遥控",
                                      size: DesignTokens.Metrics.settingTitleFont,
                                      color: .white, weight: .semibold)
        stack.addArrangedSubview(titleLabel)

        tipLabel.backgroundColor = DesignTokens.Colors.cardWhite
        tipLabel.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.interactionTipCorner)
        tipLabel.layer.masksToBounds = true
        tipLabel.text = "输入 TV 端显示的互动地址（如 192.168.1.8:9978），点击按键即发送遥控指令。"
        stack.addArrangedSubview(tipLabel)

        baseField.textColor = .white
        baseField.backgroundColor = DesignTokens.Colors.inputBg
        baseField.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.inputFieldCorner)
        baseField.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.inputFieldFont))
        baseField.autocorrectionType = .no
        baseField.autocapitalizationType = .none
        baseField.keyboardType = .URL
        baseField.placeholder = "TV 端互动地址（IP:端口）"
        baseField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        baseField.leftViewMode = .always
        baseField.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.inputFieldHeight).isActive = true
        stack.addArrangedSubview(baseField)

        // 方向区：上 / 左·确认·右 / 下 三行。
        let upRow = buttonRow([.up])
        let midRow = buttonRow([.left, .ok, .right])
        let downRow = buttonRow([.down])
        stack.addArrangedSubview(upRow)
        stack.addArrangedSubview(midRow)
        stack.addArrangedSubview(downRow)

        let actionRow = UIStackView.horizontal(spacing: DesignTokens.dp(8))
        for command in [InteractionCommand.back, .home, .menu, .play, .pause] {
            actionRow.addArrangedSubview(commandButton(command))
        }
        stack.addArrangedSubview(actionRow)
    }

    private func buttonRow(_ commands: [InteractionCommand]) -> UIStackView {
        let row = UIStackView.horizontal(spacing: DesignTokens.dp(8))
        for command in commands {
            row.addArrangedSubview(commandButton(command))
        }
        return row
    }

    private func commandButton(_ command: InteractionCommand) -> UIButton {
        let button = UIButton.capsule(command.displayName,
                                      size: 14,
                                      height: DesignTokens.Metrics.interactionButtonHeight,
                                      corner: DesignTokens.Metrics.interactionButtonCorner)
        button.addAction(UIAction { [weak self] _ in
            self?.send(command)
        }, for: .touchUpInside)
        return button
    }

    private func send(_ command: InteractionCommand) {
        let raw = baseField.text ?? ""
        guard let url = InteractionMessenger.requestURL(for: command, base: raw) else {
            tipLabel.text = "地址无效，请输入 TV 端显示的互动地址（IP:端口）。"
            return
        }
        tipLabel.text = "已发送：\(command.displayName)（\(command.rawValue)）"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = InteractionMessenger.requestBody(for: command)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.tipLabel.text = "发送失败：\(error.localizedDescription)"
                } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    self.tipLabel.text = "TV 端返回 HTTP \(http.statusCode)"
                } else {
                    self.tipLabel.text = "指令已送达：\(command.displayName)"
                }
            }
        }.resume()
    }
}
