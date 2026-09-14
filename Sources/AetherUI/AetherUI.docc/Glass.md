# Glass

Низкоуровневые glass-примитивы AetherUI: фон, кнопки, control group,
liquid lens. Базовые компоненты, на основе которых построены nav bar,
tab bar, modal, context menu, toolbar.

## Overview

Семейство surface-классов использует единый ``AetherAppearanceStyle``. Явно
выбранный Legacy создаёт классический public-UIKit renderer на
`UIBlurEffect.Style.systemChromeMaterial`; Liquid Glass v1/v2 используют
`UIGlassEffect` на поддерживаемой системе и compatibility renderer на более
ранних версиях iOS:

- ``GlassBackgroundView`` — основной строительный блок: glass-surface
  с настраиваемой формой, tint'ом, blur'ом, корнерами.
- ``GlassBackgroundContainerView`` — контейнер для нескольких
  ``GlassBackgroundView``, использующий `UIGlassContainerEffect` для
  объединения соседних glass-поверхностей.
- ``GlassButton`` — самостоятельная glass-кнопка с title, image, loading,
  disabled-состояниями.
- ``GlassButtonView`` — упрощённый glass-control с фиксированным размером.
- ``GlassBarButtonView`` — glass-кнопка для использования в bar button
  context'е.
- ``GlassControlGroup`` — горизонтальный layout нескольких glass-кнопок
  в едином capsule с морфом при изменении состава.
- ``GlassControlPanel`` — расширенный glass-controller с группами
  segments.
- ``LiquidLensView`` — liquid lens-эффект для индикатора выбранного
  элемента (используется в TabBar).
- ``AetherGlassConfig`` — глобальная конфигурация glass-системы.

`appearanceStyle: nil` следует application runtime и обновляется live. Явное
значение закрепляет renderer конкретного компонента и имеет приоритет над
глобальным style. Legacy не является availability fallback и никогда не
создаёт `UIGlassEffect`, private backdrop/filter или Liquid Glass lens.

## GlassBackgroundView

Основной glass-компонент. Используется как основа для всех остальных
glass-классов и для прямой композиции custom UI:

```swift
let glass = GlassBackgroundView(style: .regular, appearanceStyle: .legacy)
glass.frame = CGRect(x: 16, y: 100, width: 200, height: 60)
view.addSubview(glass)

glass.update(
    size: glass.bounds.size,
    cornerRadius: 30,
    isDark: traitCollection.userInterfaceStyle == .dark,
    tintColor: .init(kind: .panel),
    isInteractive: true,
    isVisible: true,
    transition: .immediate
)

// Контент, к которому применяется glass-deformation:
let label = UILabel()
label.text = "Glass"
glass.contentView.addSubview(label)
```

### Style

| Стиль | Описание |
|---|---|
| `.regular` | Обычный glass со стандартным tint. |
| `.clear` | Прозрачный glass без panel tint (только refraction). |
| `.prominent` | Усиленный glass для повышения контраста (используется в context menu). |

### TintColor

| Kind | Назначение |
|---|---|
| `.panel` | Стандартный panel tint (соответствует UIKit `.regular` material). |
| `.clear` | Без tint, только refraction. |
| `.tinted(UIColor)` | Кастомный цвет tint (пример: `.tinted(.systemBlue.withAlphaComponent(0.3))`). |

### Shape

| Shape | Описание |
|---|---|
| `.rectangle` | Прямоугольник с настраиваемым corner radius. |
| `.capsule` | Capsule (скругление = height/2). |

### Свойства

| Свойство | Тип | Назначение |
|---|---|---|
| `contentView` | `UIView` | Контейнер для пользовательского контента; применяется glass-deformation. |
| `maskContentView` | `UIView` | Контейнер для контента, маскированного по форме glass'а. |
| `appearanceStyleOverride` | ``AetherAppearanceStyle``? | `nil` следует runtime; explicit value закрепляет renderer. |
| `surfaceRole` | ``AetherSurfaceRole`` | Semantic role для Legacy fill, border и shadow. |
| `tracksTraitCollection` | `Bool` | Автоматическое обновление dark/light при смене traitCollection. |
| `isDarkOverride` | `Bool?` | Принудительное dark/light (override traitCollection). |
| `glassCornerRadius` | `CGFloat?` | Текущий corner radius. |
| `glassTintColor` | `TintColor` | Текущий tint. |
| `glassIsInteractive` | `Bool` | Включение iOS 26 `UIGlassEffect.isInteractive` warp. |
| `glassParams` | `GlassParams?` | Read-only параметры glass-эффекта. |

