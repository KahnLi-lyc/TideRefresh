import UIKit

@MainActor
final class DemoDetailViewController: UIViewController {
    // MARK: - Private Properties

    private let item: DemoItem

    // MARK: - Views

    private lazy var contentView: UIListContentView = {
        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.text = item.title
        configuration.secondaryText = item.subtitle
        configuration.secondaryTextProperties.numberOfLines = 0
        configuration.image = UIImage(systemName: item.symbol)
        configuration.imageProperties.tintColor = .systemTeal
        let content = UIListContentView(configuration: configuration)
        content.translatesAutoresizingMaskIntoConstraints = false
        return content
    }()

    // MARK: - Initialization

    init(item: DemoItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.title
        view.backgroundColor = .systemBackground
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            contentView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }
}
