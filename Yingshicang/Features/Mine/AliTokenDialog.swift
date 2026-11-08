import UIKit

/// R-48 阿里 Token 校验：normalize 去首尾与内部空白；合法 = 32 位十六进制字符。
enum AliTokenValidator {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }

    static func isValid(_ raw: String) -> Bool {
        let token = normalize(raw)
        guard token.count == 32 else { return false }
        return token.allSatisfy { c in c.isHexDigit }
    }
}

/// R-48 阿里 Token 弹层：居中弹窗（inputDialogHeight 220dp 口径），输入 32 位 Token，
/// 校验通过后写入 Settings.aliToken。
final class AliTokenDialogViewController: CardDialogViewController {
    private let textField = UITextField()
    private let errorLabel = UILabel.make(size: DesignTokens.Metrics.inputFieldFont,
                                          color: DesignTokens.Colors.accentRed,
                                          lines: 0)
    private let onSaved: (() -> Void)?

    init(onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
        super.init(config: CardDialogViewController.Config(
            title: "阿里云盘 Token",
            height: DesignTokens.dp(DesignTokens.Metrics.inputDialogHeight),
            anchor: .center
        ))
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        textField.text = Settings.shared.aliToken
    }

    override func buildBody(into stack: UIStackView) {
        let hint = UILabel.make(
            text: "用于网盘类站点的阿里云盘直链解析。Token 为 32 位十六进制字符串，保存后立即对网盘站点生效。",
            size: DesignTokens.Metrics.inputFieldFont,
            color: DesignTokens.Colors.text,
            lines: 0
        )
        stack.addArrangedSubview(hint)

        textField.textColor = .white
        textField.backgroundColor = DesignTokens.Colors.inputBg
        textField.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.inputFieldCorner)
        textField.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.inputFieldFont))
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.placeholder = "粘贴 32 位 Token"
        textField.clearButtonMode = .whileEditing
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        textField.leftViewMode = .always
        textField.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.inputFieldHeight).isActive = true
        stack.addArrangedSubview(textField)

        errorLabel.text = " "
        stack.addArrangedSubview(errorLabel)

        let saveButton = UIButton.capsule("保存",
                                          size: DesignTokens.Metrics.sheetActionFont,
                                          height: DesignTokens.Metrics.dialogConfirmHeight,
                                          corner: DesignTokens.Metrics.dialogConfirmCorner)
        saveButton.backgroundColor = DesignTokens.Colors.main
        saveButton.addAction(UIAction { [weak self] _ in
            self?.saveTapped()
        }, for: .touchUpInside)
        stack.addArrangedSubview(saveButton)

        let clearButton = UIButton.text("清除 Token",
                                        size: DesignTokens.Metrics.sheetActionFont,
                                        color: DesignTokens.Colors.gray)
        clearButton.addAction(UIAction { [weak self] _ in
            Settings.shared.aliToken = ""
            self?.textField.text = nil
            self?.errorLabel.text = " "
            AliDriveClient.shared.reset()
            self?.onSaved?()
        }, for: .touchUpInside)
        stack.addArrangedSubview(clearButton)

        // R-47：H5 授权容器的真实业务入口——打开阿里云盘开放平台授权页，
        // 授权流程结束时地址带 tok/token/access_token 参数会被容器拦截回传，
        // 这里校验通过才落 Keychain（与手动粘贴同一条校验链）。
        let webAuthButton = UIButton.text("网页授权获取 Token",
                                          size: DesignTokens.Metrics.sheetActionFont,
                                          color: DesignTokens.Colors.main)
        webAuthButton.addAction(UIAction { [weak self] _ in self?.webAuthorizeTapped() },
                                for: .touchUpInside)
        stack.addArrangedSubview(webAuthButton)
    }

    /// 网页授权：影视仓未内置开放平台应用凭据（client_id/secret 属于注册应用所有者），
    /// 用户自配过 client_id 时走完整授权页；没有时如实提示为什么只能手动粘贴。
    private func webAuthorizeTapped() {
        guard let url = AliDriveAuth.authorizeURL(clientID: Settings.shared.aliClientID,
                                                  redirectURI: "https://openapi.alipan.com/oauth/callback") else {
            errorLabel.text = "网页授权需要在设置里填写开放平台 Client ID；未注册应用时请手动粘贴 Token"
            return
        }
        let container = WebContainerViewController.authorizing(
            url: url,
            allowedHosts: ["openapi.alipan.com", "auth.alipan.com", "www.alipan.com"]) { [weak self] token in
                // 与手动粘贴同一条校验链：不合法的回传不落盘。
                guard AliTokenValidator.isValid(token) else {
                    self?.errorLabel.text = "网页回传的 Token 格式不正确（32 位十六进制）"
                    return
                }
                Settings.shared.aliToken = AliTokenValidator.normalize(token)
                AliDriveClient.shared.reset()
                self?.onSaved?()
            }
        present(container, animated: true)
    }

    private func saveTapped() {
        let raw = textField.text ?? ""
        guard AliTokenValidator.isValid(raw) else {
            let token = AliTokenValidator.normalize(raw)
            errorLabel.text = token.isEmpty
                ? "Token 不能为空"
                : "格式不正确：需要 32 位十六进制字符，当前 \(token.count) 位"
            return
        }
        Settings.shared.aliToken = AliTokenValidator.normalize(raw)
        AliDriveClient.shared.reset()
        errorLabel.text = " "
        dismiss(animated: true)
        onSaved?()
    }
}

