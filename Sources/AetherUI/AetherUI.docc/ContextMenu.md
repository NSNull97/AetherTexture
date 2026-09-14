# ContextMenu

Glass-стилизованное контекстное меню с морфом «source → menu»,
поддержкой submenu, action rows, headers, separators, лифт-эффектом для
preview-режима.

## Overview

``ContextMenuController`` отображает меню над исходным view. Контроллер
выбирает внутренний режим по текущему appearance: Legacy и Liquid Glass
сейчас используют общий движок перехода source → menu, сохраняя разные
материалы. Публичного выбора стиля анимации нет.

Для карточки или строки можно передать optional `preview`: lifted snapshot
или собственный content остаётся над меню во время выбора действия.

Items меню:

- ``ContextMenuItem/header(title:)`` — серый заголовок-разделитель.
- ``ContextMenuItem/action(_:)`` — tappable row с icon, text, submenu.
- ``ContextMenuItem/separator`` — тонкий hairline-separator.
- ``ContextMenuItem/actionRow(_:)`` — горизонтальная полоса compact
  buttons (quick actions).

## Базовый шаблон

### Long-press на view

```swift
let view = UIView()
view.layer.cornerRadius = 12

let longPress = UILongPressGestureRecognizer(target: self, action: #selector(showMenu))
view.addGestureRecognizer(longPress)

@objc func showMenu(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began else { return }

    let menu = ContextMenuController(
        source: .init(view: view, cornerRadius: 12),
        items: [
            .action(.init(
                title: "Поделиться",
                icon: UIImage(systemName: "square.and.arrow.up"),
                action: { _, _ in /* share */ }
            )),
            .action(.init(
                title: "Удалить",
                icon: UIImage(systemName: "trash"),
                textColor: .destructive,
                action: { _, _ in /* delete */ }
            ))
        ],
        preview: .init()
    )
    menu.present()
}
```

### Tap-to-open на bar button

См. <doc:NavigationBar> — раздел «Context menu на bar button».

```swift
navigationItem.rightBarButtonItem = UIBarButtonItem(
    title: nil,
    image: UIImage(systemName: "ellipsis"),
    contextMenuItemsProvider: {
        return [
            .action(.init(title: "Настройки", action: { _, _ in })),
            .separator,
            .action(.init(title: "Выход", textColor: .destructive, action: { _, _ in }))
        ]
    }
)
```

## Source

```swift
public struct Source {
    public weak var view: UIView?
    public var cornerRadius: CGFloat?
    public var hidesDuringPresentation: Bool
}
```

| Параметр | Назначение |
|---|---|
| `view` | Source view, относительно которого позиционируется меню. |
| `cornerRadius` | Corner radius source view'а для морфа. `nil` → `view.layer.cornerRadius`. |
| `hidesDuringPresentation` | По умолчанию `true`. Обычное меню временно владеет визуальной копией source; оригинал восстанавливается при dismiss. В preview-режиме флаг управляет видимостью оригинала. |

Обычное меню скрывает оригинал через source lease независимо от этого
флага, чтобы в анимации не было двух копий стекла. Lease сохраняет alpha,
transform и interaction исходного view и восстанавливает их при teardown.

## Preview

### ``ContextMenuController/Preview``

Static glass menu + lifted snapshot source:

```swift
ContextMenuController(
    source: .init(view: cardView),
    items: items,
    preview: .init(verticalSpacing: 8.0, lift: 1.04)
)
```

| Параметр | По умолчанию | Назначение |
|---|---|---|
| `verticalSpacing` | `8.0` | Gap между финальным lifted preview-snapshot и menu снизу. |
| `lift` | `1.04` | Scale factor для snapshot (1.04 = +4%). |
| `content` | `nil` | Custom preview-view вместо snapshot source. |
| `accessory` | `nil` | Custom view над preview, например reaction strip. |

Preview стартует из позиции source-view и сохраняет ее по X/Y, пока снизу
хватает места. Меню всегда остается снизу от preview; если снизу не
хватает места, preview анимированно поднимается вверх и так же
возвращается при dismiss. Accessory всегда размещается сверху от preview.

Accessory принимает любую `UIView`; размер можно задать явно через
`preferredSize`, иначе контроллер возьмет Auto Layout fitting /
`intrinsicContentSize` / `bounds.size`:

```swift
let reactions = ReactionStripView()

ContextMenuController(
    source: .init(view: messageBubble, cornerRadius: 16),
    items: items,
    preview: .init(
        accessory: .init(
            view: reactions,
            preferredSize: CGSize(width: 252, height: 48),
            spacing: 8
        )
    )
)
```

Подробнее о переходе и воспроизводимом примере: <doc:ContextMenuMotionGuide>.

## Локальный appearance и public transition containers

