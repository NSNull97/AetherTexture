# ListView

Виртуализованный список с transaction-based API: вставки, удаления,
обновления, sticky headers, selection, drag-to-reorder, pull-to-refresh,
keyboard avoidance, particle dissolve через Metal.

## Overview

``AetherListNode`` — Texture-native порт `Display.ListView` из Telegram-iOS
на базе `ASScrollNode`. Виртуализация позволяет работать со списками в десятки
тысяч элементов без лагов: в памяти держатся только visible + preload buffer.
Deprecated ``AetherListView`` оставлен только как legacy compatibility layer.

Ключевые возможности:

- **Виртуализация** — binary search по visible range; reuse node при
  scroll'е.
- **Transaction API** — batched insert/delete/update/move с
  identity-based reindex'ом.
- **Анимации удаления** — `.fade`, `.slide(.up|.down)`, `.scale`,
  `.particleDissolve(tileSize:)` (Metal compute).
- **Sticky floating headers** — date-секции в chat-list, group-headers.
- **Selection** — `.none` / `.single` / `.multiple` режимы.
- **Swipe actions** — Telegram-style left/right reveal buttons,
  overswipe boundary action, haptics и tap-to-close.
- **Drag-to-reorder** с long-press lift'ом и snap finish'ем.
- **Pull-to-refresh** (стандартный `UIRefreshControl`).
- **Keyboard avoidance** — автоматическая корректировка bottom inset
  на keyboard frame.
- **Stack from bottom** (chat-style) — top padding при coротком content;
  auto-scroll-to-bottom при mutations.
- **Particle dissolve** — Metal-shader dust effect для Telegram-style
  destructive remove.

## Базовый шаблон

```swift
class MyChatItem: AetherListItem {
    let id: Int
    let text: String

    init(id: Int, text: String) {
        self.id = id
        self.text = text
    }

    var approximateHeight: CGFloat { 60 }

    func createNode(params: AetherListItemLayoutParams,
                    previousItem: AetherListItem?,
                    nextItem: AetherListItem?) -> (AetherListItemNode, AetherListItemNodeLayout) {
        let node = MyChatNode()
        node.configure(text: text)
        return (node, AetherListItemNodeLayout(
            contentSize: CGSize(width: params.width, height: 60)
        ))
    }

    func updateNode(_ node: AetherListItemNode,
                    params: AetherListItemLayoutParams,
                    previousItem: AetherListItem?,
                    nextItem: AetherListItem?,
                    animation: AetherListItemUpdateAnimation) -> AetherListItemNodeLayout {
        (node as? MyChatNode)?.configure(text: text)
        return AetherListItemNodeLayout(
            contentSize: CGSize(width: params.width, height: 60)
        )
    }
}

class MyChatNode: AetherListItemNode {
    private let labelNode = ASTextNode()

    override init() {
        super.init()
        addSubnode(labelNode)
    }

    func configure(text: String) {
        labelNode.attributedText = NSAttributedString(
            string: text,
            attributes: [.font: UIFont.systemFont(ofSize: 17)]
        )
    }

    override func layout() {
        super.layout()
        labelNode.frame = bounds.insetBy(dx: 16, dy: 8)
    }
}

// Использование:
let listNode = AetherListNode()
screenNode.addSubnode(listNode)
listNode.frame = screenNode.bounds

let items = (0..<100).map { MyChatItem(id: $0, text: "Item \($0)") }
listNode.transaction(
    deleteIndices: [],
    insertIndicesAndItems: items.enumerated().map { i, item in
        AetherListInsertItem(index: i, item: item)
    },
    updateIndicesAndItems: [],
    options: [.synchronous]
)
```

## Transaction API

Главная точка модификации — метод `transaction(...)`:

```swift
listNode.transaction(
    deleteIndices: [
        AetherListDeleteItem(index: 5, animation: .slide(.down)),
        AetherListDeleteItem(index: 8, animation: .particles)
    ],
    insertIndicesAndItems: [
        AetherListInsertItem(index: 5, item: newItem)
    ],
    updateIndicesAndItems: [
        AetherListUpdateItem(index: 0, previousIndex: 0, item: updatedItem)
    ],
    options: [.animateInsertions],
    scrollToItem: AetherListScrollToItem(index: 5, position: .visible)
)
```

### Применение операций

Порядок применения внутри одной транзакции:

1. **Deletes** — индексы в исходном (pre-transaction) coordinate space.
2. **Moves** — `fromIndex` в post-delete space, `toIndex` в post-move
   space.
3. **Inserts** — индексы в final coordinate space.

### Identity-based reindex

Reindex выполняется по reference identity `node.item === item`, что
позволяет сохранить stable node ссылки на items, переехавшие в другие
позиции в результате deletes/inserts.

### Options

| Option | Назначение |
|---|---|
| `.animateInsertions` | Insertions с анимацией. |
| `.animateAlpha` | Fade in/out вместо slide. |
| `.synchronous` | Выполнение без отложенной queue. |
| `.crossfade` | Crossfade при update. |

## Item / Node архитектура

### AetherListItem (протокол)

Item — модель элемента, описывающая как создать и обновить node.

| Свойство / метод | Default | Назначение |
|---|---|---|
| `createNode(params:previousItem:nextItem:)` | — | Создание node + layout. |
| `updateNode(_:params:previousItem:nextItem:animation:)` | — | Обновление существующего node. |
| `approximateHeight` | `44.0` | Приблизительная высота для placeholder layout. |
| `selectable` | `true` | Может ли быть selected (tapped). |
| `swipeActions` | `.none` | Left/right Telegram-style swipe actions. |
| `swipeActionSelected(_:listNode:isFullSwipe:)` | (no-op) | Callback на выбор swipe action. |
| `selected(listNode:)` | (no-op) | Callback на tap (когда selectionMode == .none). |
| `isFloatingHeader` | `false` | Является ли sticky header'ом. |
| `canReorder` | `true` | Может ли участвовать в drag-to-reorder. |

### AetherListItemNode (базовый класс view)

| Свойство / метод | Назначение |
|---|---|
| `index` | Текущий индекс (read-only). |
| `item` | Текущий item (read-only). |
| `contentSize` | Размер contentView. |
| `insets` | Inset'ы вокруг content. |
| `layout` | Текущий `AetherListItemNodeLayout`. |
| `apparentHeight` | Видимая высота (с учётом анимаций). |
| `transitionOffset` | Offset во время transition'а. |
| `isSelected` | Текущее состояние selection. |
| `totalHeight` | `contentSize.height + insets.top + insets.bottom`. |
| `contentBounds` / `apparentFrame` | Фреймы для layout. |
| `applyLayout(_:)` | Применение layout. |
| `updateAbsoluteRect(_:within:)` | Обновление абсолютной позиции (override для эффектов). |
| `didChangeSelection(animated:)` | Callback на изменение selection (override). |
| `animateInsertion(duration:)` | Анимация insert (override). |
| `animateRemoval(duration:completion:)` | Анимация remove (override). |
| `setHighlighted(_:at:animated:)` | Highlight при touch (override). |
| `tapped()` / `longTapped()` / `selected()` | Callbacks (override). |
| `particleDissolveTargetNode` | Node для capture в particle dissolve. |

### AetherListItemNodeLayout

```swift
public struct AetherListItemNodeLayout {
    public let contentSize: CGSize
    public let insets: UIEdgeInsets
    public var totalHeight: CGFloat
}
```

## Layout params

```swift
public struct AetherListItemLayoutParams: Equatable {
    public let width: CGFloat              // available width
    public let leftInset: CGFloat          // safe area left
    public let rightInset: CGFloat         // safe area right
    public let availableHeight: CGFloat    // viewport height
}
```

## Insets и keyboard

```swift
listNode.insets = UIEdgeInsets(top: navHeight, left: 0, bottom: tabHeight, right: 0)

// Анимированное обновление:
listNode.updateInsets(newInsets, transition: .animated(duration: 0.3, curve: .easeInOut))

// Авто-keyboard:
listNode.automaticallyAdjustsContentInsetForKeyboard = true
listNode.keyboardDismissBehavior = .interactive
```

При `automaticallyAdjustsContentInsetForKeyboard = true` listNode
наблюдает `keyboardWillChangeFrame`/`keyboardWillHide` и накладывает
keyboard bottom inset поверх user-supplied `insets`. Анимируется
keyboard curve/duration. Если список находится у нижнего края,
`updateInsets` / keyboard transitions сохраняют bottom anchor и не
сдвигают видимые последние rows над input bar.

## Swipe Actions

