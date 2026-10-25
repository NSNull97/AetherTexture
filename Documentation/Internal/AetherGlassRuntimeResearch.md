# Исследование Liquid Glass: iOS 26 / 27 и AetherUI

Дата: 14 сентября 2026. Исследуемый код зафиксирован SHA в `Research/GlassRuntime/results/*-environment.json`.

## Что это исследование даёт

У AetherUI уже есть основа: публичное стекло, контейнеры слияния, собственный blur, приватная линза, SDF-преломление и сложные переходы. Однако системный материал имеет гораздо больше независимых составляющих, чем используется сейчас. Самые полезные находки — приватный дескриптор `_UIViewGlass`, полноценные фильтры `glassBackground` / `glassForeground`, составной `CASDFKeyFillHighlightEffect` и реальные анимации этих параметров.

В исходном состоянии кода обнаружены две конкретные проблемы: не подключённые к UIKit значения `lumaMin/lumaMax` и пропуск смены `regular/clear` при одинаковых tint и interactivity. Прямое сравнение симуляторов также показало, что **существующий на обеих версиях adaptive-luminance setter меняет материал на 26, но не даёт этого результата в проверенном regular-пути 27**. Ниже эти факты отделены от идей расширения.

Эта работа добавляет отдельное приложение для симулятора, результаты экспериментов и документацию; исходники фреймворка я здесь не изменял.

**Состояние рабочего дерева при завершении:** параллельно появились `NativeGlassDescriptorAdapter.swift`, учёт `requestedNativeEffectStyle` / `appliedNativeEffectStyle` и descriptor options в `GlassBackgroundView`, а также изменения context menu. Они не входят в эту исследовательскую правку. Поэтому пункты про отсутствующий adapter и style guard ниже описывают исходный срез и задачу для интеграции; соответствующая работа уже началась отдельно. Её полноценная проверка не выполнялась этим стендом. `EffectSettingsContainerView` при последней проверке оставался прежним. См. [зафиксированный статус исходников](Research/GlassRuntime/results/findings-source-status.json).

## Доказательства и охват

Обозначения:

- **SDK** — декларация в установленном SDK, с availability и расположением.
- **Runtime** — класс, метод, тип аргумента или протокол найден в работающем процессе.
- **Опыт** — объект создан, параметр вызван и результат проверен в дереве слоёв / фильтров; для ряда сценариев также на скриншотах.
- **Кандидат** — символ существует, но его полезное поведение ещё не подтверждено.

Основной набор iOS 27: SDK 27.0, runtime **27.0 (24A434)**, arm64, iPhone 18 Pro, область окна 402 × 874 pt. В каждом запуске просканировано 40 615 загруженных Objective-C-классов; по широкому фильтру имён сохранено 395 классов, 27 протоколов и 291 совпадение по селекторам. Часть совпадений относится к соседним технологиям и не является API интерфейсного стекла.

Для сравнения скачан и установлен официальный arm64 runtime **iOS 26.0 (23A343)**. Создан отдельный симулятор iPhone 17 Pro с такой же областью окна **402 × 874 pt**. На 26 выполнены те же 18 сценариев в обеих темах; сохранены 321 класс, 32 протокола и 260 selector hits из 54 752 загруженных классов. Большая общая численность загруженных классов не означает больше glass API: состав зависимостей у runtime различается.

Обе версии запускали один и тот же код, собранный **SDK 27, deployment target 26.0**. Отдельная сборка SDK 26 не выполнялась. Размеры образцов и контент совпадают; модели устройств различаются, поэтому это не performance benchmark.

Загружались UIKit, QuartzCore, SwiftUI, SwiftUICore, MaterialKit, CoreMaterial, DesignLibrary, AnimationKit, RenderBox, BaseBoardUI. Сохранены соответствующие результаты `dlopen`, свойства, ivars, методы экземпляров и классов, настоящие Objective-C type encodings. Из шести образов прочитаны относящиеся к теме строки `__cstring`.

Для iOS 27 выполнены **18 сценариев × 2 темы**, получены параметры настоящих фильтров, дескрипторы CASDF и отдельный снимок анимаций при `effect = nil → UIGlassEffect`. Приложение компилирует без изменений класс `EffectSettingsContainerView`, извлечённый из текущего `GlassUtils.swift`, для проверки экспорта свойств в Objective-C.

Артефакты:

- [Код стенда](Research/GlassRuntime/GlassProbe.m), [запуск](Research/GlassRuntime/run.py), [анализ](Research/GlassRuntime/analyze.py).
- [Полный каталог iOS 27](Research/GlassRuntime/RuntimeCatalog-ios27.md), включая сигнатуры и протоколы.
- [Сводка iOS 27](Research/GlassRuntime/results/ios27-summary.json), [тёмная тема](Research/GlassRuntime/results/ios27-dark-summary.json).
- [Дерево слоёв и параметры](Research/GlassRuntime/results/ios27-hierarchy.json), [живые анимации](Research/GlassRuntime/results/ios27-materialization.json).
- [Метаданные классов](Research/GlassRuntime/results/ios27-inventory.json), [отдельные объекты](Research/GlassRuntime/results/ios27-objects.json), [строки образов](Research/GlassRuntime/results/ios27-strings.json).
- [206 совпадений в заголовках и Swift interfaces SDK](Research/GlassRuntime/results/sdk27-api-index.json).
- Скриншоты: [светлая тема](Research/GlassRuntime/results/ios27-grid.png), [тёмная тема](Research/GlassRuntime/results/ios27-dark-grid.png).
- iOS 26: [каталог](Research/GlassRuntime/RuntimeCatalog-ios26.md), [сводка](Research/GlassRuntime/results/ios26-summary.json), [светлая тема](Research/GlassRuntime/results/ios26-grid.png), [тёмная тема](Research/GlassRuntime/results/ios26-dark-grid.png).
- [Машиночитаемое сравнение 26 → 27](Research/GlassRuntime/results/ios26-to-ios27-diff.json) и [скрипт сравнения](Research/GlassRuntime/compare.py).

Это широкий срез доступного runtime, а не утверждение, что восстановлен весь закрытый код Apple. Чистые Swift-типы, невызванные пути, shader implementation и незагруженные сервисы не исчерпываются `objc_copyClassList`.

## Подтверждённые различия 26.0 → 27.0

| Механизм | iOS 26.0, 23A343 | iOS 27.0, 24A434 |
|---|---|---|
| `glassBackground` / `glassForeground` | Оба существуют и участвуют в рендере | Оба существуют; это не новые имена фильтров 27 |
| `CAFilter.filterTypes` | 42 типа | Те же 42 типа |
| Непустые параметры живого `glassBackground`, объединение по образцам | 54 ключа | 70 ключей |
| Непустые параметры `glassForeground` | 12 ключей | 12 ключей |
| Blur fill / ring shadow / встроенные key-fill highlight inputs | В этих живых фильтрах не наблюдались | Появились соответствующие группы параметров |
| `inputBlurDistance4` / `inputBlurOpacity4` | Наблюдались в фильтрах | В исследованных фильтрах не заданы |
| `CASDFLayer.gaussianRadius` | Нет в собственной таблице класса | Есть getter/setter и property |
| `CASDFKeyFillHighlightEffect` | Есть | Есть; добавлены diffuse height/amount/spread scale |
| `_UIViewGlass.setAdaptiveFixedLuminance:` | В опыте 0/1 меняют тон материала | Метод существует, но 0/1 оставляют одинаковые inputs regular |
| Setter `_flexVariant` | **`set_flexVariant:`** | **`_setFlexVariant:`** |
| `_UIViewGlass.setFixedBackgroundColor:` | Не найден; сценарий не применяет настройку | Найден; фон заменяется фиксированным заполнением |
| `_UIViewGlass.systemTintAmount` | Не найден | Возвращает NSNumber 0.5; encoding возврата **`@`**, не `double` |
| `_UIViewGlassGroup` | `groupBackdrops` | Дополнительно `foreground` и `_smoothness` |
| `_UILiquidLensView.liftedContentView` | **strong** | **weak** |
| `_UILiquidLensView.liftProgress` | Readonly, внутренний AnimatableFloat | Read/write, `_UIDebouncingAnimatableFloat` |
| `_UILiquidLensView` дополнительные методы | Нет `restingBorderColor`, `forceUnliftWithoutAnimations` | Методы есть |
| `_UIFlexInteraction` | `layerToFlex`, `flexPresentationModifier`, `modifierIsAttached`, `isActive` в таблице | Эти методы отсутствуют; добавлены `supportsMultiLayer`, `isMatchingRadii`, glow-corner configuration |
| `AnimationKit.LiquidMorphAnimation` | В загруженном процессе не найден | Найден вместе с системой timeline / milestone / lensing |
| Materialization после очистки `nil` | В снимке только 6 служебных match key paths | 68 key paths light / 66 dark, включая оптику |
| Materialization после очистки `UIVisualEffect()` | 67 key paths, включая оптику | Те же 68 light / 66 dark |
| Render host | `_UIMultiLayer` вокруг `view.layer` | Та же принципиальная особенность; это не только изменение 27 |

Методные diff основаны на `class_copyMethodList`, то есть на **собственных реализациях класса**. Появление override не равно появлению API впервые; например, `description` мог наследоваться. Полные 48 изменившихся таблиц сохранены в diff. Числа «только до/после» также включают переименованные Swift-классы и различия загруженных зависимостей.

