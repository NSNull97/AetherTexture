# Appearance

Выбор глобального renderer между классическим Legacy и двумя поколениями
Liquid Glass.

## Overview

``AetherAppearanceStyle`` содержит ровно три канонических case:

| Case | Отображаемое имя | Поведение |
|---|---|---|
| `.legacy` | Legacy | `UIBlurEffect(.systemChromeMaterial)` без Liquid Glass pipeline. |
| `.liquidGlassV1` | Liquid Glass v1 | Первое поколение Liquid Glass, ранее iOS 26 style. |
| `.liquidGlassV2` | Liquid Glass v2 | Второе поколение Liquid Glass, ранее iOS 27 style. |

Legacy не означает «стиль для старой iOS». Это явно выбираемая классическая
тема, которая работает и на актуальной системе. Названия Liquid Glass v1/v2
обозначают поколения дизайна, а не availability.

## Настройка приложения

Укажите style в Application DSL:

```swift
AetherApplication {
    AppearanceStyle(.legacy)
    WindowScene(id: "main") { _ in
        AetherNavigationController(rootViewController: RootController())
    }
}
```

Остальные варианты задаются тем же способом:

```swift
AppearanceStyle(.liquidGlassV1)
AppearanceStyle(.liquidGlassV2)
```

Эквивалентный modifier:

```swift
AetherApplication {
    WindowScene(id: "main") { _ in RootController() }
}
.appearanceStyle(.legacy)
```

По умолчанию используется `.liquidGlassV1`, что сохраняет прежнее поведение
`.iOS26`.

## Динамическая смена

Уже созданную иерархию можно обновить без пересоздания окна:

```swift
AetherApplicationRuntime.shared?.updateAppearanceStyle(.legacy)
```

Компоненты сохраняют content, layout, gestures и control state, заменяя только
surface renderer. При переходе в Legacy Liquid Glass effect views/layers
удаляются, а не остаются скрытыми под непрозрачным фоном.

Локальные цветовые и surface overrides через
``AetherControllerAppearanceProviding`` применяются после глобального style и
не создают отдельную theme-систему.

## Legacy renderer

Legacy разрешает semantic role компонента в обычные UIKit tokens. Каждая
surface использует публичный `UIVisualEffectView` с
`UIBlurEffect(.systemChromeMaterial)` вместо `UIGlassEffect`:

- attached bars используют system background и separator;
- floating surfaces, cards и popup получают semantic fill, border и мягкую
  обычную shadow;
- buttons и selection indicators используют tint/fill, disabled alpha и
  pressed feedback;
- inputs используют secondary/tertiary fill и обычный focus border;
- Reduce Transparency делает поверхность плотнее, а Reduce Motion отключает
  style-only scale/morph motion.

Legacy не создаёт нативный `UIGlassEffect`. Контекстное меню использует
общую геометрию перехода с Liquid Glass, но сохраняет Legacy material.

## Appearance контекстного меню и transition containers

```swift
let menu = ContextMenuController(
    source: .init(view: button),
    items: items,
    appearanceStyle: .legacy
)
menu.present()
```

`ContextMenuController` сам разрешает внутренний режим из appearance.
Публичного стиля анимации нет. Сейчас оба внутренних режима используют
один движок source → menu; Legacy меняет renderer на
`UIBlurEffect.Style.systemChromeMaterial`. Source lease сохраняет и
восстанавливает состояние исходного view при закрытии и отмене.

`appearanceStyle: nil` наследует runtime в момент `present()`. Explicit
значение закрепляет renderer. Изменение поколения у inherited presentation
закрывает активное меню; следующий `present()` создаёт актуальный renderer.
Optional `preview: .init(...)` задаёт lifted content независимо от appearance.

У `LensTransitionContainer`, `AetherSourceMorphController` и
`AetherAttachmentMenuController` `nil` также означает наследование runtime,
а non-`nil` — закреплённый appearance. Legacy source/attachment popup работает
через UIKit alpha/scale; Legacy lens container сохраняет публичный
`contentsView` и анимирует геометрию через Core Animation без private SDF.

## Миграция и Codable

Переименование публичных case:

```swift
.iOS26  // deprecated alias -> .liquidGlassV1
.iOS27  // deprecated alias -> .liquidGlassV2
```

Новые значения сериализуются под стабильными идентификаторами `legacy`,
`liquid-glass-v1` и `liquid-glass-v2`. Decoder также принимает старые строки
`iOS26`, `ios26`, `iOS 26`, `iOS27`, `ios27` и `iOS 27`.

## Availability

Настоящие platform checks остаются привязаны к ОС:

```swift
if #available(iOS 26.0, *) {
    // native UIGlassEffect path
}
```

На системе без нужного Liquid Glass API выбранное поколение сохраняется в
appearance model, а renderer использует совместимый fallback. Legacy никогда
не включается автоматически по версии ОС.
