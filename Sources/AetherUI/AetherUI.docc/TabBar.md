# TabBar

Корневой плавающий tab bar со style-aware surface, опциональным search tab item,
bottomBarAccessory, минимизацией при скролле и Apple-Music-style
expanded accessory.

## Overview

``AetherTabBarController`` — root-контейнер приложения с плавающим
tab bar. В отличие от `UITabBarController`, не владеет nav bar'ом — каждая
вкладка содержит ``AetherNavigationController`` с собственным баром на
каждом экране (см. <doc:NavigationController>).

Основные возможности:

- ``TabBarView`` — плавающая style-aware surface с item'ами и badges;
  Liquid Glass добавляет edge-effect на скролле, Legacy — классический
  `systemChromeMaterial` и тонкий separator со стороны контента.
- ``SearchTabItem`` — последний слот общего expanded pill'а, который
  физически отделяется в самостоятельный search-круг при минимизации.
- ``AetherTabBarController/bottomBarAccessory`` — accessory-полоса над
  pill'ом (Now Playing pill и аналогичные сценарии).
- ``AetherTabBarController/tabBarMinimizeBehavior`` — авто-минимизация
  при скролле вниз (iOS 26 `tabBarMinimizeBehavior` API surface).
- ``AetherTabBarController/presentExpandedAccessory(_:animated:)`` —
  Apple-Music-style морф accessory pill'а в fullscreen-карточку.
- ``AetherTabBarController/tabContextMenuItemsProvider`` — context-menu
  на long-press tab item'а.

## Базовый шаблон

```swift
func makeRootController() -> AetherTabBarController {

    func makeTab(_ root: ViewController, item: UITabBarItem) -> AetherNavigationController {
        let nav = AetherNavigationController(mode: .single)
        nav.setViewControllers([root], animated: false)
        nav.tabBarItem = item
        return nav
    }

    let chats = makeTab(ChatsController(), item: UITabBarItem(
        title: "Чаты",
        image: UIImage(systemName: "message.fill"),
        tag: 0
    ))
    let settings = makeTab(SettingsController(), item: UITabBarItem(
        title: "Настройки",
        image: UIImage(systemName: "gearshape.fill"),
        tag: 1
    ))

    let tabs = AetherTabBarController()
    tabs.setControllers([chats, settings], selectedIndex: 0)
    return tabs
}
```

> Important: `AetherTabBarController` ожидает в качестве дочерних
> контроллеров ``AetherNavigationController`` или ``AetherViewController``,
> **не** `UINavigationController`. Использование стандартного
> `UINavigationController` нарушит layout dispatch.

## Управление контроллерами

```swift
tabs.setControllers([chats, settings, profile], selectedIndex: 0)
tabs.controllers              // [UIViewController]
tabs.currentController        // UIViewController?
tabs.selectedIndex = 1        // программное переключение
```

## Appearance

``AetherTabBarController`` не принимает theme-объекты. Базовый вид берётся
из app-level ``AppearanceStyle`` (см. <doc:Appearance>). Локальная настройка делается через
``AetherControllerAppearanceProviding`` на активном экране:

```swift
final class SettingsController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .tab else { return nil }
        return AetherAppearanceOverride(
            tabBar: AetherTabBarAppearanceOverride(
                selectedIconColor: .systemPink
            )
        )
    }
}
```

Если состояние override меняется во время жизни экрана, вызовите
``AetherTabBarController/invalidateAppearance()``. Текущее разрешённое
значение доступно read-only через ``AetherTabBarController/resolvedAppearance``.

### Bottom inset

`effectiveBottomInset` использует `theme.bottomInset` без дополнительного
fallback: floating pill держит фиксированный 21pt visual gap от нижней
границы экрана на всех устройствах.

### Ширина по количеству вкладок

В liquid-glass режиме pill использует контентную ширину, пока вкладок мало.
Четыре и более вкладки, а также конфигурация с Search, используют всю
доступную строку внутри 25pt боковых отступов. Для стандартной theme:

```swift
preferredPillWidth = theme.innerPadding * 2
    + theme.preferredItemWidth * tabCount             // default: 20 + 88 × count
pillWidth = tabCount >= 4 || hasSearch
    ? availableWidth
    : min(preferredPillWidth, theme.maximumRowWidth)
```