Для одинакового regular 120.67 × 90 pt в light наблюдались:

| Параметр | 26 | 27 |
|---|---:|---:|
| Inner refraction amount | −60 | −45 |
| Outer refraction amount | 18 | 22.5 |
| Blur radius | 2.3333 | 5 |
| Shadow opacity | 0.40625 | 0.1375 |
| Ring shadow opacity | Не задан | 0.06 |

Это измеренные параметры выбранной среды, не универсальная формула миграции. Сравнивать только opacity тени ошибочно: в 27 появился дополнительный ring-shadow вклад.

У AetherUI `LiquidLensView` уже удерживает собственный `liftedContainerView` через `private let`, поэтому смена strong→weak у системного свойства **не доказывает утечку или исчезновение контента в нашем коде**. Но она существенна для любой новой обёртки, которая полагается на удержание объекта линзой.

Особенно полезная подтверждённая деталь: существующий обход `UIVisualEffect()` вместо `nil` на iOS 26.0 в `GlassBackgroundView.applyNativeGlassEffect` следует **сохранить**. Это не исторический мусор: отдельный опыт подтвердил появление optical animations после пустого эффекта. Поведение 26.1 этим сравнением не проверялось.

## 1. Главный приватный вход: `_UIViewGlass`

**Runtime + опыт, iOS 27.** У публичного `UIGlassEffect` есть приватные:

```objc
- glass;                         // returns _UIViewGlass
+ effectWithGlass:(id)glass;     // returns UIGlassEffect
- style;                         // NSInteger
- setStyle:(NSInteger)style;
```

Это позволяет получить системный дескриптор из публичного эффекта, настроить его и передать обратно фабрике. Не нужно выбирать непроверенный целочисленный `variant` через `initWithVariant:`.

| Возможность `_UIViewGlass` | Проверка на iOS 27 | Применение в AetherUI |
|---|---|---|
| `setExcludingShadow:` | Обе shadow opacity в `glassBackground` становятся 0 | Убрать системную тень там, где уже есть наша; избежать двойной тени |
| `setExcludingPlatter:` | Убирает `glassBackground` у образца | Разделить подложку и прочие части материала |
| `setContentLensing:` | Добавляет настоящий `glassForeground` | Преломление текста / иконок / содержимого во время morph |
| `setFixedBackgroundColor:` | В опыте с black исчезает backdrop, появляется заполнение CASDF | Специальный непрозрачный материал; не путать с обычным tint |
| `setExcludingForeground:` | Свойство читается обратно; обычный regular и без этого не имел foreground-фильтра | Проверить вместе с включённым content lensing |
| `setExcludingControlLensing:` / `setExcludingControlDisplacement:` | Setter вызван, но статический regular сохраняет те же параметры backdrop | Нужен тест активного control / lift; обещать отключение общего преломления нельзя |
| `setAdaptiveFixedLuminance:` | Значения 0 и 1 не изменили параметры regular ни в light, ни в dark | Не считать готовым исправлением нашей luma |
| `setAdaptive:`, `setAdaptiveInitialLuminance:`, `setAdaptiveStyle:` | Методы найдены; семантика не проверена | Исследовать адаптивную контрастность отдельно |
| `setSmoothness:` | 40 сохраняется; одиночный regular сохраняет те же параметры фильтра | Проверить два сближающихся элемента, а не один прямоугольник |
| `setAllowsGrouping:` | Значение сохраняется; одиночный элемент не доказывает эффект группировки | Отделять поверхности и группы backdrop |
| `setBackdropGroupName:` | Метод и свойство найдены | Управляемая общая выборка фона для разных элементов |
| `setBoostWhitePoint:` | Значение сохраняется; видимого изменения regular filter inputs нет | Кандидат, не проверенная настройка яркости |
| `setFlexible:`, `_setFlexVariant:` | Сигнатуры найдены | Реакция на касание, интеграция с `_UIFlexInteraction` |
| `setControlTintColor:`, `setSharpTinting:`, `setMeshed:` | Runtime | Отдельные контрольные / mesh-пути |
| `setHighlightsDisplayAngle:`, `setIntelligence:` | Runtime | Направление бликов и Siri / intelligence-пути |
| `identifier`, `subvariant`, `debugIdentifier` | Runtime | Диагностика и идентичность материала |
| `+systemTintAmount` | Возвращает **0.5** в исследованной конфигурации iOS 27 | Системная настройка плотности; нельзя превращать это наблюдение в константу |

