# ``AetherUI``

Texture-first UIKit-hosted фреймворк навигации со style-aware surfaces,
интерактивными переходами и плавающим tab bar для iOS 15+.

## Overview

AetherUI представляет собой Texture-first реализацию ключевых навигационных
компонентов, спроектированных по образцу Telegram-iOS. UIKit остаётся системной
boundary-оболочкой, а reusable renderable-компоненты переходят на
`ASDisplayNode`; ``TextNode``, ``AetherListItemNode``, ``AetherListNode`` и
node-first wrappers для navigation/page/toolbar/state/control surfaces уже
используют Texture-backed public APIs.
Единый appearance runtime поддерживает классический non-Liquid-Glass Legacy и два
поколения Liquid Glass. Компоненты сохраняют общие content/layout/state, а
semantic surface renderer выбирает system surface либо Liquid Glass backend.

Основные компоненты фреймворка:

- ``AetherViewController`` — базовый контроллер с собственным nav bar, accessory-зонами
  и единой точкой раскладки для tab bar, floating toolbar и content-unavailable
  overlay.
- ``AetherNavigationController`` — стек экранов с per-screen nav bar,
  style-aware переходами при push/pop и интерактивным edge-swipe pop'ом.
- ``AetherTabBarController`` — корневой tab bar с плавающим pill-контейнером,
  опциональным search-кружком в стиле Apple Music и `bottomBarAccessory`-полосой
  над pill'ом.
- ``AetherScreenNode``, ``AetherNavigationNode``, ``AetherTabContainerNode`` и
  ``AetherPageContainerNode`` — node-first путь для новых экранов, навигации,
  вкладок и paging-контейнеров.
- ``AetherWindow`` — `UIWindow`-подкласс с keyboard tracking, интерактивным
  drag-to-dismiss клавиатуры и status bar dispatcher'ом.
- Семейство **glass-примитивов** (``GlassBackgroundView``, ``GlassControlGroup``,
  ``GlassButton``, ``EdgeEffectView``, ``LiquidLensView``) — Liquid Glass
  backends для nav bar, tab bar, modals, context menu и toolbar. Legacy ветка
  тех же компонентов использует публичный `systemChromeMaterial` и semantic
  UIKit tokens без `UIGlassEffect`.
- Готовые sheets и оверлеи: ``AetherModalController``,
  ``AetherActionSheetController``, ``AetherAlertController``,
  ``AetherToastController``, ``AetherTooltipController``,
  ``ContextMenuController``.
- Высокопроизводительный ``AetherListNode`` — Texture-native порт
  `Display.ListView` из Telegram-iOS с виртуализацией, transactions, sticky
  headers, swipe actions, reorder и Metal-частицами. ``AetherListView`` —
  deprecated legacy layer.
- Node wrappers для оставшихся reusable surfaces: `AetherNavigationBarNode`,
  `AetherToolbarNode`, `AetherSliderNode`, `AetherContentUnavailableNode`,
  `AetherSkeletonNode`. Их анимационно-критичные UIKit/CoreAnimation internals
  остаются скрытыми за node API.

> Important: AetherUI требует iOS 15.0+ и Swift 5.9+. Для liquid-glass-эффектов,
> зависящих от системного `UIGlassEffect`, требуется iOS 26+. На более ранних
> версиях используется compatibility glass fallback (`UIVisualEffectView` с тонированными
> слоями).

## Архитектура одного экрана

Иерархия контроллеров и view-объектов на типовом экране:

```
AetherNativeWindow / AetherWindow
 └── AetherWindowRootViewController      // status bar / orientation / system UI
      └── AetherTabBarController
           ├── TabBarView                  // style-aware tab surface + search
           ├── (опц.) TabBarAccessoryView  // полоса над pill'ом (Now Playing и т.п.)
           └── AetherNavigationController (per tab)
                ├── NavigationBarView      // принадлежит топовому ViewController
                ├── ViewController.view    // контент приложения
                └── (опц.) AetherFloatingToolbarView
```

Каждый ``AetherViewController`` владеет **собственным** ``NavigationBarView``. Бар не
является shared-объектом; он перемещается синхронно с контроллером во время
push/pop. Это ключевое архитектурное решение: два бара одновременно
перекрашиваются и сдвигаются в рамках единого transition'а. Liquid Glass
добавляет surface morph, а Legacy сохраняет ту же механику с обычной
UIKit-анимацией.

## Quick links

@Links(visualStyle: detailedGrid) {
    - <doc:QuickStart>
    - <doc:Appearance>
    - <doc:ViewController>
    - <doc:NavigationController>
    - <doc:TabBar>
    - <doc:Glass>
}

## Topics

### С чего начать

- <doc:QuickStart>
- <doc:Appearance>

### Основа

- <doc:ViewController>
- <doc:AetherWindow>

### Навигация

- <doc:NavigationController>
- <doc:NavigationBar>
- <doc:Search>

### Tab Bar

- <doc:TabBar>

### Glass-примитивы

- <doc:Glass>
- <doc:EdgeEffect>

### Контекстные меню и модальные окна

- <doc:ContextMenu>
- <doc:Modal>

### Списки и виртуализация

- <doc:ListView>

### Sheets / Alerts / Overlays

- <doc:ActionSheet>
- <doc:Alert>
- <doc:Toast>
- <doc:Tooltip>

### Bars и toolbars

- <doc:Toolbar>

### Малые контролы

- <doc:SegmentedControl>
- <doc:Skeleton>
- <doc:ContentUnavailable>
