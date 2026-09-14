import UIKit
import AetherUI
import AsyncDisplayKit

// MARK: - Appearance Store

final class ExampleAppearanceStore {
    static let shared = ExampleAppearanceStore()
    static let didChange = Notification.Name("AetherUI.ExampleAppearanceStore.didChange")

    private(set) var appearance: AetherAppearance = ExampleAppearanceStore.makeAppearance(style: .liquidGlassV1, dark: false)

    private init() {}

    func update(style: AetherAppearanceStyle? = nil, dark: Bool? = nil, edgeStrong: Bool? = nil) {
        let currentStyle = style ?? appearance.style
        let currentDark = dark ?? appearance.overallDarkAppearance
        let strongEdges = edgeStrong ?? (appearance.edgeEffectBlurRadiusAtEdge > 3.0)
        appearance = Self.makeAppearance(style: currentStyle, dark: currentDark, edgeStrong: strongEdges)
        AetherApplicationRuntime.shared?.updateAppearance(appearance)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private static func makeAppearance(
        style: AetherAppearanceStyle,
        dark: Bool,
        edgeStrong: Bool = false
    ) -> AetherAppearance {
        var appearance = AetherAppearance(style: style)
        appearance.overallDarkAppearance = dark
        appearance.emptyAreaColor = dark
            ? UIColor(red: 0.045, green: 0.047, blue: 0.055, alpha: 1.0)
            : .systemBackground
        appearance.edgeEffectColor = style.usesLiquidGlass
            ? (dark
                ? UIColor(red: 0.07, green: 0.08, blue: 0.095, alpha: 1.0)
                : .systemBackground)
            : .clear
        appearance.separatorColor = dark
            ? UIColor.white.withAlphaComponent(0.13)
            : .separator
        if edgeStrong && style.usesLiquidGlass {
            appearance.edgeEffectBlurRadiusAtEdge = 8.0
            appearance.edgeEffectBlurRadiusAtFade = 7.0
            appearance.edgeEffectStyle = .strong
        }
        return appearance
    }
}

extension ExampleAppearanceStore {
    var isDark: Bool {
        appearance.overallDarkAppearance
    }

    var backgroundColor: UIColor {
        appearance.emptyAreaColor
    }

    var secondaryBackgroundColor: UIColor {
        isDark
            ? UIColor(red: 0.085, green: 0.09, blue: 0.105, alpha: 1.0)
            : .secondarySystemGroupedBackground
    }

    var toolbarTheme: AetherToolbarTheme {
        isDark ? .dark : .light
    }

    var canTuneGlassEdges: Bool {
        appearance.style.usesLiquidGlass
    }

    func cycleAppearanceStyle() {
        let styles = AetherAppearanceStyle.allCases
        guard let currentIndex = styles.firstIndex(of: appearance.style), !styles.isEmpty else {
            return
        }
        update(style: styles[(currentIndex + 1) % styles.count])
    }
}

// MARK: - Scene Wiring

enum ExampleRootFactory {
    static func makeRoot(window: AetherNativeWindow, observer: inout NSObjectProtocol?) -> UIViewController {
        let store = ExampleAppearanceStore.shared
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--animation-reference") || arguments.contains("--animation-reference-autoplay") {
            let root = TextureAnimationReferenceController(autoplay: arguments.contains("--animation-reference-autoplay"))
            let navigation = AetherNavigationController(mode: .single)
            navigation.setViewControllers([root], animated: false)
            navigation.updateAppearance(store.appearance)
            window.overrideUserInterfaceStyle = .light
            window.backgroundColor = store.backgroundColor
            return navigation
        }
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 21.0, weight: .medium)

        let components = makeTab(
            root: TextureComponentsController(),
            title: "Components",
            symbolName: "rectangle.grid.2x2",
            symbolConfig: symbolConfig
        )
        let settingsRoot = TextureSettingsController()
        let settings = makeTab(
            root: settingsRoot,
            title: "Settings",
            symbolName: "gearshape.fill",
            symbolConfig: symbolConfig
        )
        let search = makeTab(
            root: TextureSearchController(),
            title: "Search",
            symbolName: "magnifyingglass",
            symbolConfig: symbolConfig,
            isSearch: true
        )

        let tabs = AetherTabBarController()
        tabs.setControllers([components, settings, search], selectedIndex: 0)
        settingsRoot.hostTabBar = tabs

        let applyAppearance: (AetherAppearance) -> Void = { [weak window, weak tabs] appearance in
            guard let window, let tabs else { return }
            window.overrideUserInterfaceStyle = appearance.overallDarkAppearance ? .dark : .light
            window.backgroundColor = appearance.emptyAreaColor
            tabs.updateAppearance(appearance)
            for controller in tabs.controllers {
                if let navigationController = controller as? AetherNavigationController {
                    navigationController.updateAppearance(appearance)
                } else if let controller = controller as? AetherViewController {
                    controller.setNeedsStatusBarAppearanceUpdate()
                }
            }
        }

        observer = NotificationCenter.default.addObserver(
            forName: ExampleAppearanceStore.didChange,
            object: store,
            queue: .main
        ) { _ in
            applyAppearance(store.appearance)
        }
        applyAppearance(store.appearance)

        return tabs
    }

    private static func makeTab(
        root: AetherViewController,
        title: String,
        symbolName: String,
        symbolConfig: UIImage.SymbolConfiguration,
        isSearch: Bool = false
    ) -> AetherNavigationController {
        let icon = UIImage(systemName: symbolName, withConfiguration: symbolConfig)
        let item: UITabBarItem = isSearch
            ? SearchTabItem(image: icon, selectedImage: icon)
            : UITabBarItem(title: title, image: icon, selectedImage: icon)
        root.tabBarItem = item

        let nav = AetherNavigationController(mode: .single)
        nav.setViewControllers([root], animated: false)
        nav.tabBarItem = item
        return nav
    }
}

// MARK: - Example Runtime Helpers

private final class TextureNodeHostView: UIView {
    let node: ASDisplayNode

    init(node: ASDisplayNode) {
        self.node = node
        super.init(frame: .zero)
        backgroundColor = .clear
        addSubview(node.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        node.frame = bounds
    }
}

private func exampleFloatingToolbar(_ segments: [AetherFloatingToolbarView.Segment]) -> AetherFloatingToolbarView {
    let toolbar = AetherFloatingToolbarView(segments: segments, theme: exampleFloatingToolbarTheme())
    toolbar.sideInset = 12.0
    toolbar.segmentSpacing = 8.0
    return toolbar
}

private func exampleFloatingToolbarTheme() -> AetherFloatingToolbarView.Theme {
    ExampleAppearanceStore.shared.isDark ? .dark : .light
}

private func exampleToolbarButton(
    _ systemName: String,
    action: @escaping () -> Void
) -> AetherFloatingToolbarView.Button {
    AetherFloatingToolbarView.Button(icon: UIImage(systemName: systemName), action: action)
}

private func exampleTopInset(
    for controller: AetherViewController,
    layout: ContainerViewLayout
) -> CGFloat {
    max(controller.cleanNavigationHeight, layout.safeInsets.top + 60.0)
}

private func exampleBottomInset(
    for controller: AetherViewController,
    layout: ContainerViewLayout
) -> CGFloat {
    var bottomInset = max(layout.safeInsets.bottom, layout.additionalInsets.bottom)
    if let toolbar = controller.floatingToolbar, toolbar.frame.minY.isFinite, toolbar.frame.minY > 0.0 {
        bottomInset = max(bottomInset, layout.size.height - toolbar.frame.minY)
    }
    return bottomInset
}

private func updateExampleListLayout(
    controller: AetherViewController,
    listNode: AetherListNode,
    layout: ContainerViewLayout,
    transition: ContainedViewLayoutTransition,
    didAlignInitialTop: inout Bool
) {
    transition.updateFrame(node: listNode, frame: CGRect(origin: .zero, size: layout.size))
    listNode.updateInsets(
        UIEdgeInsets(
            top: exampleTopInset(for: controller, layout: layout),
            left: layout.safeInsets.left,
            bottom: exampleBottomInset(for: controller, layout: layout),
            right: layout.safeInsets.right
        ),
        transition: transition,
        preserveContentOffset: false
    )
    if !didAlignInitialTop {
        listNode.scrollToTop(animated: false)
        didAlignInitialTop = true
    }
}

private func centeredFrame(for size: CGSize, in rect: CGRect) -> CGRect {
    CGRect(
        x: rect.minX + floor((rect.width - size.width) / 2.0),
        y: rect.minY + floor((rect.height - size.height) / 2.0),
        width: size.width,
        height: size.height
    )
}

// MARK: - Common List Rows

private final class TextureMenuItem: AetherListItem {
    let id: AnyHashable
    let title: String
    let subtitle: String?
    let iconName: String
    let tintColor: UIColor
    let trailing: String?
    let action: () -> Void

    init(
        id: AnyHashable,
        title: String,
        subtitle: String? = nil,
        iconName: String,
        tintColor: UIColor = .systemBlue,
        trailing: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.tintColor = tintColor
        self.trailing = trailing
        self.action = action
    }

    var stableId: AnyHashable { id }
    var approximateHeight: CGFloat { subtitle == nil ? 58.0 : 72.0 }
    var estimatedHeight: CGFloat { approximateHeight }
    var selectable: Bool { true }

    func createNode(
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?
    ) -> (AetherListItemNode, AetherListItemNodeLayout) {
        let node = TextureMenuRowNode(frame: .zero)
        node.configure(item: self)
        return (node, layout(width: params.width))
    }

    func updateNode(
        _ node: AetherListItemNode,
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?,
        animation: AetherListItemUpdateAnimation
    ) -> AetherListItemNodeLayout {
        (node as? TextureMenuRowNode)?.configure(item: self)
        return layout(width: params.width)
    }

    func selected(listNode: AetherListNode) {
        action()
    }

    private func layout(width: CGFloat) -> AetherListItemNodeLayout {
        AetherListItemNodeLayout(contentSize: CGSize(width: width, height: approximateHeight))
    }
}

private final class TextureMenuRowNode: AetherListItemNode {
    private let iconBackgroundNode = ASDisplayNode()
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let subtitleNode = ASTextNode()
    private let trailingNode = ASTextNode()
    private let chevronNode = ASImageNode()
    private let separatorNode = ASDisplayNode()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubnode(iconBackgroundNode)
        iconBackgroundNode.addSubnode(iconNode)
        addSubnode(titleNode)
        addSubnode(subtitleNode)
        addSubnode(trailingNode)
        addSubnode(chevronNode)
        addSubnode(separatorNode)