Важная особенность: getter `contentLensing` в опыте не отразил результат setter, хотя после `effectWithGlass:` появился `glassForeground`. Некоторые compatibility getters не дают полного представления о новом внутреннем материале. Оценивать результат следует по рендеру и реально установленным параметрам.

На iOS 26 adaptive fixed luminance работает иначе: в light значение 0 меняет face black/white и делает поверхность тёмной; в dark значение 1 меняет материал в обратную сторону. На iOS 27 оба значения сохраняют исходные filter inputs своей темы. Существование selector недостаточно для включения этой capability.

В описании `_UIViewGlass` виден мост в `DesignLibrary.GlassMaterialProvider.Configuration` и SwiftUI glass. Это подтверждает наличие общего описания материала, но само по себе не раскрывает устойчивый Swift ABI для прямых вызовов DesignLibrary.

## 2. Полноценные фильтры стекла

**Опыт, iOS 27.** Список `CAFilter.filterTypes` содержит 42 типа, среди них:

`glassBackground`, `glassForeground`, `chromaticAberration`, `chromaticAberrationMap`, `displacementMap`, `variableBlur`, `gaussianBlur`, `luminanceMap`, `luminanceCurveMap`, `vibrantColorMatrix`, `vibrantColorMatrixSourceOver`.

В живом дереве собраны **70 разных input keys `glassBackground`** и **12 input keys `glassForeground`**. Они полностью сохранены в JSON, вместе со значениями. Это не перечень гипотетически допустимых KVC-ключей: это непустые значения уже настроенных UIKit фильтров.

| Подсистема | Основные поля |
|---|---|
| Внутреннее и внешнее преломление | `inputInnerRefractionAmount/Height`, `inputOuterRefractionAmount/Height`, `inputRefractionDistance0/1`, `inputRefractionOpacity` |
| Пространственное размытие | `inputBlurRadius`, `inputBlurDistance0…3`, `inputBlurOpacity0…3`, `inputBlurFillBlurRadius` |
| Примесь окружающих цветов | `inputBleedAmount`, `inputBleedHeight`, `inputBleedDistance0/1`, `inputBleedBlurRadius`, `inputBleedOpacity`, `inputBleedColorMatrix*`, `inputBleedDarkenBlend` |
| Тон поверхности | `inputFaceColorMatrixBlack/White/Saturation/FillColor/MaxLuma/MaxLumaSDR`, `inputFaceOpacity` |
| Обычная и кольцевая тень | `inputShadow*`, `inputRingShadowOpacity/BlurRadius/Offset/StrokeWidth/Mask` |
| Составные блики | `inputKeyFillHighlightAmount/Angle/ColorBias/EffectOffset/Height/Spread/SpreadSDR` |
| SDR и диапазон яркости | `inputSDRHoldingTone*`, `inputSDRShadowOpacity`, `inputClamp`, `inputClampPreserveHue`, `inputMaxHeadroom` |
| SDF-источник | `inputSourceSublayerName`, в исследованных системных слоях обычно `@0` |
| Преломление foreground | `inputRefractionAmount/Height/Offset`, `inputEdgeStart/End/OpacityStart/OpacityEnd` |
| Цветовая аберрация foreground | `inputAberrationAmount/Angle/Height/Offset` |

Пример regular 120.67 × 90 pt, light, iOS 27: inner amount −45, outer amount 22.5, blur radius 5, ring shadow opacity ≈0.06, shadow opacity ≈0.1375. При `setExcludingShadow:YES` обе opacity становятся 0. При `setContentLensing:YES` появляется foreground с refraction amount −16 и aberration amount −5.

Это **наблюдения для одной геометрии и среды**, не предлагаемые дефолты AetherUI. Размер, форма, тема, системная настройка стекла, accessibility и OS build влияют на результат.

В текущем [LensSDFFilter](../../Sources/AetherUI/ContextMenu/LensTransition/LensSDFFilter.swift) используется `gaussianBlur + displacementMap` и один `CASDFGlassDisplacementEffect`. Это полезная оптическая деформация, но она не включает всю перечисленную систему. Ближайшее расширение — отдельное управление системным material descriptor и foreground lensing, а не замена всех фильтров нашими константами.

У `CAFilter` неизвестный KVC-ключ может возвращать `nil` без исключения. Поэтому «KVC не упал» не доказывает поддержку. Отдельно созданные filters могут также возвращать `nil`, пока UIKit ещё не установил значения. Строки `glass` и `sdf` нельзя автоматически считать именами фильтров только из-за похожих названий классов.

## 3. CASDF: что есть помимо displacement

**Runtime; часть эффектов также найдена в живом дереве.**

