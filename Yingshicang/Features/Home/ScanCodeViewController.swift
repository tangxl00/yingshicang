import AVFoundation
import UIKit

/// R-44 扫码页：AVFoundation 相机扫码（QR），扫描结果通过回调交给宿主。
/// 相机不可用（模拟器 / 权限被拒）时降级为手动输入框，保证页面始终可用。
/// 相机行为需真机复测；CI 与模拟器走手动输入路径。
final class ScanCodeViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    private let onScanned: (String) -> Void
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "scan.camera.queue")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isSessionConfigured = false
    private var lastScannedAt: Date?

    private let statusLabel = UILabel.make(size: 13, color: DesignTokens.Colors.text, lines: 0)
    private let manualField = UITextField()
    private let scanHintLabel = UILabel.make(size: 12, color: DesignTokens.Colors.text, lines: 0)

    /// 扫描冷却（秒）：避免同一张码连续触发多次回调。
    static let scanCooldown: TimeInterval = 2.0

    init(onScanned: @escaping (String) -> Void) {
        self.onScanned = onScanned
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Colors.mainBg
        title = "扫码"

        let stack = UIStackView.vertical(spacing: DesignTokens.dp(12))
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: DesignTokens.dp(16), left: DesignTokens.dp(14),
            bottom: DesignTokens.dp(16), right: DesignTokens.dp(14)
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.dp(12)),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        scanHintLabel.text = "将二维码对准取景框即可自动识别；相机不可用时可在下方手动输入地址。"
        stack.addArrangedSubview(scanHintLabel)

        statusLabel.text = "正在请求相机权限…"
        stack.addArrangedSubview(statusLabel)

        manualField.textColor = .white
        manualField.backgroundColor = DesignTokens.Colors.inputBg
        manualField.layer.cornerRadius = DesignTokens.dp(DesignTokens.Metrics.inputFieldCorner)
        manualField.font = .systemFont(ofSize: DesignTokens.sp(DesignTokens.Metrics.inputFieldFont))
        manualField.autocorrectionType = .no
        manualField.autocapitalizationType = .none
        manualField.keyboardType = .URL
        manualField.placeholder = "手动输入配置地址"
        manualField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        manualField.leftViewMode = .always
        manualField.heightAnchor.constraint(equalToConstant: DesignTokens.Metrics.inputFieldHeight).isActive = true
        stack.addArrangedSubview(manualField)

        let confirmButton = UIButton.capsule("确认地址",
                                             size: DesignTokens.Metrics.sheetActionFont,
                                             height: DesignTokens.Metrics.dialogConfirmHeight,
                                             corner: DesignTokens.Metrics.dialogConfirmCorner)
        confirmButton.backgroundColor = DesignTokens.Colors.main
        confirmButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            let text = (self.manualField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            self.finish(with: text)
        }, for: .touchUpInside)
        stack.addArrangedSubview(confirmButton)

        configureSession()
    }

    // MARK: - 相机会话

    private func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSessionAndPreview()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupSessionAndPreview()
                    } else {
                        self?.statusLabel.text = "相机权限被拒绝，请使用手动输入，或在系统设置中开启相机权限。"
                    }
                }
            }
        default:
            statusLabel.text = "相机权限被拒绝，请使用手动输入，或在系统设置中开启相机权限。"
        }
    }

    private func setupSessionAndPreview() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            statusLabel.text = "当前设备无可用相机（模拟器），请使用手动输入。"
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            statusLabel.text = "相机初始化失败，请使用手动输入。"
            return
        }
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            statusLabel.text = "相机初始化失败，请使用手动输入。"
            return
        }

        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()
        isSessionConfigured = true
        statusLabel.text = "相机已就绪，对准二维码自动识别。"

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.cornerRadius = DesignTokens.Corner.card
        layer.masksToBounds = true
        previewLayer = layer

        let previewHolder = UIView()
        previewHolder.backgroundColor = DesignTokens.Colors.black60
        previewHolder.layer.cornerRadius = DesignTokens.Corner.card
        previewHolder.layer.masksToBounds = true
        previewHolder.heightAnchor.constraint(equalToConstant: DesignTokens.dp(220)).isActive = true
        previewHolder.layer.addSublayer(layer)
        // layer 不参与 Auto Layout，布局时机通过回调对齐宿主 bounds。
        previewDidLayout = { [weak self, weak previewHolder] in
            guard let self = self, let holder = previewHolder else { return }
            self.previewLayer?.frame = holder.bounds
        }

        if let stack = scanHintLabel.superview, let index = stack.arrangedSubviews.firstIndex(of: scanHintLabel) {
            stack.insertArrangedSubview(previewHolder, at: index + 1)
        }
    }

    private var previewDidLayout: (() -> Void)?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewDidLayout?()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard isSessionConfigured else { return }
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isSessionConfigured else { return }
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - 扫描回调

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }
        let now = Date()
        if let last = lastScannedAt, now.timeIntervalSince(last) < ScanCodeViewController.scanCooldown {
            return
        }
        lastScannedAt = now
        finish(with: value)
    }

    private func finish(with value: String) {
        onScanned(value)
        if presentingViewController != nil {
            dismiss(animated: true)
        } else if let nav = navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        }
    }
}
