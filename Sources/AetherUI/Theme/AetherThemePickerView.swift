import UIKit

/// A small, self-contained theme switcher with an animated day/night scene.
///
/// The picker owns the visual state only. Hosts can apply the selected value
/// to their appearance coordinator through `themeChanged` (or observe
/// `UIControl.Event.valueChanged`). The `.system` value follows the current
/// trait collection without changing the host application's appearance.
public final class AetherThemePickerView: UIControl {

    // MARK: - Public API

    public enum Theme: String, CaseIterable, Codable, Sendable, Equatable, Hashable {
        case light
        case dark
        case system

        public var title: String {
            switch self {
            case .light: return "Light"
            case .dark: return "Dark"
            case .system: return "System"
            }
        }

        /// Human-readable title suitable for settings lists and tests.
        public var displayName: String { title }

        public var accessibilityLabel: String { title }

        fileprivate var iconName: String {
            switch self {
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            case .system: return "circle.lefthalf.filled"
            }
        }
    }

    /// Alias retained for callers that prefer the shorter mode terminology.
    public typealias Mode = Theme

    /// The selected value. Assigning this value updates the picker without an
    /// animation; use `setTheme(_:animated:)` for an explicit transition.
    public var theme: Theme {
        get { selectedTheme }
        set { setTheme(newValue, animated: false) }
    }

    /// Alias for `theme` used by controls that call this value a mode.
    public var mode: Mode {
        get { selectedTheme }
        set { setTheme(newValue, animated: false) }
    }

    public private(set) var selectedTheme: Theme

    /// Called after the selection changes. The control also sends
    /// `UIControl.Event.valueChanged` for target/action clients.
    public var themeChanged: ((Theme) -> Void)?

    /// Closure spelling used by some Aether controls.
    public var modeChanged: ((Mode) -> Void)?

    /// Optional minimum card height. Zero fits the landscape, segment and
    /// caption without leaving an unused band below the content.
    public var preferredHeight: CGFloat = 0.0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    public override var intrinsicContentSize: CGSize {
        contentSize(forWidth: 320.0, bottomSafeAreaInset: 0)
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = size.width.isFinite && size.width > 0 ? size.width : intrinsicContentSize.width
        return contentSize(forWidth: width, bottomSafeAreaInset: safeAreaInsets.bottom)
    }

    /// Measure the same spacing used by the view's constraints. Bottom safe
    /// area is supplied by the host after its floating-card inset is removed.
    func contentSize(forWidth width: CGFloat, bottomSafeAreaInset: CGFloat) -> CGSize {
        let captionWidth = max(0, width - 36.0)
        let captionHeight = ceil(captionLabel.sizeThatFits(
            CGSize(width: captionWidth, height: .greatestFiniteMagnitude)
        ).height)
        let contentHeight = 12.0 + max(0, width - 24.0) * 0.52 + 12.0
            + segmentedControl.preferredHeight + 8.0 + captionHeight + 12.0
        return CGSize(width: width, height: max(preferredHeight, contentHeight) + max(0, bottomSafeAreaInset))
    }

    /// A modal owns its adaptive outline. The opaque card must fill that
    /// outline rather than clipping it again with standalone fixed corners.
    var usesModalSurfaceCorners = false {
        didSet {
            cardView.layer.cornerRadius = usesModalSurfaceCorners ? 0 : 26
            cardView.layer.masksToBounds = !usesModalSurfaceCorners
        }
    }

    public init(theme: Theme = .system, frame: CGRect = .zero) {
        self.selectedTheme = theme
        super.init(frame: frame)
        commonInit()
    }

    public convenience init(mode: Mode, frame: CGRect = .zero) {
        self.init(theme: mode, frame: frame)
    }

    public required init?(coder: NSCoder) {
        self.selectedTheme = .system
        super.init(coder: coder)
        commonInit()
    }

    /// Selects a theme and optionally animates the landscape and selection
    /// pill. Setting the current value is a no-op and does not emit events.
    public func setTheme(_ theme: Theme, animated: Bool = true) {
        guard theme != selectedTheme else { return }
        selectedTheme = theme
        updateInterfaceStyleOverride()
        updateCaption()
        let shouldAnimate = animated && !UIAccessibility.isReduceMotionEnabled
        updateCardColors(animated: shouldAnimate)
        segmentedControl.setSelectedIndex(Theme.allCases.firstIndex(of: theme) ?? 0, animated: shouldAnimate)
        themeChanged?(theme)
        modeChanged?(theme)
        sendActions(for: .valueChanged)
    }