### Метод update

```swift
public func update(
    size: CGSize,
    cornerRadius: CGFloat,
    isDark: Bool,
    tintColor: TintColor,
    isInteractive: Bool,
    isVisible: Bool,
    transition: ContainedViewLayoutTransition
)
```

Главный метод обновления glass-параметров. Принимает все ключевые
характеристики и `transition` для анимированного перехода.

Упрощённая версия:

```swift
public func update(
    size: CGSize,
    cornerRadius: CGFloat,
    transition: ContainedViewLayoutTransition
)
```

### setNativeCornerConfiguration (iOS 18+)

```swift
glass.setNativeCornerConfiguration(.uniform(radius: 24))
```

Использует UIKit'овский `UICornerConfiguration` для тонкого контроля
corner shape (continuous, mixed radii). Доступен на iOS 18+.

### useCustomGlassImpl

```swift
GlassBackgroundView.useCustomGlassImpl = true
```

Принудительное использование fallback-реализации (CALayer + filters)
вместо `UIGlassEffect`. По умолчанию — `false` на iOS 26+ (используется
системная реализация).

## GlassBackgroundContainerView

Контейнер для нескольких ``GlassBackgroundView``, объединяющий их через
`UIGlassContainerEffect` (iOS 26+):

```swift
let container = GlassBackgroundContainerView(spacing: 7.0)
container.contentView.addSubview(glass1)
container.contentView.addSubview(glass2)

container.update(
    size: container.bounds.size,
    isDark: false,
    transition: .immediate
)
```

Initializer также принимает `appearanceStyle:`. В Legacy контейнер сохраняет
тот же публичный `contentView`, но не создаёт `UIGlassContainerEffect`.

При сближении соседних glass-поверхностей (на расстояние ≤ `spacing`)
они визуально merge в единую поверхность через системный
`UIGlassContainerEffect`. На iOS < 26 эффект отсутствует, но layout
сохраняется.

Используется в ``TabBarView`` для merge между pill'ом и search-кружком.

## GlassButton

Самостоятельная glass-кнопка с поддержкой title, image, loading,
disabled:

```swift
let button = GlassButton(title: "Подтвердить", image: UIImage(systemName: "checkmark"))
button.contentColor = .label
button.tint = .init(kind: .panel)
button.cornerRadius = nil   // nil → capsule
button.action = { btn in
    print("Tapped")
}
view.addSubview(button)
```

### Свойства

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `title` | `String?` | `nil` | Текст. |
| `image` | `UIImage?` | `nil` | Иконка. |
| `action` | `((GlassButton) -> Void)?` | `nil` | Tap-callback. |
| `appearanceStyleOverride` | ``AetherAppearanceStyle``? | `nil` | Per-button override; выше application runtime. |
| `tint` | `TintColor` | `.init(kind: .panel)` | Glass tint. |
| `contentColor` | `UIColor` | `.label` | Цвет title и tint иконки. |
| `cornerRadius` | `CGFloat?` | `nil` | `nil` — capsule, число — заданный radius. |
| `contentPadding` | `CGFloat` | `14` | Padding внутри кнопки. |
| `iconTitleSpacing` | `CGFloat` | `8` | Gap между иконкой и текстом. |
| `minimumSize` | `CGSize` | `(36, 36)` | Минимальный размер. |
| `isDarkAppearance` | `Bool?` | `nil` | Override dark/light. |
| `isEnabled` | `Bool` | `true` | Включение взаимодействия. |
| `isLoading` | `Bool` | `false` | Показ loading-индикатора (заменяет title/image). |

### Программное обновление

```swift
button.update(
    title: "Готово",
    image: UIImage(systemName: "checkmark.circle"),
    contentColor: .systemGreen,
    transition: .animated(duration: 0.3, curve: .easeInOut)
)
```

## GlassBarButtonView

Упрощённая glass-кнопка для bar button context'а:

```swift
let button = GlassBarButtonView(
    icon: UIImage(systemName: "ellipsis"),
    title: nil,
    state: .glass,
    appearanceStyle: .legacy
)
button.contentTintColor = .label
button.action = { sourceView in
    print("Tapped")
}
```

### DisplayState

| State | Описание |
|---|---|
| `.glass` | Полноценный glass-эффект (по умолчанию для nav bar). |
| `.transparent` | Прозрачный фон (для секций без glass). |

### Context menu integration

Свойство ``GlassBarButtonView/contextMenuItemsProvider`` позволяет
установить provider для ``ContextMenuController``:

```swift
button.contextMenuItemsProvider = {
    return [
        ContextMenuItem.action(.init(title: "Поделиться", action: { _, dismiss in dismiss.dismiss() })),
        ContextMenuItem.action(.init(title: "Удалить", textColor: .destructive, action: { _, dismiss in dismiss.dismiss() }))
    ]
}
button.contextMenuTrigger = .longPress     // или .tap
// Для lifted preview при необходимости:
// button.contextMenuPreview = .init(verticalSpacing: 8, lift: 1.04)
```

## GlassControlGroup

Горизонтальный layout нескольких glass-кнопок в едином capsule с
автоматическим морфом при изменении состава:

```swift
let group = GlassControlGroup(appearanceStyle: .legacy)
view.addSubview(group)

let items: [GlassControlGroup.Item] = [
    .init(id: "share" as AnyHashable,
          content: .icon(UIImage(systemName: "square.and.arrow.up")!),
          action: { print("Share") }),
    .init(id: "delete" as AnyHashable,
          content: .icon(UIImage(systemName: "trash")!),
          action: { print("Delete") })
]

let size = group.update(
    items: items,
    background: .panel,
    preferClearGlass: false,
    foregroundColor: .label,
    isDark: false,
    availableHeight: 44,
    minWidth: 44,
    transition: .immediate
)
group.frame = CGRect(origin: .zero, size: size)
```

### Item.Content

| Content | Описание |
|---|---|
| `.icon(UIImage)` | Иконка. |
| `.text(String)` | Текст. |
| `.customView(UIView)` | Произвольный view. |

### Background

| Background | Описание |
|---|---|
| `.panel` | Стандартный panel tint. |
| `.tinted(UIColor)` | Кастомный tint. |
| `.clear` | Без tint. |

### Морф при изменении

При вызове `update(items:...)` с изменённым составом:
- Удалённые items fade out.
- Добавленные items fade in.
- Перемещённые items animate position.
- Glass surface деформируется, отслеживая новые границы группы.

Длительность fade'а — 0.2с.

### Доступ к item view

```swift
let view = group.itemView(id: "share" as AnyHashable)        // UIView?
let button = group.itemButton(id: "share" as AnyHashable)    // UIControl?
```

Используется для определения source view при отображении context menu
анкорно к кнопке.

## GlassControlPanel

Расширенный glass-controller с группами segments. Подробности — в
исходнике (`GlassControlGroup.swift`).

## LiquidLensView

Liquid lens-эффект для индикатора выбранного элемента (используется в
``TabBarView`` для подсветки активной вкладки):

```swift
let lens = LiquidLensView(kind: .externalContainer, appearanceStyle: .legacy)
view.addSubview(lens)

// Контент: обычные item-views внутри lens.contentView,
// "выбранные" версии внутри lens.selectedContentView.
lens.contentView.addSubview(itemView1)
lens.contentView.addSubview(itemView2)
lens.selectedContentView.addSubview(selectedItemView1)
lens.selectedContentView.addSubview(selectedItemView2)

// Установка позиции и размера выбранного элемента:
lens.selectionOrigin = CGPoint(x: 100, y: 0)
lens.selectionSize = CGSize(width: 80, height: 44)

// Анимированное обновление:
lens.update(
    size: lens.bounds.size,
    selectionOrigin: CGPoint(x: 200, y: 0),
    selectionSize: CGSize(width: 80, height: 44),
    transition: .animated(duration: 0.4, curve: .spring)
)
```

### Kind

| Kind | Описание |
|---|---|
| `.standalone` | Lens рендерит собственный glass-фон. |
| `.externalContainer` | Lens встроен в внешний glass-контейнер (используется в TabBar). |