`appearanceStyle: nil` у ``ContextMenuController`` наследует глобальный
runtime; non-`nil` закрепляет renderer для конкретного меню:

```swift
let menu = ContextMenuController(
    source: .init(view: button),
    items: items,
    appearanceStyle: .legacy
)
```

Низкоуровневый lens container также поддерживает локальный appearance:

```swift
let lens = LensTransitionContainer(
    effectView: sourceEffectView,
    appearanceStyle: .legacy
)
lens.contentsView.addSubview(contentView)
```

У `LensTransitionContainer` `nil` следует за live runtime, explicit style
закреплён. Legacy implementation сразу создаёт публичный
`systemChromeMaterial` renderer и не инициализирует private SDF/displacement
lens. Публичный `contentsView` сохраняется при runtime rebuild; движение
выполняется через обычные Core Animation size/position/corner-radius keyframes.

Для standalone source/attachment popup действуют те же правила:

```swift
let morph = AetherSourceMorphController(
    contentView: contentView,
    targetSize: CGSize(width: 320, height: 280),
    appearanceStyle: .legacy
)
morph.present(from: sourceView)

let attachments = AetherAttachmentMenuController(
    items: attachmentItems,
    appearanceStyle: .legacy
)
attachments.present(from: sourceView)
```

`nil` наследует application runtime, explicit style закреплён. Legacy
source/attachment popup использует `systemChromeMaterial` и UIKit alpha/scale
без glass renderer, source proxy snapshot, Liquid morph calculations или
`CADisplayLink`. При смене inherited поколения активная презентация
синхронно очищается; следующий `present` строит новый renderer.

## ContextMenuItem

### `.header(title:)`

```swift
.header(title: "Действия")
```

Plain серый заголовок-разделитель.

### `.action(_:)`

```swift
.action(.init(
    id: "delete",
    title: "Удалить",
    subtitle: "Без возможности восстановления",
    icon: UIImage(systemName: "trash"),
    iconSide: .trailing,
    textColor: .destructive,
    isSelected: false,
    isEnabled: true,
    action: { item, dismissHandle in
        // dismissHandle.dismiss(animated: true) — для явного закрытия
    }
))
```

#### ContextMenuActionItem

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `id` | `AnyHashable` | `UUID()` | Уникальный идентификатор. |
| `title` | `String` | — | Заголовок. |
| `subtitle` | `String?` | `nil` | Subtitle (рендерится под title). |
| `icon` | `UIImage?` | `nil` | Иконка. |
| `iconSide` | `IconSide` | `.trailing` | `.leading` или `.trailing`. |
| `textColor` | `TextColor` | `.primary` | `.primary` или `.destructive` (red). |
| `isSelected` | `Bool` | `false` | Checkmark на leading (если `iconSide == .trailing`). |
| `isEnabled` | `Bool` | `true` | Активность row. |
| `submenu` | `[ContextMenuItem]?` | `nil` | Submenu (рендерится с trailing chevron). |
| `action` | `((ActionItem, DismissHandle) -> Void)?` | `nil` | Tap-callback. |

#### ContextMenuDismissHandle

```swift
public final class ContextMenuDismissHandle {
    public func dismiss(animated: Bool = true)
}
```

Передаётся в action callback. Используется для явного закрытия меню,
если требуется задержка (например, async-операция):

```swift
.action(.init(title: "Подтвердить", action: { _, dismiss in
    Task {
        await performAction()
        dismiss.dismiss()
    }
}))
```

> Note: По умолчанию меню автоматически закрывается после выполнения
> action callback. Использование `dismissHandle` нужно только для
> explicit control.

### `.separator`

```swift
.separator
```

Тонкий inset-hairline между группами.

### `.actionRow(_:)`

Горизонтальная полоса compact-buttons:

```swift
.actionRow([
    .init(title: "Like", icon: UIImage(systemName: "heart"), action: { _, _ in }),
    .init(title: "Comment", icon: UIImage(systemName: "bubble.left"), action: { _, _ in }),
    .init(title: "Share", icon: UIImage(systemName: "square.and.arrow.up"), action: { _, _ in })
])
```

Каждая cell отображается как icon centered above short title. Cells
equal-width. Running highlight tracks под пальцем (sliding lens).
`subtitle`, `iconSide`, `submenu` игнорируются (compact cells не
поддерживают submenus).

## Submenu

```swift
.action(.init(
    title: "Sort by",
    icon: UIImage(systemName: "arrow.up.arrow.down"),
    submenu: [
        .action(.init(title: "Date", isSelected: true, action: { _, _ in })),
        .action(.init(title: "Name", action: { _, _ in })),
        .action(.init(title: "Size", action: { _, _ in }))
    ]
))
```