| Класс | Существенные свойства / назначение |
|---|---|
| `CASDFLayer` | `effect`, `smoothness`, `gaussianRadius`, `effectOffset`, `mergeElements` |
| `CASDFElementLayer` | `mode`, `operation`, `gradientOvalization`, `contentsZeroValueDistance`, `contentsOneValueDistance`, `hitTestsAsFill` |
| `CASDFGlassDisplacementEffect` | `height`, `curvature`, `angle`, **`maskOffset`** |
| `CASDFGlassHighlightEffect` | `color`, `height`, `angle`, `spread`, `amount`, `curvature`, `global` |
| **`CASDFKeyFillHighlightEffect`** | Независимые key/fill color, height, angle, spread, amount; scale/offset; diffuse height/amount/spread; curvature |
| `CASDFShadowEffect` | Тень SDF, включая offset / radius / invert; свойства перечислены в каталоге |
| `CASDFFillEffect` | Заполнение фигуры |
| `CASDFGradientEffect`, `CASDFGradientContourEffect` | Градиентное заполнение и контуры |
| `CASDFOutputEffect` | `minimum`, `maximum`; в живом стекле используется как источник поля расстояний |
| `CASDFVisualizationEffect` | Диагностическая визуализация |
| `CASDFGenerator` | `generateSDFWithRequest:forImage:` |
| `CASDFGeneratorRequest` | bit depth, padding, maximum distance, gradient smoothing; `requestForEffect:` / `requestForEffects:` |

Наш SDF-путь пока не даёт отдельной настройки составных бликов, SDF-тени, полевого объединения нескольких элементов, mask offset и генерации SDF из произвольного изображения. Это реальные направления расширения. Для произвольного контура одного `cornerRadius` недостаточно.

На iOS 27 в обычном системном regular виден **`CASDFKeyFillHighlightEffect`**, а не только более простой `CASDFGlassHighlightEffect`. Простая обводка и одна светлая дуга не описывают этот материал полностью.

## 4. Где находится рендер

**Опыт, iOS 27.** UIView hierarchy остаётся обычной: `UIVisualEffectView → contentView → UILabel`. Сам `view.layer` при этом не содержит системный backdrop в своих потомках.

В исследованных образцах реальная структура слоёв включала:

```text
_UIMultiLayer                         ← view.layer.superlayer
  … CALayer / UIVisualEffectView layer / content
  … CABackdropLayer
      filter: glassBackground
      CASDFLayer (@0)
        CASDFOutputEffect
        CASDFElementLayer(s)
  … CASDFLayer (SDF)
      CASDFKeyFillHighlightEffect
      CAPortalLayer
  … optional CALayer + glassForeground
```

Точная вложенность сохранена в `renderContainer` каждого образца. Это схема, а не контракт количества уровней.

Следствие для будущих приватных extensions: поиск только по `subviews`, классу `_UIVisualEffectBackdropView` или потомкам `nativeView.layer` может не найти рендер. Нельзя после такой неудачи делать вывод, что native glass не активен. Нужен capability-aware resolver с проверкой владельца материала, без произвольного захвата соседнего backdrop.

Это не утверждение о подтверждённой поломке текущего context-menu: сейчас surface distortion ставится на внешний `finalMenuGlassSurfaceView.layer`. Однако при переносе этой деформации непосредственно на системный backdrop важна именно такая структура.

## 5. Анимация появления и Liquid Morph

**Опыт.** При публичной анимации `effect = nil → regular` зафиксировано 68 различных animation key paths во всём окне. Часть — постоянные binding/match-анимации SDF; оставшиеся включают material inputs:

`filters.glassBackground.inputInnerRefractionAmount`, `inputOuterRefractionAmount`, `inputBleedAmount`, `inputBlurRadius`, `inputFaceOpacity`, `inputRingShadowOpacity`, `inputShadowRadius`, а также `effect.keyHeight`, `effect.fillSpread`, `effect.diffuseAmountScale`, `effect.curvature` и opacity.

Это прямое свидетельство согласованной materialization нескольких оптических составляющих. Снимок одной фазы не является полной кривой, подтверждением interruptibility или измерением задержки.

Сравнение двух способов очистки сохранено отдельно: `*-materialization.json` и `*-materialization-empty.json`. iOS 26 после `nil` дал 6 служебных match key paths, после пустого эффекта — 67, включая параметры материала. iOS 27 в light дал 68 в обоих опытах, в dark — 66. Следовательно, интерпретировать первый снимок iOS 26 как отсутствие системной materialization было бы неправильно.

**Runtime / строки образов:**

