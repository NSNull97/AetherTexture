# SegmentedControl

iOS-style segmented control с настраиваемой темой, async-validation
перед commit'ом и smooth thumb-анимацией.

## Overview

``AetherSegmentedControl`` — UIControl-аналог `UISegmentedControl` с
расширенным функционалом:

- Items с title + опциональным image.
- Кастомизируемая тема (colors, fonts, sizing).
- Async validation перед commit'ом selected index.
- Smooth thumb-анимация.

## Базовый шаблон

```swift
let segmented = AetherSegmentedControl(
    theme: AetherSegmentedControl.Theme(),
    items: [
        .init(title: "All"),
        .init(title: "Photos"),
        .init(title: "Videos")
    ],
    selectedIndex: 0
)
segmented.selectedIndexChanged = { index in
    print("Selected: \(index)")
}
view.addSubview(segmented)
```

## Item

```swift
public struct Item: Equatable {
    public let title: String
    public let image: UIImage?
    public let badgeValue: String?
}
```

Изображение располагается перед подписью с отступом 5 pt. Template images
окрашиваются в `textColor` / `selectedTextColor` соответствующего слоя.
При RTL изображение располагается справа от подписи.

```swift
let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
let segmented = AetherSegmentedControl(items: [
    .init(title: "Light", image: UIImage(systemName: "sun.max.fill", withConfiguration: symbol)),
    .init(title: "Dark", image: UIImage(systemName: "moon.fill", withConfiguration: symbol)),
    .init(title: "System", image: UIImage(systemName: "circle.lefthalf.filled", withConfiguration: symbol))
])
segmented.titleFont = .systemFont(ofSize: 13, weight: .semibold)
segmented.selectedTitleFont = .systemFont(ofSize: 13, weight: .semibold)
segmented.itemHorizontalPadding = 8
```

## Theme

```swift
public final class Theme: Equatable {
    public let textColor: UIColor
    public let selectedTextColor: UIColor
}
```

## Async validation

Перед commit'ом нового selected index выполняется async-validation:

```swift
segmented.selectedIndexShouldChange = { newIndex, commit in
    // commit(true) — разрешить переключение
    // commit(false) — заблокировать (selected index не меняется)

    Task {
        let isAllowed = await checkPermission()
        await MainActor.run {
            commit(isAllowed)
        }
    }
}
```

Если `selectedIndexShouldChange` не установлен, переключение разрешено
по default. После commit вызывается `selectedIndexChanged`.

## Layout

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `cornerRadius` | `CGFloat?` | `nil` | `nil` — capsule (height/2). |
| `thumbInset` | `CGFloat` | `2.0` | Inset thumb'а от border'ов. |
| `preferredHeight` | `CGFloat` | `36.0` | Preferred высота (используется в `intrinsicContentSize`). |
| `itemHorizontalPadding` | `CGFloat` | `16.0` | Минимальные отступы с каждой стороны содержимого item. |
| `titleFont` | `UIFont?` | `nil` | Кастомный шрифт; `nil` — 14 pt regular с Dynamic Type. |
| `selectedTitleFont` | `UIFont?` | `nil` | Кастомный шрифт; `nil` — 14 pt semibold с Dynamic Type. |

## Программное управление

```swift
segmented.items = [...]                            // обновление items
segmented.selectedIndex = 1                         // мгновенно
segmented.setSelectedIndex(2, animated: true)       // анимировано

segmented.updateTheme(newTheme)                     // динамическая смена темы
```

## API

### ``AetherSegmentedControl``

| Свойство / метод | Назначение |
|---|---|
| `init(theme:items:selectedIndex:cornerRadius:appearanceStyle:)` | Создание. |
| `items` | Items (read-write). |
| `selectedIndex` | Selected index (read-write). |
| `setSelectedIndex(_:animated:)` | Animated переключение. |
| `selectedIndexChanged` | Callback после commit'а. |
| `selectedIndexShouldChange` | Async validation closure. |
| `cornerRadius` | Corner radius (`nil` → capsule). |
| `thumbInset` | Inset thumb'а. |
| `preferredHeight` | Default `intrinsicContentSize.height`. |
| `updateTheme(_:)` | Динамическая смена темы. |

### ``AetherSegmentedControl/Item``

См. структуру выше.

### ``AetherSegmentedControl/Theme``

См. свойства выше.

## Edge cases

- **`selectedIndex` out of bounds.** При `items.count == 0` или
  `selectedIndex >= items.count` value clamps к valid range; thumb
  скрывается при пустых items.
- **Async validation timeout.** При отсутствии вызова `commit(_:)`
  внутри `selectedIndexShouldChange` selected index остаётся в исходном
  state. UI feedback (thumb position) не возвращается; рекомендуется
  явный `commit(false)` для cancel-ов.
- **Theme смена во время animated transition'а.** `updateTheme(_:)`
  применяется immediately; in-flight thumb animation продолжается с
  новыми цветами.

## See Also

- <doc:Glass>
- <doc:NavigationBar>
