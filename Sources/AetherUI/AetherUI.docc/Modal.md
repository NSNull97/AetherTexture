# Modal

Двухдетентный glass-sheet с поддержкой sticky-footer, scroll
arbitration, keyboard handling, embedded navigation stack.

## Overview

``AetherModalController`` — модальный sheet, презентуемый через
стандартный UIKit `present(_:animated:)`:

- Два detent'а: `.stage1` (компактный с боковыми insets, glass виден
  с обеих сторон) и `.stage2` (full-width, edge-to-edge tint).
- Верхние углы 34pt по умолчанию; нижние задаются для каждого detent.
  В `.stage2` без нижнего отступа они по умолчанию прямые.
- Cooperation с inner scroll view (gesture arbitration: drag по scroll
  content переключает control между sheet drag и scroll).
- Sticky footer с автоматическим edge-effect frost'ом.
- Keyboard handling: автоматический подъём footer'а над клавиатурой;
  `primaryScrollView.contentInset.bottom` обновляется на keyboard
  overlap.
- Custom transition animations: source-to-modal morph из кнопки
  или полностью свой `UIViewControllerAnimatedTransitioning`.
- ``AetherModalNavigationController`` — wrapper с встроенным
  ``AetherNavigationController`` для модалок со стеком.
- ``AetherThemePickerModalController`` — нижняя модальная карточка для
  анимированного переключателя темы с высотой по содержимому.

## Базовый шаблон

```swift
let content = MyContentController()

let modal = AetherModalController()
modal.embedContent(content)
modal.primaryScrollView = content.scrollView   // (опц.) кооперация со scroll
present(modal, animated: true)

// Программное переключение detent'а:
modal.setDetent(.stage2, animated: true)

// Закрытие через стандартный UIKit:
dismiss(animated: true)
```

## Detents

```swift
public enum Detent: Hashable {
    case stage1   // компактный
    case stage2   // full-height
}
```

При drag'е sheet snap'ится к ближайшему допустимому detent'у. По
умолчанию доступны оба:

```swift
let config = AetherModalController.Config(
    detents: [.stage1, .stage2],
    initialDetent: .stage1
)
```

### Single-detent mode

```swift
// Только stage2: движение вниз может закрыть sheet;
// промежуточного компактного положения нет.
let config = AetherModalController.Config(
    detents: [.stage2]
)
```

## Config

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `sideInset` | `CGFloat` | `8.0` | Боковой inset sheet'а в `.stage1`; при `sizesToContent` — в обоих detent'ах. |
| `bottomInsetStage1` | `CGFloat` | `8.0` | Расстояние от bottom edge до screen bottom в `.stage1`. |
| `bottomInsetStage2` | `CGFloat` | `0.0` | То же в `.stage2` (sheet flush с bottom). |
| `topInsetStage1` | `CGFloat` | `-1` (automatic) | Расстояние от safe-area top; отрицательное значение пересчитывается как половина текущего контейнера. |
| `topInsetStage2` | `CGFloat` | `10.0` | То же в `.stage2`. |
| `topCornerRadius` | `CGFloat` | `34.0` | Top corner radius. |
| `bottomCornerRadiusStage1` | `CGFloat?` | `nil` | Нижний радиус compact sheet. `nil` → `topCornerRadius`. |
| `bottomCornerRadiusStage2` | `CGFloat?` | `nil` | Нижний радиус expanded sheet. `nil` → `0` при `bottomInsetStage2 == 0`, иначе `topCornerRadius`. |
| `bottomCornersFollowContainer` | `Bool` | `false` | На iOS 26+ нижние углы концентричны контейнеру с учётом отступов. Заданные радиусы — минимальные; на более ранних системах используются как фиксированные. |
| `dimAlphaStage1` | `CGFloat` | `0.25` | Dim alpha над presenter в `.stage1`. |
| `dimAlphaStage2` | `CGFloat` | `0.4` | То же в `.stage2`. |
| `dimTintColor` | `UIColor` | `.systemBackground` | Tint поверхности sheet и фон встроенной навигации. |
| `detents` | `Set<Detent>` | `[.stage1, .stage2]` | Допустимые detent'ы. |
| `initialDetent` | `Detent?` | `nil` | Detent при открытии. `nil` → первый из allowed. |
| `fixedSize` | `CGSize?` | `nil` | Центрированная intrinsic-sized поверхность вместо геометрии detent'ов. |
| `sizesToContent` | `Bool` | `false` | Нижняя шторка с высотой из `contentHeight(forWidth:safeAreaInsets:)`, с учётом бокового и нижнего inset. Приоритетнее `fixedSize`. |
| `showsGrabber` | `Bool` | `true` | Показывать верхний grabber sheet'а. |