- `AnimationKit.LiquidMorphAnimation`, `AnimationKit.LensingSDFLayer`.
- `UIKit._UILiquidMorphAnimation`, `UIKit._UIZoomLiquidMorphAnimator`.
- `_UIContextMenuLiquidMorphPresentationAnimation`: `animationProgress`, `retargetDismissingMenuToPreview:`, `prepareTransitionToView:`, `performTransition`, completion и source preview.
- Строки AnimationKit: `System Liquid Morph`, `Morph v2 Lensing`, `Reduce Motion Liquid Morph`, а также полные key paths обоих glass filters.

У `AnimationKit.LiquidMorphAnimation` и Swift `UIKit._UILiquidMorphAnimation` Objective-C-таблица почти пустая: `init` и destruction. Наличие класса **не означает**, что можно вызвать полноценный morph через `performSelector`. Прямой перенос требует отдельного исследования Swift ABI либо пригодного ObjC-моста.

Практический порядок для AetherUI:

1. Использовать публичную анимацию `UIVisualEffectView.effect`, когда её достаточно.
2. В приватном backend синхронизировать управление материалом с уже имеющейся geometry/content timeline.
3. Исследовать native foreground lensing как альтернативу части snapshot distortion.
4. Выносить прямое использование AnimationKit в отдельный эксперимент, не делать его обязательным для показа меню.

Текущие [AetherContentMaterialization](../../Sources/AetherUI/Glass/AetherContentMaterialization.swift) и [ContextMenuGlassmorphicTransitionView](../../Sources/AetherUI/ContextMenu/ContextMenuGlassmorphicTransitionView.swift) сохраняют ценность: они решают подготовку содержимого, геометрию, прерывание и reversal. Новые находки относятся прежде всего к оптике материала.

## 6. Касание, lift, drag, glow

**Runtime.** `_UIFlexInteraction` раскрывает больше механизмов, чем `UIGlassEffect.isInteractive`:

- `preferredActivationMode`, `preferredFlexSources`, `preferredVariant`.
- `shouldUsePresentationLayers`, `isMatchingRadii`.
- translation, drift X/Y, scale X/Y, velocity integrator, `UIUpdateLink`.
- `showGlowAt:`, `moveGlowTo:shouldDissipate:`, `hideGlow`.
- `activateIfPermitted`, `deactivate`, `updateFlex`, `updateWithInteractionPulse`.
- Delegate: `flexInteraction:shouldBeginAtPoint:` и `flexInteraction:didIssueUpdate:`.

`_UILiquidLensView` в iOS 27 сохраняет используемый нами `initWithRestingBackground:` и `setLifted:animated:alongsideAnimations:completion:`. Дополнительно найдены `liftProgress`, `restingBorderColor`, `restingShadowProperties`, `belowGlassWarpBackdrop`, `forceUnliftWithoutAnimations`, `forceUnliftTimerWithoutAnimations` и `flexInteraction`.

Простой `setLifted:` не следует предполагать: в таблице этого класса есть основной метод с четырьмя аргументами и `set_lifted:`. Наш fallback уже проверяет `responds(to:)`; расширяя его, нужно сохранять эту проверку и фактический ABI.

Наш [GlassTouchEffect](../../Sources/AetherUI/Glass/GlassTouchEffect.swift) реализует собственные spring/translation/glow. Кандидат улучшения — управляемый native flex для отдельных controls. Числовые значения activation modes и variants пока не восстановлены, а конфликт с текущим tracking ещё не исследован.

## 7. Яркость, адаптация и monochrome

### Подтверждённая проблема AetherUI: luma-контейнер

В [GlassUtils.swift](../../Sources/AetherUI/Glass/GlassUtils.swift) `EffectSettingsContainerView` содержит только два обычных Swift stored properties:

```swift
public var lumaMin: Double = 0.0
public var lumaMax: Double = 0.0
```

У них нет observer, подключения к material descriptor или реализации UIKit-протокола. Поиск по Sources показывает запись значений в glass/lens paths, но не применение их к Apple API. Стенд, скомпилировавший этот класс из текущего исходника, получает `false` для всех четырёх Objective-C selectors: `lumaMin`, `lumaMax`, `setLumaMin:`, `setLumaMax:`.

То есть изменения этих переменных сами по себе не управляют яркостью native glass. Наличие `overrideUserInterfaceStyle` в соседнем коде может визуально маскировать этот пробел.

Добавление `@objc` само по себе тоже не создаст связи с UIKit. Нужен реальный consumer / adapter; просто названия свойств не являются протоколом системы.

### Реально существующие механизмы

