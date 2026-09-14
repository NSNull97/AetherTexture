# Context Menu Accessibility

Действия меню остаются обычными интерактивными строками `ContextMenuItem`.
Временные visual snapshots и переходная оболочка не должны становиться
дополнительными accessibility elements. Названия и действия задаются
содержимым меню, независимо от appearance.

Reduce Motion упрощает движение, сохраняя выбор действия и восстановление
исходной кнопки. Проверяйте закрытие во время открытия, повторное открытие,
VoiceOver и смену appearance при активном меню. После teardown исходный
control должен получить прежнее состояние interaction.

`preview: .init(...)` позволяет показать собственный content и accessory
над меню. Доступность этих view остаётся ответственностью их владельца.
См. <doc:ContextMenu> и <doc:ContextMenuMotionGuide>.