    // MARK: - View hierarchy

    private let cardView = UIView()
    private let sceneView = ThemeSceneView()
    /// The same glass/lens segmented control used throughout Aether.
    public let segmentedControl = AetherSegmentedControl(items: Theme.allCases.map { theme in
        AetherSegmentedControl.Item(
            title: theme.title,
            image: UIImage(systemName: theme.iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        )
    })
    private let captionLabel = UILabel()
    private var reduceMotionObserver: NSObjectProtocol?

    private func commonInit() {
        isOpaque = false
        backgroundColor = .clear
        accessibilityIdentifier = "aether.themePicker"
        isAccessibilityElement = false

        cardView.layer.cornerRadius = 26.0
        cardView.layer.cornerCurve = .continuous
        cardView.layer.masksToBounds = true
        addSubview(cardView)

        sceneView.isAccessibilityElement = false
        cardView.addSubview(sceneView)

        segmentedControl.titleFont = .systemFont(ofSize: 13, weight: .semibold)
        segmentedControl.selectedTitleFont = .systemFont(ofSize: 13, weight: .semibold)
        segmentedControl.itemHorizontalPadding = 8.0
        segmentedControl.selectedIndex = Theme.allCases.firstIndex(of: selectedTheme) ?? 0
        segmentedControl.accessibilityIdentifier = "aether.themePicker.segmentedControl"
        segmentedControl.selectedIndexChanged = { [weak self] index in
            guard Theme.allCases.indices.contains(index) else { return }
            self?.setTheme(Theme.allCases[index], animated: true)
        }
        cardView.addSubview(segmentedControl)

        captionLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .medium)
        captionLabel.textAlignment = .center
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.numberOfLines = 2
        captionLabel.isAccessibilityElement = false
        cardView.addSubview(captionLabel)

        setupConstraints()
        updateInterfaceStyleOverride()
        updateCaption()
        updateCardColors(animated: false)
        reduceMotionObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCardColors(animated: false)
        }
    }

    private func setupConstraints() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            sceneView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12.0),
            sceneView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12.0),
            sceneView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12.0),
            sceneView.heightAnchor.constraint(equalTo: sceneView.widthAnchor, multiplier: 0.52),

            segmentedControl.leadingAnchor.constraint(equalTo: sceneView.leadingAnchor),
            segmentedControl.trailingAnchor.constraint(equalTo: sceneView.trailingAnchor),
            segmentedControl.topAnchor.constraint(equalTo: sceneView.bottomAnchor, constant: 12.0),
            segmentedControl.heightAnchor.constraint(equalToConstant: segmentedControl.preferredHeight),

            captionLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18.0),
            captionLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18.0),
            captionLabel.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8.0),
            captionLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.safeAreaLayoutGuide.bottomAnchor, constant: -12.0)
        ])
    }

    deinit {
        if let reduceMotionObserver {
            NotificationCenter.default.removeObserver(reduceMotionObserver)
        }
    }

    // MARK: - State and accessibility

    private var effectiveDark: Bool {
        switch selectedTheme {
        case .light: return false
        case .dark: return true
        case .system: return traitCollection.userInterfaceStyle == .dark
        }
    }

    private func updateInterfaceStyleOverride() {
        switch selectedTheme {
        case .light: overrideUserInterfaceStyle = .light
        case .dark: overrideUserInterfaceStyle = .dark
        case .system: overrideUserInterfaceStyle = .unspecified
        }
    }

    private func updateCaption() {
        switch selectedTheme {
        case .light:
            captionLabel.text = "Light appearance stays on, day and night."
        case .dark:
            captionLabel.text = "Dark appearance stays on, day and night."
        case .system:
            captionLabel.text = "Follows your device appearance."
        }
        invalidateIntrinsicContentSize()
    }

    private func updateCardColors(animated: Bool) {
        let dark = effectiveDark
        let updates = {
            self.cardView.backgroundColor = dark ? UIColor(red: 0.075, green: 0.075, blue: 0.09, alpha: 1) : UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
            self.captionLabel.textColor = dark ? UIColor.white.withAlphaComponent(0.55) : UIColor.black.withAlphaComponent(0.52)
        }
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: updates)
        } else {
            updates()
        }
        segmentedControl.isDarkAppearance = dark
        segmentedControl.updateTheme(.init(
            textColor: dark ? UIColor.white.withAlphaComponent(0.65) : UIColor.black.withAlphaComponent(0.65),
            selectedTextColor: dark ? .white : .black
        ))
        sceneView.setDark(dark, animated: animated)
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard selectedTheme == .system,
              previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        updateCardColors(animated: !UIAccessibility.isReduceMotionEnabled)
    }

    override public var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            segmentedControl.isEnabled = isEnabled
        }
    }

}