```swift
let config = AetherModalController.Config(
    sideInset: 16,
    topInsetStage1: 200,
    topCornerRadius: 24,
    dimAlphaStage2: 0.5,
    detents: [.stage2],
    initialDetent: .stage2
)
let modal = AetherModalController(config: config)
```

### Theme picker bottom sheet

``AetherThemePickerModalController`` открывается снизу с внешними отступами
8 pt слева, справа и снизу. Верхние углы имеют радиус 26 pt, нижние на iOS 26+
подстраиваются под скругление окна и отступ карточки. На более ранних
системах используется радиус 26 pt. Высота точно
рассчитывается по сцене, переключателю и подписи при текущей доступной
ширине. Под подписью остаётся 12 pt плюс та часть нижней safe area, которая
перекрывает карточку: при safe area 34 pt и внешнем отступе 8 pt это 26 pt.

```swift
let modal = AetherThemePickerModalController(theme: .system)
modal.themeChanged = { [weak window] theme in
    switch theme {
    case .light: window?.overrideUserInterfaceStyle = .light
    case .dark: window?.overrideUserInterfaceStyle = .dark
    case .system: window?.overrideUserInterfaceStyle = .unspecified
    }
}
modal.present(from: hostViewController)
```

При повороте и изменении размера окна модалка заново измеряет picker.
Grabber скрыт, дополнительного пустого блока под подписью нет.
Параметры `themeChanged`, `dismissAfterSelection` и `appearanceStyle`
доступны на controller'е.
Днём облако плавно дрейфует по замкнутой траектории, ночью иногда пролетают
падающие звёзды. Фоновое движение останавливается при закрытии карточки,
уходе приложения в фон и включённом Reduce Motion.

Для собственного контента включите `Config.sizesToContent` и переопределите
`contentHeight(forWidth:safeAreaInsets:)`, вернув полную высоту с учётом
нижней safe area и grabber, если он включён. Метод получает ширину за вычетом
`sideInset`, а нижняя safe area уже уменьшена на `bottomInsetStage1` или
`bottomInsetStage2`: повторно вычитать отступ не нужно. Ширину экрана через
`UIScreen.main` определять не требуется. Для поверхности на всю ширину до
самого нижнего края задайте `sideInset: 0`, оба нижних inset по 0 и оба
нижних corner radius по 0.

### Intrinsic-sized card

Для центрированной карточки остаётся `Config.fixedSize`. Такой режим
ограничивает размер доступной safe area и сохраняет прежнее поведение:

```swift
let modal = AetherModalController(
    config: .init(fixedSize: CGSize(width: 320, height: 278), showsGrabber: false)
)
```

## Embed content

### Через child controller

```swift
let content = ContentController()
modal.embedContent(content)
```

`embedContent` выполняет:

- `addChild(content)`
- Добавление `content.view` в `modal.contentView`
- `didMove(toParent: modal)`

### Через прямую subview

```swift
let label = UILabel()
modal.contentView.addSubview(label)
// Раскладка label в layoutSubviews подкласса modal'а
```

> Important: `contentView` соответствует текущим видимым bounds шторки.
> При смене detent контент получает новый layout. Используйте актуальные
> bounds, safe area и `ContainerViewLayout`, а не постоянный размер stage2.
> Общий материал расположен позади контента отдельным sibling; modal не
> масштабирует и не растеризует дерево страниц во время drag.

## Sticky footer

```swift
let sendButton = UIButton(type: .system)
sendButton.setTitle("Отправить", for: .normal)
modal.footerView = sendButton
modal.footerHeight = 56            // обязательно — auto-layout-only footer'ы вернут 0
```

Footer:

- Закреплён к bottom modal'а; следует за sheet через detent'ы.
- Над footer'ом рендерится edge-effect frost (`footerEdgeFadeHeight = 28pt`
  по умолчанию).