        iconBackgroundNode.cornerRadius = 11.0
        titleNode.maximumNumberOfLines = 1
        subtitleNode.maximumNumberOfLines = 1
        trailingNode.maximumNumberOfLines = 1
        chevronNode.image = UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate)
        chevronNode.tintColor = .tertiaryLabel
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: TextureMenuItem) {
        let store = ExampleAppearanceStore.shared
        backgroundColor = store.backgroundColor
        iconBackgroundNode.backgroundColor = item.tintColor
        iconNode.image = UIImage(systemName: item.iconName)?.withRenderingMode(.alwaysTemplate)
        iconNode.tintColor = .white
        titleNode.attributedText = Self.text(item.title, font: .systemFont(ofSize: 16.0, weight: .semibold), color: .label)
        subtitleNode.attributedText = item.subtitle.map {
            Self.text($0, font: .systemFont(ofSize: 13.0), color: .secondaryLabel)
        }
        trailingNode.attributedText = item.trailing.map {
            Self.text($0, font: .systemFont(ofSize: 14.0, weight: .medium), color: .secondaryLabel, alignment: .right)
        }
        separatorNode.backgroundColor = .separator
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let iconSide: CGFloat = 38.0
        let iconFrame = CGRect(x: 18.0, y: floor((bounds.height - iconSide) / 2.0), width: iconSide, height: iconSide)
        iconBackgroundNode.frame = iconFrame
        iconNode.frame = iconBackgroundNode.bounds.insetBy(dx: 8.0, dy: 8.0)

        let chevronSide: CGFloat = 14.0
        chevronNode.frame = CGRect(
            x: bounds.width - 16.0 - chevronSide,
            y: floor((bounds.height - chevronSide) / 2.0),
            width: chevronSide,
            height: chevronSide
        )

        let trailingWidth: CGFloat = trailingNode.attributedText == nil ? 0.0 : 86.0
        trailingNode.frame = CGRect(
            x: chevronNode.frame.minX - trailingWidth - 8.0,
            y: floor((bounds.height - 20.0) / 2.0),
            width: trailingWidth,
            height: 20.0
        )

        let textX = iconFrame.maxX + 14.0
        let textRight = (trailingWidth > 0.0 ? trailingNode.frame.minX : chevronNode.frame.minX) - 10.0
        let textWidth = max(0.0, textRight - textX)
        let titleSize = titleNode.layoutThatFits(
            ASSizeRange(min: .zero, max: CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude))
        ).size
        if subtitleNode.attributedText == nil {
            titleNode.frame = CGRect(
                x: textX,
                y: floor((bounds.height - titleSize.height) / 2.0),
                width: textWidth,
                height: titleSize.height
            )
            subtitleNode.frame = .zero
        } else {
            let subtitleSize = subtitleNode.layoutThatFits(
                ASSizeRange(min: .zero, max: CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude))
            ).size
            let contentHeight = titleSize.height + 3.0 + subtitleSize.height
            let titleY = floor((bounds.height - contentHeight) / 2.0)
            titleNode.frame = CGRect(x: textX, y: titleY, width: textWidth, height: titleSize.height)
            subtitleNode.frame = CGRect(x: textX, y: titleNode.frame.maxY + 3.0, width: textWidth, height: subtitleSize.height)
        }

        let pixel = 1.0 / UIScreen.main.scale
        separatorNode.frame = CGRect(x: textX, y: bounds.height - pixel, width: bounds.width - textX, height: pixel)
    }

    private static func text(
        _ string: String,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .natural
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(
            string: string,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}

// MARK: - Components Tab

final class TextureComponentsController: AetherViewController {
    private let listNode = AetherListNode()
    private var didAlignInitialListTop = false
    private var appearanceObserver: NSObjectProtocol?

    init() {
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: ExampleAppearanceStore.shared.backgroundColor))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Components"
        node.addSubnode(listNode)
        listNode.backgroundColor = .clear
        applyAppearance()
        reloadRows()
        observeAppearance()
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        updateExampleListLayout(
            controller: self,
            listNode: listNode,
            layout: layout,
            transition: transition,
            didAlignInitialTop: &didAlignInitialListTop
        )
    }

    private func reloadRows() {
        let rows: [TextureMenuItem] = [
            TextureMenuItem(
                id: "animation-reference",
                title: "Animation Reference",
                subtitle: "Edit / filter menus, profile, back badge, camera",
                iconName: "play.rectangle.fill",
                tintColor: .systemIndigo
            ) { [weak self] in self?.push(TextureAnimationReferenceController()) },
            TextureMenuItem(
                id: "appearance-gallery",
                title: "Appearance Gallery",
                subtitle: "Legacy / Liquid Glass v1 / v2 on real components",
                iconName: "square.grid.3x3.fill",
                tintColor: .systemCyan
            ) { [weak self] in self?.push(TextureAppearanceGalleryController()) },
            TextureMenuItem(
                id: "chats",
                title: "Chats List",
                subtitle: "AetherListNode, swipe actions, toolbar, dialog push",
                iconName: "bubble.left.and.bubble.right.fill",
                tintColor: .systemBlue
            ) { [weak self] in self?.push(TextureChatsController()) },
            TextureMenuItem(
                id: "navigation",
                title: "Navigation Surfaces",
                subtitle: "shared bar, top accessory, pushed screens",
                iconName: "rectangle.stack.fill",
                tintColor: .systemIndigo
            ) { [weak self] in self?.push(TextureShowcaseController(topic: .navigation)) },
            TextureMenuItem(
                id: "controls",
                title: "Controls",
                subtitle: "segmented, toolbar, glass buttons",
                iconName: "switch.2",
                tintColor: .systemGreen
            ) { [weak self] in self?.push(TextureShowcaseController(topic: .controls)) },
            TextureMenuItem(
                id: "states",
                title: "States",
                subtitle: "loading, empty, toast, modal calls",
                iconName: "sparkles",
                tintColor: .systemPurple
            ) { [weak self] in self?.push(TextureShowcaseController(topic: .states)) },
            TextureMenuItem(
                id: "texture",
                title: "Texture Runtime",
                subtitle: "ASDisplayNode layout and node-first rows",
                iconName: "cpu.fill",
                tintColor: .systemOrange
            ) { [weak self] in self?.push(TextureShowcaseController(topic: .texture)) }
        ]
        listNode.transaction(
            insertIndicesAndItems: rows.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )
    }

    private func observeAppearance() {
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: ExampleAppearanceStore.didChange,
            object: ExampleAppearanceStore.shared,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
            self?.listNode.transaction(options: [.forceUpdate, .crossfade])
        }
    }

    private func applyAppearance() {
        view.backgroundColor = ExampleAppearanceStore.shared.backgroundColor
        node.backgroundColor = ExampleAppearanceStore.shared.backgroundColor
    }
}

// MARK: - Appearance Gallery

private final class TextureAppearanceGallerySurface: UIView {
    private let surface: GlassBackgroundView
    var contentView: UIView { surface.contentView }

    init(role: AetherSurfaceRole, cornerRadius: CGFloat) {
        self.galleryCornerRadius = cornerRadius
        self.surface = GlassBackgroundView(style: .regular)
        super.init(frame: .zero)
        surface.surfaceRole = role
        addSubview(surface)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let galleryCornerRadius: CGFloat

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.frame = bounds
        surface.update(
            size: bounds.size,
            cornerRadius: galleryCornerRadius,
            transition: .immediate
        )
    }
}

private final class TextureAppearanceGalleryController: AetherViewController {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let styleSelector = UISegmentedControl(
        items: AetherAppearanceStyle.allCases.map(\.displayName)
    )
    private let darkSwitch = UISwitch()
    private let galleryBottomAccessory = TextureSettingsBottomAccessoryView(frame: .zero)
    private var appearanceObserver: NSObjectProtocol?