### Свойства

| Свойство | Тип | Назначение |
|---|---|---|
| `contentView` | `UIView` | Контент в неактивном состоянии. |
| `selectedContentView` | `UIView` | Контент в активном состоянии (виден через lens). |
| `selectionOrigin` | `CGPoint?` | Позиция «вырезаемой» области. |
| `selectionSize` | `CGSize?` | Размер «вырезаемой» области. |
| `isAnimating` | `Bool` | Read-only состояние анимации. |
| `onUpdatedIsAnimating` | `((Bool) -> Void)?` | Callback на изменение animating-состояния. |
| `isDarkAppearance` | `Bool?` | Override dark/light. |
| `appearanceStyleOverride` | ``AetherAppearanceStyle``? | `nil` следует runtime; Legacy использует classic selection renderer. |

### TransitionInfo

Дополнительные параметры для анимированного перехода (lift effect и
аналогичные эффекты). См. исходник `LiquidLensView.swift`.

## AetherGlassConfig

Глобальная конфигурация glass-системы:

```swift
// Изменение глобальных параметров:
AetherGlassConfig.current = AetherGlassConfig(
    style: .regular,                    // дефолтный стиль
    legacyBlurBackend: .systemMaterial  // backend для iOS < 26
)
```

### Свойства

| Свойство | Тип | Назначение |
|---|---|---|
| `style` | `SystemGlassEffectStyle` | Дефолтный стиль glass. |
| `legacyBlurBackend` | `LegacyBlurBackend` | Backend для iOS < 26. |

### LegacyBlurBackend

| Backend | Описание |
|---|---|
| `.systemMaterial` | `UIBlurEffect(style: .systemMaterial)` |
| `.regular` | `UIBlurEffect(style: .regular)` |
| `.prominent` | `UIBlurEffect(style: .prominent)` |
| `.custom(UIBlurEffect)` | Произвольный blur effect. |

## UIView+CornerConfiguration (iOS 18+)

Хелпер для применения `UICornerConfiguration` к произвольному `UIView`:

```swift
view.applyCornerConfiguration(.uniform(radius: 24))
```

На iOS < 18 — no-op. Использует системный `UIView.cornerConfiguration` API
для тонкого контроля corner curves.

## API сводка

См. таблицы выше для детального API каждого компонента.

## Edge cases

- **Glass не отображается на iOS < 26.** Проверьте
  ``GlassBackgroundView/useCustomGlassImpl``: если `true`, используется
  CALayer-fallback, который требует non-zero `cornerRadius` и `size`.
  При `cornerRadius = 0` glass рендерится как обычный непрозрачный
  background.
- **Hit testing на glass surface.** ``GlassBackgroundView/hitTest(_:with:)``
  forward'ит в `contentContainer.hitTest`, который возвращает `nil`,
  если на контейнере нет ни одного gesture recognizer'а, и ни один
  subview не принимает touch. Это намеренное поведение для
  «проходимых» glass-поверхностей. Для активации tap'а на pill'е
  добавляйте gesture recognizer на `contentView`, не на сам pill.
- **iOS 26 `UIGlassEffect.isInteractive` warp.** Для активации finger
  warp'а требуется `isUserInteractionEnabled = true` на самом
  ``GlassBackgroundView`` (не только на subviews). Без этого warp не
  получает hit-test events.
- **Double-glass artefact.** Размещение `GlassBarButtonView` внутри
  `GlassControlGroup` приводит к double-glass artefact'у: внутренний
  iOS 26 monochromatic treatment иконки инвертируется относительно
  внешнего capsule'а. ``NavigationBarImpl`` обходит это через прямое
  размещение customView в container'е (без обёртки в group), когда все
  bar items имеют `customView` и нет авто-back-кнопки.
- **`tracksTraitCollection = false`.** Если используется
  ``GlassBackgroundView/isDarkOverride``, обычно требуется выключить
  автоматическое отслеживание traitCollection — иначе override'ы будут
  перезаписываться при смене dark/light system mode.

## See Also

- <doc:NavigationBar>
- <doc:TabBar>
- <doc:EdgeEffect>
- <doc:ContextMenu>
- <doc:Toolbar>