`AetherListNode` портирует актуальную механику Telegram из
`ItemListRevealOptionsNode`: кастомный горизонтальный pan recognizer,
порог направления `4pt / 2.5x`, velocity cutoff `100pt/s`, spring
settle на ширину action-группы, Texture-native action button nodes и
expanded boundary action при overswipe.

```swift
final class ChatItem: AetherListItem {
    var swipeActions: AetherListSwipeActions {
        AetherListSwipeActions(
            left: [
                AetherListSwipeAction(
                    key: "unread",
                    title: "Не прочитан",
                    icon: .image(UIImage(systemName: "bubble.left.fill")!),
                    backgroundColor: .systemBlue,
                    textColor: .secondaryLabel
                )
            ],
            right: [
                AetherListSwipeAction(
                    key: "mute",
                    title: "Убрать звук",
                    icon: .image(UIImage(systemName: "speaker.slash.fill")!),
                    backgroundColor: .systemOrange,
                    textColor: .secondaryLabel
                ),
                AetherListSwipeAction(
                    key: "delete",
                    title: "Удалить",
                    icon: .image(UIImage(systemName: "trash.fill")!),
                    backgroundColor: .systemRed,
                    textColor: .secondaryLabel
                ),
                AetherListSwipeAction(
                    key: "archive",
                    title: "В архив",
                    icon: .image(UIImage(systemName: "archivebox.fill")!),
                    backgroundColor: .systemGray,
                    textColor: .secondaryLabel
                )
            ]
        )
    }

    func swipeActionSelected(
        _ action: AetherListSwipeAction,
        listNode: AetherListNode,
        isFullSwipe: Bool
    ) {
        switch action.key {
        case "delete":
            // mirror the model delete through transaction(...)
            break
        default:
            break
        }
    }
}
```

List-level callbacks:

```swift
listNode.swipeActionSelected = { index, action, isFullSwipe in
    print(index, action.key, isFullSwipe)
}
listNode.swipeActionsInteractivelyOpened = { index in }
listNode.swipeActionsInteractivelyClosed = { index in }
```

Programmatic control:

```swift
listNode.setSwipeActionsOpened(.right, at: 3, animated: true)
listNode.closeSwipeActions(animated: true)
let offset = listNode.swipeRevealOffset(at: 3)
```

## Scroll API

```swift
listNode.scrollToItem(at: 5, position: .center, animated: true)

listNode.scrollToBottom(animated: true)
listNode.scrollToTop(animated: true)
listNode.scrollToTopInPages(animated: true)     // Telegram-style status-bar tap

listNode.stopScrolling()                    // прерывание active scroll
listNode.visibleSize                         // CGSize
listNode.itemCount                           // Int
listNode.isTracking / isDragging             // Bool

listNode.visibleContentOffset()              // CGFloat
listNode.forEachVisibleItemNode { node in ... }
listNode.nodeForItem(at: 3)                  // AetherListItemNode?
```

`AetherListNode` перехватывает системный status-bar tap через
`scrollViewShouldScrollToTop` и вызывает `scrollToTopInPages(animated:)`.
Программный `scrollToTop(animated:)` остается полным переходом к началу.

### Scroll positions

```swift
public enum AetherListScrollPosition {
    case visible                           // no-op если уже видим
    case top(offset: CGFloat)
    case bottom(offset: CGFloat)
    case center
}
```

## Stack from bottom (chat style)

```swift
listNode.stackFromBottom = true
```

При активации:

- При коротком content (height < viewport) top padding добавляется
  автоматически — content sticks to bottom.
- При длинном content — обычный scroll.
- В executeTransaction snapshot'ится `wasNearBottom` (через
  `isNearBottom(tolerance:)`); после mutations если был at bottom, auto
  scroll-to-bottom (chat anchor поведение).

```swift
listNode.stackFromBottomAutoAnchorTolerance = 60   // pixels от bottom для anchor'а
```

## Selection

```swift
listNode.selectionMode = .single   // .none | .single | .multiple

listNode.setSelected(true, at: 3, animated: true)
listNode.clearSelection(animated: true)

listNode.selectedIndices            // [Int]
listNode.selectionChanged = { indices in
    print("Selected: \(indices)")
}
```

При `selectionMode != .none` tap toggles selection; на node вызывается
`isSelected = true/false` и `didChangeSelection(animated:)`.

## Drag-to-reorder

```swift
listNode.allowsReorder = true
listNode.canMoveItem = { fromIndex, toIndex in
    return toIndex != 0   // нельзя moveить в самый верх
}
listNode.didMoveItem = { fromIndex, toIndex in
    // Обновление data source
}
```