    init() {
        // Let the enclosing navigation controller resolve the live runtime
        // appearance.  Capturing `.defaultTheme` here would pin the nav bar to
        // whichever generation happened to be active when the screen opened.
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Appearance Gallery"
        view.addSubview(scrollView)
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive

        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])

        styleSelector.addTarget(self, action: #selector(styleChanged), for: .valueChanged)
        styleSelector.heightAnchor.constraint(equalToConstant: 34).isActive = true
        stackView.addArrangedSubview(makeSectionTitle("Global runtime style"))
        stackView.addArrangedSubview(styleSelector)

        let appearanceRow = UIStackView()
        appearanceRow.axis = .horizontal
        appearanceRow.alignment = .center
        appearanceRow.spacing = 12
        let darkLabel = makeLabel(
            "Dark appearance",
            font: .preferredFont(forTextStyle: .body)
        )
        appearanceRow.addArrangedSubview(darkLabel)
        appearanceRow.addArrangedSubview(UIView())
        appearanceRow.addArrangedSubview(darkSwitch)
        darkSwitch.addTarget(self, action: #selector(darkAppearanceChanged), for: .valueChanged)
        stackView.addArrangedSubview(appearanceRow)

        let card = TextureAppearanceGallerySurface(role: .card, cornerRadius: 14)
        card.heightAnchor.constraint(equalToConstant: 82).isActive = true
        let cardTitle = makeLabel("Card surface", font: .preferredFont(forTextStyle: .headline))
        let cardSubtitle = makeLabel(
            "Semantic colors, border and shadow update in place.",
            font: .preferredFont(forTextStyle: .subheadline),
            color: .secondaryLabel
        )
        card.contentView.addSubview(cardTitle)
        card.contentView.addSubview(cardSubtitle)
        [cardTitle, cardSubtitle].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            cardTitle.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16),
            cardTitle.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -16),
            cardTitle.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 14),
            cardSubtitle.leadingAnchor.constraint(equalTo: cardTitle.leadingAnchor),
            cardSubtitle.trailingAnchor.constraint(equalTo: cardTitle.trailingAnchor),
            cardSubtitle.topAnchor.constraint(equalTo: cardTitle.bottomAnchor, constant: 5)
        ])
        stackView.addArrangedSubview(makeSectionTitle("Card"))
        stackView.addArrangedSubview(card)

        let buttonRow = UIStackView()
        buttonRow.axis = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fillEqually
        buttonRow.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let enabledButton = GlassButton(title: "Enabled", image: UIImage(systemName: "checkmark"))
        let disabledButton = GlassButton(title: "Disabled", image: UIImage(systemName: "lock"))
        disabledButton.isEnabled = false
        buttonRow.addArrangedSubview(enabledButton)
        buttonRow.addArrangedSubview(disabledButton)
        stackView.addArrangedSubview(makeSectionTitle("Buttons and states"))
        stackView.addArrangedSubview(buttonRow)

        let inputSurface = TextureAppearanceGallerySurface(role: .input, cornerRadius: 10)
        inputSurface.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let textField = UITextField()
        textField.placeholder = "Search or enter text"
        textField.clearButtonMode = .whileEditing
        textField.translatesAutoresizingMaskIntoConstraints = false
        inputSurface.contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: inputSurface.contentView.leadingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: inputSurface.contentView.trailingAnchor, constant: -14),
            textField.topAnchor.constraint(equalTo: inputSurface.contentView.topAnchor),
            textField.bottomAnchor.constraint(equalTo: inputSurface.contentView.bottomAnchor)
        ])
        stackView.addArrangedSubview(makeSectionTitle("Input"))
        stackView.addArrangedSubview(inputSurface)

        let segmented = AetherSegmentedControl(
            items: [
                .init(title: "One"),
                .init(title: "Two", badgeValue: "2"),
                .init(title: "Three")
            ],
            selectedIndex: 1
        )
        segmented.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stackView.addArrangedSubview(makeSectionTitle("Selection"))
        stackView.addArrangedSubview(segmented)

        let slider = AetherSlider(value: 0.62)
        slider.heightAnchor.constraint(equalToConstant: 52).isActive = true
        stackView.addArrangedSubview(slider)

        let toolbar = AetherToolbarView(
            theme: ExampleAppearanceStore.shared.toolbarTheme,
            toolbar: AetherToolbar(
                leftAction: .init(title: "Cancel"),
                middleAction: .init(title: "Disabled", isEnabled: false),
                rightAction: .init(title: "Done")
            )
        )
        toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stackView.addArrangedSubview(makeSectionTitle("Toolbar"))
        stackView.addArrangedSubview(toolbar)

        let floatingToolbar = AetherFloatingToolbarView(
            segments: [
                .standalone(.init(icon: UIImage(systemName: "chevron.left"))),
                .pill([
                    .init(icon: UIImage(systemName: "square.and.arrow.up")),
                    .init(icon: UIImage(systemName: "bookmark"), isEnabled: false)
                ]),
                .standalone(.init(icon: UIImage(systemName: "ellipsis")))
            ],
            theme: ExampleAppearanceStore.shared.isDark ? .dark : .light
        )
        floatingToolbar.heightAnchor.constraint(equalToConstant: AetherFloatingToolbarView.defaultHeight).isActive = true
        stackView.addArrangedSubview(makeSectionTitle("Floating surface"))
        stackView.addArrangedSubview(floatingToolbar)

        let popup = TextureAppearanceGallerySurface(role: .popup, cornerRadius: 14)
        popup.heightAnchor.constraint(equalToConstant: 66).isActive = true
        let popupButton = GlassButton(title: "Open real Aether alert", image: UIImage(systemName: "rectangle.on.rectangle"))
        popupButton.translatesAutoresizingMaskIntoConstraints = false
        popupButton.action = { [weak self] _ in self?.presentGalleryAlert() }
        popup.contentView.addSubview(popupButton)
        NSLayoutConstraint.activate([
            popupButton.centerXAnchor.constraint(equalTo: popup.contentView.centerXAnchor),
            popupButton.centerYAnchor.constraint(equalTo: popup.contentView.centerYAnchor),
            popupButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        stackView.addArrangedSubview(makeSectionTitle("Popup / overlay"))
        stackView.addArrangedSubview(popup)

        applyAppearance()
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: ExampleAppearanceStore.didChange,
            object: ExampleAppearanceStore.shared,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
        }
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        aetherTabBarController?.setBottomBarAccessory(galleryBottomAccessory, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        aetherTabBarController?.setBottomBarAccessory(nil, animated: true)
        super.viewWillDisappear(animated)
    }

    override func containerLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition
    ) {
        super.containerLayoutUpdated(layout, transition: transition)
        transition.updateFrame(view: scrollView, frame: CGRect(origin: .zero, size: layout.size))
        scrollView.contentInset = UIEdgeInsets(
            top: exampleTopInset(for: self, layout: layout) + 12,
            left: 0,
            bottom: exampleBottomInset(for: self, layout: layout) + 20,
            right: 0
        )
        scrollView.scrollIndicatorInsets = scrollView.contentInset
    }

    @objc private func styleChanged() {
        let styles = AetherAppearanceStyle.allCases
        guard styles.indices.contains(styleSelector.selectedSegmentIndex) else { return }
        ExampleAppearanceStore.shared.update(style: styles[styleSelector.selectedSegmentIndex])
    }

    @objc private func darkAppearanceChanged() {
        ExampleAppearanceStore.shared.update(dark: darkSwitch.isOn)
    }

    private func applyAppearance() {
        let store = ExampleAppearanceStore.shared
        view.backgroundColor = store.backgroundColor
        node.backgroundColor = store.backgroundColor
        for case let toolbar as AetherToolbarView in stackView.arrangedSubviews {
            toolbar.theme = store.toolbarTheme
        }
        for case let floatingToolbar as AetherFloatingToolbarView in stackView.arrangedSubviews {
            floatingToolbar.theme = store.isDark ? .dark : .light
        }
        styleSelector.selectedSegmentIndex = AetherAppearanceStyle.allCases.firstIndex(
            of: store.appearance.style
        ) ?? UISegmentedControl.noSegment
        darkSwitch.setOn(store.isDark, animated: false)
    }

    private func presentGalleryAlert() {
        let alert = AetherAlertController(
            title: "Appearance Gallery",
            message: "This is the real Aether alert surface in the selected style.",
            actions: [
                AetherAlertAction(title: "Disabled", enabled: false),
                AetherAlertAction(title: "Done", style: .primary)
            ],
            textFields: [AetherAlertTextField(placeholder: "Input surface")]
        )
        present(alert, animated: true)
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = makeLabel(
            text,
            font: .preferredFont(forTextStyle: .caption1),
            color: .secondaryLabel
        )
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor = .label) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }
}

private enum TextureShowcaseTopic: String {
    case navigation
    case controls
    case states
    case texture

    var title: String {
        switch self {
        case .navigation: return "Navigation"
        case .controls: return "Controls"
        case .states: return "States"
        case .texture: return "Texture"
        }
    }

    var rows: [(String, String, String, UIColor)] {
        switch self {
        case .navigation:
            return [
                ("Shared Navigation Bar", "One bar instance hosts pushed controllers", "rectangle.stack.fill", .systemIndigo),
                ("Top Accessory", "Texture-hosted accessory under the title", "rectangle.topthird.inset.filled", .systemBlue),
                ("Native Window", "AetherNativeWindow owns layout, keyboard and overlays", "macwindow", .systemTeal)
            ]
        case .controls:
            return [
                ("Segmented Control", "AetherSegmentedControlNode for compact choices", "capsule.fill", .systemGreen),
                ("AetherFloating", "Floating toolbar actions above bottom chrome", "rectangle.bottomthird.inset.filled", .systemOrange),
                ("Glass Button Node", "ASControlNode-backed tap target", "circle.grid.cross.fill", .systemPink)
            ]
        case .states:
            return [
                ("Loading", "Texture row skeleton placeholder model", "hourglass", .systemGray),
                ("Empty", "Content-unavailable style empty state", "tray", .systemBlue),
                ("Modal", "Overlay presentation from a node screen", "rectangle.stack.badge.plus", .systemPurple)
            ]
        case .texture:
            return [
                ("AetherListNode", "Virtualized ASScrollNode list engine", "list.bullet.rectangle", .systemBlue),
                ("Rows", "ASTextNode, ASImageNode and ASControlNode content", "square.stack.3d.up.fill", .systemIndigo),
                ("Transactions", "Insert, move, delete, update without UIKit cells", "arrow.triangle.2.circlepath", .systemGreen)
            ]
        }
    }
}

private final class TextureShowcaseController: AetherViewController {
    private let topic: TextureShowcaseTopic
    private let listNode = AetherListNode()
    private var didAlignInitialListTop = false
    private var generatedRowCount = 0
    private var accessoryVisible = false
    private var appearanceObserver: NSObjectProtocol?
    private lazy var actionToolbar = exampleFloatingToolbar([
        .pill([
            exampleToolbarButton("plus") { [weak self] in self?.appendGeneratedRow() },
            exampleToolbarButton("rectangle.stack.badge.plus") { [weak self] in self?.presentDemoModal() },
            exampleToolbarButton("arrow.right") { [weak self] in self?.pushNextController() }
        ])
    ])

    init(topic: TextureShowcaseTopic) {
        self.topic = topic
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: ExampleAppearanceStore.shared.backgroundColor))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = topic.title
        node.addSubnode(listNode)
        floatingToolbar = actionToolbar
        listNode.backgroundColor = .clear
        applyAppearance()
        reloadRows()
        observeAppearance()
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        updateExampleListLayout(
            controller: self,
            listNode: listNode,
            layout: layout,
            transition: transition,
            didAlignInitialTop: &didAlignInitialListTop
        )
    }

    private func reloadRows() {
        var rows = topic.rows.enumerated().map { index, row in
            TextureMenuItem(
                id: "\(topic.rawValue)-\(index)",
                title: row.0,
                subtitle: row.1,
                iconName: row.2,
                tintColor: row.3,
                trailing: "Node"
            ) { [weak self] in self?.performTopicAction(index: index) }
        }
        if generatedRowCount > 0 {
            rows += (0..<generatedRowCount).map { index in
                TextureMenuItem(
                    id: "\(topic.rawValue)-generated-\(index)",
                    title: "Generated Row \(index + 1)",
                    subtitle: "Inserted through AetherListNode transaction",
                    iconName: "plus.rectangle.on.rectangle",
                    tintColor: .systemMint,
                    trailing: "Live"
                ) { [weak self] in self?.moveGeneratedRow(index) }
            }
        }
        listNode.transaction(
            deleteIndices: (0..<listNode.itemCount).map { AetherListDeleteItem(index: $0, animation: .fade) },
            insertIndicesAndItems: rows.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )
    }

    private func presentDemoModal() {
        let modal = AetherModalController(config: .init(detents: [.stage1], initialDetent: .stage1))
        modal.embedContent(AetherScreenController(screenNode: TextureModalNode(title: "Texture modal")))
        present(modal, animated: true)
    }

    private func performTopicAction(index: Int) {
        switch (topic, index) {
        case (.navigation, 0):
            accessoryVisible.toggle()
            didAlignInitialListTop = false
            setTopBarAccessory(accessoryVisible ? TextureSettingsTopAccessoryView(text: "Navigation accessory") : nil, animated: true)
        case (.navigation, 1):
            pushNextController()
        case (.navigation, 2):
            presentDemoModal()
        case (.controls, 0):
            accessoryVisible.toggle()
            didAlignInitialListTop = false
            setTopBarAccessory(accessoryVisible ? TextureSegmentAccessoryView() : nil, animated: true)
        case (.controls, 1):
            appendGeneratedRow()
        case (.controls, 2):
            push(TextureControlsPlaygroundController())
        case (.states, 0):
            showLoadingState()
        case (.states, 1):
            showEmptyState()
        case (.states, 2):
            presentDemoModal()
        case (.texture, 0):
            appendGeneratedRow()
        case (.texture, 1):
            moveGeneratedRow(0)
        case (.texture, 2):
            deleteGeneratedRow()
        default:
            break
        }
    }

    private func appendGeneratedRow() {
        generatedRowCount += 1
        reloadRows()
    }

    private func moveGeneratedRow(_ index: Int) {
        guard generatedRowCount > 1 else {
            appendGeneratedRow()
            return
        }
        let baseCount = topic.rows.count
        let from = baseCount + min(max(0, index), generatedRowCount - 1)
        let to = baseCount + ((from - baseCount + 1) % generatedRowCount)
        guard from < listNode.itemCount, to < listNode.itemCount else {
            reloadRows()
            return
        }
        listNode.transaction(moveIndices: [AetherListMoveItem(fromIndex: from, toIndex: to)], options: [.animateInsertions])
    }

    private func deleteGeneratedRow() {
        guard generatedRowCount > 0 else { return }
        generatedRowCount -= 1
        let index = topic.rows.count + generatedRowCount
        guard index < listNode.itemCount else {
            reloadRows()
            return
        }
        listNode.transaction(deleteIndices: [AetherListDeleteItem(index: index, animation: .scale)], options: [.animateInsertions])
    }

    private func pushNextController() {
        push(TextureShowcaseController(topic: topic))
    }

    private func showLoadingState() {
        let rows = (0..<5).map {
            TextureMenuItem(
                id: "loading-\($0)",
                title: "Loading placeholder \($0 + 1)",
                subtitle: "Texture row updated without UIKit cells",
                iconName: "hourglass",
                tintColor: .systemGray
            ) { }
        }
        listNode.transaction(
            deleteIndices: (0..<listNode.itemCount).map { AetherListDeleteItem(index: $0, animation: .fade) },
            insertIndicesAndItems: rows.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.animateInsertions, .crossfade]
        )
    }

    private func showEmptyState() {
        let row = TextureMenuItem(
            id: "empty-state",
            title: "No Results",
            subtitle: "Tap to restore the live state list",
            iconName: "tray",
            tintColor: .systemBlue,
            trailing: "Reset"
        ) { [weak self] in self?.reloadRows() }
        listNode.transaction(
            deleteIndices: (0..<listNode.itemCount).map { AetherListDeleteItem(index: $0, animation: .fade) },
            insertIndicesAndItems: [AetherListInsertItem(index: 0, item: row)],
            options: [.animateInsertions, .crossfade]
        )
    }

    private func observeAppearance() {
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: ExampleAppearanceStore.didChange,
            object: ExampleAppearanceStore.shared,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
            self?.listNode.transaction(options: [.forceUpdate, .crossfade])
        }
    }

    private func applyAppearance() {
        let store = ExampleAppearanceStore.shared
        view.backgroundColor = store.backgroundColor
        node.backgroundColor = store.backgroundColor
        actionToolbar.theme = exampleFloatingToolbarTheme()
    }
}