/// Short spelling for hosts that do not need the `View` suffix.
public typealias AetherThemePicker = AetherThemePickerView

// MARK: - Illustrated scene

private final class ThemeSceneView: UIView {
    private let skyLayer = CAGradientLayer()
    private let starsLayer = CAShapeLayer()
    private let sunLayer = CAShapeLayer()
    private let sunRaysLayer = CAShapeLayer()
    private let moonLayer = CAShapeLayer()
    private let cloudLayer = CAShapeLayer()
    private let shootingStarLayers = [CAGradientLayer(), CAGradientLayer()]
    private let farHillLayer = CAShapeLayer()
    private let nearHillLayer = CAShapeLayer()
    private let houseBodyLayer = CAShapeLayer()
    private let houseRoofLayer = CAShapeLayer()
    private let houseWindowLayer = CAShapeLayer()
    private var isDark = false
    private var geometrySize: CGSize = .zero
    private var ambientObservers: [NSObjectProtocol] = []
    private var applicationIsActive = true
    private var cloudElapsedTime: TimeInterval = 0
    private var cloudAnimationStartTime: CFTimeInterval?
    private let cloudLoopDuration: TimeInterval = 16

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 18.0
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        isUserInteractionEnabled = false
        layer.name = "aether.theme.scene"
        sunLayer.name = "aether.theme.sun"
        moonLayer.name = "aether.theme.moon"
        cloudLayer.name = "aether.theme.cloud"
        starsLayer.name = "aether.theme.stars"

        skyLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        skyLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        layer.addSublayer(skyLayer)
        layer.addSublayer(starsLayer)
        for (index, shootingStar) in shootingStarLayers.enumerated() {
            shootingStar.name = "aether.theme.shootingStar.\(index)"
            shootingStar.startPoint = CGPoint(x: 0, y: 0.5)
            shootingStar.endPoint = CGPoint(x: 1, y: 0.5)
            shootingStar.colors = [UIColor.white.withAlphaComponent(0).cgColor,
                                  UIColor.white.withAlphaComponent(0.22).cgColor,
                                  UIColor.white.withAlphaComponent(0.95).cgColor]
            shootingStar.locations = [0, 0.65, 1]
            shootingStar.opacity = 0
            layer.addSublayer(shootingStar)
        }
        [sunLayer, moonLayer, cloudLayer, farHillLayer, nearHillLayer,
         houseBodyLayer, houseRoofLayer, houseWindowLayer].forEach(layer.addSublayer)
        sunLayer.addSublayer(sunRaysLayer)

