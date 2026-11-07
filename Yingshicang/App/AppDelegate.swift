import AVFoundation
import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 全应用强制深色：原 App 资源里的主背景 #001A37 是深色体系，
        // 一旦跟随系统浅色，标题与分隔线对比度会失效。
        if #available(iOS 13.0, *) {
            application.windows.forEach { $0.overrideUserInterfaceStyle = .dark }
        }
        configureAudioSession()
        AppEnvironment.shared.bootstrap()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = .dark
        window.backgroundColor = DesignTokens.Colors.mainBg
        window.rootViewController = AppEnvironment.shared.makeRootController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    /// 后台播放的音频会话（质检 P2：`UIBackgroundModes=audio` 声明此前没有对应实现，
    /// 完全没有配置 `AVAudioSession`，退到后台会被系统静音）。
    ///
    /// 选 `.playback`：这是唯一允许「屏幕锁定/切后台继续出声」的分类；
    /// `mode: .moviePlayback` 让系统按影视内容处理（不做语音优化、不打断其他 App 的短提示音策略）。
    /// 配置失败只记日志：播放前台仍可用，不能因为音频会话失败就阻断启动。
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
            Log.info("[Audio] session ready: playback/moviePlayback")
        } catch {
            Log.error("[Audio] session setup failed: \(error.localizedDescription)")
        }
    }

    /// 播放中被电话/其他 App 抢占时，系统会中断音频；恢复前台后重新激活会话，
    /// 否则后续 `AVPlayer.play()` 会静默无声。
    func applicationDidBecomeActive(_ application: UIApplication) {
        guard AVAudioSession.sharedInstance().isOtherAudioPlaying == false else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