- `footerHeight` добавляется в `additionalSafeAreaInsets.bottom`
  content area у базового modal и ручного режима навигации. В автоматическом
  режиме навигации каждая страница получает собственный footer inset.

### Кастомизация frost'а

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `footerEdgeFadeHeight` | `CGFloat` | `28.0` | Высота gradient fade зоны. |
| `footerEdgeTintColor` | `UIColor?` | `nil` | Tint frost'а (nil → `config.dimTintColor` × 0.86 alpha). |
| `footerEdgeBlurRadius` | `CGFloat` | `2.0` | Blur radius. |

## Scroll arbitration

```swift
modal.primaryScrollView = content.tableView
```

При установке `primaryScrollView`:

1. **Gesture arbitration**: жест согласуется с положением scroll и
   допустимыми detents. Движение вверх расширяет компактный sheet, если
   доступен stage2; при единственном stage1 длинный контент прокручивается.
   Движение вниз передаётся sheet, когда scroll достиг верхней границы.
2. **Keyboard handling**: модальный controller наблюдает
   `keyboardWillChangeFrame`; обнаруженный overlap с keyboard
   добавляется в `primaryScrollView.contentInset.bottom` и
   `verticalScrollIndicatorInsets.bottom`. Active first responder
   автоматически scrolls в visible area.

> Tip: При смене `primaryScrollView` keyboard contribution автоматически
> переносится со старого scroll view на новый.

## Keyboard handling

Без дополнительной настройки модальный controller:

- Подъёмает footer над keyboard (footer follows keyboard top edge).
- Обновляет `primaryScrollView.contentInset.bottom` на keyboard overlap.
- Scrolls active first responder в visible область.
- Реагирует на keyboard show/hide/resize/dismiss с системной длительностью
  и curve.

Никакого кода со стороны caller'а не требуется — достаточно установить
`primaryScrollView`.

## Программное управление

```swift
modal.currentDetent              // .stage1 | .stage2
modal.currentDetentProgress      // CGFloat — прогресс drag'а

modal.setDetent(.stage2, animated: true)

// Закрытие — стандартный UIKit:
dismiss(animated: true)
```

## Custom transition animations

По умолчанию модалка открывается как bottom sheet снизу. Для morph
из конкретной кнопки в модальное окно используйте встроенный source
transition:

```swift
let modal = AetherModalNavigationController(
    rootViewController: AttachmentsController(),
    config: .init(detents: [.stage1], initialDetent: .stage1)
)
modal.useSourceTransition(from: attachmentButton)
present(modal, animated: true)
```

Если source view живёт не дольше самой кнопки или frame уже рассчитан,
можно передать frame в window coordinates:

```swift
let frame = attachmentButton.convert(attachmentButton.bounds, to: nil)
modal.useSourceTransition(sourceFrameInWindow: frame)
```

Тонкая настройка:

```swift
modal.useSourceTransition(
    from: attachmentButton,
    configuration: .init(
        presentationDuration: 0.5,
        dismissalDuration: 0.24,
        overscaleAmount: 0.018,
        sourceCornerRadius: 22,
        targetCornerRadius: 34
    )
)
```

Для полностью своей анимации присвойте объект, реализующий
``AetherModalTransitionAnimation``:

```swift
final class MyModalTransition: AetherModalTransitionAnimation {
    func makePresentationAnimator(
        for modalController: AetherModalController
    ) -> UIViewControllerAnimatedTransitioning? {
        MyPresentAnimator()
    }

    func makeDismissalAnimator(
        for modalController: AetherModalController
    ) -> UIViewControllerAnimatedTransitioning? {
        MyDismissAnimator()
    }
}

modal.transitionAnimation = MyModalTransition()
```

## Delegate

```swift
public protocol AetherModalControllerDelegate: AnyObject {
    func modalController(_ controller: AetherModalController, didUpdateDetentProgress progress: CGFloat)
    func modalController(_ controller: AetherModalController, didChangeDetent detent: AetherModalController.Detent)
    func modalControllerWillBeginInteractiveResize(_ controller: AetherModalController)
    func modalControllerDidEndInteractiveResize(_ controller: AetherModalController)
}
```

Все методы default-имплементацией пустые.

