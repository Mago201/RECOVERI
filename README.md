# RECOVERI v2.00 — Hedge-Recovery EA для MT5

Советник для **восстановления убыточных позиций** через хеджирование с фрагментным закрытием. После активации:

1. **Хеджирует** убыточную позицию (CORE) встречным объёмом — фиксирует просадку.
2. Открывает **сетку восстановления** (GRID или ZONE).
3. Когда recovery-корзина даёт `InpCycleProfit` прибыли — закрывает recovery + откусывает фрагмент от хеджа и от убыточной позиции.
4. Повторяет циклы, пока CORE не закроется полностью. Затем закрывает остаток хеджа и переходит в IDLE.

> ⚠️ **Требуется hedging-mode счёт MT5** (несколько встречных позиций по одному символу). На netting-счетах EA откажется запускаться.

## Установка

1. Скопировать `RECOVERI.mq5` в `<MT5>/MQL5/Experts/`.
2. MetaEditor → **F7** (Compile).
3. Перетащить на график пары, где есть убыточная ручная позиция, разрешить автоторговлю.

## Логика работы (state machine)

```
                    ┌─────────────────────────────────────────┐
                    ▼                                         │
   ┌──────┐   activate    ┌─────────┐  hedge ok   ┌──────────────┐
   │ IDLE │──────────────►│ HEDGING │────────────►│ RECOVERING   │
   └──────┘               └─────────┘             └──────────────┘
       ▲                                              │
       │  core fully recovered                        │  cycle target hit:
       │  (after fragment cycles)                     │   - close all REC
       └──────────────────────────────────────────────┘   - partial-close hedge & core
                                                          - cycle++
```

## Активация (`InpTriggerMode`)

- **MANUAL** — нажимаешь кнопку **Activate** на панели. EA берёт самую убыточную позицию на текущем символе (с magic ≠ InpMagic) как CORE.
- **AUTO** — автоматически берёт самую убыточную ручную позицию, как только её убыток ≥ `InpTriggerLossMoney`.

## Режимы восстановления (`InpRecoveryMode`)

| Режим | Тип ордеров | Когда работает лучше |
|-------|-------------|----------------------|
| `GRID` | Лимитники (BUY_LIMIT/SELL_LIMIT) от текущей цены в сторону хеджа | Флэт, низкая волатильность |
| `ZONE` | Стопы (BUY_STOP/SELL_STOP) в сторону хеджа | Тренд, продолжение движения |

Параметры:
- `InpRecoveryLevels` — количество уровней (по умолчанию 5)
- `InpRecoveryStepPts` — шаг в пунктах
- `InpRecoveryStartLot` — лот первого уровня
- `InpRecoveryLotMult` — множитель лота (1.0 = равные, >1 = мартингейл)

## Positive Grid (опционально)

`InpUsePositiveGrid` — позволяет добавлять recovery-позиции **в направлении движения цены в нашу пользу**, ускоряя восстановление.

- `InpPosGridStepPts` — каждые N пунктов благоприятного движения добавляется новая позиция в сторону хеджа.
- `InpPosGridMinDistTPPts` — мягкий гейт: если cycle P/L уже ≥ 80% цели, новые positive-grid ордера не открываются (мы и так почти у цели).

## Фрагментное закрытие (ядро стратегии)

Когда recovery-корзина даёт прибыль ≥ `InpCycleProfit`:
1. Закрываются **все** recovery-позиции и pending-ордера → банкуется прибыль.
2. От HEDGE отрезается фрагмент `InpFragmentLot` (через `PositionClosePartial`).
3. От CORE отрезается фрагмент `InpFragmentLot`.
4. Цикл инкрементируется, новые recovery-ордера ставятся на следующем тике.

Фрагменты HEDGE и CORE равны → нетто-объём остаётся 0 (просадка по-прежнему заблокирована), но **часть исходного убытка реализована**, и компенсирована прибылью recovery.

Когда CORE опустошён — закрывается остаток HEDGE → IDLE.

## Кнопки панели

| Кнопка | Действие |
|--------|----------|
| **Activate** | (только в IDLE) взять самую убыточную позицию как CORE и начать хеджирование |
| **Pause** / **Resume** | Поставить state-machine на паузу. Ордера не закрываются, но новые циклы не запускаются. |
| **Stop / Reset** | Закрыть **всё** (recovery + hedge), сбросить state в IDLE. CORE-позиция (если она была ручная и до конца не отработана) **остаётся открытой** — её придётся закрыть руками. |

