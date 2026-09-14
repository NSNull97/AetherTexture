import UIKit
import AetherUI

private final class ExampleAppearanceRuntimeDefinition: AetherApp {
    init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            AppearanceStyle(.liquidGlassV1)
        }
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = AetherApplicationRuntime.installShared(ExampleAppearanceRuntimeDefinition.self)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
