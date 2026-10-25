# Аудит AetherModalNavigation — 28 сентября 2026

Вывод: стоит переделать внутреннюю композицию модальной навигации, сохранив её публичный API. Ошибки затрагивают владение view, геометрию, материалы и завершение переходов. Одной настройкой длительности push/pop или радиуса это не исправить.

Изучены приложенная запись (19,70 с, 1206×2622, 60 fps), текущие `Modal`, `NavigationContainer`, навигационный coordinator, стеклянные поверхности и существующие тесты. Исходники реализации не изменялись; приложение и XCTest в рамках аудита не запускались. Ниже отдельно обозначены наблюдения на видео, статически подтверждённые дефекты и гипотезы, требующие воспроизведения.

В рабочей копии уже есть незакоммиченные изменения, в том числе footer-переходов и фона внутренней навигации. Соответствие этой версии бинарнику из записи не установлено. Самих экранов создания плейлиста и выбора треков в `Sources`, `Example`, `Examples`, `Tests` нет; их собственные цвета фона и настройки материалов проверить здесь нельзя.

## Что видно на записи

| Участок | Наблюдение | Что это означает для исправления |
| --- | --- | --- |
| Примерно 00:01,5–00:05,5; контрольный кадр 00:02,80 | При перемещении шторки внутри неё появляется повтор фонового navbar «Все плейлисты» и списка обложек. Повтор смещён вниз примерно на величину верхнего отступа шторки. | Проверять захват фона и координаты material при drag. По изображению нельзя заключить, что создан второй controller. |
| Примерно 00:07,5–00:08,2; кадр 00:07,65 | Push раскрывает резкую вертикальную границу разных поверхностей. У формы, заголовка, входящего экрана и нижней кнопки нет визуально цельного перехода. | Нужны согласованные фон, viewport и общий progress для контента/chrome/footer. |
| 00:08–00:12,5; кадр 00:12,50 | Прозрачный светлый верх экрана выбора резко стыкуется с непрозрачным тёмным списком; сквозь верх остаётся виден экран под модалкой. | Согласовать политику background/material страниц. Часть проблемы может находиться в коде потребляющего приложения. |
| Примерно 00:13–00:15,8 | При следующем вертикальном перемещении повтор фонового экрана возникает и на странице выбора треков. | Дефект связан с общей оболочкой или общими материалами, а не только с формой создания. |
| Примерно 00:16,3–00:16,7 | На pop одновременно видны слои двух страниц, форма просвечивает через верх уходящей страницы; заголовки и нижняя кнопка требуют проверки на синхронность с движением тела. | Проверять промежуточные кадры, отмену и завершение перехода, а не только итоговый top controller. |

Кадры и последовательности:

- [Повтор фонового экрана — 02.80.png](../../Research/ModalNavigationAudit-2026-09-28/frames/02.80.png).
- [Push — 07.65.png](../../Research/ModalNavigationAudit-2026-09-28/frames/07.65.png).
- [Несогласованные поверхности — 12.50.png](../../Research/ModalNavigationAudit-2026-09-28/frames/12.50.png).
- [Последовательность push](../../Research/ModalNavigationAudit-2026-09-28/frames/push.jpg): слева направо, верхний ряд перед нижним; старт 7,3 с, шаг около 0,1 с.
- [Последовательность pop](../../Research/ModalNavigationAudit-2026-09-28/frames/pop.jpg): старт 16,0 с, тот же порядок и шаг.
- [Обзор всей записи](../../Research/ModalNavigationAudit-2026-09-28/frames/overview.jpg): слева направо и сверху вниз, шаг около 0,5 с. Последняя пустая ячейка — заполнение сетки.

## Что исправлять в первую очередь

### 1. Дублирование изображения фона: проверить rasterization и материал

**Наблюдение подтверждено видео; конкретная первопричина пока гипотеза.** На время drag/settle весь `contentView` принудительно получает `shouldRasterize = true`. Внутри находятся навигационный chrome и потенциально другие живые glass/blur views. Начало и конец этой оптимизации совпадают по смыслу с фазами, в которых на видео резко меняется изображение фона.