private final class TextureSegmentAccessoryView: NavigationBarContentView {
    var selectionChanged: ((Int) -> Void)?

    private let titleNode = ASTextNode()
    private let segmentedNode = AetherSegmentedControlNode(
        items: [
            AetherSegmentedControl.Item(title: "Compact"),
            AetherSegmentedControl.Item(title: "Dense"),
            AetherSegmentedControl.Item(title: "Debug")
        ],
        selectedIndex: 0
    )

    override var nominalHeight: CGFloat { 52.0 }
    override var mode: NavigationBarContentMode { .expansion }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleNode.attributedText = NSAttributedString(
            string: "Mode",
            attributes: [.font: UIFont.systemFont(ofSize: 13.0, weight: .semibold), .foregroundColor: UIColor.secondaryLabel]
        )
        addSubview(titleNode.view)
        addSubview(segmentedNode.view)
        segmentedNode.selectionChanged = { [weak self] index in
            self?.selectionChanged?(index)
        }
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let titleBounds = CGRect(x: 16.0, y: 8.0, width: 52.0, height: 36.0)
        let titleSize = titleNode.layoutThatFits(ASSizeRange(min: .zero, max: titleBounds.size)).size
        titleNode.frame = centeredFrame(for: titleSize, in: titleBounds)
        segmentedNode.frame = CGRect(x: 72.0, y: 8.0, width: max(0.0, bounds.width - 88.0), height: 36.0)
    }
}

private final class TextureControlsPlaygroundController: AetherViewController {
    private let listNode = AetherListNode()
    private let modeAccessory = TextureSegmentAccessoryView()
    private var mode = 0
    private var extraRows = 0
    private var didAlignInitialListTop = false
    private var appearanceObserver: NSObjectProtocol?
    private lazy var actionsToolbar = exampleFloatingToolbar([
        .pill([
            exampleToolbarButton("plus") { [weak self] in self?.insertControlRow() },
            exampleToolbarButton("shuffle") { [weak self] in self?.shuffleMode() },
            exampleToolbarButton("rectangle.stack.badge.plus") { [weak self] in self?.presentControlModal() }
        ])
    ])

    init() {
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: ExampleAppearanceStore.shared.backgroundColor))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Controls"
        topBarAccessory = modeAccessory
        floatingToolbar = actionsToolbar
        node.addSubnode(listNode)
        listNode.backgroundColor = .clear
        modeAccessory.selectionChanged = { [weak self] index in
            self?.mode = index
            self?.reloadRows(animated: true)
        }
        applyAppearance()
        reloadRows(animated: false)
        observeAppearance()
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        updateExampleListLayout(
            controller: self,
            listNode: listNode,
            layout: layout,
            transition: transition,
            didAlignInitialTop: &didAlignInitialListTop
        )
    }

    private func reloadRows(animated: Bool) {
        let modeTitle = ["Compact", "Dense", "Debug"][min(mode, 2)]
        var rows: [TextureMenuItem] = [
            TextureMenuItem(id: "segmented", title: "Segmented Control", subtitle: "Current mode: \(modeTitle)", iconName: "capsule.fill", tintColor: .systemGreen, trailing: modeTitle) { [weak self] in self?.shuffleMode() },
            TextureMenuItem(id: "floating", title: "AetherFloating", subtitle: "Bottom actions are real floating chrome", iconName: "rectangle.bottomthird.inset.filled", tintColor: .systemOrange) { [weak self] in self?.insertControlRow() },
            TextureMenuItem(id: "modal", title: "Modal", subtitle: "Presents Texture content through AetherModal", iconName: "rectangle.stack.badge.plus", tintColor: .systemPurple) { [weak self] in self?.presentControlModal() }
        ]
        rows += (0..<extraRows).map { index in
            TextureMenuItem(
                id: "control-extra-\(index)",
                title: "Inserted Control \(index + 1)",
                subtitle: "Added from floating toolbar",
                iconName: "slider.horizontal.3",
                tintColor: .systemBlue,
                trailing: "Live"
            ) { [weak self] in self?.deleteLastControlRow() }
        }
        listNode.transaction(
            deleteIndices: (0..<listNode.itemCount).map { AetherListDeleteItem(index: $0, animation: .fade) },
            insertIndicesAndItems: rows.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: animated ? [.animateInsertions, .crossfade] : [.synchronous]
        )
    }

    private func insertControlRow() {
        extraRows += 1
        reloadRows(animated: true)
    }

    private func deleteLastControlRow() {
        guard extraRows > 0 else { return }
        extraRows -= 1
        reloadRows(animated: true)
    }

    private func shuffleMode() {
        mode = (mode + 1) % 3
        reloadRows(animated: true)
    }

    private func presentControlModal() {
        let modal = AetherModalController(config: .init(detents: [.stage1], initialDetent: .stage1))
        modal.embedContent(AetherScreenController(screenNode: TextureModalNode(title: "Controls modal")))
        present(modal, animated: true)
    }

    private func observeAppearance() {
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: ExampleAppearanceStore.didChange,
            object: ExampleAppearanceStore.shared,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
            self?.listNode.transaction(options: [.forceUpdate, .crossfade])
        }
    }

    private func applyAppearance() {
        view.backgroundColor = ExampleAppearanceStore.shared.backgroundColor
        node.backgroundColor = ExampleAppearanceStore.shared.backgroundColor
        actionsToolbar.theme = exampleFloatingToolbarTheme()
    }
}

private final class TextureModalNode: AetherScreenNode {
    private let titleNode = ASTextNode()
    private let subtitleNode = ASTextNode()

    init(title: String) {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        titleNode.attributedText = Self.text(title, size: 24.0, weight: .semibold, color: .label)
        subtitleNode.attributedText = Self.text("Presented from a Texture-backed Example screen.", size: 15.0, weight: .regular, color: .secondaryLabel)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let stack = ASStackLayoutSpec.vertical()
        stack.spacing = 8.0
        stack.alignItems = .center
        stack.justifyContent = .start
        stack.children = [titleNode, subtitleNode]
        return ASInsetLayoutSpec(insets: UIEdgeInsets(top: 42.0, left: 24.0, bottom: 24.0, right: 24.0), child: stack)
    }

    private static func text(_ string: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }
}

// MARK: - Chats

private struct ExampleChat: Equatable {
    let id: Int
    let name: String
    let message: String
    let time: String
    let unread: Int
    let color: UIColor
}

final class TextureChatsController: AetherViewController {
    private let listNode = AetherListNode()
    private let deleteAccessory = TextureDeleteAccessoryView()
    private var chats: [ExampleChat] = []
    private var nextChatId = 0
    private var deleteAnimation: AetherListItemDeleteAnimation = .fade
    private var didAlignInitialListTop = false
    private var appearanceObserver: NSObjectProtocol?
    private lazy var actionsToolbar = exampleFloatingToolbar([
        .pill([
            exampleToolbarButton("plus.message.fill") { [weak self] in self?.insertRandomChat() },
            exampleToolbarButton("arrow.up.arrow.down") { [weak self] in self?.moveRandomChat() },
            exampleToolbarButton("trash.fill") { [weak self] in self?.deleteRandomChat() }
        ])
    ])

