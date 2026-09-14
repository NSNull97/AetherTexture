import UIKit
import AsyncDisplayKit

public struct AetherSliderNodeTheme: Equatable {
    public var minimumTrackTintColor: UIColor
    public var minimumTrackAlpha: CGFloat

    public init(
        minimumTrackTintColor: UIColor = .systemBlue,
        minimumTrackAlpha: CGFloat = 0.82
    ) {
        self.minimumTrackTintColor = minimumTrackTintColor
        self.minimumTrackAlpha = minimumTrackAlpha
    }

    public static let system = AetherSliderNodeTheme()

    fileprivate var legacyTheme: AetherSlider.Theme {
        AetherSlider.Theme(
            minimumTrackTintColor: minimumTrackTintColor,
            minimumTrackAlpha: minimumTrackAlpha
        )
    }
}

public final class AetherSliderNode: AetherDisplayNode {
    public var theme: AetherSliderNodeTheme {
        didSet { sliderView?.theme = theme.legacyTheme }
    }

    public var minimumValue: Float = 0.0 {
        didSet { sliderView?.minimumValue = minimumValue }
    }

    public var maximumValue: Float = 1.0 {
        didSet { sliderView?.maximumValue = maximumValue }
    }

    public var value: Float {
        get { _value }
        set { setValue(newValue, animated: false) }
    }

    public var isContinuous: Bool = true {
        didSet { sliderView?.isContinuous = isContinuous }
    }

    public var valueChanged: (Float) -> Void = { _ in } {
        didSet { sliderView?.valueChanged = valueChanged }
    }

    public var preferredHeight: CGFloat {
        get { preferredHeightOverride ?? sliderView?.preferredHeight ?? resolvedDefaultPreferredHeight }
        set {
            preferredHeightOverride = newValue
            sliderView?.preferredHeight = newValue
        }
    }

    public var trackHeight: CGFloat {
        get { trackHeightOverride ?? sliderView?.trackHeight ?? resolvedDefaultTrackHeight }
        set {
            trackHeightOverride = newValue
            sliderView?.trackHeight = newValue
        }
    }

    public var thumbSize: CGSize {
        get { thumbSizeOverride ?? sliderView?.thumbSize ?? resolvedDefaultThumbSize }
        set {
            thumbSizeOverride = newValue
            sliderView?.thumbSize = newValue
        }
    }

    public var contentInsets: UIEdgeInsets = UIEdgeInsets(top: 6.0, left: 0.0, bottom: 6.0, right: 0.0) {
        didSet { sliderView?.contentInsets = contentInsets }
    }

    public var accessibilityStep: Float = 0.1 {
        didSet { sliderView?.accessibilityStep = accessibilityStep }
    }

    public var isDarkAppearance: Bool? {
        didSet { sliderView?.isDarkAppearance = isDarkAppearance }
    }

    public var minimumValueImage: UIImage? {
        didSet { sliderView?.minimumValueImage = minimumValueImage }
    }

    public var maximumValueImage: UIImage? {
        didSet { sliderView?.maximumValueImage = maximumValueImage }
    }

    public var valueImageTintColor: UIColor = .secondaryLabel {
        didSet { sliderView?.valueImageTintColor = valueImageTintColor }
    }

    /// `nil` follows the application runtime; an explicit value is forwarded
    /// before the wrapped UIKit slider allocates any backing renderer.
    public var appearanceStyleOverride: AetherAppearanceStyle? {
        didSet { sliderView?.appearanceStyleOverride = appearanceStyleOverride }
    }

    public var isEnabled: Bool = true {
        didSet { sliderView?.isEnabled = isEnabled }
    }

    public override var isUserInteractionEnabled: Bool {
        didSet { sliderView?.isUserInteractionEnabled = isUserInteractionEnabled }
    }

    private let hostNode: ASDisplayNode
    private weak var loadedSliderView: AetherSlider?
    private var _value: Float
    private var preferredHeightOverride: CGFloat?
    private var trackHeightOverride: CGFloat?
    private var thumbSizeOverride: CGSize?

    private var sliderView: AetherSlider? {
        loadedSliderView
    }

    public init(
        value: Float = 0.0,
        theme: AetherSliderNodeTheme = .system,
        appearanceStyle: AetherAppearanceStyle? = nil
    ) {
        self.theme = theme
        self._value = value
        self.minimumValueImage = nil
        self.maximumValueImage = nil
        self.appearanceStyleOverride = appearanceStyle
        let legacyTheme = theme.legacyTheme
        self.hostNode = ASDisplayNode(viewBlock: {
            AetherSlider(
                value: value,
                theme: legacyTheme,
                appearanceStyle: appearanceStyle
            )
        })
        super.init()
        addSubnode(hostNode)
    }

    public override func didLoad() {
        super.didLoad()
        loadedSliderView = hostNode.view as? AetherSlider
        loadedSliderView?.theme = theme.legacyTheme
        loadedSliderView?.minimumValue = minimumValue
        loadedSliderView?.maximumValue = maximumValue
        loadedSliderView?.isContinuous = isContinuous
        loadedSliderView?.valueChanged = valueChanged
        if let preferredHeightOverride {
            loadedSliderView?.preferredHeight = preferredHeightOverride
        }
        if let trackHeightOverride {
            loadedSliderView?.trackHeight = trackHeightOverride
        }
        if let thumbSizeOverride {
            loadedSliderView?.thumbSize = thumbSizeOverride
        }
        loadedSliderView?.contentInsets = contentInsets
        loadedSliderView?.accessibilityStep = accessibilityStep
        loadedSliderView?.isDarkAppearance = isDarkAppearance
        loadedSliderView?.minimumValueImage = minimumValueImage
        loadedSliderView?.maximumValueImage = maximumValueImage
        loadedSliderView?.valueImageTintColor = valueImageTintColor
        loadedSliderView?.appearanceStyleOverride = appearanceStyleOverride
        loadedSliderView?.isEnabled = isEnabled
        loadedSliderView?.isUserInteractionEnabled = isUserInteractionEnabled
        loadedSliderView?.setValue(_value, animated: false)
    }

    public override func layout() {
        super.layout()
        hostNode.frame = bounds
    }

    public func setValue(_ value: Float, animated: Bool) {
        _value = min(max(value, minimumValue), maximumValue)
        sliderView?.setValue(_value, animated: animated)
    }

    internal var sliderViewForTesting: AetherSlider? {
        sliderView
    }

    private var resolvedAppearanceStyle: AetherAppearanceStyle {
        appearanceStyleOverride ?? AetherAppearance.runtimeCurrent.style
    }

    private var resolvedDefaultPreferredHeight: CGFloat {
        resolvedAppearanceStyle.usesLiquidGlass ? 50.0 : 44.0
    }

    private var resolvedDefaultTrackHeight: CGFloat {
        resolvedAppearanceStyle.usesLiquidGlass ? 32.0 : 4.0
    }

    private var resolvedDefaultThumbSize: CGSize {
        resolvedAppearanceStyle.usesLiquidGlass
            ? CGSize(width: 44.0, height: 38.0)
            : CGSize(width: 28.0, height: 28.0)
    }
}