Код: [beginInteractiveResize](../../Sources/AetherUI/Modal/AetherModalController.swift#L955), [начало drag](../../Sources/AetherUI/Modal/AetherModalPresentationController.swift#L320).

Приоритетная проверка: записать тот же сценарий с отключённой rasterization; затем отдельно убрать масштабирование material вместе с контентом. Логировать активный backend. Проверки разделить, чтобы установить причину. Native `GlassBackgroundView` сам по себе не создаёт копию presenter: он создаёт `UIVisualEffectView(UIGlassEffect)` ([код](../../Sources/AetherUI/Glass/GlassBackgroundView.swift#L1171)).

Apple отдельно описывает зависимость visual effects от окна/compositor и ограничения снимков поддерева, прозрачности предков и масок. Это аргумент против обращения с живым материалом как с обычной кэшируемой картинкой, но документация не доказывает причину именно этого артефакта. [UIVisualEffectView](https://developer.apple.com/documentation/uikit/uivisualeffectview).

### 2. Исправить очистку удалённых страниц

**Подтверждено кодом.** `NavigationContainer.updateControllerViews` ищет view только среди контроллеров нового стека. View уже удалённого контроллера в этот набор не входит и не удаляется. Для пустого стека метод сразу выходит. Внешний `cleanupRemovedChildren` убирает child controller, но не его view.

Это отдельный реальный механизм оставшихся слоёв после `setViewControllers`, replacement и неанимированного pop через внешний navigation controller. Он не доказан как причина повторного изображения presenter на видео. У прямого `NavigationContainer.popController(animated: false)` есть собственное удаление view; проблема относится к пути через `setControllers`.

Код: [сопоставление view со стеком](../../Sources/AetherUI/NavigationController/NavigationContainer.swift#L260), [очистка children](../../Sources/AetherUI/NavigationController/NavigationController.swift#L1846).

Исправление: хранить фактически смонтированные страницы и удалять все, не входящие в разрешённый набор текущего состояния. В покое — одна страница либо ни одной; при переходе — только source и target. Проверять отдельно view hierarchy и controller containment.

### 3. Перестать переносить footer между несовместимыми контейнерами

**Два подтверждённых дефекта.**

Первый: в покое footer стоит у видимого низа шторки с учётом масштаба и клавиатуры. При push/pop его переносят в страницу и ставят на `screen.bounds.height - height`. Страница имеет полную высоту stage2 даже в коротком stage1. Поэтому footer может уйти за нижний clip; при клавиатуре также теряется компенсация. Фон/fade footer остаётся в прежнем host, а сама кнопка двигается со страницей.

Код: [видимый низ footer](../../Sources/AetherUI/Modal/AetherModalController.swift#L771), [перенос в страницу](../../Sources/AetherUI/Modal/AetherModalNavigationController.swift#L206).

Второй: после отменённого interactive pop текущему `footerView` присваивают тот же объект. Setter возвращает его в `footerHost` только при изменении identity. Footer остаётся внутри страницы и теряет sticky-позиционирование. Cleanup специально пропускает текущий footer. Аналогичный случай возможен, если две страницы возвращают один экземпляр footer.

Код: [setter](../../Sources/AetherUI/Modal/AetherModalController.swift#L167), [повторное применение и cleanup](../../Sources/AetherUI/Modal/AetherModalNavigationController.swift#L175), [ветка отмены](../../Sources/AetherUI/NavigationController/NavigationContainer.swift#L491).

Исправление: постоянный modal footer host; source/target footer анимируются внутри него вместе со своими фонами. Завершение и отмена явно восстанавливают владельца, frame, видимость и bottom inset. Footer не должен менять модель координат ради перехода.

### 4. Заменить модель «полная поверхность stage2, scale и внешний clip»

**Модель подтверждена кодом; степень её участия в каждом артефакте требует визуальной проверки.** Сейчас glass и контент имеют размер максимального detent. Изменение ширины масштабирует всю поверхность, а внешний root отрезает лишнюю высоту. В результате видимая граница шторки и граница самого материала не совпадают; в compact-состоянии оптический нижний край материала находится за пределами viewport. Текст, controls и внутренние радиусы масштабируются вместе с ним.

Код: [установка stage2 canvas](../../Sources/AetherUI/Modal/AetherModalPresentationController.swift#L126), [scale и layout](../../Sources/AetherUI/Modal/AetherModalController.swift#L715), [внешний clip](../../Sources/AetherUI/Modal/AetherModalController.swift#L1015).

Исправление: material соответствует реальным bounds шторки; navigation content имеет явно определённый viewport. Если для производительности сохраняется большой canvas, видимый rect и obstruction должны передаваться всем потребителям, включая scroll, footer, hit testing и navigation transitions. Оптимизировать это после корректной базовой реализации и измерений.

### 5. Ввести единую политику скруглений

**Подтверждено кодом.** `AetherModalPresentationController.deviceCornerRadius` всегда возвращает `0`, поэтому низ шторки всегда получает `topCornerRadius`, обычно 34. `NavigationContainer.screenCornerRadius` также всегда возвращает `0`, поэтому ветка скругления движущейся страницы не выполняется. Комментарии о согласовании с устройством не соответствуют реализации.

Код: [внешний радиус](../../Sources/AetherUI/Modal/AetherModalPresentationController.swift#L54), [выбор углов modal](../../Sources/AetherUI/Modal/AetherModalController.swift#L1003), [радиус страницы](../../Sources/AetherUI/NavigationController/NavigationContainer.swift#L70), [неиспользуемая ветка coordinator](../../Sources/AetherUI/NavigationController/NavigationTransitionCoordinator.swift#L271).

Дополнительно при замене Legacy на Liquid пересоздаётся renderer, но `lastCornerSignature` не сбрасывается. При тех же числах новый native material может не получить custom corners: [смена appearance](../../Sources/AetherUI/Modal/AetherModalController.swift#L451), [ранний выход](../../Sources/AetherUI/Modal/AetherModalController.swift#L1038), [замена renderer](../../Sources/AetherUI/Glass/GlassBackgroundView.swift#L1136).

Исправление: явно задать форму compact/expanded modal и правила для движущейся страницы; использовать эту геометрию в root clip, материале и source morph. Не подставлять радиус физического экрана во вложенную шторку автоматически. При замене renderer переустанавливать форму независимо от совпадения чисел.

### 6. Сделать drag и settle непрерывными

**Подтверждено кодом.** При захвате шторки в середине settle сохраняется текущий `dragStartFrame`, но `applyDrag` фактически строит следующий frame от точного stage1 или stage2. Первый новый шаг может перескочить от промежуточной позиции к позиции, вычисленной от конечного detent.

Код: [захват текущей позиции](../../Sources/AetherUI/Modal/AetherModalPresentationController.swift#L207), [расчёт drag](../../Sources/AetherUI/Modal/AetherModalPresentationController.swift#L320).

Ещё один дефект: для единственного разрешённого `.stage1` движение вверх внутри scroll забирается шторкой; scroll recognizer отменяется, contentOffset сбрасывается вверх, а сама шторка лишь делает rubber-band. Длинный контент нормально не прокручивается. [Арбитраж](../../Sources/AetherUI/Modal/AetherModalPresentationController.swift#L299), [отмена scroll](../../Sources/AetherUI/Modal/AetherModalPresentationController.swift#L232).

Исправление: продолжать движение от фактического progress/frame и скорости прерванной анимации. Передавать жест scroll, когда дальнейшее расширение недоступно. Явно определить совместимость вертикального drag, горизонтального pop и клавиатурных изменений.

### 7. Объединить жизненный цикл навигационного перехода

**Риск, видимый в коде; конкретное проявление требует воспроизведения.** Состояние разделено между навигационным стеком, container, shared navbar, временными bars, modal flags и `DispatchQueue.main.async`. Установка обычного перехода защищена `isInstallingTransition`; интерактивная ветка вызывает layout и добавляет view до назначения coordinator без такой защиты. Реентрантный layout может увидеть переход как ещё не начавшийся.

Код: [защищённая установка](../../Sources/AetherUI/NavigationController/NavigationContainer.swift#L282), [интерактивная установка](../../Sources/AetherUI/NavigationController/NavigationContainer.swift#L432), [отложенное применение footer](../../Sources/AetherUI/Modal/AetherModalNavigationController.swift#L148).

Исправление: один transition context с source/target, исходной и целевой геометрией, progress и исходом commit/cancel. Тело, заголовок, кнопки, search accessory и footer получают один progress. Завершение синхронно фиксирует стек и очищает временные view. Операции во время перехода имеют определённый порядок. Сам факт существования временных navbar не является ошибкой; ошибка — нарушение владения, видимости или cleanup.

## Предлагаемая структура переделки

Сохранить `AetherModalNavigationController`, `Config`, push/pop/setViewControllers и контракт `AetherModalContent` для потребителей. Внутренние обязанности разделить следующим образом:

```text
Modal root — видимые bounds и единая форма шторки
├── Material surface — реальная геометрия шторки
├── Navigation viewport — 1 страница в покое, 2 при переходе
├── Navigation chrome — title, buttons, search/accessory
├── Footer host — постоянный владелец footer и его фона
└── Grabber

Sheet geometry → bounds, viewport, corners, keyboard/bottom obstruction
Navigation transition context → source, target, progress, commit/cancel
Gesture arbitration → scroll / detent drag / horizontal pop
```

Это схема обязанностей. Конкретный z-order материала и элементов нужно проверить на всех backend. Живые материалы не следует включать в общую rasterization переносимого контента. Цвета страниц должны соответствовать явному контракту: прозрачная страница показывает предусмотренную поверхность modal, а не случайные остатки другой страницы или второго фонового слоя.

В текущей рабочей копии уже убрано принудительное `.clear` у корня внутренней навигации. Это может скрывать часть старого просвечивания, но не устраняет несогласованные viewport, lifecycle footer и оставшиеся view. Изменение одного backgroundColor не является полной переделкой.

## Порядок работ и критерии готовности

1. Создать минимальный демонстрационный сценарий: контрастный presenter, форма с footer, страница со scroll/search, два detent. Текущий Example не демонстрирует `AetherModalNavigationController`.
2. Изолировать повтор фона: отдельные A/B прогоны rasterization, масштабирования material, native/других backend. Сохранить запись до/после на том же устройстве.
3. Исправить view cleanup, footer ownership и восстановление после cancel. Эти ошибки определяются кодом и не зависят от гипотезы о backdrop.
4. Перевести shell, material и navigation viewport на одну геометрию; согласовать corners, safe area и keyboard obstruction.
5. Перевести push/pop и detent interruption на явное состояние переходов; убрать зависимость корректности от следующего прохода main queue.
6. Проверить весь сценарий записи и промежуточные кадры, затем измерять стоимость layout/render и добавлять только подтверждённо безопасные оптимизации.

| Проверка | Ожидаемый результат |
| --- | --- |
| Медленный drag и прерывание settle в обе стороны | Нет повторного изображения presenter, скачка позиции, отставания материала и границ |
| Push/pop на stage1 и stage2 | Согласованное движение страниц/chrome; footer остаётся у видимого низа |
| Interactive pop: завершение и отмена на разных progress | Корректные стек, superview, frame, insets и доступность controls |
| Footer→нет footer, разные высоты, один общий footer | Нет пропадания, зависшего fade и неверного владельца |
| Push/pop при клавиатуре и её закрытие | Footer не уходит под клавиатуру, нет двойных inset и скачка layout |
| Неанимированный pop, replacement, пустой стек | Удалённые view отсутствуют, число смонтированных страниц соответствует состоянию |
| Только `.stage1`, длинный список | Контент доступен обычной прокруткой |
| Быстрые последовательные переходы и dismiss во время движения | Нет зависшего coordinator, rasterization или временных view |
| Поворот/resize и смена Legacy↔Liquid | Материал, clip, corners и viewport остаются согласованными |
| Поддерживаемые версии iOS и backend | Согласованный результат без привязки корректности к одному renderer |

Существующие [AetherModalNavigationContentTests](../../Tests/AetherUITests/AetherModalNavigationContentTests.swift#L7) проверяют базовые переходы, footer и задержанные display frames. Основной анимированный footer-сценарий использует полную высоту; отсутствуют критические проверки compact viewport, отмены interactive pop, hierarchy после удаления, settle interruption и реального backdrop. Эти пробелы объясняют, почему проверки конечного состояния могут не ловить видимые в ролике нарушения.

Переделку можно считать завершённой после воспроизведения исходного сценария без артефактов, проверки отмены/прерывания и подтверждения инвариантов hierarchy. Само прохождение текущих тестов для этого недостаточно.
