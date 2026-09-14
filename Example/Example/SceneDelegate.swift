import UIKit
import AetherUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var appearanceObserver: NSObjectProtocol?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = AetherNativeWindow(windowScene: windowScene)
        let tabs = ExampleRootFactory.makeRoot(window: window, observer: &appearanceObserver)

        window.contentController = tabs
        window.makeKeyAndVisible()
        self.window = window
    }
}