UI: long-press 0.4с активирует lift; swap по identity при drag'е поверх
других items; snap finish при отпускании.

`AetherListItem.canReorder = false` исключает item из reorder
(headers, separators).

## Pull-to-refresh

```swift
listNode.refreshHandler = { done in
    Task {
        await fetchNewData()
        done()
    }
}

listNode.beginRefreshing()                  // программное начало
listNode.isRefreshing                        // Bool
```

Использует стандартный `UIRefreshControl`.

## Sticky floating headers

```swift
class DateHeaderItem: AetherListItem {
    let date: String

    var isFloatingHeader: Bool { true }
    var canReorder: Bool { false }
    var selectable: Bool { false }

    // ... createNode, updateNode
}

let items = [
    DateHeaderItem(date: "Today"),
    MessageItem(...),
    MessageItem(...),
    DateHeaderItem(date: "Yesterday"),
    MessageItem(...),
]

listNode.transaction(insertIndicesAndItems: items.enumerated().map { ... })
```

При scroll'е current pinned header держится в иерархии даже вне preload
range (через internal `currentStickyHeaderIndex()` + `ensureStickyHeaderNode(at:)`).
`zPosition = 1000` для pinned. Когда следующий header достигает текущего,
текущий «выталкивается» вверх.

## Particle dissolve (Metal)

Telegram-style dust burst для destructive remove:

```swift
listNode.transaction(
    deleteIndices: [
        AetherListDeleteItem(index: 3, animation: .particles)
    ],
    insertIndicesAndItems: [],
    updateIndicesAndItems: [],
    options: []
)
```

Реализация через `AetherDustEffectView` (см. `AetherDustEffectLayer.swift`):

- `CAMetalLayer`-backed view.
- Metal compute kernels (init + update).
- Render PSO с premultiplied alpha.
- Texture из CGImage через CGContext + `MTLTexture.replace`.

Шейдеры (`DustEffectShaders.metal`, `loki.metal`, `loki_header.metal`)
скомпилированы в `default.metallib` через
`.process("ListView/DustEffect/Metal")` в Package.swift.

### Опциональный overlay host

Для управления, где рендерится dust effect (default — внутри listNode):

```swift
listNode.particleDissolveOverlayHostNode = overlayNode
```

### AetherDustEffectView

Прямое использование dust effect для произвольного view:

```swift
let dustView = AetherDustEffectView()
view.addSubview(dustView)
dustView.frame = view.bounds

let snapshot = AetherDustEffectView.snapshot(of: targetView)!
dustView.addItem(frame: targetView.frame, image: snapshot, tileSize: 1.0)

dustView.becameEmpty = {
    dustView.removeFromSuperview()
}
```

