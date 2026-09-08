import TideRefresh
import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    // MARK: - Public Properties

    var window: UIWindow?

    // MARK: - Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        controller.title = "TideRefresh"
        controller.view.backgroundColor = .systemBackground
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
