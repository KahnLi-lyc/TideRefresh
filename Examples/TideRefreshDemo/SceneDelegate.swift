import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    // MARK: - Public Properties

    var window: UIWindow?

    // MARK: - Lifecycle

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let navigation = UINavigationController(rootViewController: DemoViewController())
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--dark-mode") { window.overrideUserInterfaceStyle = .dark }
        if let index = arguments.firstIndex(of: "--demo-mode"),
           arguments.indices.contains(index + 1),
           let mode = DemoMode(rawValue: arguments[index + 1])
        {
            navigation.setViewControllers([DemoViewController(), DemoListViewController(mode: mode)], animated: false)
        }
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        self.window = window
    }
}