```swift
modal.delegate = self
```

## AetherModalNavigationController

Wrapper над ``AetherModalController`` со встроенным
``AetherNavigationController``:

```swift
let root = SettingsController()
let modal = AetherModalNavigationController(
    rootViewController: root,
    config: .init(detents: [.stage1, .stage2], initialDetent: .stage2)
)
present(modal, animated: true)
```

Поддерживает push/pop внутри модалки:

```swift
modal.pushViewController(ProfileController(), animated: true)
modal.popViewController(animated: true)
modal.popToRoot(animated: true)
modal.setViewControllers([root, profile], animated: false)
modal.replaceTopController(newRoot, animated: true)

modal.rootViewController     // root controller (read-only)
modal.topViewController      // верхний controller стека
modal.viewControllers        // полный стек
```

Доступ к встроенному nav controller:

```swift
modal.internalNavigationController   // AetherNavigationController
```

Контент, chrome и footer используют один прогресс push/pop. Footer остаётся
в modal host со своим фоном; его не переносят внутрь движущейся страницы.
Завершение и отмена перехода синхронно восстанавливают владельца footer,
scroll configuration и набор видимых страниц. При активном navigation
transition вертикальный sheet drag не начинается.

> Note: Nav bar контроллеров внутри модалки автоматически адаптирован
> под grabber-полосу: `statusBarHeight` заменяется на
> ``AetherModalController/grabberContainerHeight`` (17pt), что
> обеспечивает правильное позиционирование bar content под grabber'ом.
> Edge-effect frost nav bar'а расширяется вверх для покрытия grabber
> region'а.

## AetherModalContent protocol

Опциональный протокол для ViewController'ов, презентуемых внутри
``AetherModalNavigationController``. Позволяет content'у объявить свои
footer / scroll preferences без явного кода со стороны caller'а:

```swift
final class SendPushViewController: AetherViewController, AetherModalContent {
    private(set) lazy var sendButton: UIButton = ...
    private(set) var scroll: UIScrollView?

    var modalFooterView: UIView? { sendButton }
    var modalFooterHeight: CGFloat { 98 }
    var modalPrimaryScrollView: UIScrollView? { scroll }
}

// Caller:
let modal = AetherModalNavigationController(
    rootViewController: SendPushViewController(),
    config: .init(detents: [.stage1, .stage2], initialDetent: .stage2)
)
present(modal, animated: true)
```

### Свойства протокола

| Свойство | Тип | Default | Назначение |
|---|---|---|---|
| `modalFooterView` | `UIView?` | `nil` | View для footer slot'а. |
| `modalFooterHeight` | `CGFloat` | `0` | Полная высота footer'а. |
| `modalFooterEdgeFadeHeight` | `CGFloat` | `28` | Высота gradient fade. |
| `modalFooterEdgeTintColor` | `UIColor?` | `nil` | Tint frost'а. |
| `modalFooterEdgeBlurRadius` | `CGFloat` | `2` | Blur radius. |
| `modalFooterEdgeEffectEnabled` | `Bool` | `true` | Показывать frosted band под footer; `false` для отдельной плавающей стеклянной кнопки. |
| `modalPrimaryScrollView` | `UIScrollView?` | `nil` | Scroll view для arbitration. |

Все свойства — opt-in. По умолчанию
`contentConfigurationMode == .perScreen`: навигатор берёт footer и scroll
view у текущего верхнего экрана независимо от того, реализует ли протокол
root. Если верхний экран не реализует протокол, footer убирается, а для
scroll arbitration используется `primaryScrollViewForChrome`.

Для общего footer, которым управляет сам modal или его подкласс, выберите
ручной режим до загрузки view:

```swift
let modal = AetherModalNavigationController(rootViewController: root)
modal.contentConfigurationMode = .manual
modal.footerView = sharedFooter
modal.footerHeight = 76
modal.primaryScrollView = rootScrollView
```

> Important: Раньше отсутствие протокола у root неявно сохраняло ручную
> настройку. При миграции такого подкласса явно задайте `.manual`.
> В `.perScreen` footer inset уже входит в layout конкретной страницы;
> не добавляйте `modalFooterHeight` к нему повторно.

## API сводка

### ``AetherModalController``