    init() {
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: ExampleAppearanceStore.shared.backgroundColor))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Chats"
        topBarAccessory = deleteAccessory
        node.addSubnode(listNode)
        floatingToolbar = actionsToolbar
        listNode.backgroundColor = .clear
        listNode.preloadPages = 1
        listNode.allowsReorder = true
        listNode.didMoveItem = { [weak self] from, to in
            self?.reflectMove(from: from, to: to)
        }

        deleteAccessory.selectionChanged = { [weak self] index in
            self?.deleteAnimation = TextureDeleteAccessoryView.animation(at: index)
        }

        applyAppearance()
        seedChats()
        observeAppearance()
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        updateExampleListLayout(
            controller: self,
            listNode: listNode,
            layout: layout,
            transition: transition,
            didAlignInitialTop: &didAlignInitialListTop
        )
    }

    fileprivate func openChat(_ chat: ExampleChat) {
        push(TextureChatDialogController(chat: chat))
    }

    fileprivate func performSwipeAction(_ action: AetherListSwipeAction, chat: ExampleChat) {
        if action.key == AnyHashable("delete") {
            deleteChat(id: chat.id)
        } else if action.key == AnyHashable("archive") {
            deleteChat(id: chat.id)
        } else if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            let updated: ExampleChat
            if action.key == AnyHashable("unread") {
                updated = ExampleChat(
                    id: chat.id,
                    name: chat.name,
                    message: chat.message,
                    time: chat.time,
                    unread: max(1, chat.unread + 1),
                    color: chat.color
                )
            } else {
                updated = ExampleChat(
                    id: chat.id,
                    name: chat.name,
                    message: "Muted · \(chat.message)",
                    time: chat.time,
                    unread: 0,
                    color: chat.color
                )
            }
            chats[index] = updated
            listNode.transaction(
                updateIndicesAndItems: [AetherListUpdateItem(index: index, previousIndex: index, item: makeItem(chat: updated))],
                options: [.crossfade]
            )
        } else {
            deleteChat(id: chat.id)
        }
    }

    private func seedChats() {
        chats = (0..<2_500).map { _ in makeRandomChat() }
        let items = chats.map { makeItem(chat: $0) }
        listNode.transaction(
            insertIndicesAndItems: items.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )
    }

    private func insertRandomChat() {
        let chat = makeRandomChat(today: true)
        let index = min(Int.random(in: 0...max(0, min(chats.count, 40))), chats.count)
        chats.insert(chat, at: index)
        listNode.transaction(
            insertIndicesAndItems: [AetherListInsertItem(index: index, item: makeItem(chat: chat), forceAnimateInsertion: true)],
            options: [.animateInsertions, .requestItemInsertionAnimations]
        )
    }

    private func moveRandomChat() {
        guard chats.count > 2 else { return }
        let from = Int.random(in: 0..<min(chats.count, 80))
        var to = Int.random(in: 0..<min(chats.count, 80))
        while to == from {
            to = Int.random(in: 0..<min(chats.count, 80))
        }
        let chat = chats.remove(at: from)
        chats.insert(chat, at: to)
        listNode.transaction(
            moveIndices: [AetherListMoveItem(fromIndex: from, toIndex: to)],
            options: [.animateInsertions]
        )
    }

    private func deleteRandomChat() {
        guard !chats.isEmpty else { return }
        let index = Int.random(in: 0..<min(chats.count, 80))
        chats.remove(at: index)
        listNode.transaction(
            deleteIndices: [AetherListDeleteItem(index: index, animation: deleteAnimation)],
            options: [.animateInsertions]
        )
    }

    private func deleteChat(id: Int) {
        guard let index = chats.firstIndex(where: { $0.id == id }) else { return }
        chats.remove(at: index)
        listNode.transaction(
            deleteIndices: [AetherListDeleteItem(index: index, animation: deleteAnimation)],
            options: [.animateInsertions]
        )
    }

    private func reflectMove(from: Int, to: Int) {
        guard from >= 0, from < chats.count, to >= 0, to < chats.count else { return }
        let chat = chats.remove(at: from)
        chats.insert(chat, at: to)
    }

    private func makeItem(chat: ExampleChat) -> TextureChatItem {
        TextureChatItem(
            chat: chat,
            open: { [weak self] chat in self?.openChat(chat) },
            swipe: { [weak self] action, chat in self?.performSwipeAction(action, chat: chat) }
        )
    }

    private func makeRandomChat(today: Bool = false) -> ExampleChat {
        let id = nextChatId
        nextChatId += 1
        let name = Self.names[id % Self.names.count]
        let message = Self.messages.randomElement() ?? "Окей"
        let time = today
            ? String(format: "%02d:%02d", Int.random(in: 10...23), Int.random(in: 0...59))
            : Self.times[id % Self.times.count]
        let unread = Int.random(in: 0...100) < 18 ? Int.random(in: 1...9) : 0
        return ExampleChat(
            id: id,
            name: name,
            message: message,
            time: time,
            unread: unread,
            color: Self.colors[id % Self.colors.count]
        )
    }

    private func observeAppearance() {
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: ExampleAppearanceStore.didChange,
            object: ExampleAppearanceStore.shared,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
            self?.listNode.transaction(options: [.forceUpdate, .crossfade])
        }
    }

    private func applyAppearance() {
        let store = ExampleAppearanceStore.shared
        view.backgroundColor = store.backgroundColor
        node.backgroundColor = store.backgroundColor
        actionsToolbar.theme = exampleFloatingToolbarTheme()
    }

    private static let names = [
        "Анна Ахматова", "Виктор Пелевин", "Мария Кюри", "Марина Цветаева",
        "Антон Чехов", "Лев Толстой", "Сергей Есенин", "Николай Гоголь",
        "Фёдор Достоевский", "Татьяна Толстая", "Иван Бунин", "Борис Пастернак"
    ]

    private static let messages = [
        "Уже в пути", "Звонила тебе", "Что думаешь?", "Файл во вложении",
        "Можно завтра встретиться?", "Окей, договорились", "Перезвоню через 10 минут",
        "Спасибо!", "Отправил по почте", "Проверишь билд?", "Сейчас посмотрю",
        "Да, выглядит быстрее"
    ]

    private static let times = ["17:39", "17:11", "09:59", "19:02", "12:01", "21:05", "Пн", "Вт", "Ср"]
    private static let colors: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .systemPink, .systemTeal]
}

private final class TextureDeleteAccessoryView: NavigationBarContentView {
    var selectionChanged: ((Int) -> Void)?

    private let titleNode = ASTextNode()
    private let segmentedNode = AetherSegmentedControlNode(
        items: [
            AetherSegmentedControl.Item(title: "Fade"),
            AetherSegmentedControl.Item(title: "Slide"),
            AetherSegmentedControl.Item(title: "Scale"),
            AetherSegmentedControl.Item(title: "Particles")
        ],
        selectedIndex: 0
    )

    override var nominalHeight: CGFloat { 52.0 }
    override var mode: NavigationBarContentMode { .expansion }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleNode.attributedText = NSAttributedString(
            string: "Delete",
            attributes: [.font: UIFont.systemFont(ofSize: 13.0, weight: .semibold), .foregroundColor: UIColor.secondaryLabel]
        )
        addSubview(titleNode.view)
        addSubview(segmentedNode.view)
        segmentedNode.selectionChanged = { [weak self] index in
            self?.selectionChanged?(index)
        }
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let titleBounds = CGRect(x: 16.0, y: 8.0, width: 56.0, height: 36.0)
        let titleSize = titleNode.layoutThatFits(ASSizeRange(min: .zero, max: titleBounds.size)).size
        titleNode.frame = centeredFrame(for: titleSize, in: titleBounds)
        segmentedNode.frame = CGRect(x: 74.0, y: 8.0, width: max(0.0, bounds.width - 90.0), height: 36.0)
    }

    static func animation(at index: Int) -> AetherListItemDeleteAnimation {
        switch index {
        case 1: return .slide(.up)
        case 2: return .scale
        case 3: return .particles
        default: return .fade
        }
    }
}

private final class TextureChatItem: AetherListItem {
    let chat: ExampleChat
    let open: (ExampleChat) -> Void
    let swipe: (AetherListSwipeAction, ExampleChat) -> Void

    init(
        chat: ExampleChat,
        open: @escaping (ExampleChat) -> Void,
        swipe: @escaping (AetherListSwipeAction, ExampleChat) -> Void
    ) {
        self.chat = chat
        self.open = open
        self.swipe = swipe
    }

    var stableId: AnyHashable { chat.id }
    var approximateHeight: CGFloat { 72.0 }
    var estimatedHeight: CGFloat { 72.0 }
    var selectable: Bool { true }
    var swipeActions: AetherListSwipeActions {
        AetherListSwipeActions(
            left: [
                AetherListSwipeAction(
                    key: "unread",
                    title: "Unread",
                    icon: Self.icon("bubble.left.fill"),
                    backgroundColor: .systemBlue
                )
            ],
            right: [
                AetherListSwipeAction(
                    key: "mute",
                    title: "Mute",
                    icon: Self.icon("speaker.slash.fill"),
                    backgroundColor: .systemOrange
                ),
                AetherListSwipeAction(
                    key: "delete",
                    title: "Delete",
                    icon: Self.icon("trash.fill"),
                    backgroundColor: .systemRed
                ),
                AetherListSwipeAction(
                    key: "archive",
                    title: "Archive",
                    icon: Self.icon("archivebox.fill"),
                    backgroundColor: .systemGray
                )
            ]
        )
    }

    func createNode(
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?
    ) -> (AetherListItemNode, AetherListItemNodeLayout) {
        let node = TextureChatRowNode(frame: .zero)
        node.configure(item: self)
        return (node, layout(width: params.width))
    }

    func updateNode(
        _ node: AetherListItemNode,
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?,
        animation: AetherListItemUpdateAnimation
    ) -> AetherListItemNodeLayout {
        (node as? TextureChatRowNode)?.configure(item: self)
        return layout(width: params.width)
    }

    func selected(listNode: AetherListNode) {
        open(chat)
    }

    func swipeActionSelected(_ action: AetherListSwipeAction, listNode: AetherListNode, isFullSwipe: Bool) {
        swipe(action, chat)
    }

    private func layout(width: CGFloat) -> AetherListItemNodeLayout {
        AetherListItemNodeLayout(contentSize: CGSize(width: width, height: 72.0))
    }

    private static func icon(_ name: String) -> AetherListSwipeAction.Icon {
        guard let image = UIImage(systemName: name) else { return .none }
        return .image(image)
    }
}

private final class TextureChatRowNode: AetherListItemNode {
    private let avatarNode = ASDisplayNode()
    private let avatarTextNode = ASTextNode()
    private let nameNode = ASTextNode()
    private let messageNode = ASTextNode()
    private let timeNode = ASTextNode()
    private let unreadNode = ASDisplayNode()
    private let unreadTextNode = ASTextNode()
    private let separatorNode = ASDisplayNode()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubnode(avatarNode)
        avatarNode.addSubnode(avatarTextNode)
        addSubnode(nameNode)
        addSubnode(messageNode)
        addSubnode(timeNode)
        addSubnode(unreadNode)
        unreadNode.addSubnode(unreadTextNode)
        addSubnode(separatorNode)

        avatarNode.cornerRadius = 28.0
        avatarNode.clipsToBounds = true
        unreadNode.backgroundColor = .systemBlue
        unreadNode.cornerRadius = 10.0
        messageNode.maximumNumberOfLines = 1
        nameNode.maximumNumberOfLines = 1
        timeNode.maximumNumberOfLines = 1
        unreadTextNode.maximumNumberOfLines = 1
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: TextureChatItem) {
        let store = ExampleAppearanceStore.shared
        let chat = item.chat
        backgroundColor = store.backgroundColor
        avatarNode.backgroundColor = chat.color
        avatarTextNode.attributedText = Self.text(String(chat.name.prefix(1)), font: .systemFont(ofSize: 24.0, weight: .semibold), color: .white, alignment: .center)
        nameNode.attributedText = Self.text(chat.name, font: .systemFont(ofSize: 17.0, weight: .semibold), color: .label)
        messageNode.attributedText = Self.text(chat.message, font: .systemFont(ofSize: 15.0), color: .secondaryLabel)
        timeNode.attributedText = Self.text(chat.time, font: .systemFont(ofSize: 14.0), color: .secondaryLabel, alignment: .right)
        unreadNode.isHidden = chat.unread == 0
        unreadTextNode.isHidden = chat.unread == 0
        unreadTextNode.attributedText = chat.unread == 0
            ? nil
            : Self.text("\(chat.unread)", font: .systemFont(ofSize: 12.0, weight: .semibold), color: .white, alignment: .center)
        separatorNode.backgroundColor = .separator
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let avatarSide: CGFloat = 56.0
        avatarNode.frame = CGRect(x: 16.0, y: 8.0, width: avatarSide, height: avatarSide)
        let avatarTextSize = avatarTextNode.layoutThatFits(ASSizeRange(min: .zero, max: avatarNode.bounds.size)).size
        avatarTextNode.frame = centeredFrame(for: avatarTextSize, in: avatarNode.bounds)

        let textX = avatarNode.frame.maxX + 12.0
        let rightInset: CGFloat = 16.0
        let timeWidth: CGFloat = 62.0
        let titleWidth = max(0.0, bounds.width - rightInset - timeWidth - textX - 8.0)
        let nameSize = nameNode.layoutThatFits(ASSizeRange(min: .zero, max: CGSize(width: titleWidth, height: CGFloat.greatestFiniteMagnitude))).size
        let messageSize = messageNode.layoutThatFits(ASSizeRange(min: .zero, max: CGSize(width: bounds.width - textX - rightInset, height: CGFloat.greatestFiniteMagnitude))).size
        let textStackHeight = nameSize.height + 4.0 + messageSize.height
        let textTop = floor((bounds.height - textStackHeight) / 2.0)
        timeNode.frame = CGRect(x: bounds.width - rightInset - timeWidth, y: textTop, width: timeWidth, height: nameSize.height)
        nameNode.frame = CGRect(x: textX, y: textTop, width: titleWidth, height: nameSize.height)

        let messageRight: CGFloat
        if !unreadNode.isHidden {
            let text = unreadTextNode.attributedText?.string ?? ""
            let badgeWidth = max(20.0, text.size(withAttributes: [.font: UIFont.systemFont(ofSize: 12.0, weight: .semibold)]).width + 12.0)
            unreadNode.frame = CGRect(x: bounds.width - rightInset - badgeWidth, y: textTop + nameSize.height + 5.0, width: badgeWidth, height: 20.0)
            let unreadTextSize = unreadTextNode.layoutThatFits(ASSizeRange(min: .zero, max: unreadNode.bounds.size)).size
            unreadTextNode.frame = centeredFrame(for: unreadTextSize, in: unreadNode.bounds)
            messageRight = unreadNode.frame.minX - 8.0
        } else {
            unreadNode.frame = .zero
            unreadTextNode.frame = .zero
            messageRight = bounds.width - rightInset
        }
        messageNode.frame = CGRect(x: textX, y: textTop + nameSize.height + 4.0, width: max(0.0, messageRight - textX), height: messageSize.height)

        let pixel = 1.0 / UIScreen.main.scale
        separatorNode.frame = CGRect(x: textX, y: bounds.height - pixel, width: bounds.width - textX, height: pixel)
    }

    private static func text(
        _ string: String,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .natural
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}

