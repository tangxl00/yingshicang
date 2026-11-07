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
        AppEnvironment.shared.bootstrap()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = .dark
        window.backgroundColor = DesignTokens.Colors.mainBg
        window.rootViewController = AppEnvironment.shared.makeRootController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