## Защита счёта

`InpUseEquityStop` + `InpEquityStopPct` — если equity / balance × 100 ≤ порога, EA закрывает все свои позиции (recovery + hedge) и переходит в `EMERGENCY`. CORE при этом тоже закрывается через `CloseAllPositions()`. Восстановление — только перезапуск EA.

## Persistence (переживание рестарта)

`InpUsePersistence = true` — состояние пишется в `GlobalVariables`:
- state, ticket CORE/HEDGE, начальный объём CORE, last positive-grid price, номер цикла.

Префикс ключей: `RECOVERI_<symbol>_<magic>_`. Можно запускать несколько экземпляров EA на разных парах одновременно.

## Фильтры времени и новостей

- `InpUseTimeFilter` + `InpStartHour`/`InpEndHour` — окно работы. Блокирует **только открытие** новых hedge/recovery — закрытие циклов и emergency-stop работают всегда.
- `InpUseNewsFilter` — встроенный экономкалендарь MT5, по обеим валютам символа. Уровни: `InpNewsHigh` / `InpNewsMedium`. Окно: `InpNewsMinsBefore` / `InpNewsMinsAfter`.

## Уведомления

`InpUseAlert` (всплывашка), `InpUseSound` + `InpSoundFile`, `InpUsePush` (телефон через Tools → Options → Notifications). Срабатывают на: adopt CORE, hedge open, cycle target, recovery complete, emergency stop, аварии.

## Информационная панель

Показывает в реальном времени: state, режим/триггер, CORE (тикет, объём текущий/начальный, цена, P/L), HEDGE, номер цикла, число открытых recovery-позиций и pending-ордеров, P/L текущего цикла vs цель, статус Positive Grid.

## Типовые сценарии

**1) «Спасти ручную BUY EUR/USD 0.05 в просадке −20$ через grid»**
```
InpTriggerMode      = MANUAL
InpRecoveryMode     = GRID
InpRecoveryLevels   = 5
InpRecoveryStepPts  = 200
InpRecoveryStartLot = 0.01
InpFragmentLot      = 0.01
InpCycleProfit      = 1.0
```
Открыть EA на EURUSD → нажать **Activate**. EA откроет SELL 0.05 хедж + 5 BuyLimit ниже рынка. По мере отскоков частично закрывает 0.01 от core+hedge раз в цикл (~$1 прибыли).

**2) «Авто-режим, агрессивный с positive-grid в тренде»**
```
InpTriggerMode      = AUTO
InpTriggerLossMoney = 10
InpRecoveryMode     = ZONE
InpRecoveryLevels   = 5
InpRecoveryStepPts  = 150
InpRecoveryLotMult  = 1.2          (мартингейл-сетка)
InpUsePositiveGrid  = true
InpPosGridStepPts   = 80
InpFragmentLot      = 0.01
InpCycleProfit      = 2.0
InpUseEquityStop    = true
InpEquityStopPct    = 60
```

**3) «Только европейская сессия, без новостей»**
```
InpUseTimeFilter   = true,  InpStartHour = 9,  InpEndHour = 18
InpUseNewsFilter   = true,  InpNewsHigh  = true, InpNewsMinsBefore = 30, InpNewsMinsAfter = 30
```

## Что выкинуто из v1.20

- Старые режимы (Averaging / Martingale / HedgeLock / SmartClose) — заменены единой стратегией Hedge-Recovery.
- Виртуальные TP/SL/BE/TSL по каждой позиции — не нужны в hedge-recovery.
- Старая безусловная сетка лимитников — заменена recovery-grid внутри state machine.
- Управление чужими позициями (manual-mode/own-mode) — теперь EA адоптирует одну CORE-позицию, и работает только с ней + своими hedge/recovery.

Если для прежней логики нужен старый файл — он остался в истории коммитов до v2.0.

## Дисклеймер

Hedge-recovery с мартингейлом/фрагментацией — высокорисковая техника. На сильном тренде против CORE без `EquityStop` — слив. Тестируй в Strategy Tester на исторических данных, потом на демо. Автор ответственности не несёт.