- Без Search pill центрируется: 2 вкладки занимают 196pt, 3 — 284pt,
  а 4–6 заполняют строку внутри 25pt margins.
- С Search используется одна full-width glass-поверхность. Search занимает
  последний равный слот внутри pill; отдельный Search-круг появляется только
  в minimized-состоянии.
- На узких экранах `sideInset` остаётся минимальным безопасным отступом,
  поэтому строка автоматически сжимается вместе с доступной шириной.

## Search tab item

Search-слот внутри общего pill'а, который отделяется в круг при минимизации
(Apple Music style):

```swift
let search = UIViewController()
search.tabBarItem = SearchTabItem(image: UIImage(systemName: "magnifyingglass")!)

tabs.setControllers([chats, settings, search], selectedIndex: 0)
```

При вызове ``AetherTabBarController/activateSearch()``:

- Tab bar pill сжимается в иконку активной вкладки.
- Search-кружок расширяется в горизонтальную glass-капсулу с встроенным
  `UITextField`.
- Поле не становится first responder автоматически; клавиатура появляется
  только после явного тапа в поле.
- Spring-анимация с glassmorphism scale-эффектами.

Деактивация — ``AetherTabBarController/deactivateSearch()``.

ViewController может реагировать на активацию через override:

```swift
override func tabBarActivateSearch() {
    // Подготовить search UI / результаты без принудительного focus.
}

override func tabBarDeactivateSearch() {
    searchController?.deactivate()
}
```

Подробнее — <doc:Search>.

## Bottom bar accessory

Accessory-полоса над tab bar pill'ом (Now Playing, Mini Player и
аналогичные сценарии):

```swift
class NowPlayingAccessory: TabBarAccessoryView {
    // Legacy presents this at no less than the 58pt classic mini-player row.

    override func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        // Раскладка subview-объектов в финальной области (size.width × size.height).
    }
}

let accessory = NowPlayingAccessory()
tabs.bottomBarAccessory = accessory                              // мгновенное присваивание
tabs.setBottomBarAccessory(accessory, animated: true)            // style-aware crossfade
```

Accessory:

- Оборачивается во внутренний `GlassBackgroundView`-wrapper.
- В Liquid Glass использует тот же material style, tint и light/dark
  resolution, что tab pill и Search; отличается только политика interaction.
- В Legacy получает rounded-rect surface высотой минимум 58pt: 16pt от краёв,
  без gap над tab bar и без обводки. Поверхность — полноценный
  `UIBlurEffect.Style.systemUltraThinMaterial` без полупрозрачного color wash.
  Локальная тень сделана контрастнее, но короче generic floating surface
  (opacity 0.26, radius 8pt, offset y=2pt).
- В Liquid Glass сохраняет floating gap 8pt и текущие layout metrics tab bar.
- Tab bar автоматически включает accessory в
  `additionalSafeAreaInsets.bottom` и childLayout.additionalInsets, что
  обеспечивает корректный отступ для scroll-контента.
- Blur tab bar расширяется вверх для покрытия accessory. В Legacy
  `NavigationBackgroundView` продолжает chrome material вверх с rounded-cutout,
  а wrapper accessory заполняет cutout собственным full-alpha
  `systemUltraThinMaterial`. В non-App-Store-safe сборке оба
  `UIVisualEffectView` получают общий backdrop grouping identifier по схеме
  LNPopupController; APPSTORE_SAFE оставляет только публичные UIKit effects.
  В Liquid Glass ту
  же область покрывает edge-effect frost.

### Динамическое изменение размера

```swift
class ExpandableAccessory: TabBarAccessoryView {
    var isExpanded = false

    override var nominalHeight: CGFloat {
        return isExpanded ? 96.0 : 56.0
    }

    func toggle() {
        isExpanded.toggle()
        invalidateLayout() // default: короткий spring из AetherMotion
    }
}
```

Default-профиль ``AetherMotion/bottomBarAccessoryResize`` даёт изменению
размера небольшой over/under settle. Явный `transition` по-прежнему можно
передать для синхронизации с собственной анимацией контента.

### Expanded accessory (Apple Music morph)

Accessory может быть преобразован в fullscreen-карточку (стиль Apple
Music «открытие плеера») через `expandedViewControllerProvider`:

```swift
class NowPlayingAccessory: TabBarAccessoryView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        expandedViewControllerProvider = {
            return FullscreenPlayerController()
        }
    }
}
```

При тапе на glass-поверхность accessory вызывается provider; если он
возвращает не-`nil` controller, выполняется морф accessory pill'а в
fullscreen-карточку:

- Wrapper'а grows от accessory pill до full screen bounds через spring
  (0.55с, damping 0.78 — небольшой overshoot).
- Controller'а view fade-in поверх старого accessory content.
- Tab bar fade-out (карточка скрывает chrome).
- CornerRadius wrapper'а animates от capsule (~24pt) до accessory's
  capsule shape.
- Drag-to-dismiss pan на wrapper'е (с координацией со scroll views
  внутри controller'а).

Программное закрытие:

```swift
tabs.dismissExpandedAccessory(animated: true)
```

Чтение состояния:

```swift
tabs.expandedAccessoryViewController    // UIViewController?
```

## Legacy geometry и scroll edge

Legacy использует классическую edge-attached раскладку:

- высота tab bar — 83 pt при наличии нижней safe-area и 49 pt без неё;
- каждый tab занимает 40 pt по высоте с отступом 7 pt от верхнего края;
- иконка закреплена у верхнего края tab, подпись — у нижнего;
- основной фон tab bar — `UIVisualEffectView` с
  `UIBlurEffect.Style.systemChromeMaterial`, без дополнительной цветной
  подложки или `UIGlassEffect`;
- separator — один physical-pixel с opacity 0.25, как hairline у Liquid
  Glass v2; при attached accessory он скрывается, чтобы не разрезать общий
  material швом;
- при установленном bottom accessory chrome effect продолжается вверх через
  58pt reservation: cosine fade идёт от прозрачности у верхней границы к
  полному blur у начала tab bar, обходя rounded cutout аксессуара. Сам cutout
  заполняет отдельный `systemUltraThinMaterial` с тем же backdrop group в
  non-App-Store-safe сборке.

Фон и separator управляются фактической позицией scroll view. Для длинного
контента они исчезают только на крайнем нижнем `contentOffset` и возвращаются,
как только offset уходит вверх от конца. Если контент помещается в viewport
без tab bar, chrome остаётся прозрачным; показать его может только выраженный
pull-down overscroll от верхней границы (48 pt, с hysteresis до 24 pt), поэтому
обычный bounce не вызывает мерцание.

## Минимизация (`tabBarMinimizeBehavior`)

iOS 26-style auto-минимизация tab bar при скролле:

```swift
tabs.tabBarMinimizeBehavior = .onScrollDown   // или .never (default)
```

При `.onScrollDown`:

- Скролл вниз (от верха) → tab bar коллапсируется: pill сжимается в
  48×48 active-tab кружок на leading edge, search tab item — в matching
  кружок на trailing edge. Круги стоят на 28pt от краёв, а
  `bottomBarAccessory` reflows между ними с 13pt gaps.
- Скролл вверх (или достижение верха) → tab bar расширяется обратно.

Legacy всегда остаётся развёрнутым: `.onScrollDown` и прямой вызов
`setTabBarMinimized(true, ...)` не включают minimizer, а live-переход из
Liquid Glass в Legacy немедленно восстанавливает полный bar без glass-morph.

Программное управление:

```swift
let morph = AetherMotion.tabBarMorph
tabs.setTabBarMinimized(true, transition: .animated(
    duration: morph.duration,
    curve: .customSpring(
        damping: morph.dampingRatio,
        initialVelocity: morph.initialVelocity
    )
))

tabs.isTabBarMinimized   // read-only состояние
```

Один spring-clock меняет pill, Search и установленный accessory, давая
небольшой геометрический over/undershoot без дополнительного scale-transform.
Accessory использует одну непрерывно сэмплируемую кривую без waypoint и без
второго animator'а. При сворачивании ширина освобождает ряд раньше спуска, а
при раскрытии подъём освобождает ряд раньше расширения; медленная ось всё это
время продолжает двигаться, поэтому задержка читается как изгиб единой
траектории, а не как две склеенные фазы. Search меняет glyph-owner в общей
стартовой геометрии и затем движется одним представлением: видимая glass-
поверхность отделяется от pill'а, а не появляется вокруг прозрачной иконки.

