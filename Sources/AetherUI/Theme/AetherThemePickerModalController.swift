import UIKit

/// An Aether bottom card that fits the theme picker with 8pt outer margins.
/// The height adapts to the available width and reserves only the portion
/// of the bottom safe area that overlaps the floating surface.
public final class AetherThemePickerModalController: AetherModalController {
    public typealias Theme = AetherThemePickerView.Theme

    /// The picker hosted by this modal. Its bounds match the modal surface.
    public let pickerView: AetherThemePickerView

    /// Called after the picker changes selection. The modal does not change
    /// the presenting window automatically; apply the value in this callback.
    public var themeChanged: ((Theme) -> Void)?

    /// When enabled, dismisses the modal after delivering `themeChanged`.
    public var dismissAfterSelection = false

    public var theme: Theme {
        get { pickerView.theme }
        set { pickerView.setTheme(newValue, animated: true) }
    }

    public init(
        theme: Theme = .system,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        let picker = AetherThemePickerView(theme: theme)
        picker.segmentedControl.appearanceStyleOverride = appearanceStyle
        self.pickerView = picker
        let config = Config(
            sideInset: 8.0,
            bottomInsetStage1: 8.0,
            bottomInsetStage2: 8.0,
            topInsetStage1: 0.0,
            topInsetStage2: 0.0,
            topCornerRadius: 26.0,
            bottomCornerRadiusStage1: 26.0,
            bottomCornerRadiusStage2: 26.0,
            bottomCornersFollowContainer: true,
            dimAlphaStage1: 0.25,
            dimAlphaStage2: 0.25,
            detents: [.stage1],
            initialDetent: .stage1,
            sizesToContent: true,
            showsGrabber: false
        )
        super.init(config: config)
        if let appearanceStyle {
            self.appearanceStyle = appearanceStyle
        }
        picker.themeChanged = { [weak self] theme in
            guard let self else { return }
            self.themeChanged?(theme)
            if self.dismissAfterSelection {
                self.dismiss(animated: true)
            }
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        pickerView.usesModalSurfaceCorners = true
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pickerView)
        NSLayoutConstraint.activate([
            pickerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pickerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pickerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pickerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    public override func contentHeight(forWidth width: CGFloat, safeAreaInsets: UIEdgeInsets) -> CGFloat {
        pickerView.contentSize(forWidth: width, bottomSafeAreaInset: safeAreaInsets.bottom).height
    }

    /// Presents this controller through the standard Aether modal transition.
    public func present(
        from presenter: UIViewController,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        presenter.present(self, animated: animated, completion: completion)
    }
}
