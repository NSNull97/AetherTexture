# AetherModalNavigation: новая реализация

Этот документ описывает изменения после [аудита записи](README.md). Сам аудит сохранён как описание исходного состояния; его номера строк относятся к коду до переделки.

## Геометрия и материалы

Размер материала, navigation viewport и контента теперь равен фактическим `view.bounds` шторки. Изменение detent обновляет layout: размер текста и controls не меняется через `scale`, а короткая шторка не обрезает невидимый stage2 canvas. Внутренняя навигация больше не замораживает layout на время drag.

Живой материал находится отдельным sibling позади navigation content. Контент не помещается в `UIVisualEffectView.contentView` общей поверхности и не переводится в `shouldRasterize` при вертикальном жесте. Убирается композиция, которая была главным кандидатом на повтор presenter из видео. Код не предполагает, что screenshot поддерева способен сохранить внешний backdrop.

Внутренняя навигация получает согласованный фон страниц и радиус перехода от modal. View hierarchy очищается после stack replacement, неанимированных операций, завершения и отмены переходов: в покое остаётся только текущая страница; во время перехода — source и target.

Вертикальный drag начинается от реально показанного frame, в том числе при перехвате незавершённой анимации. Геометрия не перескакивает на начало detent. Если push/pop начинается во время изменения высоты, шторка приостанавливается на текущем frame и продолжает движение после навигации. Запросы detent во время перехода сохраняются; при нескольких запросах побеждает последний. Временные заголовки Texture готовы к показу до скрытия основного заголовка.

## Углы

`Config.topCornerRadius` остаётся верхним радиусом. Добавлены необязательные `bottomCornerRadiusStage1` и `bottomCornerRadiusStage2`:

- Для stage1 значение `nil` использует `topCornerRadius`.
- Для stage2 значение `nil` использует `topCornerRadius`, если `bottomInsetStage2 > 0`; при примыкании к низу экрана — `0`.
- Нижний радиус интерполируется вместе с detent progress. Радиусы ограничены половиной меньшей стороны поверхности.

Одна геометрия применяется к root, живому native material и source-morph переходу. Она не зависит от приватного радиуса физического экрана. При смене renderer форма устанавливается повторно.

## Footer и конфигурация страниц

Footer остаётся в modal host. Для перехода используются source/target slots; в каждом footer движется вместе со своим фоном и fade. Footer не переносится в полноразмерную view страницы. Отмена перехода восстанавливает исходную конфигурацию синхронно, включая случай, когда обе страницы возвращают один экземпляр footer.

`AetherModalNavigationController.contentConfigurationMode` задаёт владение конфигурацией:

| Режим | Поведение |
| --- | --- |
| `.perScreen` — по умолчанию | Каждая видимая страница через `AetherModalContent` задаёт footer и primary scroll view. Не требуется, чтобы именно root реализовывал протокол. Страница без footer освобождает его место. |
| `.manual` | Владелец modal сам задаёт `footerView`, `footerHeight`, `primaryScrollView` и остальные параметры общего footer. |

В `.perScreen` footer inset относится к конкретной странице. Source и target получают свои insets до начала перехода; окончание анимации не должно внезапно сдвигать контент из-за общего footer inset.

Переключение режима обновляет отступы сразу; если идёт push/pop, прежнее владение сохраняется до его завершения. Пересечение с клавиатурой пересчитывается в текущих координатах шторки. При смене primary scroll view вклад клавиатуры снимается со старого scroll view и переносится в новый, сохраняя пользовательский базовый inset.

### Миграция

Обычные экраны с `AetherModalContent` продолжают использовать тот же протокол и публичные push/pop методы. Если подкласс modal вручную конфигурирует общий для всего стека footer, явно включите `.manual` до загрузки view:

```swift
final class ComposerModal: AetherModalNavigationController {
    init(root: AetherViewController) {
        super.init(rootViewController: root)
        contentConfigurationMode = .manual
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // footerView, footerHeight и primaryScrollView принадлежат этому modal.
    }
}
```

Если код страницы рассчитывал на неизменную высоту stage2, замените этот расчёт на актуальный `ContainerViewLayout.size` и переданные insets. Удалите собственную компенсацию масштаба modal. Не добавляйте `modalFooterHeight` второй раз к уже полученным `additionalInsets`.

## Демонстрация

В Example: **Components → Modal Navigation → Create**. Presenter содержит контрастные обложки и подписи, чтобы выявлять повтор фона. Шторка содержит форму с текстовыми полями, footer и переход к списку треков с настоящим `AetherSearchController`.