// MARK: - Chat Dialog

final class TextureChatDialogController: AetherViewController {
    private let chat: ExampleChat
    private let listNode = AetherListNode()
    private var messages: [TextureMessageItem] = []
    private var nextMessageId = 0
    private var didAlignInitialListBottom = false
    private var appearanceObserver: NSObjectProtocol?
    private lazy var actionsToolbar = exampleFloatingToolbar([
        .pill([
            exampleToolbarButton("paperclip") { [weak self] in self?.insertAttachmentMessage() },
            exampleToolbarButton("paperplane.fill") { [weak self] in self?.sendRandomMessage() },
            exampleToolbarButton("trash.fill") { [weak self] in self?.deleteLastMessage() }
        ])
    ])

    fileprivate init(chat: ExampleChat) {
        self.chat = chat
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: ExampleAppearanceStore.shared.backgroundColor))
        hidesBottomBarWhenPushed = true
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = chat.name
        node.addSubnode(listNode)
        floatingToolbar = actionsToolbar
        listNode.backgroundColor = .clear
        listNode.stackFromBottom = true
        applyAppearance()
        seedMessages()
        observeAppearance()
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        transition.updateFrame(node: listNode, frame: CGRect(origin: .zero, size: layout.size))
        listNode.updateInsets(
            UIEdgeInsets(
                top: exampleTopInset(for: self, layout: layout),
                left: layout.safeInsets.left,
                bottom: exampleBottomInset(for: self, layout: layout),
                right: layout.safeInsets.right
            ),
            transition: transition,
            preserveContentOffset: didAlignInitialListBottom
        )
        if !didAlignInitialListBottom {
            listNode.scrollToBottom(animated: false)
            didAlignInitialListBottom = true
        }
    }

    private func seedMessages() {
        messages = (0..<70).map { index in
            makeMessage(incoming: index % 3 != 0)
        }
        listNode.transaction(
            insertIndicesAndItems: messages.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous],
            scrollToItem: AetherListScrollToItem(index: max(0, messages.count - 1), position: .bottom(offset: 0.0), animated: false)
        )
    }

    private func sendRandomMessage() {
        let message = makeMessage(incoming: false)
        messages.append(message)
        listNode.transaction(
            insertIndicesAndItems: [AetherListInsertItem(index: messages.count - 1, item: message, forceAnimateInsertion: true)],
            options: [.animateInsertions, .requestItemInsertionAnimations],
            scrollToItem: AetherListScrollToItem(index: messages.count - 1, position: .bottom(offset: 0.0), animated: true)
        )
    }

    private func insertAttachmentMessage() {
        let id = nextMessageId
        nextMessageId += 1
        let message = TextureMessageItem(id: id, text: "Файл во вложении", incoming: false, accent: .systemTeal)
        messages.append(message)
        listNode.transaction(
            insertIndicesAndItems: [AetherListInsertItem(index: messages.count - 1, item: message, forceAnimateInsertion: true)],
            options: [.animateInsertions, .requestItemInsertionAnimations],
            scrollToItem: AetherListScrollToItem(index: messages.count - 1, position: .bottom(offset: 0.0), animated: true)
        )
    }

    private func deleteLastMessage() {
        guard !messages.isEmpty else { return }
        let index = messages.count - 1
        messages.removeLast()
        listNode.transaction(
            deleteIndices: [AetherListDeleteItem(index: index, animation: .particles)],
            options: [.animateInsertions]
        )
    }

    private func makeMessage(incoming: Bool) -> TextureMessageItem {
        let id = nextMessageId
        nextMessageId += 1
        return TextureMessageItem(
            id: id,
            text: Self.messageBank.randomElement() ?? "Окей",
            incoming: incoming,
            accent: chat.color
        )
    }

    private func observeAppearance() {
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: ExampleAppearanceStore.didChange,
            object: ExampleAppearanceStore.shared,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
            self?.listNode.transaction(options: [.forceUpdate, .crossfade])
        }
    }

    private func applyAppearance() {
        let store = ExampleAppearanceStore.shared
        view.backgroundColor = store.backgroundColor
        node.backgroundColor = store.backgroundColor
        actionsToolbar.theme = exampleFloatingToolbarTheme()
    }

    private static let messageBank = [
        "Привет!", "Как дела?", "Смотри, список теперь на Texture", "Да, свайпы круглые",
        "Открыл диалог без лагов", "Отправил билд", "Проверю на устройстве",
        "Можно завтра встретиться?", "Уже в пути", "Файл во вложении",
        "Это сообщение с чуть более длинным текстом, чтобы пузырь показал перенос строки.",
        "Окей, договорились", "Перезвоню через 10 минут", "Спасибо!"
    ]
}

private final class TextureMessageItem: AetherListItem {
    let id: Int
    let text: String
    let incoming: Bool
    let accent: UIColor

    init(id: Int, text: String, incoming: Bool, accent: UIColor) {
        self.id = id
        self.text = text
        self.incoming = incoming
        self.accent = accent
    }

    var stableId: AnyHashable { id }
    var approximateHeight: CGFloat { estimatedHeight }
    var estimatedHeight: CGFloat {
        // The exact width arrives in `nodeConfiguredForParams`; this is only
        // a stable pre-layout estimate and must not depend on another scene.
        let width: CGFloat = 294.0
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: 16.0)],
            context: nil
        )
        return max(42.0, ceil(rect.height) + 24.0) + 6.0
    }

    func createNode(
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?
    ) -> (AetherListItemNode, AetherListItemNodeLayout) {
        let node = TextureMessageNode(frame: .zero)
        node.configure(item: self)
        return (node, layout(width: params.width))
    }

    func updateNode(
        _ node: AetherListItemNode,
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?,
        animation: AetherListItemUpdateAnimation
    ) -> AetherListItemNodeLayout {
        (node as? TextureMessageNode)?.configure(item: self)
        return layout(width: params.width)
    }

    private func layout(width: CGFloat) -> AetherListItemNodeLayout {
        let textWidth = max(0.0, min(width * 0.72, width - 96.0))
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: 16.0)],
            context: nil
        )
        let bubbleHeight = max(42.0, ceil(rect.height) + 24.0)
        return AetherListItemNodeLayout(contentSize: CGSize(width: width, height: bubbleHeight + 6.0))
    }
}

private final class TextureMessageNode: AetherListItemNode {
    private let bubbleNode = ASDisplayNode()
    private let textNode = ASTextNode()
    private var incoming = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubnode(bubbleNode)
        bubbleNode.addSubnode(textNode)
        bubbleNode.cornerRadius = 18.0
        bubbleNode.clipsToBounds = true
        textNode.maximumNumberOfLines = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: TextureMessageItem) {
        incoming = item.incoming
        backgroundColor = ExampleAppearanceStore.shared.backgroundColor
        bubbleNode.backgroundColor = item.incoming
            ? ExampleAppearanceStore.shared.secondaryBackgroundColor
            : item.accent.withAlphaComponent(0.92)
        textNode.attributedText = NSAttributedString(
            string: item.text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.0),
                .foregroundColor: item.incoming ? UIColor.label : UIColor.white
            ]
        )
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let maxBubbleWidth = max(0.0, min(bounds.width * 0.72, bounds.width - 96.0))
        let measured = textNode.layoutThatFits(
            ASSizeRange(min: .zero, max: CGSize(width: maxBubbleWidth - 24.0, height: CGFloat.greatestFiniteMagnitude))
        ).size
        let bubbleSize = CGSize(width: ceil(measured.width) + 24.0, height: max(42.0, ceil(measured.height) + 24.0))
        let x = incoming ? 16.0 : bounds.width - bubbleSize.width - 16.0
        bubbleNode.frame = CGRect(x: x, y: 3.0, width: bubbleSize.width, height: bubbleSize.height)
        textNode.frame = CGRect(x: 12.0, y: 11.0, width: bubbleSize.width - 24.0, height: bubbleSize.height - 22.0)
    }
}

// MARK: - Settings

final class TextureSettingsController: AetherViewController {
    weak var hostTabBar: AetherTabBarController?

    private let listNode = AetherListNode()
    private var didAlignInitialListTop = false
    private var topAccessoryVisible = false
    private var bottomAccessoryVisible = false
    private var minimizeBehavior: AetherTabBarController.TabBarMinimizeBehavior = .never
    private var strongEdges = false
    private var appearanceObserver: NSObjectProtocol?

