import UIKit

/// 应用级依赖容器。
/// 用单例而不是依赖注入框架：本项目服务对象单一、无测试替身需求，
/// 但所有可变状态都集中在这里，便于「重置 App」时统一清理。
final class AppEnvironment {
    static let shared = AppEnvironment()

    private init() {}

    func bootstrap() {
        AppDatabase.shared.setup()
        // 首次启动落一个演示配置地址，让用户进入首页就有内容可选。
        // 该地址来自原 App 的默认配置行为（R-27「配置地址」行始终有值），
        // 具体默认值在文档中未给出，本工程按「留空 + 引导用户输入」实现。
        if ConfigRepository.shared.currentConfigURL.isEmpty,
           let line = StoreHouseStore.shared.currentLine {
            ConfigRepository.shared.setCurrentConfigURL(line.url)
        }
    }

    func makeRootController() -> UIViewController {
        let tab = MainTabBarController()
        return tab
    }
}
