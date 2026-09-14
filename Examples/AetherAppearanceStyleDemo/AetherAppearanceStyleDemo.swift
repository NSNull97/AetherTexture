import UIKit
import AetherUI

public final class AetherAppearanceStyleDemoApp: AetherApp {
    public init() {}

    public var current: some ApplicationBuilder {
        AetherApplication {
            AppearanceStyle(.legacy)
            WindowScene(id: "main") { _ in
                let root = AppearanceDemoController()
                return AetherNavigationController(rootViewController: root)
            }
        }
    }
}

private final class AppearanceDemoController: AetherViewController, AetherControllerAppearanceProviding {
    private let stackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Appearance"

        stackView.axis = .vertical
        stackView.spacing = 12.0
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for style in AetherAppearanceStyle.allCases {
            let button = makeButton(title: style.displayName) {
                AetherApplicationRuntime.shared?.updateAppearanceStyle(style)
            }
            button.accessibilityIdentifier = style.stableIdentifier
            stackView.addArrangedSubview(button)
        }
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24.0),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24.0),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .navigation, context.appearance.style == .liquidGlassV2 else {
            return nil
        }
        return AetherAppearanceOverride(
            navigationBar: AetherNavigationBarAppearanceOverride(
                separator: .visible(color: .separator, opacity: 0.35)
            )
        )
    }

    private func makeButton(title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}