- `_UILumaTrackingBackdropView` имеет `transitionBoundaries` (структура из **двух double**), `backgroundLuminanceLevel`, paused/unpause и delegate `backgroundLumaView:didTransitionToLevel:`.
- `UIView._materialDidReceiveLuma:` принимает `double`.
- `_UIViewGlass` имеет adaptive setters, но fixed luminance в проверенном regular-пути iOS 27 результата не дала.
- В `glassBackground` реально заданы `inputFaceColorMatrixMaxLuma`, `MaxLumaSDR`, black/white/saturation и SDR holding tone.
- Найдены приватные traits `_UITraitControlGlassStyle` и `_UITraitGlassElevationLevel`.
- В DesignLibrary обнаружены строки `AdaptiveGlassHysteresisDarkRangeArray`, `AdaptiveGlassHysteresisLightRangeArray`, `CalistogaAllowLumaTracking`. Это ориентиры для следующего исследования, не документированные preferences для настройки приложения.

**Monochrome:** существующий `UIView._setEnableMonochromaticTreatment:` принимает **BOOL**, а `_setMonochromaticTreatment:` и `_setPreferredMonochromaticTreatment:` — **NSInteger**. `_setAllowsMonochromaticTreatment:` в методах UIView не найден. Нельзя вызывать все похожие имена одним BOOL trampoline. В нынешнем `setMonochromaticEffect` AetherUI используется `overrideUserInterfaceStyle`; наличие старых имён в `ObfuscatedSymbols` не означает, что они активны.

## 8. Публичные API, которые стоит использовать шире

Основание — availability в SDK 27 и сопоставление с Sources. Для перечисленных основных классов availability — iOS 26.0.

| API | Что даёт | Состояние AetherUI |
|---|---|---|
| `UIGlassEffect` regular/clear, tint, interactive | Базовый материал | Уже используется |
| `UIGlassContainerEffect.spacing` | Общий рендер и слияние нескольких элементов | Уже есть `GlassBackgroundContainerView` |
| `UIView.cornerConfiguration` | Модель формы, отдельные углы | Уже есть helpers |
| `UICornerRadius.containerConcentric(minimum:)` | Радиус, согласованный с геометрией контейнера | Прямых использований в Sources не найдено; наши helpers в основном fixed |
| `UIScrollView` edge effects | Системная обработка края прокрутки | Наши `EdgeEffectView` и attachment в основном рисуют эффект самостоятельно |
| `UIScrollEdgeElementContainerInteraction` | Связь labels/images/glass/controls с формой scroll edge effect | Использований не найдено |
| `UIBackgroundExtensionView` | Продолжение фона под окружающими элементами интерфейса | Использований не найдено |
| `UIButton.Configuration` glass/prominent/clear/prominentClear | Готовые варианты native controls | Полезная база сравнения для наших custom controls |
| `UIBarButtonItem.hidesSharedBackground` и соседние свойства | Управление общей подложкой системных bar items | Есть собственный Aether-аналог, не полная замена системного grouping |
| SwiftUI `GlassEffectContainer`, identity/union/transition modifiers | Объединение, morph identity и transitions | У UIKit-фреймворка нет соответствующего SwiftUI-слоя; это отдельный продуктовый выбор |

Для native scroll edges нужен renderer strategy с проверкой layout/scroll ownership, а не второе наложенное размытие поверх существующего `EdgeEffectView`. Для background extension — отдельная интеграция с контейнерами; это не дополнительная стеклянная карточка.