### Наблюдение за progress и геометрией

Для синхронных манипуляций с соседним UI назначьте weak delegate:

```swift
final class PlayerChromeDriver: AetherTabBarControllerMinimizationDelegate {
    func tabBarController(
        _ controller: AetherTabBarController,
        didUpdateMinimizationProgress progress: CGFloat,
        bottomBarAccessoryFrame frame: CGRect?
    ) {
        artwork.transform = CGAffineTransform(
            scaleX: 1.0 - 0.06 * progress,
            y: 1.0 - 0.06 * progress
        )
        floatingOverlay.frame.origin.y = (frame?.minY ?? 0.0) - 12.0
    }
}

// Keep a strong reference to the driver; the controller holds it weakly.
private let playerChromeDriver = PlayerChromeDriver()
tabs.minimizationDelegate = playerChromeDriver
```

``AetherTabBarController/tabBarMinimizationProgress`` всегда лежит в
`0...1` (`0` — expanded, `1` — minimized). При назначении delegate сразу
приходит initial snapshot; затем callback вызывается на main thread для
каждого изменившегося display-link sample и в точных endpoints.
`bottomBarAccessoryFrame` относится к
тому же отрисованному кадру и задан в координатах `controller.view`; при
UIKit-driven resize используется presentation geometry. Контракт относится
к compact/minimization chrome. Установка, удаление, intrinsic resize,
rotation и изменение размеров контейнера также публикуют новую геометрию,
даже если сам progress не изменился. Пока reusable surface находится в
fullscreen-переходе, compact frame равен `nil`; его live-геометрия приходит
через
`BottomBarAccessoryTransitionParticipant`. При animated removal `nil`
публикуется в момент освобождения public accessory slot; короткий outgoing
fade уже не считается его активной геометрией.

> Note: При открытии search tab bar принудительно переходит в minimized
> active-tab состояние, даже если auto-minimize выключен. После закрытия
> search восстанавливается состояние, которое было до активации. Это
> Liquid Glass-механика; в Legacy minimizer остаётся выключенным.

## Управление видимостью tab bar

Pushed-экран может скрыть tab bar для fullscreen-layout'а:

```swift
override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    aetherTabBarController?.updateIsTabBarHidden(true, transition: .animated(
        duration: 0.3, curve: .easeInOut
    ))
}

override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    aetherTabBarController?.updateIsTabBarHidden(false, transition: .animated(
        duration: 0.3, curve: .easeInOut
    ))
}
```

## Context menu на tab item

Long-press по tab item'у активирует ``ContextMenuController``,
если задан provider:

```swift
tabs.tabContextMenuItemsProvider = { tabIndex in
    switch tabIndex {
    case 0:  // Чаты
        return [
            ContextMenuItem.action(.init(text: "Новый чат",
                                         icon: UIImage(systemName: "square.and.pencil"),
                                         action: { /* ... */ })),
            ContextMenuItem.action(.init(text: "Новая группа",
                                         icon: UIImage(systemName: "person.2"),
                                         action: { /* ... */ }))
        ]
    default:
        return []  // подавление меню для других вкладок
    }
}
```

Альтернативно — override `contextMenuItems(forTabAt:)` в подклассе
`AetherTabBarController`.

ViewController также может реагировать на long-press через
``AetherViewController/tabBarItemContextActionType`` и
``AetherViewController/tabBarItemContextAction(sourceView:gesture:)``.

## Чтение pill / chrome geometry