| Свойство / метод | Назначение |
|---|---|
| `isReady` | Готовность Metal pipeline. |
| `animationSpeed` | Множитель скорости. |
| `animateDown` | Дрейф вниз вместо в стороны. |
| `becameEmpty` | Callback при опустошении (для cleanup'а). |
| `preheat()` | Pre-warm Metal pipeline (компиляция шейдеров). |
| `addItem(frame:image:tileSize:)` | Добавление дезинтегрируемого item'а. |
| `snapshot(of:afterScreenUpdates:)` (static) | Утилита для capture snapshot'а. |

## Callbacks

| Callback | Тип | Назначение |
|---|---|---|
| `displayedItemRangeChanged` | `(AetherListDisplayedItemRange) -> Void` | Изменение visible/loaded range. |
| `visibleContentOffsetChanged` | `(CGFloat) -> Void` | Изменение content offset. |
| `boundaryReached` | `(AetherListBoundaryTriggerContext) -> Void` | Top/bottom edge trigger для paged/infinite loading. |
| `beganInteractiveDragging` | `() -> Void` | Начало interactive drag. |
| `didEndScrolling` | `() -> Void` | Окончание scroll (включая deceleration). |
| `itemTapped` | `(Int) -> Void` | Tap по item (только при `selectionMode == .none`). |
| `swipeActionSelected` | `(Int, AetherListSwipeAction, Bool) -> Void` | Выбор swipe action. |
| `swipeActionsInteractivelyOpened` | `(Int) -> Void` | Swipe actions раскрыты пользовательским жестом. |
| `swipeActionsInteractivelyClosed` | `(Int?) -> Void` | Swipe actions закрыты пользовательским жестом/tap. |

## Boundary loading

```swift
listNode.boundaryTriggerConfiguration = AetherListBoundaryTriggerConfiguration(
    topDistance: 640,
    bottomDistance: 480,
    topItemThreshold: 24,
    bottomItemThreshold: 12,
    triggersDuringProgrammaticScroll: false
)

listNode.boundaryReached = { context in
    switch context.edge {
    case .top:
        loadOlder()
    case .bottom:
        loadNewer()
    }
}
```

`boundaryReached` дедуплицируется по текущему item/range snapshot и
снова срабатывает после ухода от edge или изменения loaded/visible
range. Для paged histories этот API обычно используется вместе с
`virtualContentInsets`, чтобы показать оценочный размер еще не
загруженной истории без spacer rows.

## Item delete animations

```swift
public enum AetherListItemDeleteAnimation: Equatable {
    case fade                                    // alpha → 0 in place
    case slide(AetherListItemOperationDirectionHint)  // slide off + fade
    case scale                                   // scale-down + fade
    case particleDissolve(tileSize: CGFloat)     // Metal dust burst
}

// Shorthand:
AetherListItemDeleteAnimation.particles   // .particleDissolve(tileSize: 1.0)
```

## Public API сводка

### ``AetherListNode``

Новый Texture-native путь для списка. Он использует `ASScrollNode`, управляет
виртуализацией/transactions/sticky headers/reorder/selection сам и оставляет
UIKit только как внутреннюю scroll/gesture boundary. Для новых экранов
используйте `keyboardDismissBehavior`, `topOverscrollBackgroundNode`,
`bottomOverscrollBackgroundNode` и `panVelocity(relativeTo:)`; одноимённые
UIKit escape hatches оставлены только для миграции.

### ``AetherListView``

Deprecated legacy UIKit list. New code should use ``AetherListNode``; legacy
`UIView` escape hatches such as `keyboardDismissMode`,
`particleDissolveOverlayHost`, `topOverscrollBackgroundView`, and
`bottomOverscrollBackgroundView` are kept only for migration.

### ``AetherListItem`` (протокол)

См. таблицу свойств / методов выше.

### ``AetherListItemNode`` (базовый класс)

См. таблицу свойств / методов выше.

### Структуры transaction'а

| Тип | Назначение |
|---|---|
| `AetherListDeleteItem(index:directionHint:animation:)` | Удаление. |
| `AetherListMoveItem(fromIndex:toIndex:directionHint:)` | Перемещение. |
| `AetherListInsertItem(index:previousIndex:item:directionHint:)` | Вставка. |
| `AetherListUpdateItem(index:previousIndex:item:directionHint:)` | Обновление в месте. |
| `AetherListTransactionOptions` | OptionSet (см. таблицу выше). |
| `AetherListScrollToItem(index:position:animated:)` | Scroll-to-item для transaction'а. |
| `AetherListUpdateSizeAndInsets(size:insets:duration:curve:)` | Bundle размера + insets. |
| `AetherListDisplayedItemRange(loadedRange:visibleRange:)` | Текущие ranges. |

## Edge cases

- **`approximateHeight` важен для performance.** При первой загрузке
  list view использует `approximateHeight` для placeholder-layout до
  создания node (chunked layout pass). Сильно неточный
  `approximateHeight` приводит к layout jumps при scroll'е к ранее
  невидимым items.
- **`contentInsetAdjustmentBehavior = .never`.** ListView выставляет
  это автоматически, чтобы insets не дублировались с системным safe
  area handling. При прямом использовании внутри ViewController с
  `safeArea` raskладкой контролируйте `insets` явно через
  `containerLayoutUpdated`.
- **Particle dissolve на iOS Simulator.** Текстуры из CGImage
  загружаются через `MTLTexture.replace` напрямую (а не через
  `MTKTextureLoader` — он капризничает на симуляторе).
- **Re-binding scroll observer при push.** При push нового экрана внутри
  tab'а sticky header'ы корректно re-bind'ятся; layout переcycycles.
- **`transactionOptions: [.synchronous]` выполняется без отложенной queue.**
  Используется только для initial load или критических state changes; для
  типовых mutation'ов use queued path.

## See Also

- <doc:ViewController>
- <doc:NavigationController>
- <doc:ContextMenu>