        starsLayer.fillColor = UIColor.white.cgColor
        sunLayer.fillColor = UIColor(red: 1, green: 0.84, blue: 0.23, alpha: 1).cgColor
        sunRaysLayer.strokeColor = sunLayer.fillColor
        sunRaysLayer.fillColor = nil
        sunRaysLayer.lineCap = .round
        moonLayer.fillColor = UIColor(red: 0.98, green: 0.98, blue: 0.85, alpha: 1).cgColor
        cloudLayer.fillColor = UIColor.white.withAlphaComponent(0.9).cgColor
        farHillLayer.fillColor = UIColor(red: 0.16, green: 0.45, blue: 0.40, alpha: 1).cgColor
        nearHillLayer.fillColor = UIColor(red: 0.10, green: 0.35, blue: 0.28, alpha: 1).cgColor
        houseBodyLayer.fillColor = UIColor(red: 0.16, green: 0.13, blue: 0.20, alpha: 1).cgColor
        houseRoofLayer.fillColor = UIColor(red: 0.11, green: 0.10, blue: 0.16, alpha: 1).cgColor
        houseWindowLayer.fillColor = UIColor(red: 1, green: 0.84, blue: 0.20, alpha: 1).cgColor
        applyPalette(animated: false)
        ambientObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applicationIsActive = false
            self?.synchronizeAmbientMotion()
        })
        ambientObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applicationIsActive = true
            self?.synchronizeAmbientMotion()
        })
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        fatalError("AetherThemePickerView scene cannot be decoded from a storyboard")
    }

    deinit {
        ambientObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        synchronizeAmbientMotion()
    }

    func setDark(_ dark: Bool, animated: Bool) {
        guard dark != isDark else {
            if !animated {
                applyPalette(animated: false)
                updateCelestialPositions(animated: false)
            }
            synchronizeAmbientMotion()
            return
        }
        isDark = dark
        applyPalette(animated: animated)
        updateCelestialPositions(animated: animated)
        synchronizeAmbientMotion()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Resizing owns the geometry; an animation from the old dimensions
        // must not put a celestial body back on an obsolete orbit.
        guard geometrySize != bounds.size else { return }
        stopCloudDrift()
        shootingStarLayers.forEach { $0.removeAllAnimations() }
        geometrySize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        skyLayer.frame = bounds
        updatePaths()
        cloudLayer.position = cloudPosition(at: cloudElapsedTime)
        updateCelestialPositions(animated: false)
        CATransaction.commit()
        synchronizeAmbientMotion()
    }

    private func updatePaths() {
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }

        // Paths are local to each body; position drives its orbit separately.
        let diameter = height * 0.23
        let bodyBounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        sunLayer.bounds = bodyBounds
        moonLayer.bounds = bodyBounds
        sunRaysLayer.frame = bodyBounds
        let sunRect = bodyBounds.insetBy(dx: diameter * 0.10, dy: diameter * 0.10)
        sunLayer.path = UIBezierPath(ovalIn: sunRect).cgPath
        let rays = UIBezierPath()
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4.0
            let center = CGPoint(x: diameter / 2.0, y: diameter / 2.0)
            rays.move(to: CGPoint(x: center.x + cos(angle) * diameter * 0.60, y: center.y + sin(angle) * diameter * 0.60))
            rays.addLine(to: CGPoint(x: center.x + cos(angle) * diameter * 0.77, y: center.y + sin(angle) * diameter * 0.77))
        }
        sunRaysLayer.path = rays.cgPath
        sunRaysLayer.lineWidth = max(1.0, diameter * 0.035)

        // One closed outline keeps only the crescent. Combining two complete
        // circles with evenOdd draws the unwanted second outer lobe as well.
        let moonPath = UIBezierPath()
        moonPath.move(to: CGPoint(x: diameter * 0.60, y: diameter * 0.02))
        moonPath.addCurve(
            to: CGPoint(x: diameter * 0.02, y: diameter * 0.52),
            controlPoint1: CGPoint(x: diameter * 0.27, y: -diameter * 0.06),
            controlPoint2: CGPoint(x: -diameter * 0.02, y: diameter * 0.20)
        )
        moonPath.addCurve(
            to: CGPoint(x: diameter * 0.73, y: diameter * 0.90),
            controlPoint1: CGPoint(x: diameter * 0.06, y: diameter * 0.88),
            controlPoint2: CGPoint(x: diameter * 0.43, y: diameter * 1.04)
        )
        moonPath.addCurve(
            to: CGPoint(x: diameter * 0.99, y: diameter * 0.60),
            controlPoint1: CGPoint(x: diameter * 0.86, y: diameter * 0.84),
            controlPoint2: CGPoint(x: diameter * 0.96, y: diameter * 0.73)
        )
        moonPath.addCurve(
            to: CGPoint(x: diameter * 0.60, y: diameter * 0.02),
            controlPoint1: CGPoint(x: diameter * 0.68, y: diameter * 0.72),
            controlPoint2: CGPoint(x: diameter * 0.34, y: diameter * 0.47)
        )
        moonPath.close()
        moonLayer.path = moonPath.cgPath
        moonLayer.fillRule = .nonZero

        let stars = UIBezierPath()
        let points: [(CGFloat, CGFloat, CGFloat)] = [
            (0.13, 0.18, 1.0), (0.24, 0.33, 0.8), (0.36, 0.16, 1.0),
            (0.47, 0.29, 0.7), (0.57, 0.12, 0.9), (0.66, 0.34, 0.8),
            (0.85, 0.25, 0.75), (0.90, 0.42, 0.55)
        ]
        for (x, y, radius) in points {
            stars.append(UIBezierPath(ovalIn: CGRect(x: width * x, y: height * y, width: radius * 2, height: radius * 2)))
        }
        starsLayer.path = stars.cgPath

        let clouds = UIBezierPath(roundedRect: CGRect(x: width * 0.11, y: height * 0.29, width: width * 0.28, height: height * 0.10), cornerRadius: height * 0.05)
        clouds.append(UIBezierPath(ovalIn: CGRect(x: width * 0.17, y: height * 0.22, width: width * 0.12, height: height * 0.14)))
        clouds.append(UIBezierPath(ovalIn: CGRect(x: width * 0.26, y: height * 0.20, width: width * 0.14, height: height * 0.17)))
        cloudLayer.path = clouds.cgPath
        for shootingStar in shootingStarLayers {
            let thickness = max(1.1, height * 0.007)
            shootingStar.bounds = CGRect(x: 0, y: 0, width: width * 0.11, height: thickness)
            shootingStar.cornerRadius = thickness / 2
            shootingStar.transform = CATransform3DMakeRotation(0.48, 0, 0, 1)
        }

        let farHill = UIBezierPath()
        farHill.move(to: CGPoint(x: 0, y: height * 0.69))
        farHill.addCurve(to: CGPoint(x: width, y: height * 0.62), controlPoint1: CGPoint(x: width * 0.30, y: height * 0.53), controlPoint2: CGPoint(x: width * 0.67, y: height * 0.78))
        farHill.addLine(to: CGPoint(x: width, y: height))
        farHill.addLine(to: CGPoint(x: 0, y: height))
        farHill.close()
        farHillLayer.path = farHill.cgPath

        let nearHill = UIBezierPath()
        nearHill.move(to: CGPoint(x: 0, y: height * 0.82))
        nearHill.addCurve(to: CGPoint(x: width, y: height * 0.75), controlPoint1: CGPoint(x: width * 0.30, y: height * 0.68), controlPoint2: CGPoint(x: width * 0.69, y: height * 0.93))
        nearHill.addLine(to: CGPoint(x: width, y: height))
        nearHill.addLine(to: CGPoint(x: 0, y: height))
        nearHill.close()
        nearHillLayer.path = nearHill.cgPath

        let houseWidth = width * 0.13
        let houseHeight = height * 0.16
        let houseX = width * 0.22
        let houseY = height * 0.66
        houseBodyLayer.path = UIBezierPath(roundedRect: CGRect(x: houseX, y: houseY, width: houseWidth, height: houseHeight), cornerRadius: 1.5).cgPath
        let roof = UIBezierPath()
        roof.move(to: CGPoint(x: houseX - houseWidth * 0.10, y: houseY + 2))
        roof.addLine(to: CGPoint(x: houseX + houseWidth * 0.50, y: houseY - houseHeight * 0.54))
        roof.addLine(to: CGPoint(x: houseX + houseWidth * 1.10, y: houseY + 2))
        roof.close()
        houseRoofLayer.path = roof.cgPath
        houseWindowLayer.path = UIBezierPath(roundedRect: CGRect(x: houseX + houseWidth * 0.40, y: houseY + houseHeight * 0.33, width: houseWidth * 0.20, height: houseHeight * 0.30), cornerRadius: 0.8).cgPath
    }

    private func orbitPosition(angle: CGFloat) -> CGPoint {
        CGPoint(
            x: bounds.width * (0.50 + 0.50 * cos(angle)),
            y: bounds.height * (1.10 - 0.95 * sin(angle))
        )
    }

    private func synchronizeAmbientMotion() {
        let canAnimate = window != nil && applicationIsActive
            && bounds.width > 0 && bounds.height > 0
            && !UIAccessibility.isReduceMotionEnabled
        if canAnimate && !isDark {
            startCloudDrift()
        } else {
            stopCloudDrift()
        }
        for (index, shootingStar) in shootingStarLayers.enumerated() {
            if canAnimate && isDark {
                startShootingStar(shootingStar, index: index)
            } else {
                shootingStar.removeAllAnimations()
            }
        }
    }

    private func cloudPosition(at time: TimeInterval) -> CGPoint {
        let phase = CGFloat(time / cloudLoopDuration) * 2 * .pi
        // A slow, slightly uneven loop gives the cloud a drifting/bobbing
        // motion without rotating it or leaving the illustrated sky.
        return CGPoint(
            x: bounds.width * 0.035 * (sin(phase) + 0.12 * sin(2 * phase)),
            y: bounds.height * 0.018 * (sin(2 * phase) + 0.35 * sin(phase))
        )
    }

    private func startCloudDrift() {
        let key = "aether.theme.cloudDrift"
        guard cloudLayer.animation(forKey: key) == nil else { return }
        let now = CACurrentMediaTime()
        let initialPosition = cloudLayer.position
        let steps = 120
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.values = (0...steps).map { index in
            // Match the frozen presentation position at both ends so theme
            // changes and returning to the foreground preserve continuity.
            let point = index == 0 || index == steps ? initialPosition : cloudPosition(
                at: cloudElapsedTime + cloudLoopDuration * Double(index) / Double(steps)
            )
            return NSValue(cgPoint: point)
        }
        animation.duration = cloudLoopDuration
        animation.beginTime = cloudLayer.convertTime(now, from: nil)
        animation.repeatCount = .infinity
        animation.calculationMode = .linear
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        cloudAnimationStartTime = now
        cloudLayer.add(animation, forKey: key)
    }

    private func stopCloudDrift() {
        guard let startedAt = cloudAnimationStartTime else { return }
        cloudElapsedTime = (cloudElapsedTime + CACurrentMediaTime() - startedAt)
            .truncatingRemainder(dividingBy: cloudLoopDuration)
        let displayedPosition = cloudLayer.presentation()?.position ?? cloudPosition(at: cloudElapsedTime)
        cloudAnimationStartTime = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cloudLayer.position = displayedPosition
        cloudLayer.removeAnimation(forKey: "aether.theme.cloudDrift")
        CATransaction.commit()
    }

    private func startShootingStar(_ shootingStar: CAGradientLayer, index: Int) {
        let key = "aether.theme.shootingStar"
        guard shootingStar.animation(forKey: key) == nil else { return }
        let width = bounds.width
        let height = bounds.height
        let start = CGPoint(x: width * (index == 0 ? 0.18 : 0.46), y: height * (index == 0 ? 0.10 : 0.08))
        let end = CGPoint(x: start.x + width * 0.34, y: start.y + height * 0.34)
        let flightStart: NSNumber = index == 0 ? 0.22 : 0.50
        let flightEnd: NSNumber = index == 0 ? 0.30 : 0.56
        let travel = CAKeyframeAnimation(keyPath: "position")
        travel.values = [start, start, end, end].map { NSValue(cgPoint: $0) }
        travel.keyTimes = [0, flightStart, flightEnd, 1]
        travel.timingFunctions = [.init(name: .linear), .init(name: .easeIn), .init(name: .linear)]

        let visibility = CAKeyframeAnimation(keyPath: "opacity")
        let first = flightStart.doubleValue
        let last = flightEnd.doubleValue
        visibility.values = [0, 0, 1, 0.8, 0, 0]
        visibility.keyTimes = [0, flightStart, NSNumber(value: first + 0.008),
                               NSNumber(value: last - 0.015), flightEnd, 1]
        visibility.timingFunction = CAMediaTimingFunction(name: .linear)

        // Different, long repeat periods leave the sky quiet between brief
        // streaks. Core Animation runs these without display links or timers.
        let group = CAAnimationGroup()
        group.duration = index == 0 ? 9.0 : 13.4
        travel.duration = group.duration
        visibility.duration = group.duration
        group.animations = [travel, visibility]
        group.beginTime = shootingStar.convertTime(CACurrentMediaTime(), from: nil)
        group.repeatCount = .infinity
        shootingStar.add(group, forKey: key)
    }

    private func updateCelestialPositions(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let visibleAngle: CGFloat = .pi * 0.30
        move(sunLayer, to: isDark ? 0.0 : visibleAngle, animated: animated)
        move(moonLayer, to: isDark ? visibleAngle : .pi, animated: animated)
    }

    private func move(_ body: CALayer, to targetAngle: CGFloat, animated: Bool) {
        let target = orbitPosition(angle: targetAngle)
        let displayedPosition = body.presentation()?.position ?? body.position
        let fromAngle = atan2(
            max(0, (bounds.height * 1.10 - displayedPosition.y) / (bounds.height * 0.95)),
            (displayedPosition.x - bounds.width * 0.50) / (bounds.width * 0.50)
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.position = target
        CATransaction.commit()

        guard animated, !UIAccessibility.isReduceMotionEnabled,
              abs(fromAngle - targetAngle) > 0.001 else {
            body.removeAnimation(forKey: "aether.theme.position")
            return
        }
        let animation = CAKeyframeAnimation(keyPath: "position")
        // A lightly damped response accelerates into the orbit and settles
        // with a small follow-through. Reversals still start at the displayed
        // position and follow the same ellipse instead of jumping endpoints.
        let duration: TimeInterval = 0.85
        let damping: CGFloat = 0.80
        let frequency: CGFloat = 12.0
        let dampedFrequency = frequency * sqrt(1 - damping * damping)
        let steps = 72
        animation.values = (0...steps).map { index in
            let time = CGFloat(duration) * CGFloat(index) / CGFloat(steps)
            let response = 1 - exp(-damping * frequency * time) * (
                cos(dampedFrequency * time) + damping * frequency / dampedFrequency * sin(dampedFrequency * time)
            )
            let progress: CGFloat = index == steps ? 1.0 : response
            return NSValue(cgPoint: orbitPosition(angle: fromAngle + (targetAngle - fromAngle) * progress))
        }
        animation.duration = duration
        animation.calculationMode = .linear
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        body.add(animation, forKey: "aether.theme.position")
    }

    private func applyPalette(animated: Bool) {
        let colors: [CGColor]
        let farHillColor: CGColor
        let nearHillColor: CGColor
        let cloudColor: CGColor
        if isDark {
            colors = [UIColor(red: 0.035, green: 0.05, blue: 0.17, alpha: 1).cgColor, UIColor(red: 0.10, green: 0.12, blue: 0.32, alpha: 1).cgColor]
            farHillColor = UIColor(red: 0.12, green: 0.16, blue: 0.38, alpha: 1).cgColor
            nearHillColor = UIColor(red: 0.08, green: 0.12, blue: 0.28, alpha: 1).cgColor
            cloudColor = UIColor.white.withAlphaComponent(0.10).cgColor
        } else {
            colors = [UIColor(red: 0.32, green: 0.70, blue: 0.96, alpha: 1).cgColor, UIColor(red: 0.75, green: 0.89, blue: 0.98, alpha: 1).cgColor]
            farHillColor = UIColor(red: 0.27, green: 0.56, blue: 0.28, alpha: 1).cgColor
            nearHillColor = UIColor(red: 0.11, green: 0.40, blue: 0.19, alpha: 1).cgColor
            cloudColor = UIColor.white.withAlphaComponent(0.9).cgColor
        }

        let apply = {
            self.skyLayer.colors = colors
            self.farHillLayer.fillColor = farHillColor
            self.nearHillLayer.fillColor = nearHillColor
            self.cloudLayer.fillColor = cloudColor
            self.cloudLayer.opacity = self.isDark ? 0.0 : 1.0
            self.starsLayer.opacity = self.isDark ? 1.0 : 0.0
            self.houseWindowLayer.opacity = self.isDark ? 1.0 : 0.12
        }
        if !animated || UIAccessibility.isReduceMotionEnabled {
            // Palette refreshes must not restart the ambient cloud cycle.
            for layer in [skyLayer, farHillLayer, nearHillLayer, cloudLayer, starsLayer, houseWindowLayer] {
                for property in ["colors", "fillColor", "opacity"] {
                    layer.removeAnimation(forKey: "aether.theme.\(property)")
                }
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            apply()
            CATransaction.commit()
            return
        }

        let duration = 0.85
        animate(layer: skyLayer, keyPath: "colors", toValue: colors, duration: duration)
        animate(layer: farHillLayer, keyPath: "fillColor", toValue: farHillColor, duration: duration)
        animate(layer: nearHillLayer, keyPath: "fillColor", toValue: nearHillColor, duration: duration)
        animate(layer: cloudLayer, keyPath: "fillColor", toValue: cloudColor, duration: duration)
        animate(layer: cloudLayer, keyPath: "opacity", toValue: isDark ? 0.0 : 1.0, duration: duration)
        animate(layer: starsLayer, keyPath: "opacity", toValue: isDark ? 1.0 : 0.0, duration: duration)
        animate(layer: houseWindowLayer, keyPath: "opacity", toValue: isDark ? 1.0 : 0.12, duration: duration)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply()
        CATransaction.commit()
    }

    private func animate(layer: CALayer, keyPath: String, toValue: Any, duration: TimeInterval) {
        let fromValue = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(toValue, forKeyPath: keyPath)
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.0, 0.18, 1.0)
        layer.add(animation, forKey: "aether.theme.\(keyPath)")
    }
}