Apple рекомендует контейнер для группы стеклянных элементов; появление материала демонстрируется через анимацию `UIVisualEffectView.effect`. См. [Build a UIKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/284/) и [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

## 9. Подтверждённая проблема исходного среза: сравнение style

В исходном `GlassBackgroundView.applyNativeGlassEffect` перед присвоением сравнивались только `tintColor` и `isInteractive`. `regular` и `clear` могут иметь одинаковые значения обоих свойств. В параллельной правке рабочего дерева это условие уже расширено; стенд подтверждает исходную причину, но не заменяет проверку той правки.

Воспроизводимый случай: `.custom(.default, color)` → `.custom(.clear, тот_же_color)`, interactivity не меняется. `makeNativeGlassEffect` создаёт новый style, но текущий guard считает эффект прежним и пропускает assignment.

Стенд создаёт две реальные `UIGlassEffect` с одинаковым красным tint и interactivity. В `objects.json / aetherStyleComparison` сохранены результат нашего условия, `isEqual:` и приватные значения style. Это проверка самого условия на настоящих UIKit-объектах; весь `GlassBackgroundView` в стенд не импортируется.

Предлагаемое исправление: хранить полный application-level key последнего native effect (`style`, tint, interactive, а при расширении — descriptor options). Так не потребуется читать приватный `style` ради сравнения в публичном backend. Регрессия должна проверять переход default↔clear с неизменным tint.

## 10. Приоритеты для фреймворка

| Приоритет | Изменение | Почему |
|---|---|---|
| P0 | Добавить style в native effect cache key; проверить параллельную правку | Подтверждённый пропуск обновления в исходном коде |
| P0 | Исправить обещание / реализацию `EffectSettingsContainerView` | Сейчас luma-параметры не соединены с материалом |
| P1 | Довести и проверить появившийся параллельно descriptor adapter `_UIViewGlass` | Даёт проверенное управление shadow/platter/content lensing |
| P1 | Разделить настройку native background и foreground lensing | Позволяет работать с настоящим преломлением содержимого |
| P1 | Исследовать materialization как единый набор каналов | Текущий blur/displacement охватывает лишь часть системного поведения |
| P1 | Добавить native scroll edge strategy и concentric corners | Публичные возможности для лучшего соответствия системному UI |
| P2 | Добавить CASDF key/fill highlights и shape composition | Для форм, которым не хватает простого displacement |
| P2 | Проверить native flex/lift integration | Может улучшить press/drag без собственных несовпадающих пружин |
| P2 | Background extension в navigation/tab containers | Улучшает фон под плавающим chrome |
| Исследование | Swift AnimationKit / DesignLibrary ABI | Классы найдены, пригодный стабильный вход не доказан |

Возможная внутренняя структура: `GlassCapabilities`, `NativeGlassDescriptorAdapter`, `NativeGlassRenderHostResolver`, `NativeGlassMaterializationController`. Adapter к завершению исследования появился в параллельной правке; остальные названия здесь — предложение. Public/safe и private backend должны сохранять существующее разделение `APPSTORE_SAFE`; проверять конкретные методы и их типы, а не только `#available(iOS 27)`.

Существующие `.liquidGlassV1` / `.liquidGlassV2` — пресеты AetherUI. По [AetherAppearanceAvailabilityAudit](AetherAppearanceAvailabilityAudit.md) они намеренно не равны версии операционной системы. Новые runtime-возможности нужно подключать по capabilities, сохраняя это разделение.

## 11. Что ещё требует проверки

- Physical device: качество compositor, Metal, энергопотребление, частота кадров и touch latency не измерялись.
- Промежуточные выпуски 26.x и другие сборки 27: один runtime не доказывает весь диапазон совместимости.
- Системная регулировка плотности стекла: прочитано текущее значение; сама настройка и её notification/trait propagation не менялись.
- Reduce Motion / Reduce Transparency / Increased Contrast: состояния зафиксированы, но не выполнена полная матрица. В AetherUI уже есть часть соответствующей обработки; нельзя считать её отсутствующей.
- Active press, drag, pinch, lifted lens: методы исследованы, но полная интерактивная последовательность не автоматизирована.
- Произвольные shapes и слияние под нагрузкой: CASDF API найден, визуальная/производительная эквивалентность не подтверждена.
- Частные integer enums: не угаданы по значениям. Swift description и совпадение selector недостаточны для объявления полного enum.

Apple описывает обновления материала iOS 27 как более сильное рассеивание сложного фона, изменённые края и блики и пользовательскую регулировку прозрачности; существующее native glass получает обновление с OS. Поэтому не все различия 26/27 требуют нового публичного класса. Источник: [Platforms State of the Union, WWDC26](https://developer.apple.com/videos/play/wwdc2026/102/).

## Повторить исследование

```sh
python3 Documentation/Internal/Research/GlassRuntime/run.py --device <booted-device-udid> --label ios27 --appearance light
python3 Documentation/Internal/Research/GlassRuntime/run.py --device <booted-device-udid> --label ios27-dark --appearance dark
python3 Documentation/Internal/Research/GlassRuntime/analyze.py ios27 ios27-dark
python3 Documentation/Internal/Research/GlassRuntime/run.py --device <ios26-device-udid> --label ios26 --appearance light
python3 Documentation/Internal/Research/GlassRuntime/run.py --device <ios26-device-udid> --label ios26-dark --appearance dark
python3 Documentation/Internal/Research/GlassRuntime/analyze.py ios26 ios26-dark
python3 Documentation/Internal/Research/GlassRuntime/compare.py ios26 ios27
python3 Documentation/Internal/Research/GlassRuntime/compare.py ios26-dark ios27-dark
```

Стенд устанавливает только `local.aether.glassprobe`. Использует scene lifecycle. Перед запуском удаляет только собственные старые JSON из своего app container, чтобы сбой не выдавался за новое исследование. Результаты копируются после появления всех файлов; screenshot делается после завершения materialization demo. Приложение завершается после сбора. SDK / runtime / git SHA / SHA256 исследованных исходников сохраняются рядом.

JSON содержит адреса живых объектов для диагностического контекста. Автоматические сводки нормализуют адреса при сравнении. `nil`, неизвестный KVC-ключ и непустое значение различаются в интерпретации; infinite numeric значения сериализуются строкой, а не теряются.
