# Аудит AetherUI для стекла в направлении MagicOS 11

Дата: 24 сентября 2026. Область: текущая рабочая копия AetherTextureKit, включая незакоммиченный ExperimentalGlass. Это read-only аудит production-кода. Тесты и сборка в этом прогоне не запускались; существующие отчёты ниже явно отделены от новых выводов. Название MagicOS 11 здесь означает целевой визуальный и поведенческий референс, а не доступ к реализации HONOR.

## Вывод

У нас уже есть большая часть инфраструктуры: общий хост материала, роли поверхностей, темы, анимируемая геометрия, жесты, меню, линза выбора, Metal-рефракция, blur, блики и захват фона. Статический убедительный вариант можно получить за несколько дней. Основная трудность production-варианта — корректный живой фон и его стоимость, затем одинаковое поведение материала на разных iOS и связка с жестами. Это не задача «поменять радиус blur».

Особенно существенны реальные сохранённые измерения на iPhone 7: большие поверхности уже дают 48–86 мс CPU работы стекла за callback и 11–16 callbacks/s. Это прежние замеры от 14 сентября, не новый бенчмарк и не GPU FPS. До исправления backdrop нельзя обещать стабильные 60 Гц для такого варианта на старых устройствах.

## Состояние рабочего дерева

При начале аудита изменены `Package.swift`, `Glass.md`, `ChatBackgroundNode.swift`, `AetherGlassConfig.swift`, `GlassBackgroundView.swift`, `LegacyGlassBackdropView.swift`, `LiquidLensView.swift` и часть тестов. `Glass/Experimental`, `ExperimentalGlassTests.swift`, `ThirdParty` и `Research` не отслеживаются Git. Следовательно, возможности experimental ниже уже существуют в рабочей копии, но нельзя представлять их как проверенный выпущенный baseline. Никакие пользовательские изменения не сбрасывались.

## Что уже реализовано