    init() {
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: ExampleAppearanceStore.shared.backgroundColor))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Settings"
        node.addSubnode(listNode)
        listNode.backgroundColor = .clear
        applyAppearance()
        reloadRows()
        observeAppearance()
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        updateExampleListLayout(
            controller: self,
            listNode: listNode,
            layout: layout,
            transition: transition,
            didAlignInitialTop: &didAlignInitialListTop
        )
    }

    private func reloadRows() {
        let store = ExampleAppearanceStore.shared
        let rows: [TextureMenuItem] = [
            TextureMenuItem(
                id: "appearance",
                title: "Appearance",
                subtitle: AetherAppearanceStyle.allCases.map(\.displayName).joined(separator: " / "),
                iconName: "circle.lefthalf.filled",
                tintColor: .systemBlue,
                trailing: store.appearance.style.displayName
            ) { [weak self] in self?.toggleAppearanceStyle() },
            TextureMenuItem(
                id: "dark",
                title: "Dark Appearance",
                subtitle: "Updates window, navigation and tab chrome",
                iconName: "moon.fill",
                tintColor: .systemIndigo,
                trailing: store.isDark ? "On" : "Off"
            ) { [weak self] in self?.toggleDark() },
            TextureMenuItem(
                id: "top",
                title: "Top Accessory",
                subtitle: "Texture-hosted strip under the navigation bar",
                iconName: "rectangle.topthird.inset.filled",
                tintColor: .systemPurple,
                trailing: topAccessoryVisible ? "On" : "Off"
            ) { [weak self] in self?.toggleTopAccessory() },
            TextureMenuItem(
                id: "bottom",
                title: "BottomAccessory",
                subtitle: "Tab bar accessory above the pill",
                iconName: "rectangle.bottomthird.inset.filled",
                tintColor: .systemGreen,
                trailing: bottomAccessoryVisible ? "On" : "Off"
            ) { [weak self] in self?.toggleBottomAccessory() },
            TextureMenuItem(
                id: "minimize",
                title: "Tab Minimize",
                subtitle: store.appearance.style == .legacy
                    ? "Unavailable in Legacy"
                    : "Matches tabBarMinimizeBehavior",
                iconName: "arrow.down.right.and.arrow.up.left",
                tintColor: .systemOrange,
                trailing: store.appearance.style == .legacy
                    ? "Off"
                    : (minimizeBehavior == .never ? "Never" : "Scroll")
            ) { [weak self] in self?.toggleMinimize() },
            TextureMenuItem(
                id: "edges",
                title: "Edge Effect",
                subtitle: store.canTuneGlassEdges
                    ? "Blur strength for Liquid Glass edge overlays"
                    : "Disabled by the non-glass Legacy renderer",
                iconName: "water.waves",
                tintColor: .systemTeal,
                trailing: store.canTuneGlassEdges ? (strongEdges ? "Strong" : "Soft") : "Off"
            ) { [weak self] in self?.toggleEdgeStrength() }
        ]
        listNode.transaction(
            deleteIndices: (0..<listNode.itemCount).map { AetherListDeleteItem(index: $0, animation: .fade) },
            insertIndicesAndItems: rows.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: [.synchronous]
        )
    }

    private func toggleAppearanceStyle() {
        let store = ExampleAppearanceStore.shared
        store.cycleAppearanceStyle()
        if store.appearance.style == .legacy {
            minimizeBehavior = .never
            hostTabBar?.tabBarMinimizeBehavior = .never
        }
        strongEdges = store.appearance.edgeEffectBlurRadiusAtEdge > 3.0
        reloadRows()
    }

    private func toggleDark() {
        ExampleAppearanceStore.shared.update(dark: !ExampleAppearanceStore.shared.isDark)
        reloadRows()
    }

    private func toggleTopAccessory() {
        topAccessoryVisible.toggle()
        didAlignInitialListTop = false
        setTopBarAccessory(topAccessoryVisible ? TextureSettingsTopAccessoryView(text: "Texture top accessory") : nil, animated: true)
        reloadRows()
    }

    private func toggleBottomAccessory() {
        bottomAccessoryVisible.toggle()
        hostTabBar?.setBottomBarAccessory(bottomAccessoryVisible ? TextureSettingsBottomAccessoryView() : nil, animated: true)
        reloadRows()
    }

    private func toggleMinimize() {
        guard ExampleAppearanceStore.shared.appearance.style.usesLiquidGlass else {
            minimizeBehavior = .never
            hostTabBar?.tabBarMinimizeBehavior = .never
            reloadRows()
            return
        }
        minimizeBehavior = minimizeBehavior == .never ? .onScrollDown : .never
        hostTabBar?.tabBarMinimizeBehavior = minimizeBehavior
        reloadRows()
    }

    private func toggleEdgeStrength() {
        guard ExampleAppearanceStore.shared.canTuneGlassEdges else {
            return
        }
        strongEdges.toggle()
        ExampleAppearanceStore.shared.update(edgeStrong: strongEdges)
        reloadRows()
    }

    private func observeAppearance() {
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: ExampleAppearanceStore.didChange,
            object: ExampleAppearanceStore.shared,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
            self?.listNode.transaction(options: [.forceUpdate, .crossfade])
        }
    }

    private func applyAppearance() {
        view.backgroundColor = ExampleAppearanceStore.shared.backgroundColor
        node.backgroundColor = ExampleAppearanceStore.shared.backgroundColor
    }
}

private final class TextureSettingsTopAccessoryView: NavigationBarContentView {
    private let hostView: TextureNodeHostView

    override var nominalHeight: CGFloat { 44.0 }
    override var mode: NavigationBarContentMode { .expansion }

    init(text: String) {
        self.hostView = TextureNodeHostView(node: TextureAccessoryLabelNode(text: text))
        super.init(frame: .zero)
        addSubview(hostView)
    }

    override init(frame: CGRect) {
        self.hostView = TextureNodeHostView(node: TextureAccessoryLabelNode(text: "Texture top accessory"))
        super.init(frame: frame)
        addSubview(hostView)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostView.frame = bounds.insetBy(dx: 16.0, dy: 4.0)
    }
}

private final class TextureSettingsBottomAccessoryView: TabBarAccessoryView {
    private let hostView = TextureNodeHostView(node: TextureAccessoryLabelNode(text: "Bottom bar accessory"))

    override var nominalHeight: CGFloat { 58.0 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(hostView)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostView.frame = bounds.insetBy(dx: 36.0, dy: 6.0)
    }
}

private final class TextureAccessoryLabelNode: ASDisplayNode {
    private let backgroundNode = ASDisplayNode()
    private let textNode = ASTextNode()

    init(text: String) {
        super.init()
        addSubnode(backgroundNode)
        addSubnode(textNode)
        backgroundNode.cornerRadius = 17.0
        backgroundNode.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.78)
        textNode.maximumNumberOfLines = 1
        textNode.attributedText = NSAttributedString(
            string: text,
            attributes: [.font: UIFont.systemFont(ofSize: 14.0, weight: .semibold), .foregroundColor: UIColor.label]
        )
    }

    override func layout() {
        super.layout()
        backgroundNode.frame = bounds
        let measured = textNode.layoutThatFits(ASSizeRange(min: .zero, max: bounds.size)).size
        textNode.frame = CGRect(
            x: floor((bounds.width - measured.width) / 2.0),
            y: floor((bounds.height - measured.height) / 2.0),
            width: measured.width,
            height: measured.height
        )
    }
}

// MARK: - Search

final class TextureSearchController: AetherViewController {
    private let listNode = AetherListNode()
    private let searchAccessory = TextureSearchAccessoryView()
    private var selectedScope = 0
    private var didAlignInitialListTop = false
    private var appearanceObserver: NSObjectProtocol?

    init() {
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: ExampleAppearanceStore.shared.backgroundColor))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Search"
        topBarAccessory = searchAccessory
        node.addSubnode(listNode)
        listNode.backgroundColor = .clear
        searchAccessory.selectionChanged = { [weak self] index in
            self?.selectedScope = index
            self?.reloadRows(animated: true)
        }
        applyAppearance()
        reloadRows(animated: false)
        observeAppearance()
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        updateExampleListLayout(
            controller: self,
            listNode: listNode,
            layout: layout,
            transition: transition,
            didAlignInitialTop: &didAlignInitialListTop
        )
    }

    private func reloadRows(animated: Bool) {
        let all: [TextureMenuItem] = [
            TextureMenuItem(id: "chat-anna", title: "Анна Ахматова", subtitle: "Chat result · Уже в пути", iconName: "person.fill", tintColor: .systemRed) { [weak self] in self?.push(TextureChatsController()) },
            TextureMenuItem(id: "chat-maria", title: "Мария Кюри", subtitle: "Chat result · Файл во вложении", iconName: "person.fill", tintColor: .systemGreen) { [weak self] in self?.push(TextureChatsController()) },
            TextureMenuItem(id: "component-list", title: "AetherListNode", subtitle: "Component · Virtualized Texture list", iconName: "list.bullet.rectangle", tintColor: .systemBlue) { [weak self] in self?.push(TextureChatsController()) },
            TextureMenuItem(id: "component-floating", title: "AetherFloating", subtitle: "Component · Bottom floating action surface", iconName: "rectangle.bottomthird.inset.filled", tintColor: .systemOrange) { [weak self] in self?.push(TextureControlsPlaygroundController()) },
            TextureMenuItem(id: "setting-appearance", title: "Appearance", subtitle: "Setting · Legacy and two Liquid Glass generations", iconName: "circle.lefthalf.filled", tintColor: .systemIndigo) { [weak self] in self?.push(TextureSettingsController()) }
        ]
        let rows: [TextureMenuItem]
        switch selectedScope {
        case 1:
            rows = all.filter { $0.subtitle?.contains("Chat result") == true }
        case 2:
            rows = all.filter { $0.subtitle?.contains("Component") == true }
        default:
            rows = all
        }
        listNode.transaction(
            deleteIndices: (0..<listNode.itemCount).map { AetherListDeleteItem(index: $0, animation: .fade) },
            insertIndicesAndItems: rows.enumerated().map { AetherListInsertItem(index: $0.offset, item: $0.element) },
            options: animated ? [.animateInsertions, .crossfade] : [.synchronous]
        )
    }

    private func observeAppearance() {
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: ExampleAppearanceStore.didChange,
            object: ExampleAppearanceStore.shared,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
            self?.listNode.transaction(options: [.forceUpdate, .crossfade])
        }
    }

    private func applyAppearance() {
        view.backgroundColor = ExampleAppearanceStore.shared.backgroundColor
        node.backgroundColor = ExampleAppearanceStore.shared.backgroundColor
    }
}

private final class TextureSearchAccessoryView: NavigationBarContentView {
    var selectionChanged: ((Int) -> Void)?

    private let queryNode = ASTextNode()
    private let segmentedNode = AetherSegmentedControlNode(
        items: [
            AetherSegmentedControl.Item(title: "All"),
            AetherSegmentedControl.Item(title: "Chats"),
            AetherSegmentedControl.Item(title: "Components")
        ],
        selectedIndex: 0
    )

    override var nominalHeight: CGFloat { 84.0 }
    override var mode: NavigationBarContentMode { .expansion }

    override init(frame: CGRect) {
        super.init(frame: frame)
        queryNode.maximumNumberOfLines = 1
        queryNode.attributedText = NSAttributedString(
            string: "Search in Example",
            attributes: [.font: UIFont.systemFont(ofSize: 15.0, weight: .medium), .foregroundColor: UIColor.secondaryLabel]
        )
        addSubview(queryNode.view)
        addSubview(segmentedNode.view)
        segmentedNode.selectionChanged = { [weak self] index in
            self?.selectionChanged?(index)
        }
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let queryBounds = CGRect(x: 18.0, y: 4.0, width: max(0.0, bounds.width - 36.0), height: 26.0)
        let querySize = queryNode.layoutThatFits(ASSizeRange(min: .zero, max: queryBounds.size)).size
        queryNode.frame = CGRect(
            x: queryBounds.minX,
            y: queryBounds.minY + floor((queryBounds.height - querySize.height) / 2.0),
            width: queryBounds.width,
            height: querySize.height
        )
        segmentedNode.frame = CGRect(x: 16.0, y: 36.0, width: max(0.0, bounds.width - 32.0), height: 36.0)
    }
}

// MARK: - Deterministic Animation Reference

/// Fixed content and a one-shot timeline make simulator recordings repeatable.
/// Ordinary launches never schedule this timeline.
private final class TextureAnimationReferenceController: AetherViewController {
    private let autoplay: Bool
    private let isDetail: Bool
    private let showsCamera: Bool
    private let stack = UIStackView()
    private let scrollView = UIScrollView()
    private var activeMenu: ContextMenuController?
    private var textNodes: [ASTextNode] = []
    private var scheduledSteps: [DispatchWorkItem] = []
    private var didStartAutoplay = false
    private var detailController: TextureAnimationReferenceController?
    private var badgeIndex = 0
    private let badgeValues: [String?] = ["165", "161", nil]

