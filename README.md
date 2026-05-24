# RECOVERI — Универсальный советник восстановления для MT5

Советник для **«разруливания» счёта из минуса**: берёт под управление существующие позиции (свои, ручные или все подряд) и закрывает их по выбранной стратегии восстановления.

**Текущая версия: 1.60** — Mode 5 переписан под идеологию [AW Recovery EA](https://www.mql5.com/en/blogs/post/736552). Сохранены защиты RECOVERI поверх AW (`InpEnsureNetPositive`, ATR-сетка, точечный приоритет тикета).

См. [`docs/MODE5-AW-REWRITE.md`](docs/MODE5-AW-REWRITE.md) — design-doc по v1.60.
См. [`CHANGELOG.md`](CHANGELOG.md) — полная история v1.10..v1.53.

---

## Что нового в v1.60

### Шесть секций инпутов в стиле AW Recovery

В окне настроек MT5 параметры теперь сгруппированы по тем же шести разделам, что и в AW Recovery:

| # | Секция | Назначение |
|---|---|---|
| 1 | `=== ORDERS TO RECOVERY ===` | Какие позиции брать в управление, приоритет, начальный тикет |
| 2 | `=== LAUNCH SETTINGS ===` | Триггер запуска (instant / DD% / DD$), отключение чужих EA, **Slow Start** |
| 3 | `=== TAKEPROFIT AND PARTIAL RECOVERY ===` | Цель корзины, чип-лот, net-positive guard, **TP-линия на графике** |
| 4 | `=== RECOVERY GRIDS AND AVERAGE ORDERS ===` | Геометрия усреднителей, **режим лота** (FIXED/PCT/FROM-LOSS/MAX), ATR-шаг |
| 5 | `=== TREND FILTER ===` | MA-кросс трендовый фильтр |
| 6 | `=== PROTECTION SETTINGS ===` | Equity-стоп, спред, виртуальные TP/SL/BE/TSL, фильтр времени и новостей |

Дополнительно отдельными группами идут: HedgeLock (Mode 3), Auto-unwind FSM (Mode 3), Averaging/Martingale (Modes 1/2), Уведомления, Сохранение состояния, Безусловная сетка, Ручная торговля, Панель.

### Удалено (breaking change для пользователей этих ключей)

- **Trend-flip stack** v1.43–1.53: `InpRestartGridOnTrendFlip`, `InpCloseOldGridOnTrendFlip`, `InpOldGridCloseProfit`, `InpTrendFlipTrimStrong`, `InpKeepOldGridAlive`, `InpSeedNewGridLot`. Теперь, как в AW: при флипе тренда фильтр просто блокирует новые усреднители на «неправильной» стороне; старая цепочка дозакрывается по своим `InpAvgTPpts` + чип-парой.
- **TF lock-align** v1.52: `InpLockAlignUseTF`, `InpLockAlignTF`, `InpLockAlignThresholdLot`, `InpLockAlignOnlyProfit`. Периодическая балансировка лока убрана.

`.set` файлы от v1.53 загрузятся в v1.60 без ошибок — MT5 молча игнорирует неизвестные input-ключи. GV-ключи `PR_COA`/`PR_COS`/`PR_SLA`/`PR_SLS`/`PR_SLT` затираются при первом `OnInit` v1.60 (forward-миграция).

### Сохранены ключевые отличия RECOVERI от AW

- **Net-positive guard** на каждом цикле «закрытие усреднителя + чип убыточника»: `InpEnsureNetPositive` + `InpMinNetProfit` + `InpMinNetProfitPct`. Гарантирует, что цикл не уйдёт в минус, даже если убыточник глубоко в просадке. Эффективный пол: `max(InpMinNetProfit, avgProfit*Pct/100)`. У AW Recovery такого нет.
- **`InpFirstTicket`** — закрепить конкретный тикет как первого в очереди на чип. У AW нет.
- **`InpAvgStepUseATR`** + ATR-группа — шаг сетки усреднителей из ATR выбранного ТФ. У AW шаг только фиксированный.
- **`InpRecoveryPriority`** — `EASY` / `HARD` / `FIRST_TICKET`. У AW есть аналог.
- **`InpOverlapAfterN`** — closing overlap (после N усреднителей оставлять только first+last). У AW есть аналог.

### Добавлено в v1.60

#### Slow Start

`InpUseSlowStart` + `InpSlowStartLossSteps` (3) + `InpSlowStartLossStepUSD` (50.0) — постепенная активация усреднителей по мере углубления просадки. Текущая корзина-ступень = `floor(currentLoss / step$)` ограничивает максимум одновременно открытых усреднителей. На ступени 0 (нет убытка) ни один PR-AVG не откроется.

По умолчанию выключено — поведение совпадает с v1.53 для FIXED-режима лота.

#### Динамический лот усреднителя

Новый enum `ENUM_AVG_LOT_MODE` через `InpAvgLotMode`:

| Значение | Формула | Множитель цепи (`InpAvgVolumeMul^k`) |
|---|---|---|
| `AVG_LOT_FIXED` (по умолчанию) | `InpAvgVolume * Mul^k` | да — байт-в-байт v1.53 |
| `AVG_LOT_PCT_OF_LOSING` | `losingSideVolume * InpAvgLotPctOfLosing/100` | нет — лот уже масштабируется |
| `AVG_LOT_FROM_LOSS_USD` | `floatingLoss * InpAvgLotPerLossUSD` | нет — лот уже масштабируется |
| `AVG_LOT_MAX_OF_ALL` | `max(FIXED, PCT, FROM_LOSS_USD)` | да — через FIXED |

#### TP-линия на графике

`InpDrawTPLine = true` + `InpTPLineColor` (по умолчанию `clrGold`) — рисует горизонтальную линию (`OBJ_HLINE`) на цене, при которой текущая корзина даст `InpTargetProfit`. Для `BASKET_PER_SIDE` — две линии (BUY и SELL независимо). Скрывается, если корзина пуста или идеально захеджирована.

#### Recovery progress %

В панели появилась строка вида `Recovery: 67.3% (-150.00 → -49.10)`. Базис захватывается на первом тике после срабатывания триггера, когда `bs.profit < 0`, и хранится в GV `RC_DD0`. Сбрасывается на `PR_IDLE` / смене режима / `Reset State`.

#### Цветовой статус-индикатор

Маленький квадрат рядом с заголовком панели:

| Цвет | Значение |
|---|---|
| Lime | Recovery работает (есть управляемые позиции или триггер сработал) |
| Gold | Standby (триггер настроен, но не сработал) |
| Orange | Pause / блокировка по фильтру времени или новостей |
| Red | Аварийный equity-стоп |
| Silver | Idle (пусто, триггер не настроен) |

#### Кнопка `Avg Now` (только Mode 5)

`InpShowAvgNowButton = true` (по умолчанию) показывает кнопку `Avg Now` на панели в режиме `MODE_PARTIAL_RECOVERY`. Один клик открывает один `PR-AVG-{B|S}` на стороне, которую сейчас предпочитает recovery-цикл, **игнорируя гейты по step/bar**, но соблюдая `InpMaxAveragers`, `InpMaxTrades`, `SpreadOK`, `EmergencyStop` и Slow Start. Лот считается через тот же `ComputeAvgLot()`.

---

## Установка

1. Скопируйте `RECOVERI.mq5` в `<MT5>/MQL5/Experts/`.
2. В MetaEditor — **Compile** (F7).
3. Перетащите советника на график, разрешите автоторговлю.

## Стратегии восстановления (`InpMode`)

| Режим | Описание |
|------|----------|
| `0 TargetProfit` | Просто ждёт цели и закрывает корзину. Сам не торгует. |
| `1 Averaging` | Усреднение в сторону убытка (одинаковый или линейно растущий лот). |
| `2 MartingaleGrid` | Мартингейл-сетка с множителем лота. |
| `3 HedgeLock` | Локирование чистого объёма встречной позицией (с опциональным авто-распилом). |
| `4 SmartClose` | Парное закрытие: лучшая прибыльная + худшая убыточная. |
| `5 PartialRecovery` | Дробное восстановление: лок + усреднители + чип убыточников (a la AW Recovery). |

## Что брать в управление

- `InpManageScope`: `ALL` / `MANUAL` (magic==0) / `OWN` (по `InpMagic`)
- `InpSymbolScope`: только текущий символ или все символы счёта

## Корзина и цель

- `InpBasketMode`:
  - `COMBINED` — единая корзина BUY+SELL, цель и трейлинг общие.
  - `PER_SIDE` — раздельные корзины BUY и SELL, каждая закрывается независимо.
- `InpTargetType` — `MONEY` / `PERCENT` от баланса / `PIPS` (эквивалент в пунктах).
- `InpTargetProfit` — значение цели.
- `InpUseBasketTSL` + `InpBasketTSLStart` + `InpBasketTSLStep` — трейлинг корзины.

## Виртуальные TP/SL/Breakeven по каждой позиции

Не выставляются на сервер — брокер их не видит, советник закрывает позиции сам:

- `InpUseVirtualTP` + `InpVirtualTPPts` — закрытие при +N пунктов.
- `InpUseVirtualSL` + `InpVirtualSLPts` — закрытие при −N пунктов.
- `InpUseVirtualBE` + `InpVirtualBEPts` — после +N пунктов фиксируется виртуальный безубыток.
- `InpUseVirtualTSL` + `InpVirtualTSLStartPts` + `InpVirtualTSLDistPts` — трейлинг по позициям.

Работают одновременно для всех управляемых позиций.

## Уведомления

`InpUseAlert`, `InpUseSound` + `InpSoundFile`, `InpUsePush`, `InpUseEmail`. Срабатывают на: vTP/vSL/vBE/vTSL, цель корзины, трейлинг корзины, EmergencyStop, переходы фаз HedgeLock и Partial Recovery, Slow Start блокировки.

## Сохранение состояния (Persistence)

`InpUsePersistence` — состояние пишется в `GlobalVariables` под префиксом `RECOVERI_<symbol>_<magic>_` и переживает перезапуск терминала:
- флаги Paused и EmergencyStop;
- пики корзины и виртуальный безубыток / TSL по каждой позиции;
- фаза HedgeLock FSM (`LK_*`) и фаза Partial Recovery (`PR_PH`);
- триггер запуска (`RC_TRIG`), отключение чужих EA (`OEAS_DIS`);
- **v1.60:** базис Recovery% (`RC_DD0`).

Ключи привязаны к символу + magic, поэтому несколько копий советника на разных парах работают независимо.

## Безусловная сетка лимитников

`InpUseUncondGrid` — при первом запуске сразу выставляет N уровней лимитников:
- `InpGridSide`: `BOTH` / `BUY` / `SELL`
- `InpGridLevels`, `InpGridStepPoints`, `InpGridStartLot`, `InpGridLotMultiplier`
- `InpGridReplaceFilled` — переоткрывать сработавшие уровни

Сработавший лимитник попадает под управление советника.

## Авто-распил лока (HedgeLock + InpAutoUnlock)

В режиме `MODE_HEDGE_LOCK` (`InpMode=3`) при `InpAutoUnlock=true` советник управляет локом по конечному автомату:

```
IDLE  --(loss > InpLockTriggerLoss)-->  LOCKED
LOCKED  --(одна нога в плюс >= InpUnlockProfitUSD или TSL)-->  UNWOUND
UNWOUND  --(оставшаяся нога в минус >= InpRelockTriggerLoss)-->  RELOCKED
RELOCKED --(одна нога в плюс)-->  UNWOUND
любая  --(все позиции закрыты внешне)-->  IDLE
```

| Параметр | Описание | Дефолт |
|---|---|---|
| `InpAutoUnlock` | Включить автомат | `false` |
| `InpUnlockProfitUSD` | Профит ноги для её закрытия | `30.0` |
| `InpUseSideTSL` | Трейлинг профита ноги | `true` |
| `InpUnlockTSLStart` / `InpUnlockTSLStep` | Пик и откат для TSL | `50` / `20` |
| `InpEnableRelock` | Переоткрывать частичный встречный лок | `false` |
| `InpRelockTriggerLoss` / `InpRelockLotFactor` / `InpMaxRelocks` | Параметры перелока | `80` / `0.5` / `2` |

**⚠️ Распил лока не выигрывает математически** у простого ожидания — каждый цикл «закрыть ногу + переоткрыть» теряет на спреде. Используйте на свой риск, обязательно с `InpUseEquityStop`.

## Кнопки на графике

| Кнопка | Действие |
|--------|----------|
| **Close All**     | Закрыть все управляемые позиции |
| **Pause / Resume**| Поставить советник на паузу |
| **Close BUY**     | Закрыть только BUY-сторону |
| **Close SELL**    | Закрыть только SELL-сторону |
| **Lock Now**      | Сразу залочить чистый объём встречной позицией |
| **Reset Stop**    | Сбросить аварийный equity-стоп |
| **Reset State**   | Обнулить runtime-флаги (Paused/Estop/BE/TSL остаются) |
| **BUY (manual)**  | Открыть ручной BUY на `InpManualLot` |
| **SELL (manual)** | Открыть ручной SELL на `InpManualLot` |
| **Avg Now** *(v1.60, только Mode 5)* | Открыть один PR-AVG на предпочитаемой стороне |

В **Strategy Tester (Visual mode)** все кнопки работают через polling `OBJPROP_STATE` (см. v1.42 в `CHANGELOG.md`).

## Фильтр времени

`InpUseTimeFilter` + `InpStartHour` / `InpEndHour` (если start>end — переход через полночь) + флаги дней `InpTradeMon..InpTradeSun`. Блокирует только открытие новых сделок.

## Новостной фильтр (экономкалендарь MT5)

`InpUseNewsFilter` использует **встроенный** календарь MT5 (`CalendarValueHistoryByCurrency`):
- `InpNewsHigh` / `InpNewsMedium` / `InpNewsLow`
- `InpNewsMinsBefore` / `InpNewsMinsAfter`

Срабатывает по обеим валютам символа (base + profit). На индексах/металлах пропускается.

## Защита счёта

- `InpUseEquityStop` + `InpEquityStopPct` — аварийное закрытие при просадке equity. Стоп держит состояние до сброса кнопкой **Reset Stop**.
- `InpCloseOnly` — режим «только закрытие».
- `InpMaxTrades`, `InpMaxLot`, `InpMaxSpreadPts` — предохранители.

## Типовые сценарии

### 1) «Закрой ручные сделки в плюсе $10 на любом символе»
```
InpMode = 0 (TargetProfit), InpManageScope = 1 (MANUAL), InpSymbolScope = 1 (ALL)
InpTargetProfit = 10.0, InpCloseOnly = true
```

### 2) «Усредни ручную убыточную EURUSD до безубытка, не торгуй на новостях NFP»
```
EA на графике EURUSD
InpMode = 1 (Averaging), InpManageScope = 1 (MANUAL), InpSymbolScope = 0 (CURRENT)
InpStepPoints = 300, InpStepMultiplier = 1.2, InpStartLot = 0.01, InpMaxTrades = 8
InpTargetProfit = 5.0
InpUseNewsFilter = true, InpNewsHigh = true, InpNewsMinsBefore = 30, InpNewsMinsAfter = 30
```

### 3) «Раздельные BUY и SELL корзины, каждая в +$5, по виртуальному SL −500 пт»
```
InpBasketMode = 1 (PER_SIDE)
InpTargetProfit = 5.0
InpUseVirtualSL = true, InpVirtualSLPts = 500
InpDrawTPLine = true   // отрисует две HLINE — одну на TP BUY, одну на TP SELL
```

### 4) «Только европейская сессия, мартингейл с трейлингом»
```
InpMode = 2, InpUseTimeFilter = true, InpStartHour = 9, InpEndHour = 18
InpUseBasketTSL = true, InpBasketTSLStart = 30, InpBasketTSLStep = 10
```

### 5) «Залочить просадку и автоматически распилить лок»
```
InpMode = 3 (HedgeLock), InpManageScope = 1 (MANUAL), InpSymbolScope = 0 (CURRENT)
InpBasketMode = 1 (PER_SIDE)
InpLockTriggerLoss = 50.0
InpLockLotFactor   = 1.0
InpAutoUnlock        = true
InpUnlockProfitUSD   = 30.0
InpUseSideTSL        = true
InpUnlockTSLStart    = 50.0
InpUnlockTSLStep     = 20.0
InpEnableRelock      = true
InpRelockTriggerLoss = 80.0
InpRelockLotFactor   = 0.5
InpMaxRelocks        = 2
InpUseEquityStop     = true, InpEquityStopPct = 30.0
```

### 6) «Прогнать стратегию усреднения с ручным входом в визуальном тестере»
```
InpMode = 1 (Averaging), InpManageScope = 2 (OWN), InpSymbolScope = 0 (CURRENT)
InpStartLot = 0.01, InpStepPoints = 300, InpStepMultiplier = 1.2
InpLotAdd = 0.01, InpMaxTrades = 8
InpTargetType = 0 (MONEY), InpTargetProfit = 5.0
InpUseEquityStop = true, InpEquityStopPct = 50.0
InpShowManualButtons = true, InpManualLot = 0.01
```
В тестере включи **Visual mode**, жми BUY/SELL — советник возьмёт позицию в управление и доведёт корзину до цели.

### 7) **v1.60**: «Partial Recovery с динамическим лотом и Slow Start»
```
InpMode = 5 (PartialRecovery), InpManageScope = 0 (ALL), InpSymbolScope = 0 (CURRENT)
InpStartTrigger = 2 (DD_MONEY), InpStartThreshold = 100  // активироваться при -$100
InpTargetProfit = 5.0
InpAvgLotMode = 1 (PCT_OF_LOSING)
InpAvgLotPctOfLosing = 15.0   // лот усреднителя = 15% от объёма убыточной стороны
InpAvgStepPts = 250, InpAvgStepMul = 1.2, InpAvgTPpts = 30
InpMaxAveragers = 10, InpPartCloseLot = 0.05
InpEnsureNetPositive = true, InpMinNetProfitPct = 10.0
InpUseSlowStart = true, InpSlowStartLossSteps = 4, InpSlowStartLossStepUSD = 30.0
// На -$30 откроется 1 усреднитель, на -$60 — 2, на -$90 — 3, на -$120+ — до 4
InpUseTrendFilter = true, InpTrendTF = PERIOD_H1, InpTrendFastMA = 21, InpTrendSlowMA = 50
InpDrawTPLine = true
InpUseEquityStop = true, InpEquityStopPct = 50
```

## Информационная панель

Показывает:
- режим, область управления, тип корзины
- кол-во позиций, BUY/SELL объёмы и средневзвешенные цены, P/L каждой стороны и общий
- пик(и), цель(и)
- **v1.60:** прогресс восстановления (`Recovery: NN%`)
- статус цикла (PR phase / Lock phase / Trigger)
- активные фильтры (PAUSE/TIME/NEWS)
- `Step:ATR(...) | SlowStart=N/M | Lot:FIXED/PCT/FROM-LOSS/MAX`
- статусную строку
- **v1.60:** цветовой статус-индикатор (квадрат)

## Дисклеймер

Усреднение, мартингейл и локирование увеличивают риск потери счёта. Сначала тестер стратегий и демо. Обязательно включайте `InpUseEquityStop`. `InpEnsureNetPositive` снижает, но не устраняет риск глубоких просадок. Автор ответственности не несёт.