| Слой | Реальные возможности | Где смотреть |
|---|---|---|
| Appearance | `legacy`, `liquidGlassV1`, `liquidGlassV2`, кодирование стабильных идентификаторов, конфигурация края/тона | [AetherAppearanceRuntime.swift:9](../../../../Sources/AetherUI/App/AetherAppearanceRuntime.swift#L9), [пресеты:135](../../../../Sources/AetherUI/App/AetherAppearanceRuntime.swift#L135) |
| Семантика | Роли `attachedBar`, `floatingSurface`, `toolbar`, `button`, `card`, `input`, `popup`, `selectionIndicator`; реестр обновления потребителей и accessibility notifications | [AetherSurfaceAppearance.swift:5](../../../../Sources/AetherUI/App/AetherSurfaceAppearance.swift#L5), [реестр:172](../../../../Sources/AetherUI/App/AetherSurfaceAppearance.swift#L172) |
| Общий хост | `GlassBackgroundView`, стабильный content host, regular/clear/prominent, tint и rounded rect | [GlassBackgroundView.swift:261](../../../../Sources/AetherUI/Glass/GlassBackgroundView.swift#L261) |
| Native renderer | iOS 26+ `UIGlassEffect`, tint, interactive, смена dark/light, анимации материала/геометрии | [GlassBackgroundView.swift:1171](../../../../Sources/AetherUI/Glass/GlassBackgroundView.swift#L1171), [эффект:2551](../../../../Sources/AetherUI/Glass/GlassBackgroundView.swift#L2551) |
| Custom renderer | Metal pipeline, MPS Gaussian blur, тройной пул ресурсов, CoreVideo→Metal texture bridge | [ExperimentalGlassView.swift:124](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassView.swift#L124), [blur:257](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassView.swift#L257), [CaptureBuffer.swift:19](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassCaptureBuffer.swift#L19) |
| Оптика | Thickness/index, цветовая дисперсия, Fresnel, направленный glare, sharp rim поверх размытого источника | [ExperimentalGlassView.swift:19](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassView.swift#L19), [Fragment.metal:477](../../../../Sources/AetherUI/Glass/Experimental/Metal/ExperimentalGlassFragment.metal#L477), [блики:522](../../../../Sources/AetherUI/Glass/Experimental/Metal/ExperimentalGlassFragment.metal#L522) |
| Форма | SDF rounded rectangles/superellipse, smooth union до 16 прямоугольников, аналитическая нормаль для частого случая | [ExperimentalGlassView.swift:15](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassView.swift#L15), [Fragment.metal:168](../../../../Sources/AetherUI/Glass/Experimental/Metal/ExperimentalGlassFragment.metal#L168) |
| Backdrop | Общий снимок для группы, исключение foreground, ROI, pruning, слабый explicit source, fingerprint-кеш | [ExperimentalGlassBackgroundCapture.swift:11](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassBackgroundCapture.swift#L11), [граница панели:140](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassBackgroundCapture.swift#L140), [кеш:170](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassBackgroundCapture.swift#L170) |
| Управление кадрами | Один CADisplayLink для всех поверхностей, common run-loop, отсечение невидимого и пропуск кадра при занятых GPU-ресурсах | [ExperimentalGlassFrameScheduler.swift:17](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassFrameScheduler.swift#L17), [visibility/draw:312](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassView.swift#L312) |
| Линза выбора | Lift/collapse, маски и selected content; experimental lens до iOS 26 | [ExperimentalGlassLensSurface.swift:22](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassLensSurface.swift#L22), [LiquidLensView.swift:585](../../../../Sources/AetherUI/Glass/LiquidLensView.swift#L585) |
| Меню/жесты | Геометрическое раскрытие/схлопывание, ретаргетинг прерванного открытия, velocity continuity и отдельные слои содержимого | [ContextMenuGlassmorphicTransitionView.swift:2113](../../../../Sources/AetherUI/ContextMenu/ContextMenuGlassmorphicTransitionView.swift#L2113), [ретаргетинг:3202](../../../../Sources/AetherUI/ContextMenu/ContextMenuGlassmorphicTransitionView.swift#L3202) |

По интеграции работа также не начинается с нуля: меню использует этот хост ([MenuGlassSurfaceView.swift:36](../../../../Sources/AetherUI/ContextMenu/MenuGlassSurfaceView.swift#L36)), toolbar ([AetherToolbar.swift:123](../../../../Sources/AetherUI/Toolbar/AetherToolbar.swift#L123)), floating toolbar ([AetherFloatingToolbar.swift:491](../../../../Sources/AetherUI/Toolbar/AetherFloatingToolbar.swift#L491)), alert ([AetherAlertController.swift:280](../../../../Sources/AetherUI/Alert/AetherAlertController.swift#L280)), tooltip ([AetherTooltipController.swift:225](../../../../Sources/AetherUI/Tooltip/AetherTooltipController.swift#L225)), action sheet ([AetherActionSheetItemGroupView.swift:21](../../../../Sources/AetherUI/ActionSheet/AetherActionSheetItemGroupView.swift#L21)) и navigation search ([AetherSearchController.swift:393](../../../../Sources/AetherUI/NavigationBar/AetherSearchController.swift#L393)).

## Основные пробелы

### 1. Нет отдельного независимого семейства материала

Публичный appearance enum сейчас содержит только Legacy и две генерации Liquid Glass. `AetherSurfaceRendererKind` тоже только legacy/liquidGlass. Для нового направления нужен явный профиль материала, отдельно от renderer и отдельно от версии OS. Иначе внешний вид будет скрыто меняться вместе с iOS.

`AetherGlassConfig.legacyBlurBackend` выбирает experimental только внутри legacy-backend ветки; iOS 26+ по умолчанию выбирает native. Есть глобальный `GlassBackgroundView.useCustomGlassImpl`, позволяющий принудительно уйти в custom ветку, но это не полноценная политика по ролям/устройствам. `SystemGlassEffect.make` имеет собственный путь создания эффекта и не является универсальным custom renderer factory. Источники: [AetherGlassConfig.swift:27](../../../../Sources/AetherUI/Glass/AetherGlassConfig.swift#L27), [GlassBackgroundView.swift:328](../../../../Sources/AetherUI/Glass/GlassBackgroundView.swift#L328), [SystemGlassEffect.swift:19](../../../../Sources/AetherUI/Glass/SystemGlassEffect.swift#L19).

Нужен профиль с параметрами плотности, насыщенности, tint, edge width, thickness, displacement, glare, shadow, contrast floor и motion, разрешаемый по роли поверхности. Его renderer policy: native approximation / custom Metal / public blur fallback. Это позволит A/B, постепенное включение и измеряемую деградацию качества.

### 2. Живой фон — CPU snapshot, а не системный compositor backdrop

Текущий путь вызывает `source.layer.render(in:)` ([BackgroundCapture.swift:214](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassBackgroundCapture.swift#L214)). Он работает с деревом model layers. Отсутствует независимый источник кадров видеослоя/Metal и compositor-доступ к уже смешанному пикселю. Ограничение Metal, video и system visual effects прямо документировано у публичного source property ([строка 15](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassBackgroundCapture.swift#L15)).

Для обычного статичного UIKit и программно обновляемого scroll offset уже есть рабочая основа. Для CA-анимаций, параллакса, сложного z-order и смешивания нескольких полупрозрачных панелей нужна отдельная проверка. Частое повторение model snapshot само по себе не делает его точным изображением текущей presentation geometry. Нельзя автоматически переносить правильность теста красного/синего UIView на системный blur или видео.

Практическое направление: источник фона как контракт — статичная texture + актуальные transform/scroll offset; отдельно обновляемый UIKit content; отдельная стратегия для видео/Metal (явный источник texture/frame либо blur fallback). Не делать snapshot всей сцены на каждом кадре неизбежным условием материала.

### 3. Реальная производительность уже блокирует большие поверхности на старом устройстве

Сохранённый [отчёт iPhone 7:31](../../Research/ExperimentalGlass-iPhone7-2026-09-14/README.md#L31) и [сырые структурированные результаты](../../Research/ExperimentalGlass-iPhone7-2026-09-14/build7.json):

| Сцена из прежнего прогона | Средний CPU стекла, мс/кадр | Средний capture, мс/кадр | Cadence, callbacks/s |
|---|---:|---:|---:|
| Поверхность 375×637, вероятно модалка | 84.70–85.88 | 82.11–83.40 | 11.4 |
| Меню 260×420 | 48.14–61.17 | 45.66–58.40 | 13.5–15.8 |
| Небольшая поверхность 343×42 | 18.54–19.37 | 17.30–18.15 | 51.2–53.5 |

Это Release iPhone 7 / iOS 15.8.3; GPU execution time, thermal и истинный presentation FPS не измерялись. Бюджет 60 Гц — 16.67 мс на весь кадр, а не только стекло.

Во всех 17 интервалах кеш обходился из-за `UIMotionEffectGroup`. Fingerprint отклоняет любую анимацию ([ExperimentalGlassLayerFingerprint.swift:31](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassLayerFingerprint.swift#L31)); ChatBackgroundNode действительно ставит motion effects ([ChatBackgroundNode.swift:392](../../../../Sources/AetherUI/ChatBackground/ChatBackgroundNode.swift#L392)). Привязка конкретного адреса слоя к фону и контрольный A/B ещё не выполнены. Безусловно игнорировать animationKeys нельзя: это может «оптимизировать» корректность в устаревший фон.

При площади >20% окна capture расширяется до окна ради стабильной геометрии ([BackgroundCapture.swift:54](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassBackgroundCapture.swift#L54)); при cache miss это увеличивает стоимость. Даже после улучшения этого случая нужны отдельные замеры scroll, меню, sheet и нескольких перекрывающихся surfaces.

### 4. Оптическая обратная связь от пальца пока не завершена

В experimental uniforms есть `touchPoint`, но Metal fragment только объявляет поле и не использует его в расчётах. Swift присваивает uniform, однако публичного маршрута жеста к локальной деформации в этом renderer нет. Текущий `LegacyGlassBackdropView` при touch масштабирует стекло целиком до 1.025 за 0.18 c ([LegacyGlassBackdropView.swift:83](../../../../Sources/AetherUI/Glass/LegacyGlassBackdropView.swift#L83)).

Более богатая геометрическая реакция уже есть отдельно в GlassTouchEffect ([GlassTouchEffect.swift:153](../../../../Sources/AetherUI/Glass/GlassTouchEffect.swift#L153)), а меню умеет сложные переходы. Их можно использовать, но наличие этих классов не означает, что блик, нормаль и refraction уже следуют пальцу. Нужен единый interaction state: location, velocity, press/lift progress, spring settle; затем синхронизация geometry/optics/shadow/content.

### 5. Cadence и quality tiers

Experimental scheduler запрашивает ровно 60 Гц ([FrameScheduler.swift:19](../../../../Sources/AetherUI/Glass/Experimental/ExperimentalGlassFrameScheduler.swift#L19)), в то время как LiquidLensDisplayLink допускает 120 ([LiquidLensView.swift:104](../../../../Sources/AetherUI/Glass/LiquidLensView.swift#L104)). Это потенциально разные частоты геометрии и оптики. В experimental каталоге нет thermal/Low Power policy. Display link остаётся активен, пока views находятся в окне, хотя невидимые поверхности отсеиваются.

Нужны quality tiers, event-driven redraw в покое, доступный cadence budget, лимиты активной площади/поверхностей, отдельный motion budget и graceful fallback. Увеличение 60 до 120 до оптимизации захвата лишь удвоит запрос нагрузки.

### 6. Контраст и доступность

Reduce Transparency уже учитывается в experimental visibility и заменяет панели на непрозрачные, Reduce Motion выключает часть анимаций; общий реестр отслеживает настройки. Но glass presets не делают анализ содержимого под конкретной поверхностью. Потребуется правило минимальной читаемости: tint/blur повышается на пёстром фоне, семантический foreground, high contrast и проверка Dynamic Type. Адаптивную прозрачность референса нельзя считать реализованной только потому, что есть dark/light.

### 7. API и зависимость от приватного runtime

Сам experimental Metal/CoreVideo/MPS/direct UIKit capture использует публичные механизмы. Но проект целиком не следует автоматически называть public-API-only: текущий Package.swift оставляет `APPSTORE_SAFE` закомментированным и для Swift, и для bridging ([Package.swift:28](../../../../Package.swift#L28), [строка 45](../../../../Package.swift#L45)). Host build может задавать условие извне; аудит manifest не доказывает конкретные production build settings.

Примеры private веток: `NativeGlassDescriptorAdapter` получает `glass`, `effectWithGlass:`, `setContentLensing:`, `setExcludingShadow:` ([NativeGlassDescriptorAdapter.swift:14](../../../../Sources/AetherUI/Glass/NativeGlassDescriptorAdapter.swift#L14)); native lens создаётся по скрытому имени и selector ([LiquidLensView.swift:513](../../../../Sources/AetherUI/Glass/LiquidLensView.swift#L513)); custom VisualEffectView использует скрытый blur и KVC вне safe-build ([VisualEffectView.swift:35](../../../../Sources/AetherUI/Glass/VisualEffectView/VisualEffectView.swift#L35), [KVC:299](../../../../Sources/AetherUI/Glass/VisualEffectView/VisualEffectView.swift#L299)).

При `APPSTORE_SAFE` native private lens выключен; на iOS 26+ fallback thumb становится UIView, а experimental lens выбирается только до iOS 26 ([LiquidLensView.swift:591](../../../../Sources/AetherUI/Glass/LiquidLensView.swift#L591)). Это дополнительный аргумент отделить желаемое поведение от OS/private availability. Реалистичный релизный путь нового стиля — публичный custom renderer + public blur fallback; private adapters не должны быть необходимым условием целевого эффекта.

В [ThirdParty/LiquidGlassKit.md:3](../../../../ThirdParty/LiquidGlassKit.md#L3) записано происхождение прототипа и отсутствие LICENSE в использованной копии. Перед выпуском производного renderer нужно подтвердить условия использования или заменить соответствующую реализацию. Это известный вопрос текущего проекта, не вывод о юридическом статусе без дальнейшей проверки.

## Проверки: что есть и чего они не доказывают

В [ExperimentalGlassTests.swift](../../../../Tests/AetherUITests/ExperimentalGlassTests.swift) 11 тестов: opaque/translucent occlusion, fingerprint invalidation, offscreen/overflow pruning, движение и foreground exclusion, GPU readback после resize, shared capture на 20 surfaces, weak source, scheduler/visibility, material/geometry updates, backend selection, lens selection. Дополнительно safe-build tests проверяют policy и public fallbacks ([AetherAppStoreSafeTests.swift:7](../../../../Tests/AetherUITests/AetherAppStoreSafeTests.swift#L7)).

Они полезны для корректности, но не проверяют внешнее сходство с HONOR, движение блика за пальцем, физический 120 Гц, CA presentation parity, видео/Metal, полную accessibility-матрицу, энергию или thermal. Прежние отчёты о пройденных тестах — исторические; здесь не заявляется новый запуск.

Нужные acceptance checks: светлый/тёмный и пёстрый фон; статичная/скроллящаяся/параллакс-сцена; touch down/drag/cancel/rapid retarget; навигация/меню/sheet/tab/segment; два перекрывающихся стекла; поворот и keyboard; Reduce Motion/Transparency/high contrast/Dynamic Type; physical old/current/ProMotion. Регистрировать CPU p50/p95/p99, GPU command duration, actual presented-frame pacing, память и thermal, а не только callback cadence. Качество — покадровое сравнение с согласованным референсом и видео на той же длительности жеста.

## Рекомендуемая реализация

1. Зафиксировать конкретный референс: устройство/сборка MagicOS, 3–5 коротких сценариев, rest/press/drag/release кадры. Из статичного скриншота spring и backdrop cadence не восстановить.
2. Сделать material profile и renderer policy, сохранив existing content hosts. Один новый стиль не должен переписывать весь navigation/tab/menu layout.
3. Прежде оптической полировки выполнить backdrop spike на реальном старом устройстве: статичная картинка+transform, явный source, actual scroll, motion A/B, большой menu/sheet. Заранее определить границу fallback.
4. Подогнать плотность, ширину края, glare и тени на 2–3 поверхностях; не включать максимальную дисперсию повсюду.
5. Связать общий interaction state с geometry, optics, shadow и content, проверить interruption/retarget.
6. Раскатить профиль по ролям, добавить accessibility, quality tiers и safe build. Затем реальная device QA.

## Оценка трудоёмкости

Это инженерная оценка, а не измерение. Предположения: один опытный iOS/Metal инженер, доступ к исходникам и реальному референсу, 3 основных поверхности, без копирования всей оболочки OS. 1 человеко-день ≈ полный рабочий день. Диапазоны не включают ожидание доступа к устройству/лицензии и уточнение референса.

| Объём | Оценка | Результат |
|---|---:|---|
| Визуальный spike на имеющейся сцене | 2–4 чел.-дня | Статичная/умеренно интерактивная демонстрация с текущим стеклом; без гарантий performance |
| Новый профиль + базовые tokens/renderer routing | 2–4 чел.-дня | Независимый управляемый стиль, единое включение по ролям |
| Backdrop/performance spike | 3–5 чел.-дней | Измеренное решение go/no-go по старым устройствам; карта ограничений |
| Оптика + touch/motion tuning | 5–9 чел.-дней | Настроенный край, блик, плотность, press/drag/release, interruption |
| Интеграция 3–5 основных поверхностей | 3–6 чел.-дней | Navigation/search/tab/menu/sheet с согласованным материалом |
| Accessibility, quality tiers, device QA | 4–7 чел.-дней | Релизный fallback, матрица поведения и performance |

Полезные суммарные ориентиры для custom-направления: убедительный PoC — **5–8 чел.-дней** (часть перечисленных работ урезана); качественная production-аппроксимация со своей Metal-оптикой на современном iPhone с контролируемыми UIKit-фонами — **18–30 чел.-дней**, примерно 4–6 рабочих недель одного инженера; расширенная поддержка старых устройств и сложных динамических фонов с допустимыми упрощениями — **28–45+ чел.-дней**. Это альтернативные уровни scope, их не нужно складывать. Быстрый вариант только на публичном native UIGlassEffect без собственной оптики имеет меньший объём; основной [AUDIT.md](../../Research/MagicOS11Audit-2026-09-24/AUDIT.md) отдельно оценивает его и гибридный релиз. Близкий паритет сложной оптики на всех ОС не покрывается диапазоном для контролируемого UIKit-фона.

Для точного совпадения со всеми системными сценариями, анимациями и закрытым compositor поведением HONOR срок пока не определим. Такой scope требует фактического референса, измерений и отдельного исследования; наша библиотека может воспроизвести наблюдаемое поведение внутри приложения, но не становится оболочкой Android.