Для размещения внешнего layout (floating toolbar, toast'ов):

```swift
tabs.pillFrame(in: someView)     // CGRect — frame pill'а в координатах someView
tabs.chromeTopY(in: someView)    // CGFloat? — верхняя Y-координата всего chrome (pill + accessory)
```

`chromeTopY` учитывает `bottomBarAccessory` (если есть) — это полная
верхняя граница visible chrome. ``AetherViewController/floatingToolbar``
автоматически использует её для anchor'инга.

## Public API сводка

### ``AetherTabBarController``

| Свойство / метод | Назначение |
|---|---|
| `init()` | Создание с app-level appearance. |
| `init(tabBarTheme:)` | Deprecated source-compatible adapter старой полной темы. |
| `tabBarTheme` | Deprecated get/set adapter; сохраняется как container override ниже active-screen provider. |
| `controllers` | Массив дочерних контроллеров. |
| `currentController` | Контроллер активной вкладки. |
| `selectedIndex` | Индекс активной вкладки (read-write). |
| `setControllers(_:selectedIndex:)` | Установка контроллеров и активной вкладки. |
| `resolvedAppearance` | Текущий resolved appearance tab bar (read-only). |
| `invalidateAppearance()` | Повторно применить app appearance и override активного экрана. |
| `tabContextMenuItemsProvider` | Provider для long-press context menu. |
| `bottomBarAccessory` | Accessory над pill'ом. |
| `setBottomBarAccessory(_:animated:)` | Установка с crossfade. |
| `expandedAccessoryViewController` | Текущий expanded controller. |
| `presentExpandedAccessory(_:animated:)` | Морф accessory → fullscreen. |
| `dismissExpandedAccessory(animated:)` | Реверс морфа. |
| `tabBarMinimizeBehavior` | Авто-минимизация при скролле. |
| `isTabBarMinimized` | Текущее состояние минимизации. |
| `tabBarMinimizationProgress` | Live progress `0...1` текущего compact morph'а. |
| `minimizationDelegate` | Weak per-frame observer progress + accessory frame. |
| `bottomBarAccessoryFrame` | Текущий rendered frame compact accessory в координатах root view. |
| `setTabBarMinimized(_:transition:)` | Программное переключение минимизации. |
| `updateIsTabBarHidden(_:transition:)` | Скрытие/показ tab bar. |
| `activateSearch()` / `deactivateSearch()` | Управление search-режимом. |
| `pillFrame(in:)` | Frame pill'а в координатах view. |
| `chromeTopY(in:)` | Верхняя Y-координата chrome. |

### ``TabBarView``

| Свойство / метод | Назначение |
|---|---|
| `init(theme:)` | Создание view. |
| `selectedIndex` | Индекс активной вкладки. |
| `isMinimized` | Read-only состояние минимизации. |
| `setMinimized(_:transition:)` | Программная минимизация. |
| `bottomAccessoryReservedHeight` | Высота, которую edge-effect должен покрыть выше bar. |
| `updateTheme(_:)` | Динамическая смена темы. |

### ``TabBarAccessoryView``

| Свойство / метод | Назначение |
|---|---|
| `nominalHeight` | Естественная высота. Override в подклассе. |
| `height` | Текущая высота для layout (default = nominalHeight). |
| `updateLayout(size:transition:)` | Раскладка subview-объектов. |
| `requestLayout` | Closure для запроса re-layout (framework-level). |
| `expandedViewControllerProvider` | Provider для Apple-Music-морфа. |
| `invalidateLayout(transition:)` | Запрос re-layout после изменения размера. |

## Edge cases

- **Дочерние контроллеры — только `AetherNavigationController` или
  `ViewController`.** Использование `UINavigationController` нарушит
  layout dispatch (нет `containerLayoutUpdated` в стандартном API).
- **Минимизация + search mode.** Search использует minimized active-tab
  circle как постоянный anchor, а search-кнопка разворачивается в поле.
  Раскрывать tab bar обратно во время активного search нельзя; состояние
  восстанавливается через ``AetherTabBarController/deactivateSearch()``.
- **Expanded accessory + scroll observer.** При presentExpandedAccessory
  scroll observer автоматически отсоединяется (иначе случайный scroll
  tick во время morph'а вызовет race condition с минимизацией). Observer
  переподключается при dismiss.
- **`bottomBarAccessory` z-order.** В collapsed state wrapper accessory
  находится выше tab bar. В Liquid это сохраняет native glass surface над
  edge-effect frost; в Legacy wrapper содержит content, ultra-thin material и
  shadow над rounded cutout в `NavigationBackgroundView`.
  После dismiss expanded accessory выполняется re-layout для восстановления
  корректного z-order.
- **Bottom inset.** `effectiveBottomInset` использует `theme.bottomInset`
  напрямую, поэтому floating pill сохраняет одинаковый 21pt visual gap от
  нижней границы экрана.

## See Also

- <doc:ViewController>
- <doc:NavigationController>
- <doc:Search>
- <doc:Glass>
- <doc:EdgeEffect>
- <doc:ContextMenu>