/// R-39 网盘页（best-effort）：展示阿里 Token 配置状态与说明，提供 Token 弹层入口。
final class NetdiskViewController: SwipeBackViewController,
                                    UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel.make(size: 12, color: DesignTokens.Colors.text, lines: 0)
    private var files: [AliDriveFile] = []
    /// 目录栈：从根目录一层层进，栈底是 "root"。
    private var folderStack: [String] = ["root"]
    private let client: AliDriveClient
    /// 目录栈 >1 层时可见；根目录隐藏（退出走左滑边缘）。
    private let upButton = UIButton(type: .system)

    init(client: AliDriveClient = .shared) {
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private var currentFolder: String { folderStack.last ?? "root" }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        title = "网盘"

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AliFileCell")
        tableView.rowHeight = DesignTokens.dp(46)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(24)),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(24))
        ])

        // 全屏 present、无导航控制器：Token 入口与「返回上级」都自绘。
        let tokenButton = UIButton.text("Token 管理", size: 13, color: DesignTokens.Colors.main)
        tokenButton.addAction(UIAction { [weak self] _ in self?.openTokenDialog() }, for: .touchUpInside)
        tokenButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tokenButton)

        upButton.setTitle("← 返回上级目录", for: .normal)
        upButton.setTitleColor(.white, for: .normal)
        upButton.titleLabel?.font = .systemFont(ofSize: 13)
        upButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            guard self.folderStack.count > 1 else { return }
            self.folderStack.removeLast()
            self.loadCurrentFolder()
        }, for: .touchUpInside)
        upButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(upButton)

        NSLayoutConstraint.activate([
            tokenButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.dp(8)),
            tokenButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.dp(14)),
            upButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.dp(8)),
            upButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.dp(14))
        ])

        loadCurrentFolder()
    }

    @objc private func openTokenDialog() {
        present(AliTokenDialogViewController { [weak self] in
            self?.client.reset()
            self?.folderStack = ["root"]
            self?.loadCurrentFolder()
        }, animated: true)
    }

    private func loadCurrentFolder() {
        let token = Settings.shared.aliToken
        guard AliTokenValidator.isValid(token) else {
            statusLabel.isHidden = false
            statusLabel.text = "未配置阿里云盘 Token。\n点右上角「Token」粘贴 32 位开放平台 Token 后即可浏览网盘文件。"
            files = []
            tableView.isHidden = true
            return
        }
        statusLabel.isHidden = false
        statusLabel.text = currentFolder == "root" ? "正在读取网盘根目录…" : "正在读取…"
        tableView.isHidden = true
        client.list(parentFileId: currentFolder) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let items):
                self.files = items
                self.statusLabel.isHidden = !items.isEmpty
                if items.isEmpty { self.statusLabel.text = "该目录为空" }
                self.tableView.isHidden = false
                self.tableView.reloadData()
                self.upButton.isHidden = self.folderStack.count <= 1
            case .failure(let error):
                self.files = []
                self.statusLabel.isHidden = false
                // 失败原文透出（401 = Token 失效；网络错误带真实原因），不吞错。
                self.statusLabel.text = "读取失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - UITableViewDataSource / Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        files.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AliFileCell", for: indexPath)
        let file = files[indexPath.row]
        var config = UIListContentConfiguration.cell()
        config.text = file.isFolder ? "📁 \(file.name ?? "未命名目录")" : (file.name ?? "未命名文件")
        config.textProperties.color = .white
        if let size = file.size, size > 0 {
            config.secondaryText = DownloadService.sizeText(size)
            config.secondaryTextProperties.color = DesignTokens.Colors.gray
        }
        cell.contentConfiguration = config
        cell.backgroundColor = .clear
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let file = files[indexPath.row]
        guard let fileId = file.fileId, !fileId.isEmpty else { return }
        if file.isFolder {
            folderStack.append(fileId)
            loadCurrentFolder()
            return
        }
        // 视频文件 → 取直链 → 直接进播放器（直链有时效，取到即播，不做二级缓存）。
        statusLabel.isHidden = false
        statusLabel.text = "正在获取播放地址…"
        client.downloadURL(fileId: fileId) { [weak self] result in
            guard let self = self else { return }
            self.statusLabel.isHidden = true
            switch result {
            case .success(let url):
                guard let target = URL(string: url) else {
                    self.statusLabel.isHidden = false
                    self.statusLabel.text = "播放失败：直链地址无效"
                    return
                }
                let player = LocalFilePlayerViewController(fileURL: target, title: file.name ?? "网盘播放")
                self.present(player, animated: true)
            case .failure(let error):
                self.statusLabel.isHidden = false
                self.statusLabel.text = "播放失败：\(error.localizedDescription)"
            }
        }
    }

}
