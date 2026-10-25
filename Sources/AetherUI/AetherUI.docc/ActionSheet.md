# ActionSheet

``AetherActionSheetController`` shows a floating glass card with a centered
heading and separate pill actions. The surface and row treatment follow
``AetherAlertController``. Long menus scroll inside the card.

## Presenting from a source

Pass the trigger view to animate the card from that view on opening and back
to it on closing. The source must be attached to the presenting window.
Its visual is temporarily represented by a snapshot and restored after the
closing animation.

```swift
let sheet = AetherActionSheetController(
    theme: .light,
    sourceView: menuButton
)
sheet.setItemGroups([
    AetherActionSheetItemGroup(items: [
        AetherActionSheetTextItem(title: "Медиатека"),
        AetherActionSheetButtonItem(title: "Только загруженная музыка") { [weak sheet] in
            sheet?.dismissAnimated()
        },
        AetherActionSheetButtonItem(title: "Управление плейлистами") { [weak sheet] in
            sheet?.dismissAnimated()
        }
    ])
])
present(sheet, animated: true)
```

The existing `init(theme:)` call remains valid. Without a source, the
card opens from a small centered frame.

## Items and updates

Groups support ``AetherActionSheetButtonItem``,
``AetherActionSheetTextItem``, ``AetherActionSheetSwitchItem``,
``AetherActionSheetCheckboxItem``, and custom
``AetherActionSheetItem`` views. Groups share one glass card; every
interactive item receives its own rounded fill and an 8-point gap.
The first text item is normally the heading.

```swift
sheet.updateItem(groupIndex: 0, itemIndex: 1) { _ in
    AetherActionSheetButtonItem(title: "Обновлено") { [weak sheet] in
        sheet?.dismissAnimated()
    }
}
```

`dismissAnimated()` and `dismiss(animated: true)` close through the
reverse source transition. A tap outside or Escape also
closes the sheet. The `dismissed` callback receives `true` for those
user cancellations and `false` for `dismissAnimated()`.

`AetherActionSheetTheme.light` and `.dark` use the same card and pill
colors as Alert. Custom themes may set `cardBackgroundColor` separately
from `itemBackgroundColor`.