    init(autoplay: Bool = false, isDetail: Bool = false, showsCamera: Bool = true) {
        self.autoplay = autoplay
        self.isDetail = isDetail
        self.showsCamera = showsCamera
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: .systemBackground))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        scheduledSteps.forEach { $0.cancel() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = isDetail ? "animation-reference.detail" : "animation-reference.messages"
        view.backgroundColor = .systemBackground
        navigationItem.title = isDetail ? nil : "Сообщения"
        if isDetail {
            navigationItem.titleView = TextureAnimationReferenceTitleView(
                image: Self.avatar(color: .systemBlue),
                name: "Лёха"
            )
            navigationBarItem.backButtonBadgeText = badgeValues[badgeIndex]
            navigationItem.rightBarButtonItem = showsCamera ? cameraItem() : nil
        } else {
            installMenuChrome()
        }

        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        scrollView.addSubview(stack)
        addBackdrop()
        if isDetail {
            addButton("Изменить счётчик: 165 → 161 → без числа", id: "animation-reference.change-badge") { [weak self] in
                self?.advanceBadge()
            }
            addButton("Показать / скрыть камеру", id: "animation-reference.toggle-camera") { [weak self] in
                guard let self else { return }
                self.navigationItem.rightBarButtonItem = self.navigationItem.rightBarButtonItem == nil ? self.cameraItem() : nil
            }
            addButton("Назад", id: "animation-reference.pop") { [weak self] in self?.pop() }
        } else {
            addButton("Меню «Изменить»", id: "animation-reference.open-edit") { [weak self] in self?.showMenu(trailing: false) }
            addButton("Меню фильтров", id: "animation-reference.open-filter") { [weak self] in self?.showMenu(trailing: true) }
            addButton("Профиль → экран со счётчиком и камерой", id: "animation-reference.push-profile") { [weak self] in
                self?.installProfileChrome()
                self?.schedule(after: 0.6) { $0.openDetail(showsCamera: true) }
            }
            addButton("Экран без правой кнопки", id: "animation-reference.push-empty") { [weak self] in self?.openDetail(showsCamera: false) }
            addButton("Вернуть кнопки меню", id: "animation-reference.reset") { [weak self] in self?.installMenuChrome() }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard autoplay, !didStartAutoplay else { return }
        didStartAutoplay = true
        schedule(after: 1) { $0.showMenu(trailing: false) }
        schedule(after: 3) { $0.activeMenu?.dismiss() }
        schedule(after: 4) { $0.showMenu(trailing: true) }
        schedule(after: 6) { $0.activeMenu?.dismiss() }
        schedule(after: 6.6) { $0.installProfileChrome() }
        schedule(after: 7) { $0.openDetail(showsCamera: true) }
        schedule(after: 8) { $0.detailController?.advanceBadge() }
        schedule(after: 9) { $0.detailController?.pop() }
        schedule(after: 11) { $0.openDetail(showsCamera: false) }
        schedule(after: 12) { $0.detailController?.advanceBadge() }
        schedule(after: 12.5) { $0.detailController?.advanceBadge() }
        schedule(after: 13) { $0.detailController?.pop() }
        schedule(after: 14) { $0.installMenuChrome() }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = exampleTopInset(for: self, layout: layout) + 12
        scrollView.frame = CGRect(x: 0, y: top, width: layout.size.width, height: max(0, layout.size.height - top))
        let width = max(0, layout.size.width - 32)
        let height = stack.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        stack.frame = CGRect(x: 16, y: 0, width: width, height: height)
        scrollView.contentSize = CGSize(width: layout.size.width, height: height + layout.safeInsets.bottom + 20)
    }

    private func installMenuChrome() {
        let edit = UIBarButtonItem(title: "Изменить", contextMenuItemsProvider: { [weak self] in self?.editItems() ?? [] })
        edit.accessibilityIdentifier = "animation-reference.nav-edit"
        edit.accessibilityLabel = "Изменить"
        let filter = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease"), contextMenuItemsProvider: { [weak self] in self?.filterItems() ?? [] })
        filter.accessibilityIdentifier = "animation-reference.nav-filter"
        filter.accessibilityLabel = "Фильтры"
        navigationItem.leftBarButtonItem = edit
        navigationItem.rightBarButtonItem = filter
    }

    private func installProfileChrome() {
        let profile = UIBarButtonItem(image: Self.avatar(color: .systemOrange), style: .plain, target: self, action: #selector(profileTapped))
        profile.accessibilityIdentifier = "animation-reference.nav-profile"
        profile.accessibilityLabel = "Профиль"
        profile.customView?.accessibilityIdentifier = "animation-reference.nav-profile"
        profile.customView?.accessibilityLabel = "Профиль"
        navigationItem.leftBarButtonItem = profile
        navigationItem.rightBarButtonItem = cameraItem()
    }

    private func cameraItem() -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage(systemName: "camera"), style: .plain, target: self, action: #selector(cameraTapped))
        item.accessibilityIdentifier = "animation-reference.nav-camera"
        item.accessibilityLabel = "Камера"
        return item
    }

    @objc private func profileTapped() { openDetail(showsCamera: true) }
    @objc private func cameraTapped() { navigationItem.rightBarButtonItem = nil }

    private func openDetail(showsCamera: Bool) {
        let controller = TextureAnimationReferenceController(isDetail: true, showsCamera: showsCamera)
        detailController = controller
        push(controller)
    }

    private func advanceBadge() {
        badgeIndex = (badgeIndex + 1) % badgeValues.count
        navigationBarItem.backButtonBadgeText = badgeValues[badgeIndex]
    }

    private func showMenu(trailing: Bool) {
        guard activeMenu == nil, let window = view.window else { return }
        // The navbar owns these actual groups, including its external button
        // layer. A demo-owned controller lets autoplay use normal dismissal.
        func groups(in view: UIView) -> [GlassControlGroup] {
            guard !view.isHidden, view.alpha > 0.01 else { return [] }
            let own = (view as? GlassControlGroup).map { [$0] } ?? []
            return own + view.subviews.flatMap { groups(in: $0) }
        }
        let candidates = groups(in: window).filter {
            let rect = $0.convert($0.bounds, to: window)
            return rect.height > 10 && rect.minY >= 0 && rect.midY < window.safeAreaInsets.top + 90
        }.sorted { $0.convert($0.bounds, to: window).midX < $1.convert($1.bounds, to: window).midX }
        guard let source = trailing ? candidates.last : candidates.first else { return }
        let menu = ContextMenuController(
            source: .init(view: source, cornerRadius: source.bounds.height / 2),
            items: trailing ? filterItems() : editItems(),
            hasHapticFeedback: false,
            onDismiss: { [weak self] in self?.activeMenu = nil }
        )
        activeMenu = menu
        menu.present()
    }

    private func editItems() -> [ContextMenuItem] {
        [
            action("select", "Выбрать сообщения", "checkmark.circle"),
            action("pins", "Изменить булавки", "pin"),
            action("identity", "Настроить имя и фото", "person.crop.circle")
        ]
    }

    private func filterItems() -> [ContextMenuItem] {
        [
            action("all", "Все сообщения", "tray", selected: true),
            .separator,
            action("known", "Известные отправители", "person.crop.circle"),
            action("unknown", "Неизвестные отправители", "person.crop.circle.badge.questionmark"),
            action("unread", "Непрочитанные", "bubble.left"),
            .separator,
            action("deleted", "Недавно удалённые", "trash"),
            action("manage", "Управлять фильтрами", "slider.horizontal.3")
        ]
    }

    private func action(_ id: String, _ title: String, _ symbol: String, selected: Bool = false) -> ContextMenuItem {
        .action(.init(id: id, title: title, icon: UIImage(systemName: symbol), iconSide: .leading, isSelected: selected, action: { _, handle in handle.dismiss() }))
    }

    private func schedule(after delay: TimeInterval, action: @escaping (TextureAnimationReferenceController) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            action(self)
        }
        scheduledSteps.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func addButton(_ title: String, id: String, action: @escaping () -> Void) {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = id
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        stack.addArrangedSubview(button)
    }

    private func addBackdrop() {
        let stories = UIStackView()
        stories.axis = .horizontal
        stories.distribution = .fillEqually
        stories.spacing = 16
        for (name, color) in [("Любимый пупс ❤️", UIColor.systemOrange), ("Мама", UIColor.systemGreen), ("Лёха", UIColor.systemBlue)] {
            let column = UIStackView()
            column.axis = .vertical
            column.alignment = .center
            column.spacing = 6
            let avatar = UIImageView(image: Self.avatar(color: color))
            avatar.widthAnchor.constraint(equalToConstant: 86).isActive = true
            avatar.heightAnchor.constraint(equalToConstant: 86).isActive = true
            column.addArrangedSubview(avatar)
            let label = ASTextNode()
            textNodes.append(label)
            label.attributedText = NSAttributedString(string: name, attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.secondaryLabel])
            label.view.heightAnchor.constraint(equalToConstant: 16).isActive = true
            label.view.widthAnchor.constraint(equalToConstant: 104).isActive = true
            column.addArrangedSubview(label.view)
            stories.addArrangedSubview(column)
        }
        stack.addArrangedSubview(stories)
        for (name, message) in [("RSCHS", "Заморозки в воздухе и на почве −0…−2°C"), ("YOTA", "Возможны ограничения подключения"), ("MegaFon", "Здравствуйте! Сообщение сохранено.")] {
            let label = ASTextNode()
            textNodes.append(label)
            label.attributedText = NSAttributedString(string: "\(name)\n\(message)", attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label])
            label.maximumNumberOfLines = 2
            label.view.heightAnchor.constraint(equalToConstant: 48).isActive = true
            stack.addArrangedSubview(label.view)
            let separator = UIView()
            separator.backgroundColor = .separator
            separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            stack.addArrangedSubview(separator)
        }
    }

    private static func avatar(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 86, height: 86))
        return renderer.image { context in
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 86, height: 86)).addClip()
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 86, height: 86))
            let image = UIImage(systemName: "person.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .medium))?.withTintColor(.white, renderingMode: .alwaysOriginal)
            image?.draw(in: CGRect(x: 18, y: 17, width: 50, height: 62))
        }.withRenderingMode(.alwaysOriginal)
    }
}

/// Uses the ordinary public titleView path so recordings exercise the same
/// persistent avatar plane as a real conversation header.
private final class TextureAnimationReferenceTitleView: UIView {
    private let avatarNode = ASImageNode()
    private let nameNode = ASTextNode()

    init(image: UIImage, name: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: 100, height: 58))
        isUserInteractionEnabled = false
        accessibilityIdentifier = "animation-reference.contact-title"
        accessibilityLabel = name
        avatarNode.image = image
        avatarNode.contentMode = .scaleAspectFit
        avatarNode.displaysAsynchronously = false
        addSubview(avatarNode.view)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        nameNode.attributedText = NSAttributedString(string: name, attributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ])
        nameNode.maximumNumberOfLines = 1
        nameNode.displaysAsynchronously = false
        addSubview(nameNode.view)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: 100, height: 58) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatarNode.frame = CGRect(x: (bounds.width - 38) / 2, y: 0, width: 38, height: 38)
        nameNode.frame = CGRect(x: 0, y: 41, width: bounds.width, height: 17)
        avatarNode.recursivelyEnsureDisplaySynchronously(true)
        nameNode.recursivelyEnsureDisplaySynchronously(true)
    }
}