При тапе на row с submenu вместо action callback'а открывается inline
submenu overlay (Yandex Music style):

- Parent menu затемняется и disabled.
- Submenu card overlay'ится поверх parent menu, anchored к Y-позиции
  source row.
- Tap на dimmed parent или на header chevron submenu collapse'ит
  обратно в parent.

Action на row submenu выполняется так же, как и на root-level row.

## Программное управление

```swift
let menu = ContextMenuController(...)
menu.present()              // презентация
menu.dismiss(animated: true) // явное закрытие
```

## Анимационные параметры

| Константа | Значение | Назначение |
|---|---|---|
| `morphDuration` | 0.475 с | Длительность open. |
| `dismissDuration` | 0.475 с | Длительность close. |
| `morphDamping` | 0.68 | Spring damping для open. |
| `dismissDamping` | 0.68 | Spring damping для close. |
| `dimBlurRadius` | 0.05 (default), public static | Backdrop blur dim layer. Конфигурируется глобально. |
| `menuCornerRadius` | 34.0 | Corner radius menu surface. |

Изменение глобального dim blur:

```swift
ContextMenuController.dimBlurRadius = 4.0   // более выраженный backdrop blur
```

## Glass lift effect

При нажатии на menu surface применяется expressive press feedback
(borrowed from Telegram Display TouchEffect):

1. **Base lift** — uniform scale up by 14pt на shorter axis.
2. **Anisotropic stretch** — biased scale along finger pull-direction
   (drag → right-bottom stretches Y и слегка сжимает X).
3. **Translation** — surface shifts up to 20pt toward finger.

Эффект автоматически активируется gesture recognition'ом во время
press'а; конфигурация не требуется.

## API сводка

### ``ContextMenuController``

| Свойство / метод | Назначение |
|---|---|
| `init(source:items:preview:appearanceStyle:onDismiss:)` | Создание; `appearanceStyle: nil` наследует runtime, explicit value закрепляет renderer. |
| `present()` | Презентация. |
| `dismiss(animated:)` | Явное закрытие. |
| `dimBlurRadius` (static) | Глобальный backdrop blur. |

### ``ContextMenuController/Source``

См. таблицу свойств выше.

### ``ContextMenuController/Preview``

| Параметр | Назначение |
|---|---|
| `verticalSpacing` | Расстояние между preview и меню, по умолчанию 8 pt. |
| `lift` | Масштаб lifted content, по умолчанию 1.04. |
| `content` | Собственный content вместо snapshot source. |
| `accessory` | Дополнительный view над preview. |

### Public transition primitives

| Тип | Appearance contract в Legacy |
|---|---|
| ``LensTransitionContainer`` | `appearanceStyle: nil` следует runtime, explicit `.legacy` закреплён; публичный system-Chrome blur и CA keyframes без SDF displacement. |
| ``AetherSourceMorphController`` | `nil` следует runtime; Legacy popup использует alpha/scale без snapshot/display link. |
| ``AetherAttachmentMenuController`` | Передаёт тот же optional override source-morph controller'у. |

### ``ContextMenuItem``

| Case | Назначение |
|---|---|
| `.header(title:)` | Серый заголовок. |
| `.action(_:)` | Tappable row. |
| `.separator` | Hairline separator. |
| `.actionRow(_:)` | Compact buttons row. |

### ``ContextMenuActionItem``

См. таблицу свойств выше.

### ``ContextMenuDismissHandle``

| Метод | Назначение |
|---|---|
| `dismiss(animated:)` | Явное закрытие меню из action callback. |

## Edge cases

- **Source view деаллокирован между present и dismiss.** Source
  хранится как `weak var`; при дeаллокации menu остаётся видимым, но
  morph back-to-source невозможен — выполняется fade out без морфа.
- **Conflict с UINavigationItem context menu (iOS 14+).** При установке
  bar button с `contextMenuItemsProvider` UIKit'овский
  `UIBarButtonItem.menu` игнорируется — tap routing выполняется через
  ``ContextMenuController``.
- **Submenu с очень длинным content.** Submenu card sizing'ится по
  preferred content size; для очень длинных списков добавляется
  внутренний scroll view. Header chevron остаётся sticky на верху.
- **Размещение у края экрана.** При размещении source view'а
  около edge экрана (например, левый край) menu корректно flip'ится в
  правую сторону. Computed `menuFrame` выбирает edge с большим
  available space.
- **Theme flip во время презентации.** При смене dark/light system mode
  во время open menu выполняется автоматический rebuild glass surface;
  При смене поколения appearance активное inherited меню закрывается;
  следующий `present()` использует новый renderer. Explicit override сохраняется.

## See Also

- <doc:NavigationBar>
- <doc:Glass>
- <doc:TabBar>