| Свойство / метод | Назначение |
|---|---|
| `init(config:)` | Создание. |
| `config` | Конфигурация (read-only после init). |
| `contentView` | Host для контента. |
| `contentHeight(forWidth:safeAreaInsets:)` | Измерение полной высоты нижней шторки при `sizesToContent == true`. |
| `embedContent(_:)` | Embed UIViewController. |
| `footerView` | Sticky footer. |
| `footerHeight` | Высота footer'а (обязательно при использовании). |
| `footerEdgeFadeHeight` / `footerEdgeTintColor` / `footerEdgeBlurRadius` | Кастомизация frost'а. |
| `primaryScrollView` | Scroll view для arbitration + keyboard handling. |
| `delegate` | Delegate. |
| `transitionAnimation` | Optional custom present/dismiss animation provider. |
| `currentDetent` | Текущий detent (read-only). |
| `currentDetentProgress` | Прогресс drag'а. |
| `setDetent(_:animated:)` | Программное переключение. |
| `useSourceTransition(from:)` | Source-to-modal morph из `UIView`. |
| `useSourceTransition(sourceFrameInWindow:)` | Source-to-modal morph из frame в window coordinates. |
| `grabberContainerHeight` (static) | Высота grabber-полосы (17pt). |

### ``AetherModalControllerDelegate``

См. протокол выше.

### ``AetherModalNavigationController``

| Свойство / метод | Назначение |
|---|---|
| `init(rootViewController:config:)` | Создание с root. |
| `init(config:navigationMode:)` | Создание пустого стека. |
| `internalNavigationController` | Встроенный nav controller. |
| `contentConfigurationMode` | `.perScreen` по умолчанию; `.manual` для общего footer/scroll, настроенного владельцем modal. |
| `rootViewController` / `topViewController` / `viewControllers` | Доступ к стеку. |
| `pushViewController(_:animated:)` | Push. |
| `popViewController(animated:)` | Pop. |
| `popToRoot(animated:)` | Pop до корня. |
| `setViewControllers(_:animated:)` | Замена стека. |
| `replaceTopController(_:animated:)` | Замена верхнего. |

### ``AetherModalContent`` (протокол)

См. таблицу свойств выше.

### ``AetherModalTransitionAnimation`` (протокол)

Фабрика для кастомных `UIViewControllerAnimatedTransitioning` на
presentation и dismissal. Верните `nil` для стороны, где нужно оставить
default bottom-sheet animation.

### ``AetherModalSourceTransition``

Готовая реализация ``AetherModalTransitionAnimation`` для morph-а
source view/frame в модалку и закрытия обратно в source.

## Edge cases

- **`footerHeight = 0` при наличии `footerView`.** Footer не отображается;
  edge-effect frost не создаётся. Auto-layout-only footer'ы возвращают
  `intrinsicContentSize.height == 0`, поэтому `footerHeight` обязательно
  устанавливается явно.
- **`primaryScrollView` не at top, drag вниз.** Sheet НЕ двигается —
  scroll arbitration отдаёт touch scroll view. Только когда scroll
  достигает top edge, sheet начинает двигаться.
- **Keyboard hide во время drag'а.** Keyboard observer корректно
  сбрасывает overlap; footer возвращается в position без
  glitch'а. Если `primaryScrollView` was scrolled во время keyboard
  shown, `contentInset.bottom` корректно восстанавливается.
- **Прерывание settle новым drag.** Движение продолжается от текущего
  frame, без возврата к геометрии исходного detent.
- **Push/pop и короткая шторка.** Footer привязан к видимому низу sheet,
  а source и target получают собственные bottom insets. Отмена back-жеста
  возвращает исходный footer, в том числе при общем экземпляре view.
- **Embedded nav controller status bar.** При размещении
  ``AetherNavigationController`` внутри ``AetherModalController``
  status bar height заменяется на `grabberContainerHeight = 17pt`.
  Nav bar bar content laid out под grabber'ом; edge-effect frost
  покрывает grabber region.
- **Push в модалке во время keyboard shown.** Keyboard observer
  перенаправляется на новый top controller; transition корректно
  координируется с keyboard animation.

## See Also

- <doc:NavigationController>
- <doc:NavigationBar>
- <doc:Glass>
- <doc:EdgeEffect>