- `Resize` переключает detent на обеих страницах.
- `Add tracks` находится в начале формы и доступен в короткой шторке.
- `Done` возвращает к форме; системная кнопка Back и жест от левого края используют тот же стек навигации.
- Для проверки отмены начните жест Back и верните палец к левому краю перед отпусканием.
- Поле названия и поиск позволяют проверить клавиатуру и footer.

Аргументы запуска:

```text
--modal-navigation-demo
--modal-navigation-demo --modal-navigation-stage1
--modal-navigation-demo --modal-navigation-detail
--modal-navigation-demo --modal-navigation-detail --modal-navigation-stage1
--modal-navigation-demo --modal-navigation-dark
--modal-navigation-demo --modal-navigation-dark --modal-navigation-legacy
```

В Debug `--modal-navigation-demo --modal-navigation-autoplay` выполняет последовательность через публичные методы: compact → push → expanded → pop → push → compact → pop → expanded. Это воспроизводит обычные анимации и подходит для покадрового просмотра записи; жесты и отмена interactive pop требуют отдельной проверки.

`--modal-navigation-dark` включает тёмную тему presenter и modal; `--modal-navigation-legacy` фиксирует Legacy для modal. Эти аргументы можно сочетать с выбором страницы, detent и autoplay.

Демонстрация не обращается к сети и не сохраняет данные пользователя. Кнопка Save закрывает пример.

## Проверка

Example собран через Xcode 27, scheme `Example`, Debug, iOS Simulator. Визуальная проверка выполняется на отдельном iPhone 18 Pro / iOS 27.0. Контрольные кадры:

| Страница | Stage1 | Stage2 |
| --- | --- | --- |
| Форма | [Короткая шторка](after-stage1-form.png) | [Полная шторка](after-stage2-form.png) |
| Список и поиск | [Короткая шторка](after-stage1-detail.png) | [Полная шторка](after-stage2-detail.png) |

Дополнительно проверены тёмные состояния: [native compact form](after-dark-stage1-form.png), [native expanded detail](after-dark-stage2-detail.png) и [Legacy compact detail](after-legacy-dark-stage1-detail.png).

Записан и просмотрен покадрово [тёмный native autoplay push/pop и смены detents](after-autoplay.mp4). В последовательности есть push и pop в обоих размерах шторки; footer перемещается вместе с соответствующей страницей и возвращается в постоянный host. Промежуточные кадры не показывают повтор presenter или прежний вертикальный шов материала. Из записи убрана перезагрузка Example, а последний кадр удерживается 1,5 секунды для просмотра.

В этих состояниях видна одна страница, footer остаётся у видимого низа, controls сохраняют размер, а текст presenter не повторяется внутри содержимого. Автоматические проверки geometry, stack/view ownership, footer и переходов выполняются отдельно. Отсутствие дефекта на simulator не заменяет сравнение исходного сценария на физическом устройстве с тем же renderer; интерактивный drag, его прерывание и отмена back-жеста не проверяются одним autoplay.

### Результаты автоматических проверок

- Example собран после финальных изменений (`BUILD SUCCEEDED`).
- iOS 27: 99 регрессионных тестов прошли — modal, geometry, appearance, lifecycle навигации, title/back buttons, layout provider, pending updates, edge effects и pager.
- После последней доработки координации и переключения footer mode: повторно прошёл целевой набор из 31 теста на iOS 27, включая два новых сценария mode switching.
- iOS 18.4: 32 целевых теста прошли — те же modal/geometry/lifecycle сценарии и тест очереди detent. Это дополнительно проверяет путь углов без `UICornerConfiguration`.
- `git diff --check` не выявил ошибок форматирования.

Более широкий прогон, включавший TabBar, обнаружил 9 assertion failures в трёх существовавших тестах. Сверка с `HEAD` подтверждает прежние расхождения: `testBottomBarVisibilityUsesFixedProductionTimeline` и `testHidesBottomBarPushDelaysOnlyTheFixedVisualClock` ожидают duration `0.28` / delay `0.06`, тогда как реализация уже использует `0.34` / `0`; `testLiveStyleSwitchWhileExpandedKeepsMaterialHiddenAndRetargetsDock` ожидает accessory height `58`, а установленный минимум — `56`. Эти несвязанные тесты и константы в рамках переделки modal не менялись.

SwiftPM XCTest выполняется без application host: проверка реального `present(...)` и системного gesture pipeline требует app-hosted/UI-тестов. Поэтому queue-тест проверяет владение запросами напрямую, geometry-тесты — прерывание движения, а тесты навигации — interactive completion/cancellation через recognizer callbacks. Они не выдаются за проверку UIKit-презентации или пальцевых жестов на устройстве.
