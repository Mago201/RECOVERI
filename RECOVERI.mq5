//+------------------------------------------------------------------+
//|                                                     RECOVERI.mq5 |
//|                       Universal MT5 Account Recovery EA          |
//|  v1.52                                                           |
//|  Добавлено в v1.52 (Mode 5 — ATR-сетка + выравнивание лока):     |
//|    - Шаг сетки усреднителей теперь может рассчитываться от ATR   |
//|      выбранного таймфрейма. Управление: InpAvgStepUseATR=true,   |
//|      InpAvgStepATRTF (по умолчанию D1), InpAvgStepATRPeriod (14),|
//|      InpAvgStepATRMul (множитель ATR, по умолчанию 0.5),          |
//|      InpAvgStepATRMin (минимум в пунктах — пол на случай тонкого  |
//|      рынка). Эффективный шаг = ATR(TF, period)/Point * Mul, далее |
//|      применяется существующий InpAvgStepMul^chainIdx, поэтому     |
//|      длинные цепочки по-прежнему расходятся. При выключенном      |
//|      ATR-режиме поведение прежнее (фикс. InpAvgStepPts).          |
//|    - Периодическое выравнивание лока по выбранному ТФ:           |
//|      InpLockAlignUseTF=true, InpLockAlignTF (D1), InpLockAlign-  |
//|      ThresholdLot (мин. перевес в лотах для срабатывания),       |
//|      InpLockAlignOnlyProfit (true = срезать только из «+зоны»).  |
//|      Раз в новый бар выбранного ТФ советник суммирует BUY/SELL   |
//|      объёмы по всем managed-позициям, определяет «тяжёлую»       |
//|      сторону (перевес), и откусывает её до объёма противоположной|
//|      — закрывая в первую очередь самые ПРИБЫЛЬНЫЕ позиции на     |
//|      этой стороне (фиксируем «положительную зону»). Если         |
//|      InpLockAlignOnlyProfit=false и в плюсе на тяжёлой стороне   |
//|      позиций нет, добор идёт по DESC-PnL (наименее убыточные).   |
//|      Работает в Mode 3 (HedgeLock) и Mode 5 (PartialRecovery),   |
//|      гейтится один раз на бар выбранного ТФ.                     |
//|  Добавлено в v1.51 (фикс Mode 5 — trend-flip trim):              |
//|    - Исправлен баг: при смене тренда советник закрывал           |
//|      локирующий ордер целиком (или гораздо больше, чем нужно),   |
//|      потому что TrimStrongSideToWeak() считал имбаланс ПО ВСЕМ   |
//|      managed-позициям (PR-AVG, PR-LOCK, оригиналы) и сортировал  |
//|      срезаемую сторону по PnL DESC. Лок обычно имеет наибольший  |
//|      абсолютный PnL (он крупнее по объёму), поэтому попадал      |
//|      первым в очередь на закрытие, и забирал на себя весь diff,  |
//|      включая объём ещё открытых усреднителей. В результате лок   |
//|      срезался не на величину чипа от убыточника, а на «BUY−SELL  |
//|      по всем группам».                                           |
//|    - Теперь trim работает прицельно: считает объём LOCK на одной |
//|      стороне и объём ОРИГИНАЛЬНЫХ (не-PR-*) позиций на           |
//|      противоположной стороне, и режет ИМЕННО лок до объёма       |
//|      оставшегося оригинала. Усреднители (PR-AVG-*) и позиции на  |
//|      той же стороне, что и лок, в расчёте не участвуют и trim-ом |
//|      не трогаются — они продолжают закрываться обычным путём     |
//|      (TP усреднителя + чип убыточника, либо InpCloseOldGridOn-   |
//|      TrendFlip по корзинному профиту). Пример: SELL 1.0 → 0.8    |
//|      после чипа, лок BUY 1.0; на флипе лок BUY режется на 0.2 →  |
//|      остаётся SELL 0.80 / lock BUY 0.80, усреднители целы.       |
//|    - Если лока нет (или он на обеих сторонах в каких-то          |
//|      нештатных конфигурациях) — trim ничего не делает.           |
//|  Добавлено в v1.50 (Mode 5 — Partial Recovery):                  |
//|    - Опциональное выравнивание объёмов на смене тренда:          |
//|      InpTrendFlipTrimStrong (по умолчанию false). Когда флипнул  |
//|      тренд-фильтр, советник считает суммарный объём всех         |
//|      managed-позиций раздельно по BUY/SELL (включая PR-AVG-*,    |
//|      PR-LOCK-*, исходные ручные/убыточные ордера, AVG-*, GRID-*) |
//|      и, если разница превышает minLot брокера, режет «сильную»  |
//|      сторону до объёма «слабой». На срезаемой стороне сначала    |
//|      закрываются позиции с наибольшим PnL (фиксируется прибыль   |
//|      раньше, чем убытки). Последняя позиция при необходимости    |
//|      закрывается частично, чтобы выйти ровно на нужный объём.    |
//|      После trim-а g_prAvgCount{Buy,Sell} пересчитываются скан-   |
//|      ом, при включённой persistence — сохраняется состояние.    |
//|      Работает совместно с InpRestartGridOnTrendFlip (рестарт     |
//|      счётчиков на новой стороне) и InpCloseOldGridOnTrendFlip   |
//|      (флуш старых PR-AVG по профиту корзинно): trim делает       |
//|      разовое выравнивание на флипе, остальные ключи продолжают  |
//|      применяться к оставшейся PR-AVG-цепочке.                    |
//|  Добавлено в v1.44 (Mode 5 — Partial Recovery):                  |
//|    - Закрытие старой сетки усреднителей по профиту при смене     |
//|      тренда. До 1.43 при флипе тренда счётчик усреднителей       |
//|      сбрасывался на новой стороне, а старые PR-AVG-* позиции на  |
//|      «уходящей» стороне оставались висеть и каждая отрабатывала  |
//|      свой собственный InpAvgTPpts; пока они ждали, цена уходила  |
//|      в новую сторону и старая цепочка садилась в ещё больший     |
//|      минус. Теперь в момент флипа советник «армирует» старую     |
//|      сторону: на каждом тике суммирует PnL всех PR-AVG-* на той  |
//|      стороне, и как только сумма пересекает InpOldGridCloseProfit|
//|      ($, по умолчанию 0) — закрывает их все разом одной корзиной.|
//|      Если флип повторится до закрытия — сторона переармируется   |
//|      на новую «старую». Управляется InpCloseOldGridOnTrendFlip   |
//|      (по умолчанию true) и InpOldGridCloseProfit. Состояние      |
//|      сохраняется в GV (PR_COA / PR_COS) и сбрасывается на        |
//|      смене режима / кнопкой Reset State.                         |
//|  Добавлено в v1.43 (фиксы режима 5 — Partial Recovery):          |
//|    - Net-positive guard на партиал-закрытии: при срабатывании TP |
//|      усреднителя (PR-AVG) теперь ЧИП от убыточной позиции        |
//|      рассчитывается динамически так, чтобы сумма (профит         |
//|      усреднителя + убыток откушенного куска лока/убыточника)     |
//|      была >= InpMinNetProfit. Раньше чип был фиксированный       |
//|      InpPartCloseLot, и при глубоком минусе цикл «закрыть TP +   |
//|      откусить часть» уходил в минус. Теперь либо чип             |
//|      уменьшается до безопасного объёма (≥ minLot брокера), либо  |
//|      чип пропускается и усреднитель просто фиксирует свой        |
//|      профит. Управляется ключом InpEnsureNetPositive (по         |
//|      умолчанию true). Старое поведение возвращается              |
//|      InpEnsureNetPositive=false.                                 |
//|    - Перезапуск сетки на смене тренда: если включён              |
//|      InpUseTrendFilter и тренд (быстрая/медленная MA на старшем  |
//|      ТФ) переворачивается, советник сбрасывает счётчик           |
//|      усреднителей g_prAvgCount* и one-per-bar-gate на той        |
//|      стороне, куда теперь идёт тренд, чтобы новая цепочка        |
//|      усреднителей открылась немедленно (мультипликатор объёма    |
//|      и шага начнётся с нуля), не дожидаясь шага от последнего    |
//|      «старого» усреднителя. Управляется InpRestartGridOnTrendFlip|
//|      (по умолчанию true).                                        |
//|  Добавлено в v1.42:                                              |
//|    - Фикс: кнопки панели (BUY/SELL manual, Close All и др.) не   |
//|      реагировали в Strategy Tester. В MT5 визуальном тестере     |
//|      OnChartEvent доставляет CHARTEVENT_OBJECT_CLICK ненадёжно.  |
//|      Добавлен PollPanelButtons() — опрос OBJPROP_STATE кнопок    |
//|      каждый тик; если кнопка нажата, диспетчеризуем обработчик   |
//|      через общий HandlePanelClick(). Активно ТОЛЬКО в тестере    |
//|      (MQL_TESTER=true), в live торговле поведение неизменно.    |
//|  Добавлено в v1.41:                                              |
//|    - Защита persistence-state от «застревания» между сменами     |
//|      режимов: в GV сохраняется отметка MODE; при несовпадении    |
//|      InpMode с сохранённым — LK_*, PR_PH, RC_TRIG, OEAS_DIS      |
//|      сбрасываются в дефолты (PAUSED/ESTOP/BE/TSL остаются).      |
//|    - Кнопка «Reset State» на панели — обнуляет runtime-флаги     |
//|      (g_lockPhase, g_prPhase, g_recoveryTriggered,               |
//|      g_otherEAsDisabled, peaks) и стирает соответствующие GV.    |
//|    - В OnInit() выводится фактический статус загрузки            |
//|      (clean / loaded / mode-mismatch) для удобства диагностики.  |
//|  Добавлено в v1.40 ("ULTIMATE"):                                 |
//|    - Режим MODE_PARTIAL_RECOVERY: лок + усреднители +            |
//|      ДРОБНОЕ закрытие убыточной позиции (a la AW Recovery).      |
//|      Каждый прибыльный усреднитель закрывает не только себя, но  |
//|      и кусок самого убыточного ордера через PositionClosePartial.|
//|    - Standby-mode: советник стартует только при достижении       |
//|      просадки (Instant / % / $) — InpStartTrigger.               |
//|    - Тренд-фильтр для усреднителей (быстрая/медленная MA на      |
//|      старшем ТФ) — InpUseTrendFilter.                            |
//|    - One-Per-Bar: не более одного усреднителя на свечу.          |
//|    - Closing overlap: в длинной цепочке усреднителей закрывается |
//|      только первый+последний (InpOverlapAfterN).                 |
//|    - Приоритет обработки в SmartClose/PartialRecovery:           |
//|      EASY / HARD / FIRST_TICKET.                                 |
//|    - Email-уведомления (SendMail) дополнительно к Alert/Push.    |
//|    - Disable other EAs at launch — снять чужие советники с       |
//|      символа или со всех символов (опционально).                 |
//|  v1.31:                                                          |
//|    - Кнопки ручного открытия BUY/SELL на панели                  |
//|      (для теста стратегии в визуальном режиме и на лайве)        |
//|    - Все input-параметры переведены на русский                   |
//|  v1.30:                                                          |
//|    - Авто-распил (раскулачивание) лока в режиме HedgeLock        |
//|      Фазы: IDLE -> LOCKED -> UNWOUND -> (RELOCKED) -> ...        |
//|      Закрытие выгодной ноги по цели/трейлингу                    |
//|      Опциональное переоткрытие частичного встречного лока        |
//|    - Валидация InpLockTriggerLoss > 0                            |
//|    - g_gridPlaced ставится только при реальной установке сетки   |
//|  v1.20:                                                          |
//|    - Виртуальный трейлинг-стоп по каждой позиции                 |
//|    - Уведомления Alert / Sound / Push на ключевые события        |
//|    - Сохранение состояния через GlobalVariables                  |
//|    - Безусловная сетка лимитников (BUY_LIMIT/SELL_LIMIT, N уров.)|
//|  v1.10:                                                          |
//|    - Закрытие по стороне (BUY/SELL отдельные корзины)            |
//|    - Виртуальные TP/SL/безубыток по каждой позиции               |
//|    - Кнопки на панели: Close All / Pause / Lock Now / etc.       |
//|    - Фильтры по времени и экономкалендарю MT5                    |
//+------------------------------------------------------------------+
#property copyright "RECOVERI"
#property version   "1.52"
#property strict
#property description "Universal MT5 Recovery EA v1.52 - ATR averaging grid + lock alignment by TF"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//=== Enums ==========================================================
enum ENUM_RECOVERY_MODE
  {
   MODE_TARGET_PROFIT     = 0,    // 0: Только закрытие по цели
   MODE_AVERAGING         = 1,    // 1: Усреднение
   MODE_MARTINGALE        = 2,    // 2: Мартингейл-сетка
   MODE_HEDGE_LOCK        = 3,    // 3: Хедж-лок
   MODE_SMART_CLOSE       = 4,    // 4: Парное закрытие (SmartClose)
   MODE_PARTIAL_RECOVERY  = 5     // 5: Дробное восстановление (a la AW Recovery)
  };

enum ENUM_MANAGE_SCOPE
  {
   MANAGE_ALL    = 0,         // 0: Все позиции
   MANAGE_MANUAL = 1,         // 1: Только ручные (magic==0)
   MANAGE_OWN    = 2          // 2: Только свои (по InpMagic)
  };

enum ENUM_SYMBOL_SCOPE
  {
   SCOPE_CURRENT = 0,         // 0: Текущий символ
   SCOPE_ALL     = 1          // 1: Все символы
  };

enum ENUM_TARGET_TYPE
  {
   TARGET_MONEY   = 0,        // 0: Деньги (валюта депо)
   TARGET_PERCENT = 1,        // 1: % от баланса
   TARGET_PIPS    = 2         // 2: Эквивалент в пунктах
  };


enum ENUM_BASKET_MODE
  {
   BASKET_COMBINED = 0,       // 0: Общая корзина BUY+SELL
   BASKET_PER_SIDE = 1        // 1: Раздельные корзины BUY и SELL
  };

enum ENUM_GRID_SIDE
  {
   GRID_BOTH = 0,             // 0: Обе стороны (BUY_LIMIT + SELL_LIMIT)
   GRID_BUY  = 1,             // 1: Только BUY_LIMIT (ниже рынка)
   GRID_SELL = 2              // 2: Только SELL_LIMIT (выше рынка)
  };

enum ENUM_LOCK_PHASE
  {
   PHASE_IDLE     = 0,        // 0: лока нет
   PHASE_LOCKED   = 1,        // 1: обе стороны открыты (лок)
   PHASE_UNWOUND  = 2,        // 2: одна нога закрыта, ведём оставшуюся
   PHASE_RELOCKED = 3         // 3: переоткрыт встречный лок поверх остатка
  };

enum ENUM_START_TRIGGER
  {
   START_INSTANT       = 0,   // 0: Запуск сразу
   START_DD_PERCENT    = 1,   // 1: По просадке в % от баланса
   START_DD_MONEY      = 2    // 2: По просадке в валюте депо
  };

enum ENUM_RECOVERY_PRIORITY
  {
   PRIO_EASY           = 0,   // 0: Сначала самые лёгкие (минимальный убыток)
   PRIO_HARD           = 1,   // 1: Сначала самые тяжёлые (максимальный убыток)
   PRIO_FIRST_TICKET   = 2    // 2: Конкретный тикет первым
  };

enum ENUM_PR_PHASE
  {
   PR_IDLE       = 0,         // 0: ожидание триггера
   PR_LOCKING    = 1,         // 1: выравнивание объёмов в лок
   PR_RECOVERING = 2,         // 2: распил усреднителями + partial close
   PR_DONE       = 3          // 3: восстановление завершено
  };

enum ENUM_DISABLE_EAS
  {
   DISABLE_NONE        = 0,   // 0: Не выключать другие советники
   DISABLE_SAME_SYMBOL = 1,   // 1: Выключить советники на этом символе
   DISABLE_ALL_SYMBOLS = 2    // 2: Выключить советники на всех символах
  };

// Internal: result of LoadState() for diagnostic logging in OnInit().
// Not exposed as input.
enum ENUM_LOAD_STATUS
  {
   LS_CLEAN         = 0,      // 0: persistence-storage пуст -> чистый старт
   LS_LOADED        = 1,      // 1: state совпал по режиму и загружен полностью
   LS_MODE_MISMATCH = 2       // 2: сохранённый mode != InpMode -> mode-specific keys обнулены
  };

//=== Inputs =========================================================
input group "=== Общие ==="
input ENUM_RECOVERY_MODE InpMode          = MODE_TARGET_PROFIT;  // Режим восстановления
input ENUM_MANAGE_SCOPE  InpManageScope   = MANAGE_ALL;          // Какие позиции брать в управление
input ENUM_SYMBOL_SCOPE  InpSymbolScope   = SCOPE_CURRENT;       // Область по символу
input long               InpMagic         = 20260520;            // Magic number советника
input string             InpComment       = "RECOVERI";          // Комментарий к ордерам
input int                InpSlippage      = 30;                  // Допустимое проскальзывание (пункты)
input double             InpMaxSpreadPts  = 0;                   // Макс. спред (пункты, 0 = не проверять)

input group "=== Корзина и цель ==="
input ENUM_BASKET_MODE   InpBasketMode    = BASKET_COMBINED;     // Режим корзины
input ENUM_TARGET_TYPE   InpTargetType    = TARGET_MONEY;        // Тип цели
input double             InpTargetProfit  = 10.0;                // Значение цели
input bool               InpUseBasketTSL  = false;               // Включить трейлинг корзины
input double             InpBasketTSLStart= 20.0;                // Старт трейлинга (профит корзины)
input double             InpBasketTSLStep = 5.0;                 // Откат от пика для закрытия

input group "=== Виртуальные TP/SL ==="
input bool               InpUseVirtualTP  = false;               // Включить виртуальный TP
input int                InpVirtualTPPts  = 200;                 // Виртуальный TP (пункты)
input bool               InpUseVirtualSL  = false;               // Включить виртуальный SL
input int                InpVirtualSLPts  = 1000;                // Виртуальный SL (пункты)
input bool               InpUseVirtualBE  = false;               // Включить виртуальный безубыток
input int                InpVirtualBEPts  = 100;                 // Триггер безубытка (пункты)

input group "=== Виртуальный трейлинг-стоп (по каждой позиции) ==="
input bool               InpUseVirtualTSL  = false;              // Включить трейлинг по позициям
input int                InpVirtualTSLStartPts = 200;            // Профит для активации трейлинга (пункты)
input int                InpVirtualTSLDistPts  = 100;            // Расстояние трейлинга от пика (пункты)

input group "=== Стратегии (Averaging/Martingale) ==="
input double             InpStartLot      = 0.01;                // Стартовый лот
input double             InpLotMultiplier = 1.5;                 // Множитель лота (мартингейл)
input double             InpLotAdd        = 0.0;                 // Прибавка к лоту (усреднение, 0 = не использовать)
input int                InpStepPoints    = 300;                 // Базовый шаг сетки (пункты)
input double             InpStepMultiplier= 1.2;                 // Множитель шага сетки
input int                InpMaxTrades     = 10;                  // Макс. позиций в корзине
input double             InpMaxLot        = 1.0;                 // Лимит лота на одну позицию

input group "=== HedgeLock ==="
input double             InpLockTriggerLoss= 50.0;               // Убыток корзины для открытия лока (валюта депо)
input double             InpLockLotFactor = 1.0;                 // Доля чистого объёма для лока (1.0 = 100%)


input group "=== Авто-распил лока (Mode 3) ==="
input bool               InpAutoUnlock          = false;   // Включить авто-распил после лока
input double             InpUnlockProfitUSD     = 30.0;    // Профит ОДНОЙ ноги для её закрытия (валюта депо)
input bool               InpUseSideTSL          = true;    // Трейлинг профита ноги при распиле
input double             InpUnlockTSLStart      = 50.0;    // Пик профита ноги для активации TSL
input double             InpUnlockTSLStep       = 20.0;    // Откат от пика для закрытия ноги
input bool               InpEnableRelock        = false;   // Переоткрывать частичный встречный лок при провале
input double             InpRelockTriggerLoss   = 80.0;    // Убыток на оставшейся ноге для перелока (валюта депо)
input double             InpRelockLotFactor     = 0.5;     // Доля объёма оставшейся ноги для перелока (0..1]
input int                InpMaxRelocks          = 2;       // Максимум последовательных перелоков


input group "=== Standby-режим (старт по триггеру) ==="
input ENUM_START_TRIGGER InpStartTrigger     = START_INSTANT;        // Триггер запуска
input double             InpStartThreshold   = 100.0;                // Порог: % просадки или сумма ($)
input bool               InpAutoResetAfterDone = false;              // Автосброс триггера после восстановления

input group "=== Partial Recovery (Mode 5) ==="
input double             InpPartCloseLot     = 0.10;                 // Размер части убыточной позиции для закрытия (лот)
input double             InpAvgVolume        = 0.15;                 // Объём первого усреднителя (≈ Part * 1.5)
input double             InpAvgVolumeMul     = 1.0;                  // Множитель объёма усреднителей (>=1)
input int                InpAvgStepPts       = 250;                  // Шаг сетки усреднителей (пункты)
input double             InpAvgStepMul       = 1.2;                  // Множитель шага усреднителей
input int                InpAvgTPpts         = 30;                   // TP усреднителя (пункты, должен > 3*spread)
input int                InpMaxAveragers     = 15;                   // Макс. число одновременных усреднителей
input bool               InpPRBidirectional  = false;                // Открывать усреднители в обе стороны
input int                InpOverlapAfterN    = 0;                    // Closing overlap: 0=off, N=>после N оставлять только first+last
input ENUM_RECOVERY_PRIORITY InpRecoveryPriority = PRIO_HARD;        // Приоритет: какие убыточные ордера обрабатывать первыми
input ulong              InpFirstTicket      = 0;                    // Конкретный тикет первым (0=не использовать)
input bool               InpEnsureNetPositive = true;                // Mode5: гарантировать неотрицательный итог пары (TP усреднителя + чип убыточника)
input double             InpMinNetProfit      = 0.0;                 // Mode5: минимальный итог пары в валюте депо (>=0), абсолютный «пол»
input double             InpMinNetProfitPct   = 0.0;                 // Mode5: минимальный итог пары в % от прибыли усреднителя (0..100). Эффективный пол = max(InpMinNetProfit, avgProfit*Pct/100)
input bool               InpRestartGridOnTrendFlip = true;           // Mode5: при смене тренда сбрасывать счётчик усреднителей на новой стороне
input bool               InpCloseOldGridOnTrendFlip = true;          // Mode5: при смене тренда закрывать старую сетку усреднителей по профиту корзинно
input double             InpOldGridCloseProfit     = 0.0;            // Mode5: мин. суммарный профит старой сетки для её закрытия (валюта депо, >=0)
input bool               InpTrendFlipTrimStrong    = false;          // Mode5: при смене тренда срезать лок до объёма противоположного оригинала (PR-AVG не трогаются)

input group "=== Тренд-фильтр для усреднителей ==="
input bool               InpUseTrendFilter   = false;                // Включить тренд-фильтр (MA cross на старшем ТФ)
input ENUM_TIMEFRAMES    InpTrendTF          = PERIOD_H1;            // Таймфрейм для тренд-фильтра
input int                InpTrendFastMA      = 21;                   // Период быстрой MA
input int                InpTrendSlowMA      = 50;                   // Период медленной MA
input bool               InpOneOrderPerBar   = false;                // Не более одного усреднителя на свечу

input group "=== ATR-сетка усреднителей (Mode 5) ==="
input bool               InpAvgStepUseATR    = false;                // Брать шаг сетки усреднителей из ATR выбранного ТФ
input ENUM_TIMEFRAMES    InpAvgStepATRTF     = PERIOD_D1;            // ТФ для ATR (D1 по умолчанию)
input int                InpAvgStepATRPeriod = 14;                   // Период ATR
input double             InpAvgStepATRMul    = 0.5;                  // Множитель ATR (шаг = ATR/Point * Mul, в пунктах)
input int                InpAvgStepATRMin    = 100;                  // Минимум шага в пунктах (пол при тонком рынке/нулевом ATR)

input group "=== Выравнивание лока по ТФ (Mode 3/5) ==="
input bool               InpLockAlignUseTF      = false;             // Выравнивать перевес BUY/SELL раз в бар выбранного ТФ
input ENUM_TIMEFRAMES    InpLockAlignTF         = PERIOD_D1;         // ТФ выравнивания (D1 по умолчанию)
input double             InpLockAlignThresholdLot = 0.0;              // Мин. перевес в лотах для срабатывания (0 = только > minLot)
input bool               InpLockAlignOnlyProfit = true;              // Срезать только позиции в плюсе («положительная зона»)

input group "=== Отключение чужих советников ==="
input ENUM_DISABLE_EAS   InpDisableOtherEAs  = DISABLE_NONE;         // Снять других ботов при старте recovery

input group "=== Защита счёта ==="
input bool               InpUseEquityStop = false;               // Включить аварийный equity-стоп
input double             InpEquityStopPct = 50.0;                // Порог equity (% от баланса)
input bool               InpCloseOnly     = false;               // Только закрытие (новые сделки не открывать)

input group "=== Фильтр времени ==="
input bool               InpUseTimeFilter = false;               // Включить фильтр времени
input int                InpStartHour     = 0;                   // Начало торгового окна (час 0..24)
input int                InpEndHour       = 24;                  // Конец торгового окна (час 0..24)
input bool               InpTradeMon      = true;                // Понедельник
input bool               InpTradeTue      = true;                // Вторник
input bool               InpTradeWed      = true;                // Среда
input bool               InpTradeThu      = true;                // Четверг
input bool               InpTradeFri      = true;                // Пятница
input bool               InpTradeSat      = false;               // Суббота
input bool               InpTradeSun      = false;               // Воскресенье

input group "=== Новостной фильтр (MT5 Calendar) ==="
input bool               InpUseNewsFilter = false;               // Включить новостной фильтр
input bool               InpNewsHigh      = true;                // Блокировать события High
input bool               InpNewsMedium    = false;               // Блокировать события Medium
input bool               InpNewsLow       = false;               // Блокировать события Low
input int                InpNewsMinsBefore= 30;                  // Минут до события
input int                InpNewsMinsAfter = 30;                  // Минут после события

input group "=== Уведомления ==="
input bool               InpUseAlert      = true;                // Всплывающий Alert()
input bool               InpUseSound      = false;               // Звук
input string             InpSoundFile     = "alert.wav";         // Звуковой файл
input bool               InpUsePush       = false;               // Push на телефон (Settings -> Notifications)
input bool               InpUseEmail      = false;               // Email (требует SMTP в Tools->Options->Email)

input group "=== Сохранение состояния ==="
input bool               InpUsePersistence= true;                // Сохранять paused/BE/TSL/peaks через GlobalVariables

input group "=== Безусловная сетка (limit-ордера) ==="
input bool               InpUseUncondGrid     = false;           // Включить безусловную сетку лимитников
input ENUM_GRID_SIDE     InpGridSide          = GRID_BOTH;       // Сторона сетки
input int                InpGridLevels        = 5;               // Количество уровней
input int                InpGridStepPoints    = 200;             // Шаг между уровнями (пункты)
input double             InpGridStartLot      = 0.01;            // Лот первого уровня
input double             InpGridLotMultiplier = 1.0;             // Множитель лота (1.0 = одинаковый, >1 = мартингейл)
input bool               InpGridReplaceFilled = false;           // Переоткрывать сработавшие уровни

input group "=== Ручная торговля (тестер/график) ==="
input bool               InpShowManualButtons = true;            // Показывать кнопки ручного открытия BUY/SELL
input double             InpManualLot         = 0.01;            // Лот для ручных кнопок BUY/SELL

input group "=== Панель ==="
input bool               InpShowPanel     = true;                // Показывать панель на графике
input color              InpPanelColor    = clrWhite;            // Цвет текста панели
input int                InpPanelFontSize = 10;                  // Размер шрифта панели

//=== Globals ========================================================
CTrade         trade;
CPositionInfo  pos;
CSymbolInfo    sym;
CAccountInfo   acc;

struct BasketState
  {
   int      count, buyCount, sellCount;
   double   buyVolume, sellVolume;
   double   buyPriceAvg, sellPriceAvg;
   double   profit, buyProfit, sellProfit;
   ulong    worstBuyTicket, worstSellTicket;
   datetime lastOpenTime;
   double   lastOpenPriceB, lastOpenPriceS;
   double   lastOpenLotB,   lastOpenLotS;
  };


double  g_peakProfit     = 0.0;
double  g_peakBuyProfit  = 0.0;
double  g_peakSellProfit = 0.0;
bool    g_emergencyStop  = false;
bool    g_paused         = false;
string  g_panelPrefix    = "RECOVERI_";
string  g_blockReason    = "";
ulong   g_beTickets[];

// Per-position virtual trailing stop state
ulong   g_tslTickets[];     // tickets being trailed
double  g_tslPeaks[];       // peak profit (in points) per ticket

// Grid state
bool    g_gridPlaced     = false;

// Lock-unwind state machine
ENUM_LOCK_PHASE    g_lockPhase     = PHASE_IDLE;
ENUM_POSITION_TYPE g_remainingSide = POSITION_TYPE_BUY;  // valid only in PHASE_UNWOUND
double  g_lockPeakBuy    = 0.0;
double  g_lockPeakSell   = 0.0;
int     g_relockCount    = 0;

// Standby mode
bool    g_recoveryTriggered = false;       // true once start trigger has fired
double  g_baselineBalance   = 0.0;         // captured at OnInit for % drawdown calc
bool    g_otherEAsDisabled  = false;       // disable-other-EAs done once

// Partial Recovery state
ENUM_PR_PHASE g_prPhase     = PR_IDLE;
datetime      g_prLastBarTime = 0;         // for one-per-bar averagers (BUY side)
datetime      g_prLastBarTimeS= 0;         // for one-per-bar averagers (SELL side)
int           g_prAvgCountBuy = 0;
int           g_prAvgCountSell= 0;
int           g_prLastTrend   = 0;         // last seen trend direction (-1/0/+1) for flip detection

// v1.44: close-old-grid-on-trend-flip state.  Set when trend flips while
// PR_RECOVERING; on each tick we sum PnL of all PR-AVG-* on the marked
// side and close the whole basket when it crosses InpOldGridCloseProfit.
bool                g_prCloseOldActive = false;
ENUM_POSITION_TYPE  g_prCloseOldSide   = POSITION_TYPE_BUY;

// v1.52: gate for the TF-driven lock alignment routine.  Tracks the
// last bar time of InpLockAlignTF on which AlignLockByTF() ran, so the
// routine fires once per bar and not on every tick.
datetime            g_alignLastBarTime = 0;

// GlobalVariables key prefix (instance-scoped: symbol + magic)
string  g_gvPrefix       = "";

#define BTN_CLOSE_ALL    "RECOVERI_BTN_CLOSE_ALL"
#define BTN_CLOSE_BUY    "RECOVERI_BTN_CLOSE_BUY"
#define BTN_CLOSE_SELL   "RECOVERI_BTN_CLOSE_SELL"
#define BTN_PAUSE        "RECOVERI_BTN_PAUSE"
#define BTN_LOCK         "RECOVERI_BTN_LOCK"
#define BTN_RESET        "RECOVERI_BTN_RESET"
#define BTN_RESET_STATE  "RECOVERI_BTN_RESET_STATE"
#define BTN_MANUAL_BUY   "RECOVERI_BTN_MANUAL_BUY"
#define BTN_MANUAL_SELL  "RECOVERI_BTN_MANUAL_SELL"

//+------------------------------------------------------------------+
int OnInit()
  {
   // --- Input validation ---
   if(InpStartTrigger != START_INSTANT && InpStartThreshold <= 0)
     {
      Print("InpStartThreshold must be > 0 when InpStartTrigger != INSTANT");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpMode == MODE_PARTIAL_RECOVERY)
     {
      if(InpPartCloseLot <= 0)
        { Print("InpPartCloseLot must be > 0"); return INIT_PARAMETERS_INCORRECT; }
      if(InpAvgVolume <= 0)
        { Print("InpAvgVolume must be > 0"); return INIT_PARAMETERS_INCORRECT; }
      if(InpAvgVolume < InpPartCloseLot)
        Print("WARNING: InpAvgVolume (", InpAvgVolume,
              ") < InpPartCloseLot (", InpPartCloseLot,
              "). Recommended ratio is 1.5x. Recovery may be unstable.");
      if(InpAvgStepPts <= 0)
        { Print("InpAvgStepPts must be > 0"); return INIT_PARAMETERS_INCORRECT; }
      if(InpAvgTPpts <= 0)
        { Print("InpAvgTPpts must be > 0"); return INIT_PARAMETERS_INCORRECT; }
      if(InpMaxAveragers <= 0)
        { Print("InpMaxAveragers must be > 0"); return INIT_PARAMETERS_INCORRECT; }
      if(InpUseTrendFilter && (InpTrendFastMA <= 0 || InpTrendSlowMA <= 0 || InpTrendFastMA >= InpTrendSlowMA))
        { Print("Trend filter MA periods invalid (need 0<fast<slow)"); return INIT_PARAMETERS_INCORRECT; }
      if(InpMinNetProfit < 0)
        { Print("InpMinNetProfit must be >= 0"); return INIT_PARAMETERS_INCORRECT; }
      if(InpOldGridCloseProfit < 0)
        { Print("InpOldGridCloseProfit must be >= 0"); return INIT_PARAMETERS_INCORRECT; }
      // v1.52 ATR-grid sanity
      if(InpAvgStepUseATR)
        {
         if(InpAvgStepATRPeriod <= 0)
           { Print("InpAvgStepATRPeriod must be > 0"); return INIT_PARAMETERS_INCORRECT; }
         if(InpAvgStepATRMul <= 0)
           { Print("InpAvgStepATRMul must be > 0"); return INIT_PARAMETERS_INCORRECT; }
         if(InpAvgStepATRMin <= 0)
           { Print("InpAvgStepATRMin must be > 0 (floor in points)"); return INIT_PARAMETERS_INCORRECT; }
        }
     }

   // v1.52: TF-based lock alignment is available in Mode 3 (HedgeLock) and
   // Mode 5 (PartialRecovery). Sanity-check inputs here regardless of
   // the active mode so misconfig fails fast.
   if(InpLockAlignUseTF && InpLockAlignThresholdLot < 0)
     {
      Print("InpLockAlignThresholdLot must be >= 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpMode == MODE_HEDGE_LOCK)
     {
      if(InpLockTriggerLoss <= 0)
        {
         Print("InpLockTriggerLoss must be > 0 for HedgeLock mode");
         return INIT_PARAMETERS_INCORRECT;
        }
      if(InpLockLotFactor <= 0)
        {
         Print("InpLockLotFactor must be > 0");
         return INIT_PARAMETERS_INCORRECT;
        }
      if(InpAutoUnlock)
        {
         if(InpUnlockProfitUSD <= 0)
           {
            Print("InpUnlockProfitUSD must be > 0 when InpAutoUnlock=true");
            return INIT_PARAMETERS_INCORRECT;
           }
         if(InpUseSideTSL && (InpUnlockTSLStart <= 0 || InpUnlockTSLStep <= 0))
           {
            Print("InpUnlockTSLStart and InpUnlockTSLStep must be > 0 when InpUseSideTSL=true");
            return INIT_PARAMETERS_INCORRECT;
           }
         if(InpEnableRelock)
           {
            if(InpRelockTriggerLoss <= 0)
              {
               Print("InpRelockTriggerLoss must be > 0 when InpEnableRelock=true");
               return INIT_PARAMETERS_INCORRECT;
              }
            if(InpRelockLotFactor <= 0 || InpRelockLotFactor > 1.0)
              {
               Print("InpRelockLotFactor must be in (0, 1]");
               return INIT_PARAMETERS_INCORRECT;
              }
            if(InpMaxRelocks < 1)
              {
               Print("InpMaxRelocks must be >= 1 when InpEnableRelock=true");
               return INIT_PARAMETERS_INCORRECT;
              }
           }
        }
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints((ulong)InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS);
   if(InpShowManualButtons && InpManualLot <= 0)
      Print("WARNING: InpShowManualButtons=true but InpManualLot<=0; manual buttons will refuse to open.");
   g_gvPrefix = StringFormat("RECOVERI_%s_%I64d_", _Symbol, InpMagic);
   g_baselineBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   ENUM_LOAD_STATUS loadStatus = LS_CLEAN;
   if(InpUsePersistence) loadStatus = LoadState();
   string lsName = (loadStatus == LS_CLEAN         ? "clean"
                  : loadStatus == LS_LOADED        ? "loaded"
                  : "mode-mismatch (mode-specific state cleared)");
   PrintFormat("RECOVERI init: persistence=%s state=%s mode=%d magic=%I64d",
               InpUsePersistence ? "on" : "off", lsName, (int)InpMode, InpMagic);
   if(InpShowPanel) CreatePanel();
   if(InpUseUncondGrid && !g_gridPlaced) PlaceUnconditionalGrid();  // sets g_gridPlaced internally
   PrintFormat("RECOVERI v1.52 Mode=%d Manage=%d SymScope=%d Basket=%d AutoUnlock=%d Trigger=%d Thr=%.2f Magic=%I64d",
               (int)InpMode,(int)InpManageScope,(int)InpSymbolScope,(int)InpBasketMode,
               (int)InpAutoUnlock, (int)InpStartTrigger, InpStartThreshold, InpMagic);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpUsePersistence) SaveState();
   ObjectsDeleteAll(0, g_panelPrefix);
   // Clear our own IPC disable flags so siblings don't ricochet on re-launch
   if(InpDisableOtherEAs == DISABLE_ALL_SYMBOLS && GlobalVariableCheck("RECOVERI_DISABLE_ALL"))
      GlobalVariableDel("RECOVERI_DISABLE_ALL");
   if(InpDisableOtherEAs == DISABLE_SAME_SYMBOL)
     {
      string key = StringFormat("RECOVERI_DISABLE_%s", _Symbol);
      if(GlobalVariableCheck(key)) GlobalVariableDel(key);
     }
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // Strategy Tester workaround: OnChartEvent is unreliable in Visual mode,
   // so poll panel buttons every tick and dispatch their handlers manually.
   // No-op outside the tester.
   PollPanelButtons();

   // Self-disable signal from a sibling RECOVERI instance
   if(InpDisableOtherEAs == DISABLE_NONE && CheckSelfDisableSignal())
     {
      Print("RECOVERI: self-disable signal received from sibling instance, removing.");
      ExpertRemove();
      return;
     }

   if(CheckEmergencyStop())
     {
      CloseAllManaged();
      BasketState bs0; BuildBasket(bs0); UpdatePanel(bs0);
      return;
     }
   if(InpUseVirtualTP || InpUseVirtualSL || InpUseVirtualBE)
      VirtualSLTPCheck();

   if(InpUseVirtualTSL)
      VirtualTSLCheck();

   if(InpUseUncondGrid && InpGridReplaceFilled)
      ReplenishGrid();


   BasketState bs;
   BuildBasket(bs);
   ApplyBasketTrailing(bs);

   if(bs.count > 0 && CheckBasketTargets(bs))
      BuildBasket(bs);

   // --- Standby trigger check (gates new-position opening below) ---
   bool triggered = IsRecoveryTriggered(bs);

   if(!InpCloseOnly && bs.count > 0 && IsTradingAllowed() && triggered)
     {
      // Disable other EAs once, when trigger fires for the first time
      if(InpDisableOtherEAs != DISABLE_NONE && !g_otherEAsDisabled)
        {
         DisableOtherEAs();
         g_otherEAsDisabled = true;
         if(InpUsePersistence) SaveState();
        }

      switch(InpMode)
        {
         case MODE_AVERAGING:        DoAveraging(bs);        break;
         case MODE_MARTINGALE:       DoMartingale(bs);       break;
         case MODE_HEDGE_LOCK:       DoHedgeLock(bs);        break;
         case MODE_SMART_CLOSE:      DoSmartClose(bs);       break;
         case MODE_PARTIAL_RECOVERY: DoPartialRecovery(bs);  break;
         case MODE_TARGET_PROFIT: break;
        }
     }
   UpdatePanel(bs);
  }

//+------------------------------------------------------------------+
//| Dispatch a single button click. Used by both OnChartEvent (live) |
//| and PollPanelButtons() (Strategy Tester Visual mode workaround). |
//+------------------------------------------------------------------+
void HandlePanelClick(const string sparam)
  {
   if(sparam == BTN_CLOSE_ALL)       { Print("BTN: Close All");    CloseAllManaged(); }
   else if(sparam == BTN_CLOSE_BUY)  { Print("BTN: Close BUY");    CloseSide(POSITION_TYPE_BUY); }
   else if(sparam == BTN_CLOSE_SELL) { Print("BTN: Close SELL");   CloseSide(POSITION_TYPE_SELL); }
   else if(sparam == BTN_PAUSE)      { g_paused = !g_paused; PrintFormat("BTN: Pause=%s", g_paused?"ON":"OFF"); if(InpUsePersistence) SaveState(); }
   else if(sparam == BTN_LOCK)       { Print("BTN: Lock Now");     ForceLockNow(); }
   else if(sparam == BTN_RESET)      { Print("BTN: Reset Stop");   g_emergencyStop = false; if(InpUsePersistence) SaveState(); }
   else if(sparam == BTN_RESET_STATE){ Print("BTN: Reset State");  DoResetState(); }
   else if(sparam == BTN_MANUAL_BUY) { Print("BTN: Manual BUY");   DoManualOpen(ORDER_TYPE_BUY); }
   else if(sparam == BTN_MANUAL_SELL){ Print("BTN: Manual SELL");  DoManualOpen(ORDER_TYPE_SELL); }
   else return;

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Strategy Tester (Visual mode) workaround:                        |
//|   in MT5 Strategy Tester CHARTEVENT_OBJECT_CLICK is delivered    |
//|   to OnChartEvent unreliably (depends on terminal build). To     |
//|   make panel buttons usable for manual BUY/SELL during a visual  |
//|   tester run, on each tick we poll OBJPROP_STATE of every panel  |
//|   button and dispatch the same handler if it is "pressed".       |
//|   No-op outside the tester.                                      |
//+------------------------------------------------------------------+
void PollPanelButtons()
  {
   if(!MQLInfoInteger(MQL_TESTER)) return;   // live: rely on OnChartEvent
   if(!InpShowPanel) return;

   static const string buttons[] =
     {
      BTN_CLOSE_ALL, BTN_CLOSE_BUY, BTN_CLOSE_SELL,
      BTN_PAUSE, BTN_LOCK, BTN_RESET, BTN_RESET_STATE,
      BTN_MANUAL_BUY, BTN_MANUAL_SELL
     };
   for(int i=0; i<ArraySize(buttons); i++)
     {
      const string name = buttons[i];
      if(ObjectFind(0, name) < 0) continue;
      if(ObjectGetInteger(0, name, OBJPROP_STATE) != 0)
         HandlePanelClick(name);
     }
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   HandlePanelClick(sparam);
  }

//+------------------------------------------------------------------+
bool IsManaged(const ulong ticket)
  {
   if(!pos.SelectByTicket(ticket)) return false;
   if(InpSymbolScope == SCOPE_CURRENT && pos.Symbol() != _Symbol) return false;
   long m = pos.Magic();
   if(InpManageScope == MANAGE_MANUAL && m != 0)        return false;
   if(InpManageScope == MANAGE_OWN    && m != InpMagic) return false;
   return true;
  }


//+------------------------------------------------------------------+
void BuildBasket(BasketState &bs)
  {
   ZeroMemory(bs);
   double buyPV=0, sellPV=0, worstB=0, worstS=0;
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      double vol = pos.Volume();
      double prc = pos.PriceOpen();
      double pft = pos.Profit() + pos.Swap() + pos.Commission();
      datetime tm= (datetime)pos.Time();
      bs.count++; bs.profit += pft;
      if(tm > bs.lastOpenTime) bs.lastOpenTime = tm;
      if(pos.PositionType() == POSITION_TYPE_BUY)
        {
         bs.buyCount++; bs.buyVolume += vol; bs.buyProfit += pft; buyPV += prc*vol;
         if(prc > bs.lastOpenPriceB || bs.lastOpenLotB == 0)
           { bs.lastOpenPriceB = prc; bs.lastOpenLotB = vol; }
         if(pft < worstB) { worstB = pft; bs.worstBuyTicket = t; }
        }
      else if(pos.PositionType() == POSITION_TYPE_SELL)
        {
         bs.sellCount++; bs.sellVolume += vol; bs.sellProfit += pft; sellPV += prc*vol;
         if(prc < bs.lastOpenPriceS || bs.lastOpenLotS == 0)
           { bs.lastOpenPriceS = prc; bs.lastOpenLotS = vol; }
         if(pft < worstS) { worstS = pft; bs.worstSellTicket = t; }
        }
     }
   if(bs.buyVolume  > 0) bs.buyPriceAvg  = buyPV  / bs.buyVolume;
   if(bs.sellVolume > 0) bs.sellPriceAvg = sellPV / bs.sellVolume;
  }

//+------------------------------------------------------------------+
double ResolveTargetMoney(double netLot)
  {
   if(InpTargetType == TARGET_MONEY)   return InpTargetProfit;
   if(InpTargetType == TARGET_PERCENT) return AccountInfoDouble(ACCOUNT_BALANCE)*InpTargetProfit/100.0;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double vp = (ts > 0) ? tv*(pt/ts) : 0.0;
   return InpTargetProfit * vp * MathMax(netLot, 0.01);
  }


//+------------------------------------------------------------------+
void ApplyBasketTrailing(const BasketState &bs)
  {
   if(!InpUseBasketTSL) return;
   if(InpBasketMode == BASKET_COMBINED)
     {
      if(bs.count == 0) { g_peakProfit = 0; return; }
      if(bs.profit > g_peakProfit) g_peakProfit = bs.profit;
      if(g_peakProfit >= InpBasketTSLStart && bs.profit <= g_peakProfit - InpBasketTSLStep)
        {
         PrintFormat("Basket TSL combined: peak=%.2f cur=%.2f", g_peakProfit, bs.profit);
         Notify(StringFormat("Basket TSL hit: peak=%.2f cur=%.2f", g_peakProfit, bs.profit));
         CloseAllManaged(); g_peakProfit = 0;
        }
      return;
     }
   // PER_SIDE
   if(bs.buyCount  == 0) g_peakBuyProfit  = 0;
   if(bs.sellCount == 0) g_peakSellProfit = 0;
   if(bs.buyCount > 0)
     {
      if(bs.buyProfit > g_peakBuyProfit) g_peakBuyProfit = bs.buyProfit;
      if(g_peakBuyProfit >= InpBasketTSLStart && bs.buyProfit <= g_peakBuyProfit - InpBasketTSLStep)
        {
         PrintFormat("Basket TSL BUY: peak=%.2f cur=%.2f", g_peakBuyProfit, bs.buyProfit);
         Notify(StringFormat("Basket TSL BUY: peak=%.2f cur=%.2f", g_peakBuyProfit, bs.buyProfit));
         CloseSide(POSITION_TYPE_BUY); g_peakBuyProfit = 0;
        }
     }
   if(bs.sellCount > 0)
     {
      if(bs.sellProfit > g_peakSellProfit) g_peakSellProfit = bs.sellProfit;
      if(g_peakSellProfit >= InpBasketTSLStart && bs.sellProfit <= g_peakSellProfit - InpBasketTSLStep)
        {
         PrintFormat("Basket TSL SELL: peak=%.2f cur=%.2f", g_peakSellProfit, bs.sellProfit);
         Notify(StringFormat("Basket TSL SELL: peak=%.2f cur=%.2f", g_peakSellProfit, bs.sellProfit));
         CloseSide(POSITION_TYPE_SELL); g_peakSellProfit = 0;
        }
     }
  }

//+------------------------------------------------------------------+
bool CheckBasketTargets(const BasketState &bs)
  {
   if(InpBasketMode == BASKET_COMBINED)
     {
      double tgt = ResolveTargetMoney(bs.buyVolume + bs.sellVolume);
      if(bs.profit >= tgt)
        {
         PrintFormat("Target combined: %.2f >= %.2f -> close all", bs.profit, tgt);
         Notify(StringFormat("Target reached: %.2f >= %.2f -> close all", bs.profit, tgt));
         CloseAllManaged(); g_peakProfit = 0;
         return true;
        }
      return false;
     }


   // PER_SIDE
   bool any = false;
   if(bs.buyCount > 0)
     {
      double tgt = ResolveTargetMoney(bs.buyVolume);
      if(bs.buyProfit >= tgt)
        {
         PrintFormat("Target BUY: %.2f >= %.2f", bs.buyProfit, tgt);
         Notify(StringFormat("Target BUY: %.2f >= %.2f", bs.buyProfit, tgt));
         CloseSide(POSITION_TYPE_BUY); g_peakBuyProfit = 0; any = true;
        }
     }
   if(bs.sellCount > 0)
     {
      double tgt = ResolveTargetMoney(bs.sellVolume);
      if(bs.sellProfit >= tgt)
        {
         PrintFormat("Target SELL: %.2f >= %.2f", bs.sellProfit, tgt);
         Notify(StringFormat("Target SELL: %.2f >= %.2f", bs.sellProfit, tgt));
         CloseSide(POSITION_TYPE_SELL); g_peakSellProfit = 0; any = true;
        }
     }
   return any;
  }

//+------------------------------------------------------------------+
void CloseAllManaged()
  {
   ulong tickets[];
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(IsManaged(t))
        { int n = ArraySize(tickets); ArrayResize(tickets, n+1); tickets[n] = t; }
     }
   for(int i=0; i<ArraySize(tickets); i++)
      if(!trade.PositionClose(tickets[i], (ulong)InpSlippage))
         PrintFormat("Close #%I64u err=%d", tickets[i], trade.ResultRetcode());
  }

//+------------------------------------------------------------------+
void CloseSide(const ENUM_POSITION_TYPE side)
  {
   ulong tickets[];
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      if(pos.PositionType() != side) continue;
      int n = ArraySize(tickets); ArrayResize(tickets, n+1); tickets[n] = t;
     }
   for(int i=0; i<ArraySize(tickets); i++)
      if(!trade.PositionClose(tickets[i], (ulong)InpSlippage))
         PrintFormat("CloseSide #%I64u err=%d", tickets[i], trade.ResultRetcode());
  }


//+------------------------------------------------------------------+
void ForceLockNow()
  {
   if(InpSymbolScope != SCOPE_CURRENT)
     { Print("ForceLockNow: requires SCOPE_CURRENT"); return; }
   BasketState bs; BuildBasket(bs);
   double net = bs.buyVolume - bs.sellVolume;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(MathAbs(net) < minLot) { Print("ForceLockNow: balanced"); return; }
   double lot = NormalizeLot(_Symbol, MathAbs(net));
   if(lot <= 0) return;
   if(net > 0) OpenPosition(_Symbol, ORDER_TYPE_SELL, lot, "MANUAL-LOCK");
   else        OpenPosition(_Symbol, ORDER_TYPE_BUY,  lot, "MANUAL-LOCK");
  }

//+------------------------------------------------------------------+
//| Manual market order from panel button                            |
//|   Used in Strategy Tester (visual mode) and on live charts to    |
//|   open a position by hand. EA picks it up automatically because  |
//|   the magic equals InpMagic. After that all standard recovery    |
//|   logic applies: targets, virtual SL/TP/TSL, basket trailing,    |
//|   averaging/martingale, hedge-lock with auto-unwind, etc.        |
//+------------------------------------------------------------------+
void DoManualOpen(const ENUM_ORDER_TYPE side)
  {
   if(InpSymbolScope != SCOPE_CURRENT)
     {
      Print("Manual open: requires SCOPE_CURRENT (manage scope = current symbol)");
      Notify("Manual open: SCOPE_CURRENT required");
      return;
     }
   if(g_emergencyStop)
     {
      Print("Manual open blocked: emergency stop is active. Press 'Reset Stop' first.");
      Notify("Manual open blocked: EMERGENCY STOP");
      return;
     }
   if(!SpreadOK(_Symbol))
     {
      PrintFormat("Manual open blocked: spread > InpMaxSpreadPts=%.0f", InpMaxSpreadPts);
      Notify("Manual open blocked: spread too wide");
      return;
     }
   if(InpManualLot <= 0)
     {
      Print("Manual open: InpManualLot must be > 0");
      Notify("Manual open: InpManualLot <= 0");
      return;
     }
   double lot = NormalizeLot(_Symbol, InpManualLot);
   if(lot <= 0)
     {
      PrintFormat("Manual open: NormalizeLot(%.2f) -> 0 (check broker min/max/step)", InpManualLot);
      Notify("Manual open: lot normalized to 0");
      return;
     }
   string tag = (side == ORDER_TYPE_BUY) ? "MANUAL-BUY" : "MANUAL-SELL";
   if(OpenPosition(_Symbol, side, lot, tag))
     {
      PrintFormat("Manual %s opened: lot=%.2f", (side==ORDER_TYPE_BUY?"BUY":"SELL"), lot);
      Notify(StringFormat("Manual %s %.2f opened on %s",
                          (side==ORDER_TYPE_BUY?"BUY":"SELL"), lot, _Symbol));
     }
  }

//+------------------------------------------------------------------+
bool VirtualBeTriggered(const ulong ticket)
  {
   for(int i=0; i<ArraySize(g_beTickets); i++)
      if(g_beTickets[i] == ticket) return true;
   return false;
  }

void VirtualBeMark(const ulong ticket)
  {
   if(VirtualBeTriggered(ticket)) return;
   int n = ArraySize(g_beTickets); ArrayResize(g_beTickets, n+1); g_beTickets[n] = ticket;
  }

//+------------------------------------------------------------------+
void VirtualSLTPCheck()
  {
   ulong tickets[];
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(IsManaged(t))
        { int n = ArraySize(tickets); ArrayResize(tickets, n+1); tickets[n] = t; }
     }
   for(int i=0; i<ArraySize(tickets); i++)
     {
      if(!pos.SelectByTicket(tickets[i])) continue;
      string s = pos.Symbol();
      double pt = SymbolInfoDouble(s, SYMBOL_POINT);
      if(pt <= 0) continue;
      double bid = SymbolInfoDouble(s, SYMBOL_BID);
      double ask = SymbolInfoDouble(s, SYMBOL_ASK);
      double op  = pos.PriceOpen();
      ENUM_POSITION_TYPE pt2 = pos.PositionType();
      double pts = (pt2 == POSITION_TYPE_BUY) ? (bid - op)/pt : (op - ask)/pt;


      bool doClose = false; string reason = "";
      if(InpUseVirtualTP && pts >= InpVirtualTPPts)             { doClose = true; reason = "vTP"; }
      else if(InpUseVirtualSL && pts <= -InpVirtualSLPts)       { doClose = true; reason = "vSL"; }
      else if(InpUseVirtualBE && VirtualBeTriggered(tickets[i]) && pts <= 0)
                                                                { doClose = true; reason = "vBE"; }
      if(InpUseVirtualBE && pts >= InpVirtualBEPts)
         VirtualBeMark(tickets[i]);
      if(doClose)
        {
         if(trade.PositionClose(tickets[i], (ulong)InpSlippage))
           {
            PrintFormat("Virtual %s on #%I64u (%.0f pts)", reason, tickets[i], pts);
            Notify(StringFormat("Virtual %s on #%I64u (%.0f pts)", reason, tickets[i], pts));
           }
        }
     }
  }

//+------------------------------------------------------------------+
bool CheckEmergencyStop()
  {
   if(g_emergencyStop) return true;
   if(!InpUseEquityStop) return false;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0) return false;
   double pct = eq / bal * 100.0;
   if(pct <= InpEquityStopPct)
     {
      PrintFormat("EMERGENCY STOP: eq=%.2f bal=%.2f (%.1f%% <= %.1f%%)", eq, bal, pct, InpEquityStopPct);
      Notify(StringFormat("EMERGENCY STOP: equity %.2f / balance %.2f (%.1f%%)", eq, bal, pct));
      g_emergencyStop = true;
      if(InpUsePersistence) SaveState();
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
bool IsTradingAllowed()
  {
   g_blockReason = "";
   if(g_paused)         { g_blockReason = "PAUSE"; return false; }
   if(!IsTimeAllowed()) { g_blockReason = "TIME";  return false; }
   if(IsNewsBlocked())  { g_blockReason = "NEWS";  return false; }
   return true;
  }

bool IsTimeAllowed()
  {
   if(!InpUseTimeFilter) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   bool dayOk = false;


   switch(t.day_of_week)
     {
      case 0: dayOk = InpTradeSun; break;
      case 1: dayOk = InpTradeMon; break;
      case 2: dayOk = InpTradeTue; break;
      case 3: dayOk = InpTradeWed; break;
      case 4: dayOk = InpTradeThu; break;
      case 5: dayOk = InpTradeFri; break;
      case 6: dayOk = InpTradeSat; break;
     }
   if(!dayOk) return false;
   int sh = MathMax(0, MathMin(24, InpStartHour));
   int eh = MathMax(0, MathMin(24, InpEndHour));
   if(sh == eh) return true;
   if(sh < eh)  return (t.hour >= sh && t.hour < eh);
   return (t.hour >= sh || t.hour < eh);
  }

bool IsNewsBlocked()
  {
   if(!InpUseNewsFilter) return false;
   datetime now = TimeCurrent();
   datetime from = now - InpNewsMinsBefore * 60;
   datetime to   = now + InpNewsMinsAfter  * 60;
   string list[2];
   list[0] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   list[1] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   for(int i=0; i<2; i++)
     {
      if(list[i] == "") continue;
      MqlCalendarValue values[];
      int n = CalendarValueHistory(values, from, to, NULL, list[i]);
      for(int k=0; k<n; k++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[k].event_id, ev)) continue;
         bool match = false;
         if(ev.importance == CALENDAR_IMPORTANCE_HIGH     && InpNewsHigh)   match = true;
         if(ev.importance == CALENDAR_IMPORTANCE_MODERATE && InpNewsMedium) match = true;
         if(ev.importance == CALENDAR_IMPORTANCE_LOW      && InpNewsLow)    match = true;
         if(match) return true;
        }
     }
   return false;
  }


//+------------------------------------------------------------------+
bool SpreadOK(const string symbol)
  {
   if(InpMaxSpreadPts <= 0) return true;
   long sp = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   return (sp <= InpMaxSpreadPts);
  }

double NormalizeLot(const string symbol, double lot)
  {
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot/step + 1e-7) * step;
   if(InpMaxLot > 0) lot = MathMin(lot, InpMaxLot);
   return NormalizeDouble(lot, 2);
  }

int CurrentStepPoints(const int n)
  {
   double s = (double)InpStepPoints * MathPow(InpStepMultiplier, MathMax(0, n-1));
   return (int)MathMax(1.0, s);
  }

//+------------------------------------------------------------------+
void DoAveraging(const BasketState &bs)
  {
   if(InpSymbolScope != SCOPE_CURRENT) return;
   if(!SpreadOK(_Symbol)) return;
   if(bs.count >= InpMaxTrades) return;
   sym.Name(_Symbol); sym.RefreshRates();
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = sym.Bid(), ask = sym.Ask();
   if(bs.buyCount > 0)
     {
      int st = CurrentStepPoints(bs.buyCount);
      if(ask <= bs.lastOpenPriceB - st*pt)
        {
         double lot = (InpLotAdd>0) ? bs.lastOpenLotB + InpLotAdd : MathMax(bs.lastOpenLotB, InpStartLot);
         OpenPosition(_Symbol, ORDER_TYPE_BUY, NormalizeLot(_Symbol, lot), "AVG-BUY");
        }
     }
   if(bs.sellCount > 0)
     {
      int st = CurrentStepPoints(bs.sellCount);
      if(bid >= bs.lastOpenPriceS + st*pt)
        {
         double lot = (InpLotAdd>0) ? bs.lastOpenLotS + InpLotAdd : MathMax(bs.lastOpenLotS, InpStartLot);
         OpenPosition(_Symbol, ORDER_TYPE_SELL, NormalizeLot(_Symbol, lot), "AVG-SELL");
        }
     }
  }


//+------------------------------------------------------------------+
void DoMartingale(const BasketState &bs)
  {
   if(InpSymbolScope != SCOPE_CURRENT) return;
   if(!SpreadOK(_Symbol)) return;
   if(bs.count >= InpMaxTrades) return;
   sym.Name(_Symbol); sym.RefreshRates();
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = sym.Bid(), ask = sym.Ask();
   if(bs.buyCount > 0)
     {
      int st = CurrentStepPoints(bs.buyCount);
      if(ask <= bs.lastOpenPriceB - st*pt)
        {
         double lot = bs.lastOpenLotB * InpLotMultiplier;
         if(lot <= 0) lot = InpStartLot;
         OpenPosition(_Symbol, ORDER_TYPE_BUY, NormalizeLot(_Symbol, lot), "MG-BUY");
        }
     }
   if(bs.sellCount > 0)
     {
      int st = CurrentStepPoints(bs.sellCount);
      if(bid >= bs.lastOpenPriceS + st*pt)
        {
         double lot = bs.lastOpenLotS * InpLotMultiplier;
         if(lot <= 0) lot = InpStartLot;
         OpenPosition(_Symbol, ORDER_TYPE_SELL, NormalizeLot(_Symbol, lot), "MG-SELL");
        }
     }
  }

//+------------------------------------------------------------------+
void DoHedgeLock(const BasketState &bs)
  {
   if(InpSymbolScope != SCOPE_CURRENT) return;
   if(!SpreadOK(_Symbol)) return;

   // v1.52: TF-driven imbalance trim ("выравнивание лока по ТФ").
   // Self-gated by InpLockAlignUseTF and once-per-bar of InpLockAlignTF.
   AlignLockByTF();

   // If auto-unwind is enabled, run the state machine instead of plain lock
   if(InpAutoUnlock) { DoLockUnwind(bs); return; }

   if(bs.count >= InpMaxTrades) return;
   if(bs.profit > -InpLockTriggerLoss) return;
   double net = bs.buyVolume - bs.sellVolume;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(MathAbs(net) < minLot) return;
   double lot = NormalizeLot(_Symbol, MathAbs(net) * InpLockLotFactor);
   if(lot <= 0) return;
   if(net > 0) OpenPosition(_Symbol, ORDER_TYPE_SELL, lot, "LOCK");
   else        OpenPosition(_Symbol, ORDER_TYPE_BUY,  lot, "LOCK");
  }


//+------------------------------------------------------------------+
//| Auto-unwind lock state machine (HedgeLock + InpAutoUnlock=true)  |
//|   IDLE     -> open lock when loss > InpLockTriggerLoss           |
//|   LOCKED   -> close profitable side at target/TSL                |
//|   UNWOUND  -> manage remaining side; optional re-lock on deep DD |
//|   RELOCKED -> close profitable side -> back to UNWOUND           |
//+------------------------------------------------------------------+
void DoLockUnwind(const BasketState &bs)
  {
   // Universal reset: nothing on the table -> phase IDLE
   if(bs.count == 0)
     {
      if(g_lockPhase != PHASE_IDLE)
        {
         g_lockPhase   = PHASE_IDLE;
         g_lockPeakBuy = 0; g_lockPeakSell = 0;
         g_relockCount = 0;
         if(InpUsePersistence) SaveState();
        }
      return;
     }

   // Auto-detect existing lock (e.g., user enabled feature mid-session)
   if(g_lockPhase == PHASE_IDLE && bs.buyCount > 0 && bs.sellCount > 0)
     {
      g_lockPhase   = PHASE_LOCKED;
      g_lockPeakBuy = bs.buyProfit  > 0 ? bs.buyProfit  : 0;
      g_lockPeakSell= bs.sellProfit > 0 ? bs.sellProfit : 0;
      Notify("Auto-unwind: existing lock detected -> PHASE_LOCKED");
      if(InpUsePersistence) SaveState();
     }

   switch(g_lockPhase)
     {
      case PHASE_IDLE:
        {
         // Open lock when loss exceeds trigger
         if(bs.count >= InpMaxTrades) return;
         if(bs.profit > -InpLockTriggerLoss) return;
         double net = bs.buyVolume - bs.sellVolume;
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(MathAbs(net) < minLot) return;
         double lot = NormalizeLot(_Symbol, MathAbs(net) * InpLockLotFactor);
         if(lot <= 0) return;
         bool ok = (net > 0)
                   ? OpenPosition(_Symbol, ORDER_TYPE_SELL, lot, "LOCK")
                   : OpenPosition(_Symbol, ORDER_TYPE_BUY,  lot, "LOCK");
         if(ok)
           {
            g_lockPhase    = PHASE_LOCKED;
            g_lockPeakBuy  = 0;
            g_lockPeakSell = 0;
            g_relockCount  = 0;
            Notify(StringFormat("Auto-unwind: lock opened (lot=%.2f) -> PHASE_LOCKED", lot));
            if(InpUsePersistence) SaveState();
           }
         break;
        }

      case PHASE_LOCKED:
      case PHASE_RELOCKED:
        {
         // External close happened (basket target / TSL / manual button)
         if(bs.buyCount == 0 || bs.sellCount == 0)
           {
            if(bs.buyCount > 0)
              { g_remainingSide = POSITION_TYPE_BUY;  g_lockPhase = PHASE_UNWOUND; }
            else if(bs.sellCount > 0)
              { g_remainingSide = POSITION_TYPE_SELL; g_lockPhase = PHASE_UNWOUND; }
            else
              { g_lockPhase = PHASE_IDLE; g_relockCount = 0; }
            g_lockPeakBuy = 0; g_lockPeakSell = 0;
            if(InpUsePersistence) SaveState();
            return;
           }

         // Update peaks per side
         if(bs.buyProfit  > g_lockPeakBuy)  g_lockPeakBuy  = bs.buyProfit;
         if(bs.sellProfit > g_lockPeakSell) g_lockPeakSell = bs.sellProfit;

         // Direct profit target on either side
         if(bs.buyProfit >= InpUnlockProfitUSD)
           {
            PrintFormat("Auto-unwind: BUY hit unlock profit %.2f >= %.2f", bs.buyProfit, InpUnlockProfitUSD);
            Notify(StringFormat("Auto-unwind: close BUY at %.2f", bs.buyProfit));
            CloseSide(POSITION_TYPE_BUY);
            g_remainingSide = POSITION_TYPE_SELL;
            g_lockPhase     = PHASE_UNWOUND;
            g_lockPeakBuy = 0; g_lockPeakSell = 0;
            if(InpUsePersistence) SaveState();
            return;
           }
         if(bs.sellProfit >= InpUnlockProfitUSD)
           {
            PrintFormat("Auto-unwind: SELL hit unlock profit %.2f >= %.2f", bs.sellProfit, InpUnlockProfitUSD);
            Notify(StringFormat("Auto-unwind: close SELL at %.2f", bs.sellProfit));
            CloseSide(POSITION_TYPE_SELL);
            g_remainingSide = POSITION_TYPE_BUY;
            g_lockPhase     = PHASE_UNWOUND;
            g_lockPeakBuy = 0; g_lockPeakSell = 0;
            if(InpUsePersistence) SaveState();
            return;
           }

         // Per-side trailing
         if(InpUseSideTSL)
           {
            if(g_lockPeakBuy >= InpUnlockTSLStart &&
               bs.buyProfit  <= g_lockPeakBuy - InpUnlockTSLStep)
              {
               PrintFormat("Auto-unwind TSL BUY: peak=%.2f cur=%.2f", g_lockPeakBuy, bs.buyProfit);
               Notify(StringFormat("Auto-unwind TSL: close BUY (peak %.2f -> %.2f)", g_lockPeakBuy, bs.buyProfit));
               CloseSide(POSITION_TYPE_BUY);
               g_remainingSide = POSITION_TYPE_SELL;
               g_lockPhase     = PHASE_UNWOUND;
               g_lockPeakBuy = 0; g_lockPeakSell = 0;
               if(InpUsePersistence) SaveState();
               return;
              }
            if(g_lockPeakSell >= InpUnlockTSLStart &&
               bs.sellProfit  <= g_lockPeakSell - InpUnlockTSLStep)
              {
               PrintFormat("Auto-unwind TSL SELL: peak=%.2f cur=%.2f", g_lockPeakSell, bs.sellProfit);
               Notify(StringFormat("Auto-unwind TSL: close SELL (peak %.2f -> %.2f)", g_lockPeakSell, bs.sellProfit));
               CloseSide(POSITION_TYPE_SELL);
               g_remainingSide = POSITION_TYPE_BUY;
               g_lockPhase     = PHASE_UNWOUND;
               g_lockPeakBuy = 0; g_lockPeakSell = 0;
               if(InpUsePersistence) SaveState();
               return;
              }
           }
         break;
        }

      case PHASE_UNWOUND:
        {
         // If user manually opened a counter side -> treat as relock
         if(bs.buyCount > 0 && bs.sellCount > 0)
           {
            g_lockPhase    = PHASE_RELOCKED;
            g_lockPeakBuy  = 0;
            g_lockPeakSell = 0;
            Notify("Auto-unwind: counter side detected -> PHASE_RELOCKED");
            if(InpUsePersistence) SaveState();
            return;
           }

         double remainingProfit = (g_remainingSide == POSITION_TYPE_BUY) ? bs.buyProfit  : bs.sellProfit;
         double remainingVolume = (g_remainingSide == POSITION_TYPE_BUY) ? bs.buyVolume  : bs.sellVolume;
         int    remainingCount  = (g_remainingSide == POSITION_TYPE_BUY) ? bs.buyCount   : bs.sellCount;

         // Remaining side closed externally (basket target / TSL / button)
         if(remainingCount == 0)
           {
            g_lockPhase   = PHASE_IDLE;
            g_relockCount = 0;
            g_lockPeakBuy = 0; g_lockPeakSell = 0;
            if(InpUsePersistence) SaveState();
            return;
           }

         // Optional re-lock if remaining side dives further
         if(InpEnableRelock &&
            g_relockCount < InpMaxRelocks &&
            remainingProfit <= -InpRelockTriggerLoss)
           {
            if(bs.count >= InpMaxTrades) return;
            double factor = MathMax(0.0, MathMin(1.0, InpRelockLotFactor));
            double lot = NormalizeLot(_Symbol, remainingVolume * factor);
            if(lot <= 0) return;
            ENUM_ORDER_TYPE counter = (g_remainingSide == POSITION_TYPE_BUY)
                                      ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            if(OpenPosition(_Symbol, counter, lot, StringFormat("RELOCK-%d", g_relockCount+1)))
              {
               g_lockPhase    = PHASE_RELOCKED;
               g_lockPeakBuy  = 0;
               g_lockPeakSell = 0;
               g_relockCount++;
               PrintFormat("Auto-unwind: RELOCK #%d opened, lot=%.2f", g_relockCount, lot);
               Notify(StringFormat("Auto-unwind: RELOCK #%d (lot=%.2f) -> PHASE_RELOCKED",
                                   g_relockCount, lot));
               if(InpUsePersistence) SaveState();
              }
           }
         break;
        }
     }
  }


//+------------------------------------------------------------------+
void DoSmartClose(const BasketState &bs)
  {
   if(bs.count < 2) return;
   ulong tickets[]; double profits[];
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      double pft = pos.Profit() + pos.Swap() + pos.Commission();
      int n = ArraySize(tickets);
      ArrayResize(tickets, n+1); ArrayResize(profits, n+1);
      tickets[n] = t; profits[n] = pft;
     }
   int n = ArraySize(tickets);
   if(n < 2) return;
   int bi = 0, wi = 0;
   for(int i=1; i<n; i++)
     {
      if(profits[i] > profits[bi]) bi = i;
      if(profits[i] < profits[wi]) wi = i;
     }
   if(bi == wi) return;
   if(profits[bi] <= 0) return;
   double minPair = ResolveTargetMoney(0.01);
   if(profits[bi] + profits[wi] < minPair) return;
   trade.PositionClose(tickets[bi]);
   trade.PositionClose(tickets[wi]);
  }

//+------------------------------------------------------------------+
//| Standby trigger: returns true once recovery should be active     |
//+------------------------------------------------------------------+
bool IsRecoveryTriggered(const BasketState &bs)
  {
   if(g_recoveryTriggered) return true;
   if(InpStartTrigger == START_INSTANT)
     { g_recoveryTriggered = true; return true; }
   if(bs.count == 0) return false;
   double drawdown = -bs.profit;  // positive number when we are losing
   if(drawdown <= 0) return false;
   bool fire = false;
   if(InpStartTrigger == START_DD_MONEY)
      fire = (drawdown >= InpStartThreshold);
   else if(InpStartTrigger == START_DD_PERCENT)
     {
      double base = (g_baselineBalance > 0) ? g_baselineBalance : AccountInfoDouble(ACCOUNT_BALANCE);
      if(base <= 0) return false;
      double pct = drawdown / base * 100.0;
      fire = (pct >= InpStartThreshold);
     }
   if(fire)
     {
      g_recoveryTriggered = true;
      Notify(StringFormat("STANDBY trigger fired: drawdown=%.2f, threshold=%.2f (%s)",
             drawdown, InpStartThreshold,
             InpStartTrigger == START_DD_PERCENT ? "%" : "$"));
      if(InpUsePersistence) SaveState();
     }
   return fire;
  }

//+------------------------------------------------------------------+
//| Disable other EAs on this/all symbols (called once on trigger)   |
//|                                                                  |
//| MQL5 не позволяет программно отцепить чужой EA с другого графика.|
//| Поэтому мы:                                                      |
//|   1) Выставляем глобальную переменную RECOVERI_DISABLE_<symbol>, |
//|      которую другие экземпляры RECOVERI могут проверять и сами   |
//|      вызывать ExpertRemove() (см. CheckSelfDisableSignal).       |
//|   2) Логируем и пушим уведомление пользователю с перечнем чартов |
//|      с активными EA — закрыть их вручную.                        |
//+------------------------------------------------------------------+
void DisableOtherEAs()
  {
   long me = ChartID();
   long cid = ChartFirst();
   string list = "";
   int found = 0;
   while(cid >= 0)
     {
      if(cid != me)
        {
         string sym2 = ChartSymbol(cid);
         bool sameSym = (sym2 == _Symbol);
         bool inScope = (InpDisableOtherEAs == DISABLE_ALL_SYMBOLS) ||
                        (InpDisableOtherEAs == DISABLE_SAME_SYMBOL && sameSym);
         if(inScope)
           {
            string ename = ChartGetString(cid, CHARTPROPERTY_EXPERT_NAME);
            if(ename != "" && ename != MQLInfoString(MQL_PROGRAM_NAME))
              {
               list += StringFormat("%s[%s] ", sym2, ename);
               found++;
              }
           }
        }
      cid = ChartNext(cid);
     }
   // Set IPC signal that sibling RECOVERI instances can self-detach via
   if(InpDisableOtherEAs == DISABLE_ALL_SYMBOLS)
      GlobalVariableSet("RECOVERI_DISABLE_ALL", (double)TimeCurrent());
   else if(InpDisableOtherEAs == DISABLE_SAME_SYMBOL)
      GlobalVariableSet(StringFormat("RECOVERI_DISABLE_%s", _Symbol), (double)TimeCurrent());

   PrintFormat("DisableOtherEAs: scope=%d charts_with_EA=%d list=%s",
               (int)InpDisableOtherEAs, found, list);
   if(found > 0)
      Notify(StringFormat("WARNING: %d other EAs detected: %s. Detach them manually.", found, list));
  }

//+------------------------------------------------------------------+
//| Check IPC signal from another RECOVERI: self-detach if matched   |
//+------------------------------------------------------------------+
bool CheckSelfDisableSignal()
  {
   if(GlobalVariableCheck("RECOVERI_DISABLE_ALL")) return true;
   if(GlobalVariableCheck(StringFormat("RECOVERI_DISABLE_%s", _Symbol))) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Trend filter (MA-cross on higher TF). Returns +1/-1/0.           |
//+------------------------------------------------------------------+
int TrendDirection()
  {
   if(!InpUseTrendFilter) return 0;  // 0 = no filter active, treat as neutral
   double fast[2], slow[2];
   int hF = iMA(_Symbol, InpTrendTF, InpTrendFastMA, 0, MODE_EMA, PRICE_CLOSE);
   int hS = iMA(_Symbol, InpTrendTF, InpTrendSlowMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hF == INVALID_HANDLE || hS == INVALID_HANDLE) return 0;
   if(CopyBuffer(hF, 0, 0, 2, fast) <= 0) { IndicatorRelease(hF); IndicatorRelease(hS); return 0; }
   if(CopyBuffer(hS, 0, 0, 2, slow) <= 0) { IndicatorRelease(hF); IndicatorRelease(hS); return 0; }
   IndicatorRelease(hF); IndicatorRelease(hS);
   if(fast[0] > slow[0]) return +1;
   if(fast[0] < slow[0]) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| One-Per-Bar helper: did a new bar appear since last open?        |
//+------------------------------------------------------------------+
bool IsNewBar(datetime &lastBar)
  {
   datetime cur = iTime(_Symbol, _Period, 0);
   if(cur == 0) return false;
   if(cur != lastBar) { lastBar = cur; return true; }
   return false;
  }

//+------------------------------------------------------------------+
//| v1.52: same as IsNewBar but parameterised by an explicit TF.      |
//| Used by AlignLockByTF() to throttle the routine to once-per-bar  |
//| of InpLockAlignTF (e.g. once per D1 bar by default).             |
//+------------------------------------------------------------------+
bool IsNewBarTF(const ENUM_TIMEFRAMES tf, datetime &lastBar)
  {
   datetime cur = iTime(_Symbol, tf, 0);
   if(cur == 0) return false;
   if(cur != lastBar) { lastBar = cur; return true; }
   return false;
  }

//+------------------------------------------------------------------+
//| v1.52: averager grid step in POINTS for a given chain index.      |
//|                                                                   |
//| Two modes:                                                        |
//|   * Fixed (default): InpAvgStepPts * InpAvgStepMul^chainIdx.      |
//|   * ATR  : ATR(InpAvgStepATRTF, InpAvgStepATRPeriod) / Point      |
//|            * InpAvgStepATRMul, then * InpAvgStepMul^chainIdx.    |
//|     A floor of InpAvgStepATRMin (points) is applied to the ATR    |
//|     base before the chain multiplier so a thin/illiquid market   |
//|     (or zero ATR / no buffer) still produces a sane spacing.     |
//|                                                                   |
//| Chain multiplier (InpAvgStepMul) is preserved in both modes so    |
//| existing parameter sets keep their geometry; only the BASE step  |
//| changes when ATR is enabled.                                      |
//+------------------------------------------------------------------+
double AvgStepPoints(const int chainIdx)
  {
   double basePts = (double)InpAvgStepPts;
   if(InpAvgStepUseATR)
     {
      double atrPts = 0.0;
      int h = iATR(_Symbol, InpAvgStepATRTF, InpAvgStepATRPeriod);
      if(h != INVALID_HANDLE)
        {
         double buf[1];
         if(CopyBuffer(h, 0, 0, 1, buf) > 0)
           {
            double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            if(pt > 0) atrPts = (buf[0] / pt) * InpAvgStepATRMul;
           }
         IndicatorRelease(h);
        }
      double minPts = (double)InpAvgStepATRMin;
      basePts = (atrPts >= minPts) ? atrPts : minPts;
     }
   return basePts * MathPow(InpAvgStepMul, MathMax(0, chainIdx));
  }

//+------------------------------------------------------------------+
//| v1.52: TF-driven lock alignment ("выравнивание лока по ТФ").     |
//|                                                                   |
//| Once per new bar of InpLockAlignTF (D1 by default), measure the  |
//| imbalance between BUY and SELL across ALL managed positions      |
//| (PR-LOCK, PR-AVG, originals, AVG-*, GRID-*, manual-lock, etc.).  |
//| If the heavier side exceeds the lighter side by more than        |
//| max(InpLockAlignThresholdLot, minLot), trim the heavier side     |
//| down to the lighter — preferring positions that are CURRENTLY    |
//| in profit (the "positive zone"), so the realized PnL footprint  |
//| of the trim is positive.                                         |
//|                                                                   |
//| InpLockAlignOnlyProfit:                                            |
//|   true  (default) — only PnL>0 candidates are touched.  If none  |
//|                     exist on the heavier side this tick, log and  |
//|                     skip; balance will be re-checked next bar.   |
//|   false           — fall back to all positions sorted DESC by    |
//|                     PnL (most profitable / least loss first).    |
//|                                                                   |
//| The last position closed may be partially closed via              |
//| ClosePartOfPosition() to land exactly on the matching volume.    |
//| PR-AVG counters are recomputed from a scan after a successful    |
//| pass to keep the next averager open with correct multiplier.    |
//+------------------------------------------------------------------+
void AlignLockByTF()
  {
   if(!InpLockAlignUseTF) return;
   if(!IsNewBarTF(InpLockAlignTF, g_alignLastBarTime)) return;

   // Sum managed volumes BUY/SELL across the whole basket.
   double buyVol = 0.0, sellVol = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;                       // also selects pos
      double v = pos.Volume();
      if(pos.PositionType() == POSITION_TYPE_BUY)       buyVol  += v;
      else if(pos.PositionType() == POSITION_TYPE_SELL) sellVol += v;
     }

   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double diff     = MathAbs(buyVol - sellVol);
   double threshold = MathMax(InpLockAlignThresholdLot, minLot);
   if(diff < threshold) return;  // already balanced enough

   ENUM_POSITION_TYPE heavy = (buyVol > sellVol) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   // Collect candidates on the heavier side.
   ulong  tickets[];
   double profits[];
   double vols[];
   int    skippedNonProfit = 0;
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      if(pos.PositionType() != heavy) continue;
      double pft = pos.Profit() + pos.Swap() + pos.Commission();
      if(InpLockAlignOnlyProfit && pft <= 0) { skippedNonProfit++; continue; }
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      ArrayResize(profits, n + 1);
      ArrayResize(vols,    n + 1);
      tickets[n] = t;
      profits[n] = pft;
      vols[n]    = pos.Volume();
     }

   int N = ArraySize(tickets);
   if(N == 0)
     {
      PrintFormat("AlignByTF[%s]: imbalance %.4f lot on %s, no candidates%s "
                  "(skippedNonProfit=%d) — will retry next bar",
                  EnumToString(InpLockAlignTF), diff,
                  heavy == POSITION_TYPE_BUY ? "BUY" : "SELL",
                  InpLockAlignOnlyProfit ? " in profit" : "",
                  skippedNonProfit);
      return;
     }

   // Sort DESC by PnL (lock the most profitable first / least loss first).
   for(int a = 0; a < N - 1; a++)
      for(int b = a + 1; b < N; b++)
         if(profits[b] > profits[a])
           {
            double tp = profits[a]; profits[a] = profits[b]; profits[b] = tp;
            ulong  tt = tickets[a]; tickets[a] = tickets[b]; tickets[b] = tt;
            double tv = vols[a];    vols[a]    = vols[b];    vols[b]    = tv;
           }

   double remaining   = diff;
   int    closedFull  = 0;
   int    closedPart  = 0;
   double closedTotal = 0.0;
   double realizedPnl = 0.0;

   for(int i = 0; i < N && remaining >= minLot; i++)
     {
      if(!pos.SelectByTicket(tickets[i])) continue;
      double posVol = pos.Volume();

      if(posVol <= remaining + 1e-9)
        {
         if(trade.PositionClose(tickets[i], (ulong)InpSlippage))
           {
            closedFull++;
            closedTotal += posVol;
            realizedPnl += profits[i];
            remaining   -= posVol;
           }
         else
           {
            PrintFormat("AlignByTF: PositionClose #%I64u failed err=%d ret=%d",
                        tickets[i], GetLastError(), trade.ResultRetcode());
           }
        }
      else
        {
         if(ClosePartOfPosition(tickets[i], remaining))
           {
            closedPart++;
            closedTotal += remaining;
            // realizedPnl approx: pro-rate by volume share
            if(posVol > 0) realizedPnl += profits[i] * (remaining / posVol);
            remaining = 0.0;
           }
         else
           {
            PrintFormat("AlignByTF: ClosePartOfPosition #%I64u %.4f failed",
                        tickets[i], remaining);
           }
        }
     }

   if(closedFull == 0 && closedPart == 0) return;

   // PR-AVG counters may have shifted if a PR-AVG position was on the
   // heavy side — rescan.
   int avgB = 0, avgS = 0;
   int t2 = PositionsTotal();
   for(int i = 0; i < t2; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      string cmt = pos.Comment();
      if(StringFind(cmt, "PR-AVG-B") >= 0)      avgB++;
      else if(StringFind(cmt, "PR-AVG-S") >= 0) avgS++;
     }
   g_prAvgCountBuy  = avgB;
   g_prAvgCountSell = avgS;

   PrintFormat("AlignByTF[%s]: trimmed %s -%.4f lot (%d full, %d partial), "
               "imbalance was %.4f, locked PnL ~%.2f %s",
               EnumToString(InpLockAlignTF),
               heavy == POSITION_TYPE_BUY ? "BUY" : "SELL",
               closedTotal, closedFull, closedPart, diff, realizedPnl,
               AccountInfoString(ACCOUNT_CURRENCY));
   Notify(StringFormat("AlignByTF: %s -%.4f lot (locked ~%.2f)",
                       heavy == POSITION_TYPE_BUY ? "BUY" : "SELL",
                       closedTotal, realizedPnl));

   if(InpUsePersistence) SaveState();
  }

//+------------------------------------------------------------------+
//| Close an arbitrary lot from a specific position (partial close). |
//+------------------------------------------------------------------+
bool ClosePartOfPosition(const ulong ticket, double lotToClose)
  {
   if(!pos.SelectByTicket(ticket)) return false;
   double posVol = pos.Volume();
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   if(lotToClose >= posVol)
      return trade.PositionClose(ticket, (ulong)InpSlippage);
   double v = MathFloor(lotToClose/step + 1e-7) * step;
   if(v < minLot) v = minLot;
   if(v >= posVol) return trade.PositionClose(ticket, (ulong)InpSlippage);
   bool ok = trade.PositionClosePartial(ticket, NormalizeDouble(v, 2), (ulong)InpSlippage);
   if(!ok) PrintFormat("PositionClosePartial #%I64u %.2f failed err=%d ret=%d",
                       ticket, v, GetLastError(), trade.ResultRetcode());
   return ok;
  }

//+------------------------------------------------------------------+
//| Are there any *original* losing positions (not lock, not avg)?   |
//+------------------------------------------------------------------+
bool HasLosingOriginalPositions()
  {
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      string cmt = pos.Comment();
      if(StringFind(cmt, "PR-AVG") >= 0) continue;
      if(StringFind(cmt, "PR-LOCK") >= 0) continue;
      double pft = pos.Profit() + pos.Swap() + pos.Commission();
      if(pft < 0) return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Pick the next losing-side ticket to chip away at, by priority.   |
//|   side=BUY  => the worst BUY we own                              |
//|   side=SELL => the worst SELL we own                             |
//+------------------------------------------------------------------+
ulong PickLosingTicket(const ENUM_POSITION_TYPE side)
  {
   if(InpRecoveryPriority == PRIO_FIRST_TICKET && InpFirstTicket != 0)
     {
      if(pos.SelectByTicket(InpFirstTicket) && pos.PositionType() == side &&
         pos.Symbol() == _Symbol)
         return InpFirstTicket;
     }
   ulong best = 0;
   double bestPft = (InpRecoveryPriority == PRIO_HARD) ? DBL_MAX : -DBL_MAX;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      if(pos.PositionType() != side) continue;
      // Skip averagers (RECOVERY orders)
      string cmt = pos.Comment();
      if(StringFind(cmt, "AVG-") >= 0 || StringFind(cmt, "PR-AVG") >= 0) continue;
      double pft = pos.Profit() + pos.Swap() + pos.Commission();
      if(pft >= 0) continue;  // only losing orders are recovery candidates
      if(InpRecoveryPriority == PRIO_HARD)
        {
         if(pft < bestPft) { bestPft = pft; best = t; }
        }
      else  // PRIO_EASY (and fallback for FIRST_TICKET miss)
        {
         if(pft > bestPft) { bestPft = pft; best = t; }
        }
     }
   return best;
  }

//+------------------------------------------------------------------+
//| Closing-overlap helper: keep only first+last averagers on a side |
//|   Closes intermediate averagers if their count >= InpOverlapAfterN |
//+------------------------------------------------------------------+
void ApplyClosingOverlap(const ENUM_POSITION_TYPE side, const string avgTag)
  {
   if(InpOverlapAfterN <= 2) return;
   ulong tickets[];
   datetime times[];
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      if(pos.PositionType() != side) continue;
      if(StringFind(pos.Comment(), avgTag) < 0) continue;
      double pft = pos.Profit() + pos.Swap() + pos.Commission();
      if(pft <= 0) continue;  // only candidates that are profitable
      int n = ArraySize(tickets);
      ArrayResize(tickets, n+1);
      ArrayResize(times,   n+1);
      tickets[n] = t;
      times[n]   = (datetime)pos.Time();
     }
   int n = ArraySize(tickets);
   if(n < InpOverlapAfterN) return;
   // Sort by time ascending (bubble sort - n is small)
   for(int i = 0; i < n-1; i++)
      for(int j = 0; j < n-i-1; j++)
         if(times[j] > times[j+1])
           {
            datetime tt = times[j]; times[j] = times[j+1]; times[j+1] = tt;
            ulong   tk = tickets[j]; tickets[j] = tickets[j+1]; tickets[j+1] = tk;
           }
   // Close everything except first and last
   for(int i = 1; i < n-1; i++)
      if(trade.PositionClose(tickets[i], (ulong)InpSlippage))
         PrintFormat("Overlap close #%I64u", tickets[i]);
  }

//+------------------------------------------------------------------+
//| MODE_PARTIAL_RECOVERY: lock + grid averagers + partial closing   |
//|                                                                  |
//| Strategy (a la AW Recovery, simplified & open-source):           |
//|   1) PR_IDLE     - wait for trigger (handled by IsRecoveryTriggered)
//|   2) PR_LOCKING  - balance volumes BUY/SELL into a lock          |
//|   3) PR_RECOVERING -                                             |
//|        - open averagers (grid step + multiplier)                 |
//|        - on each averager that hits +TP_pts, close it AND        |
//|          chip InpPartCloseLot from the worst losing position     |
//|        - optional trend filter, one-per-bar, closing overlap     |
//|   4) PR_DONE     - all losing positions closed; reset state      |
//+------------------------------------------------------------------+
void DoPartialRecovery(const BasketState &bs)
  {
   if(InpSymbolScope != SCOPE_CURRENT) return;
   if(!SpreadOK(_Symbol)) return;

   //--- universal reset -------------------------------------------------
   if(bs.count == 0)
     {
      if(g_prPhase != PR_IDLE)
        {
         PrintFormat("PartialRecovery: basket empty -> PR_IDLE (was %d)", (int)g_prPhase);
         Notify("Partial recovery complete");
         g_prPhase = PR_IDLE;
         g_prAvgCountBuy = 0; g_prAvgCountSell = 0;
         g_prCloseOldActive = false;     // v1.44: nothing left to flush
         if(InpAutoResetAfterDone) g_recoveryTriggered = false;
         if(InpUsePersistence) SaveState();
        }
      return;
     }

   //--- detect entry ----------------------------------------------------
   if(g_prPhase == PR_IDLE)
     {
      g_prPhase = PR_LOCKING;
      Notify("Partial recovery: PR_LOCKING (balancing volumes)");
      if(InpUsePersistence) SaveState();
     }

   //--- compute net to lock --------------------------------------------
   double netVol  = bs.buyVolume - bs.sellVolume;
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   //--- PR_LOCKING ------------------------------------------------------
   if(g_prPhase == PR_LOCKING)
     {
      if(MathAbs(netVol) < minLot)
        {
         g_prPhase = PR_RECOVERING;
         Notify("Partial recovery: locked, PR_RECOVERING (open averagers)");
         if(InpUsePersistence) SaveState();
        }
      else
        {
         if(bs.count >= InpMaxTrades) return;
         double lot = NormalizeLot(_Symbol, MathAbs(netVol));
         if(lot <= 0) return;
         ENUM_ORDER_TYPE side = (netVol > 0) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         if(OpenPosition(_Symbol, side, lot, "PR-LOCK"))
           {
            PrintFormat("PR-LOCK %s %.2f", EnumToString(side), lot);
            return;  // wait next tick to re-evaluate
           }
        }
     }

   //--- PR_RECOVERING ---------------------------------------------------
   if(g_prPhase != PR_RECOVERING) return;

   //--- v1.52: TF-driven imbalance trim ("выравнивание лока по ТФ") -----
   // Runs at most once per bar of InpLockAlignTF (D1 by default).
   // Independent from the trend-flip trim; complements it by handling
   // slow imbalance drift while no trend flip occurs.
   AlignLockByTF();

   //--- Sanity: any losing original positions left?  If not -> close all.
   if(!HasLosingOriginalPositions())
     {
      Print("PR: no losing original positions left -> closing residual lock+averagers");
      Notify("Partial recovery DONE: closing residual basket");
      CloseAllManaged();
      g_prPhase = PR_DONE;
      if(InpUsePersistence) SaveState();
      return;
     }

   //--- 1) Process profitable averagers => close them + chip away loss --
   ProcessProfitableAveragers(bs);

   //--- 2) Closing overlap on long averager chains ----------------------
   ApplyClosingOverlap(POSITION_TYPE_BUY,  "PR-AVG-B");
   ApplyClosingOverlap(POSITION_TYPE_SELL, "PR-AVG-S");

   //--- 3) Open new averagers if conditions are met --------------------
   if(InpCloseOnly) return;
   if(bs.count >= InpMaxTrades) return;

   sym.Name(_Symbol); sym.RefreshRates();
   double pt   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid  = sym.Bid();
   double ask  = sym.Ask();
   if(pt <= 0) return;

   int trend = TrendDirection();  // +1 / -1 / 0(filter off or neutral)

   //--- Trend reversal handling (v1.43+v1.44) ---------------------------
   // We detect a flip once and then conditionally apply two independent
   // behaviors:
   //   * v1.43 "restart grid"   - reset counters/bar-gate on the NEW side
   //                              so a fresh chain can grow immediately;
   //   * v1.44 "close old grid" - arm the OLD-side PR-AVG basket for a
   //                              profit-close (TryCloseOldGridByProfit
   //                              flushes it once combined PnL crosses
   //                              InpOldGridCloseProfit).
   // Both can be enabled together; defaults keep prior behavior + the new
   // basket-flush.
   bool trendFlipped = (trend != 0 && g_prLastTrend != 0 && trend != g_prLastTrend);
   if(trendFlipped)
     {
      PrintFormat("PR: trend flip %d -> %d", g_prLastTrend, trend);

      if(InpRestartGridOnTrendFlip)
        {
         Notify(StringFormat("PR: trend reversal -> restart grid (%s)",
                             trend > 0 ? "BUY" : "SELL"));
         if(trend > 0)
           { g_prAvgCountBuy  = 0; g_prLastBarTime  = 0; }
         else
           { g_prAvgCountSell = 0; g_prLastBarTimeS = 0; }
        }

      if(InpCloseOldGridOnTrendFlip)
        {
         // Old side = the side that was being grown under the previous
         // trend.  Re-arming on every flip is fine: even if a previous
         // close-old was still pending, the new "old side" is now the
         // direction price just abandoned.
         g_prCloseOldActive = true;
         g_prCloseOldSide   = (g_prLastTrend > 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         PrintFormat("PR: arm close-old-grid on %s side (target>=%.2f USD)",
                     (g_prCloseOldSide == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                     InpOldGridCloseProfit);
         Notify(StringFormat("PR: arm close-old-grid on %s by profit",
                             g_prCloseOldSide == POSITION_TYPE_BUY ? "BUY" : "SELL"));
        }

      // v1.51: одноразовый trim ИМЕННО ЛОКА на смене тренда.
      // Считает lockVol на одной стороне и origVol (managed-позиции
      // без тегов PR-AVG/PR-LOCK) на противоположной, режет лок до
      // объёма противоположного оригинала. Усреднители (PR-AVG-*)
      // и однонаправленные с локом оригиналы НЕ учитываются и НЕ
      // закрываются — для них работают InpRestartGridOnTrendFlip и
      // InpCloseOldGridOnTrendFlip.
      if(InpTrendFlipTrimStrong)
         TrimStrongSideToWeak();

      if(InpUsePersistence) SaveState();
     }
   if(trend != 0) g_prLastTrend = trend;

   // Try to flush the armed old-side grid every tick.  The helper closes
   // and disarms itself once combined PnL >= InpOldGridCloseProfit, or
   // disarms silently if no PR-AVG-* on the marked side remain.
   if(g_prCloseOldActive)
      TryCloseOldGridByProfit();

   // BUY averager (covers SELL losing baskets if non-bidirectional)
   bool wantBuy  = false;
   bool wantSell = false;
   if(InpPRBidirectional)
     {
      wantBuy  = true;
      wantSell = true;
     }
   else
     {
      // open averager opposite to the heavier losing side
      if(bs.sellProfit < bs.buyProfit) wantBuy  = true;  // SELL hurts more, push price up via BUY
      else                              wantSell = true;
     }

   // Apply trend filter
   if(InpUseTrendFilter && trend != 0)
     {
      if(trend < 0) wantBuy  = false;
      if(trend > 0) wantSell = false;
     }

   // BUY averager
   if(wantBuy && g_prAvgCountBuy < InpMaxAveragers)
     {
      double lastB = LastAveragerPrice(POSITION_TYPE_BUY, "PR-AVG-B");
      double step  = AvgStepPoints(g_prAvgCountBuy) * pt;
      bool spaceOK = (lastB <= 0) || (ask <= lastB - step);
      bool barOK   = !InpOneOrderPerBar || IsNewBar(g_prLastBarTime);
      if(spaceOK && barOK)
        {
         double lot = InpAvgVolume * MathPow(InpAvgVolumeMul, MathMax(0, g_prAvgCountBuy));
         lot = NormalizeLot(_Symbol, lot);
         if(lot > 0 && OpenPosition(_Symbol, ORDER_TYPE_BUY, lot, "PR-AVG-B"))
           {
            g_prAvgCountBuy++;
            if(InpUsePersistence) SaveState();
           }
        }
     }
   // SELL averager
   if(wantSell && g_prAvgCountSell < InpMaxAveragers)
     {
      double lastS = LastAveragerPrice(POSITION_TYPE_SELL, "PR-AVG-S");
      double step  = AvgStepPoints(g_prAvgCountSell) * pt;
      bool spaceOK = (lastS <= 0) || (bid >= lastS + step);
      bool barOK   = !InpOneOrderPerBar || IsNewBar(g_prLastBarTimeS);
      if(spaceOK && barOK)
        {
         double lot = InpAvgVolume * MathPow(InpAvgVolumeMul, MathMax(0, g_prAvgCountSell));
         lot = NormalizeLot(_Symbol, lot);
         if(lot > 0 && OpenPosition(_Symbol, ORDER_TYPE_SELL, lot, "PR-AVG-S"))
           {
            g_prAvgCountSell++;
            if(InpUsePersistence) SaveState();
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Find the latest opening price for an averager of given side+tag. |
//+------------------------------------------------------------------+
double LastAveragerPrice(const ENUM_POSITION_TYPE side, const string tag)
  {
   double bestPrice = 0;
   datetime bestTime = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      if(pos.PositionType() != side) continue;
      if(StringFind(pos.Comment(), tag) < 0) continue;
      datetime tm = (datetime)pos.Time();
      if(tm > bestTime)
        { bestTime = tm; bestPrice = pos.PriceOpen(); }
     }
   return bestPrice;
  }

//+------------------------------------------------------------------+
//| v1.44: close-old-grid-by-profit.                                  |
//|                                                                   |
//| When trend flips while PR_RECOVERING, DoPartialRecovery arms      |
//| g_prCloseOldActive=true and tags the OLD trend side                |
//| (g_prCloseOldSide).  This helper is called every tick afterwards: |
//|   1) Iterate every managed PR-AVG-* position on the marked side,  |
//|      summing realized+unrealized PnL (Profit + Swap + Commission).|
//|   2) If no such positions remain (TP/overlap/etc closed them all),|
//|      disarm and persist.                                          |
//|   3) If sum >= InpOldGridCloseProfit, close the entire batch in   |
//|      one pass and disarm.  We decrement g_prAvgCount* per closed  |
//|      ticket so a fresh chain on the new side keeps its multiplier |
//|      starting from zero (paired with InpRestartGridOnTrendFlip).  |
//| Note: only PR-AVG-B / PR-AVG-S are flushed.  Lock leg(s)          |
//| (PR-LOCK) and the original losing positions are NOT touched here. |
//+------------------------------------------------------------------+
void TryCloseOldGridByProfit()
  {
   if(!g_prCloseOldActive) return;

   string tag = (g_prCloseOldSide == POSITION_TYPE_BUY) ? "PR-AVG-B" : "PR-AVG-S";

   ulong  tickets[];
   double sum = 0.0;
   int    total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong tk = PositionGetTicket(i);
      if(!IsManaged(tk)) continue;                       // also selects pos
      if(pos.PositionType() != g_prCloseOldSide) continue;
      if(StringFind(pos.Comment(), tag) < 0) continue;
      sum += pos.Profit() + pos.Swap() + pos.Commission();
      int n = ArraySize(tickets); ArrayResize(tickets, n + 1); tickets[n] = tk;
     }

   if(ArraySize(tickets) == 0)
     {
      // Nothing left on the marked side -> auto-disarm.
      g_prCloseOldActive = false;
      if(InpUsePersistence) SaveState();
      return;
     }

   if(sum < InpOldGridCloseProfit) return;  // wait for combined profit

   int closed = 0;
   for(int i = 0; i < ArraySize(tickets); i++)
     {
      if(trade.PositionClose(tickets[i], (ulong)InpSlippage))
        {
         closed++;
         if(g_prCloseOldSide == POSITION_TYPE_BUY)
            g_prAvgCountBuy  = MathMax(0, g_prAvgCountBuy  - 1);
         else
            g_prAvgCountSell = MathMax(0, g_prAvgCountSell - 1);
        }
     }
   PrintFormat("PR: closed old %s grid: %d/%d avg, profit=%.2f (target>=%.2f)",
               g_prCloseOldSide == POSITION_TYPE_BUY ? "BUY" : "SELL",
               closed, ArraySize(tickets), sum, InpOldGridCloseProfit);
   Notify(StringFormat("PR: old %s grid flushed (%d avg, +%.2f)",
                       g_prCloseOldSide == POSITION_TYPE_BUY ? "BUY" : "SELL",
                       closed, sum));
   g_prCloseOldActive = false;
   if(InpUsePersistence) SaveState();
  }

//+------------------------------------------------------------------+
//| Sum total volume of ALL managed positions, separately for each   |
//| direction.  Counts every group the EA considers managed: PR-AVG, |
//| PR-LOCK, originals (no PR-* tag), AVG-*, GRID-*, MANUAL-LOCK,    |
//| etc.  Generic helper kept for diagnostics / future use.           |
//| Note: v1.51 trim no longer uses this — TrimStrongSideToWeak now  |
//| computes lockVol / origVol separately and only trims the LOCK.   |
//+------------------------------------------------------------------+
void ComputeManagedNetVolumes(double &buyVol, double &sellVol)
  {
   buyVol  = 0.0;
   sellVol = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;                       // also selects pos
      double v = pos.Volume();
      if(pos.PositionType() == POSITION_TYPE_BUY)       buyVol  += v;
      else if(pos.PositionType() == POSITION_TYPE_SELL) sellVol += v;
     }
  }

//+------------------------------------------------------------------+
//| TrimStrongSideToWeak (v1.51 - lock-targeted).                    |
//| Called once at trend-flip time when InpTrendFlipTrimStrong=true. |
//|                                                                  |
//| Прежняя реализация (v1.50) суммировала объёмы ВСЕХ managed-      |
//| позиций по сторонам и закрывала «сильную» сторону до «слабой»,   |
//| сортируя по PnL DESC. У лока обычно наибольший абсолютный PnL    |
//| (крупный объём), поэтому он попадал первым в очередь и забирал   |
//| весь diff на себя — включая объём открытых усреднителей. В       |
//| итоге пользователь видел, что лок закрывается полностью или      |
//| гораздо сильнее, чем ожидалось.                                  |
//|                                                                  |
//| Новая логика: считаем строго                                     |
//|   * lockVolBuy  / lockVolSell  — суммарный объём PR-LOCK по сторонам|
//|   * origVolBuy  / origVolSell  — суммарный объём «оригиналов»    |
//|     (managed-позиции БЕЗ тегов PR-AVG / PR-LOCK)                 |
//| и режем именно LOCK на стороне, где он есть, до объёма оригинала |
//| на противоположной стороне. Усреднители и однонаправленные с     |
//| локом оригиналы в расчёте не участвуют и trim-ом не трогаются.   |
//|                                                                  |
//| Пример пользователя:                                             |
//|   SELL original 1.0 → чип 0.2 → 0.8                               |
//|   PR-LOCK BUY 1.0                                                |
//|   trend flip → diff = lockBuy(1.0) − origSell(0.8) = 0.2          |
//|   LOCK BUY режется на 0.2 → 0.8                                  |
//|   итог: SELL 0.80 / lock BUY 0.80, усреднители (если ещё открыты) |
//|   не трогаются и закрываются по своему TP / по                   |
//|   InpCloseOldGridOnTrendFlip.                                    |
//|                                                                  |
//| Crap-cases (no-op):                                               |
//|   * лока нет ни на одной стороне → нечего тримить                 |
//|   * лок одновременно и на BUY и на SELL (нештатно) → не трогаем,  |
//|     чтобы не разрулить лок-пару непредсказуемо                    |
//|   * diff < minLot брокера → уже сбалансировано                    |
//|                                                                  |
//| После trim-а g_prAvgCount{Buy,Sell} НЕ требуют пересчёта (мы не   |
//| трогали PR-AVG-*), но всё равно делаем скан для consistency, на  |
//| случай если в будущем поменяется стратегия отбора целей.         |
//+------------------------------------------------------------------+
void TrimStrongSideToWeak()
  {
   double lockBuy  = 0.0, lockSell = 0.0;
   double origBuy  = 0.0, origSell = 0.0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;                       // also selects pos
      double v = pos.Volume();
      ENUM_POSITION_TYPE pt = pos.PositionType();
      string cmt = pos.Comment();

      if(StringFind(cmt, "PR-LOCK") >= 0)
        {
         if(pt == POSITION_TYPE_BUY)       lockBuy  += v;
         else if(pt == POSITION_TYPE_SELL) lockSell += v;
        }
      else if(StringFind(cmt, "PR-AVG") < 0)
        {
         // not lock, not averager => "original" (manual / loser / pre-existing)
         if(pt == POSITION_TYPE_BUY)       origBuy  += v;
         else if(pt == POSITION_TYPE_SELL) origSell += v;
        }
      // PR-AVG-* are intentionally ignored — trim must NOT touch them.
     }

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   bool hasLockBuy  = (lockBuy  >= minLot);
   bool hasLockSell = (lockSell >= minLot);

   // No clear single-sided lock -> nothing to trim.
   if(hasLockBuy == hasLockSell)
     {
      if(hasLockBuy && hasLockSell)
         Print("PR trim: lock present on BOTH sides, skipping trim (manual review needed)");
      return;
     }

   ENUM_POSITION_TYPE strong;
   double currentLockVol;
   double oppositeOrigVol;

   if(hasLockBuy)
     {
      strong          = POSITION_TYPE_BUY;
      currentLockVol  = lockBuy;
      oppositeOrigVol = origSell;
     }
   else
     {
      strong          = POSITION_TYPE_SELL;
      currentLockVol  = lockSell;
      oppositeOrigVol = origBuy;
     }

   double diff = currentLockVol - oppositeOrigVol;
   if(diff < minLot)
     {
      // lock already <= opposite original (e.g. someone partially closed
      // the lock manually) -> nothing to trim.
      return;
     }

   // --- Collect PR-LOCK tickets on the strong side --------------------
   ulong  tickets[];
   double profits[];
   int t1 = PositionsTotal();
   for(int i = 0; i < t1; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      if(pos.PositionType() != strong) continue;
      if(StringFind(pos.Comment(), "PR-LOCK") < 0) continue;
      double pnl = pos.Profit() + pos.Swap() + pos.Commission();
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      ArrayResize(profits, n + 1);
      tickets[n] = t;
      profits[n] = pnl;
     }

   int N = ArraySize(tickets);
   if(N == 0) return;

   // Sort DESC by PnL (most profitable lock-leg goes first).  In the
   // typical case there's exactly one lock leg and the sort is a no-op.
   for(int a = 0; a < N - 1; a++)
      for(int b = a + 1; b < N; b++)
         if(profits[b] > profits[a])
           {
            double tp = profits[a]; profits[a] = profits[b]; profits[b] = tp;
            ulong  tt = tickets[a]; tickets[a] = tickets[b]; tickets[b] = tt;
           }

   double remaining      = diff;
   int    closedFull     = 0;
   int    closedPart     = 0;
   double closedVolTotal = 0.0;

   for(int i = 0; i < N && remaining >= minLot; i++)
     {
      if(!pos.SelectByTicket(tickets[i])) continue;
      double posVol = pos.Volume();

      if(posVol <= remaining + 1e-9)
        {
         // Full close of this lock leg
         if(trade.PositionClose(tickets[i], (ulong)InpSlippage))
           {
            closedFull++;
            closedVolTotal += posVol;
            remaining      -= posVol;
           }
         else
           {
            PrintFormat("PR trim: PositionClose lock #%I64u failed err=%d ret=%d",
                        tickets[i], GetLastError(), trade.ResultRetcode());
           }
        }
      else
        {
         // Partial close to land exactly on the matching volume
         if(ClosePartOfPosition(tickets[i], remaining))
           {
            closedPart++;
            closedVolTotal += remaining;
            remaining       = 0.0;
           }
         else
           {
            PrintFormat("PR trim: ClosePartOfPosition lock #%I64u %.4f failed",
                        tickets[i], remaining);
           }
        }
     }

   if(closedFull == 0 && closedPart == 0) return;

   // PR-AVG-* were not touched, but rescan counters for safety/consistency.
   int avgB = 0, avgS = 0;
   int t2 = PositionsTotal();
   for(int i = 0; i < t2; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      string cmt = pos.Comment();
      if(StringFind(cmt, "PR-AVG-B") >= 0)      avgB++;
      else if(StringFind(cmt, "PR-AVG-S") >= 0) avgS++;
     }
   g_prAvgCountBuy  = avgB;
   g_prAvgCountSell = avgS;

   PrintFormat("PR trend-flip trim LOCK: %s side -%.4f lot (%d full, %d partial), "
               "lock %.4f -> %.4f to match opp original %.4f",
               strong == POSITION_TYPE_BUY ? "BUY" : "SELL",
               closedVolTotal, closedFull, closedPart,
               currentLockVol, currentLockVol - closedVolTotal, oppositeOrigVol);
   Notify(StringFormat("PR trim lock %s -%.4f lot (match opp orig %.4f)",
                       strong == POSITION_TYPE_BUY ? "BUY" : "SELL",
                       closedVolTotal, oppositeOrigVol));

   if(InpUsePersistence) SaveState();
  }

//+------------------------------------------------------------------+
//| For each profitable averager: close it, then chip a SAFE amount   |
//| off the worst losing position on the OPPOSITE side, sized so the  |
//| combined cycle PnL (averager profit + chip realized loss) stays   |
//| >= effective floor.                                                |
//|                                                                   |
//| effFloor = max(InpMinNetProfit, avgProfit * InpMinNetProfitPct/100)|
//|                                                                   |
//| If even the broker's minLot would drag the cycle below the floor, |
//| the chip is skipped entirely and the averager profit is locked in |
//| on its own.  Set InpEnsureNetPositive=false to fall back to the   |
//| legacy fixed-lot chipping (InpPartCloseLot every cycle).           |
//+------------------------------------------------------------------+
void ProcessProfitableAveragers(const BasketState &bs)
  {
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   ulong tickets[];
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      string cmt = pos.Comment();
      if(StringFind(cmt, "PR-AVG") < 0) continue;
      double op = pos.PriceOpen();
      ENUM_POSITION_TYPE pt2 = pos.PositionType();
      double pts = (pt2 == POSITION_TYPE_BUY) ? (bid - op)/pt : (op - ask)/pt;
      if(pts < InpAvgTPpts) continue;
      int n = ArraySize(tickets); ArrayResize(tickets, n+1); tickets[n] = t;
     }

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;

   for(int i = 0; i < ArraySize(tickets); i++)
     {
      if(!pos.SelectByTicket(tickets[i])) continue;
      ENUM_POSITION_TYPE avgSide = pos.PositionType();
      double avgVol    = pos.Volume();
      double avgProfit = pos.Profit() + pos.Swap() + pos.Commission();

      // --- Pick a losing target on the OPPOSITE side first ------------
      ENUM_POSITION_TYPE losingSide = (avgSide == POSITION_TYPE_BUY)
                                       ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      ulong target = PickLosingTicket(losingSide);
      if(target == 0) target = PickLosingTicket(avgSide);

      // --- Compute a safe chip lot that keeps net >= InpMinNetProfit --
      double safeChip = 0.0;
      bool   willChip = false;
      string skipReason = "";

      if(target != 0 && pos.SelectByTicket(target))
        {
         double tgtVol = pos.Volume();
         double tgtPnL = pos.Profit() + pos.Swap() + pos.Commission(); // expected <0

         if(tgtVol <= 0 || tgtPnL >= 0)
           {
            skipReason = "target not in loss";
           }
         else if(InpEnsureNetPositive)
           {
            double pnlPerLot = tgtPnL / tgtVol;        // <0 ($/lot)
            // Effective floor: max of absolute floor and percentage-of-profit
            double pctClamped = MathMax(0.0, MathMin(100.0, InpMinNetProfitPct));
            double effFloor   = InpMinNetProfit;
            if(pctClamped > 0.0)
               effFloor = MathMax(effFloor, avgProfit * pctClamped / 100.0);
            double headroom  = avgProfit - effFloor;
            if(headroom <= 0)
              {
               skipReason = StringFormat("avgProfit %.2f <= floor %.2f (abs=%.2f, pct=%.1f%%)",
                                         avgProfit, effFloor, InpMinNetProfit, pctClamped);
              }
            else
              {
               double maxChip = headroom / MathAbs(pnlPerLot);
               safeChip = MathMin(InpPartCloseLot, maxChip);
               // round DOWN to broker step
               safeChip = MathFloor(safeChip / step + 1e-9) * step;
               if(safeChip + 1e-9 < minLot)
                 {
                  skipReason = StringFormat("safeChip %.4f < minLot %.4f (per-lot loss %.2f)",
                                            safeChip, minLot, pnlPerLot);
                  safeChip = 0.0;
                 }
               else
                 {
                  willChip = true;
                 }
              }
           }
         else
           {
            // legacy: fixed chip
            safeChip = InpPartCloseLot;
            willChip = true;
           }
        }

      // --- Re-select the averager and close it ------------------------
      if(!pos.SelectByTicket(tickets[i])) continue;
      if(!trade.PositionClose(tickets[i], (ulong)InpSlippage)) continue;

      PrintFormat("PR: closed averager #%I64u (%s %.2f, profit=%.2f)",
                  tickets[i],
                  avgSide==POSITION_TYPE_BUY?"BUY":"SELL", avgVol, avgProfit);
      if(avgSide == POSITION_TYPE_BUY) g_prAvgCountBuy  = MathMax(0, g_prAvgCountBuy-1);
      else                              g_prAvgCountSell = MathMax(0, g_prAvgCountSell-1);

      // --- Chip the loser if safe; otherwise just lock the avg profit -
      if(willChip && target != 0)
        {
         if(ClosePartOfPosition(target, safeChip))
           {
            PrintFormat("PR: chipped %.4f from #%I64u (avgP=%.2f, prio=%d, mode=%s)",
                        safeChip, target, avgProfit, (int)InpRecoveryPriority,
                        InpEnsureNetPositive ? "net+" : "fixed");
           }
        }
      else if(target != 0)
        {
         PrintFormat("PR: chip skipped on #%I64u — %s; averager profit %.2f locked.",
                     target, skipReason, avgProfit);
        }
      else
        {
         PrintFormat("PR: no losing tickets to chip; recovery may be near completion");
        }
     }
  }

//+------------------------------------------------------------------+
//| Open a market order with the EA's magic number                   |
//+------------------------------------------------------------------+
bool OpenPosition(const string symbol, const ENUM_ORDER_TYPE type, double lot, const string tag)
  {
   if(lot <= 0) return false;
   if(!sym.Name(symbol)) return false;
   sym.RefreshRates();
   double price = (type == ORDER_TYPE_BUY) ? sym.Ask() : sym.Bid();
   string cmt = StringFormat("%s|%s", InpComment, tag);
   trade.SetExpertMagicNumber(InpMagic);
   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy(lot, symbol, price, 0.0, 0.0, cmt)
             : trade.Sell(lot, symbol, price, 0.0, 0.0, cmt);
   if(!ok)
      PrintFormat("Open %s %s %.2f failed err=%d ret=%d",
                  symbol, EnumToString(type), lot, GetLastError(), trade.ResultRetcode());
   return ok;
  }


//+------------------------------------------------------------------+
//| Panel & Buttons                                                   |
//+------------------------------------------------------------------+
void CreateLabel(const string key, int x, int y)
  {
   string name = g_panelPrefix + key;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpPanelColor);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpPanelFontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetString(0, name, OBJPROP_TEXT, "");
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }
  }

void CreateButton(const string name, int x, int y, int w, int h,
                  const string text, color bg, color fg)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrSilver);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }
  }


void CreatePanel()
  {
   string lines[] = {"title","mode","scope","basket","count","buy","sell","profit",
                     "peak","target","lock","align","filter","stop"};
   int y = 20;
   for(int i=0; i<ArraySize(lines); i++)
     {
      CreateLabel(lines[i], 10, y);
      y += InpPanelFontSize + 6;
     }
   int btnY = y + 6;
   int bw = 90, bh = 22, gap = 6;
   CreateButton(BTN_CLOSE_ALL,  10,            btnY,             bw, bh, "Close All",  clrFireBrick, clrWhite);
   CreateButton(BTN_PAUSE,      10+bw+gap,     btnY,             bw, bh, "Pause",      clrSlateGray, clrWhite);
   CreateButton(BTN_CLOSE_BUY,  10,            btnY+bh+gap,      bw, bh, "Close BUY",  clrSteelBlue, clrWhite);
   CreateButton(BTN_CLOSE_SELL, 10+bw+gap,     btnY+bh+gap,      bw, bh, "Close SELL", clrIndianRed, clrWhite);
   CreateButton(BTN_LOCK,       10,            btnY+2*(bh+gap),  bw, bh, "Lock Now",   clrGoldenrod, clrBlack);
   CreateButton(BTN_RESET,      10+bw+gap,     btnY+2*(bh+gap),  bw, bh, "Reset Stop", clrDarkGreen, clrWhite);
   CreateButton(BTN_RESET_STATE,10+bw+gap,     btnY+3*(bh+gap),  bw, bh, "Reset State",clrDarkSlateBlue, clrWhite);
   if(InpShowManualButtons)
     {
      // Lot label above the manual row
      CreateLabel("manualLot", 10, btnY+4*(bh+gap)+2);
      // Manual market open buttons
      CreateButton(BTN_MANUAL_BUY,  10,        btnY+5*(bh+gap), bw, bh, "BUY (manual)",  clrTeal,      clrWhite);
      CreateButton(BTN_MANUAL_SELL, 10+bw+gap, btnY+5*(bh+gap), bw, bh, "SELL (manual)", clrDarkOrange, clrWhite);
     }
  }

void SetLabel(const string key, const string text, color clr = clrNONE)
  {
   string name = g_panelPrefix + key;
   if(ObjectFind(0, name) < 0) return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, (clr == clrNONE) ? InpPanelColor : clr);
  }


void UpdatePanel(const BasketState &bs)
  {
   if(!InpShowPanel) return;
   string modeName = "";
   switch(InpMode)
     {
      case MODE_TARGET_PROFIT:    modeName="TargetProfit";    break;
      case MODE_AVERAGING:        modeName="Averaging";       break;
      case MODE_MARTINGALE:       modeName="Martingale";      break;
      case MODE_HEDGE_LOCK:       modeName="HedgeLock";       break;
      case MODE_SMART_CLOSE:      modeName="SmartClose";      break;
      case MODE_PARTIAL_RECOVERY: modeName="PartialRecovery"; break;
     }
   string scopeName = (InpManageScope==MANAGE_ALL ? "ALL"
                       : InpManageScope==MANAGE_MANUAL ? "MANUAL" : "OWN");
   string symScope  = (InpSymbolScope==SCOPE_CURRENT ? _Symbol : "ALL_SYMBOLS");
   string basketName= (InpBasketMode==BASKET_COMBINED ? "COMBINED" : "PER_SIDE");

   double tgtComb = ResolveTargetMoney(bs.buyVolume + bs.sellVolume);
   double tgtBuy  = ResolveTargetMoney(bs.buyVolume);
   double tgtSell = ResolveTargetMoney(bs.sellVolume);
   color profitClr = (bs.profit >= 0) ? clrLime : clrTomato;

   SetLabel("title",  "=== RECOVERI v1.52 ULTIMATE ===", clrGold);
   SetLabel("mode",   StringFormat("Mode  : %s%s", modeName, InpCloseOnly?" [CLOSE-ONLY]":""));
   SetLabel("scope",  StringFormat("Manage: %s @ %s", scopeName, symScope));
   SetLabel("basket", StringFormat("Basket: %s", basketName));
   SetLabel("count",  StringFormat("Trades: %d  (max %d)", bs.count, InpMaxTrades));
   SetLabel("buy",    StringFormat("BUY  : %d / %.2f @ %.5f  P/L %.2f",
                                   bs.buyCount, bs.buyVolume, bs.buyPriceAvg, bs.buyProfit));
   SetLabel("sell",   StringFormat("SELL : %d / %.2f @ %.5f  P/L %.2f",
                                   bs.sellCount, bs.sellVolume, bs.sellPriceAvg, bs.sellProfit));
   SetLabel("profit", StringFormat("P/L  : %.2f %s", bs.profit, AccountInfoString(ACCOUNT_CURRENCY)),
                      profitClr);
   if(InpBasketMode == BASKET_COMBINED)
     {
      SetLabel("peak",   StringFormat("Peak  : %.2f", g_peakProfit));
      SetLabel("target", StringFormat("Target: %.2f", tgtComb));
     }
   else
     {
      SetLabel("peak",   StringFormat("Peak  : B=%.2f S=%.2f", g_peakBuyProfit, g_peakSellProfit));
      SetLabel("target", StringFormat("Target: B=%.2f S=%.2f", tgtBuy, tgtSell));
     }

   // Lock-unwind status / Partial-Recovery status
   if(InpMode == MODE_PARTIAL_RECOVERY)
     {
      string prName = "";
      color  prClr  = InpPanelColor;
      switch(g_prPhase)
        {
         case PR_IDLE:        prName = "IDLE (waiting)"; prClr = clrSilver;       break;
         case PR_LOCKING:     prName = "LOCKING";        prClr = clrGold;         break;
         case PR_RECOVERING:  prName = "RECOVERING";     prClr = clrLightSkyBlue; break;
         case PR_DONE:        prName = "DONE";           prClr = clrLime;         break;
        }
      string trigStr = g_recoveryTriggered ? "TRIGGERED" : "ARMED";
      SetLabel("lock", StringFormat("PR: %s [%s] avgB=%d avgS=%d trend=%d",
                                    prName, trigStr,
                                    g_prAvgCountBuy, g_prAvgCountSell,
                                    TrendDirection()), prClr);
     }
   else if(InpMode == MODE_HEDGE_LOCK && InpAutoUnlock)
     {
      string phaseName = "";
      color  phaseClr  = InpPanelColor;
      switch(g_lockPhase)
        {
         case PHASE_IDLE:     phaseName = "IDLE";     phaseClr = clrSilver;    break;
         case PHASE_LOCKED:   phaseName = "LOCKED";   phaseClr = clrGold;      break;
         case PHASE_UNWOUND:  phaseName = StringFormat("UNWOUND (%s)",
                                          g_remainingSide==POSITION_TYPE_BUY?"BUY":"SELL");
                              phaseClr = clrLightSkyBlue; break;
         case PHASE_RELOCKED: phaseName = "RELOCKED";  phaseClr = clrOrange;   break;
        }
      SetLabel("lock", StringFormat("Unwind: %s peakB=%.2f peakS=%.2f relocks=%d/%d",
                                    phaseName, g_lockPeakBuy, g_lockPeakSell,
                                    g_relockCount, InpMaxRelocks), phaseClr);
     }
   else
     {
      string trigStr = (InpStartTrigger == START_INSTANT) ? "instant" :
                       (g_recoveryTriggered ? "TRIGGERED" : StringFormat("ARMED (thr=%.1f)", InpStartThreshold));
      SetLabel("lock", StringFormat("Trigger: %s", trigStr));
     }


   // v1.52: ATR-grid + TF-align status. Always emitted (line is permanent
   // in CreatePanel) — when both blocks are off we just show "off" so the
   // user can see at a glance that no extra logic is active.
   {
      string atrPart = "off";
      if(InpAvgStepUseATR)
        {
         double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double atrPts = 0.0;
         int h = iATR(_Symbol, InpAvgStepATRTF, InpAvgStepATRPeriod);
         if(h != INVALID_HANDLE)
           {
            double buf[1];
            if(CopyBuffer(h, 0, 0, 1, buf) > 0 && pt > 0)
               atrPts = (buf[0] / pt) * InpAvgStepATRMul;
            IndicatorRelease(h);
           }
         double basePts = MathMax(atrPts, (double)InpAvgStepATRMin);
         atrPart = StringFormat("ATR(%s,%d)x%.2f=%.0fpt",
                                EnumToString(InpAvgStepATRTF),
                                InpAvgStepATRPeriod, InpAvgStepATRMul, basePts);
        }

      string algPart = "off";
      if(InpLockAlignUseTF)
        {
         double bv = 0, sv = 0;
         int total = PositionsTotal();
         for(int i = 0; i < total; i++)
           {
            ulong t = PositionGetTicket(i);
            if(!IsManaged(t)) continue;
            double v = pos.Volume();
            if(pos.PositionType() == POSITION_TYPE_BUY)       bv += v;
            else if(pos.PositionType() == POSITION_TYPE_SELL) sv += v;
           }
         double imb = bv - sv;
         algPart = StringFormat("Align(%s) imb=%+.2f%s",
                                EnumToString(InpLockAlignTF), imb,
                                InpLockAlignOnlyProfit ? " +zone" : "");
        }
      SetLabel("align", StringFormat("Step:%s | %s", atrPart, algPart));
   }

   string filt = "Filter:";
   if(g_paused)         filt += " PAUSE";
   if(InpUseTimeFilter) filt += IsTimeAllowed() ? " time-OK" : " TIME-BLK";
   if(InpUseNewsFilter) filt += IsNewsBlocked() ? " NEWS-BLK" : " news-OK";
   if(filt == "Filter:") filt += " none";
   color fclr = (g_paused || g_blockReason != "") ? clrOrange : InpPanelColor;
   SetLabel("filter", filt, fclr);

   string statusText; color statusClr;
   if(g_emergencyStop) { statusText = "STATUS: EMERGENCY STOP"; statusClr = clrRed; }
   else if(g_paused)   { statusText = "STATUS: PAUSED";          statusClr = clrOrange; }
   else                { statusText = "STATUS: OK";              statusClr = clrLime; }
   SetLabel("stop", statusText, statusClr);

   ObjectSetString(0, BTN_PAUSE, OBJPROP_TEXT, g_paused ? "Resume" : "Pause");
   if(InpShowManualButtons)
      SetLabel("manualLot", StringFormat("Manual lot: %.2f", InpManualLot), clrLightGray);
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Notifications: Alert / Sound / Push                              |
//+------------------------------------------------------------------+
void Notify(const string text)
  {
   string tag = StringFormat("[RECOVERI %s] %s", _Symbol, text);
   if(InpUseAlert) Alert(tag);
   if(InpUseSound && InpSoundFile != "") PlaySound(InpSoundFile);
   if(InpUsePush)  SendNotification(tag);
   if(InpUseEmail) SendMail(StringFormat("RECOVERI %s", _Symbol), tag);
  }

//+------------------------------------------------------------------+
//| Per-position virtual trailing stop                               |
//+------------------------------------------------------------------+
int TslIndexOf(const ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_tslTickets); i++)
      if(g_tslTickets[i] == ticket) return i;
   return -1;
  }

void TslSet(const ulong ticket, const double peakPts)
  {
   int idx = TslIndexOf(ticket);
   if(idx < 0)
     {
      int n = ArraySize(g_tslTickets);
      ArrayResize(g_tslTickets, n+1);
      ArrayResize(g_tslPeaks,   n+1);
      g_tslTickets[n] = ticket;
      g_tslPeaks[n]   = peakPts;
     }
   else
      g_tslPeaks[idx] = peakPts;
  }

void TslRemove(const ulong ticket)
  {
   int idx = TslIndexOf(ticket);
   if(idx < 0) return;
   int n = ArraySize(g_tslTickets);
   for(int i = idx; i < n-1; i++)
     {
      g_tslTickets[i] = g_tslTickets[i+1];
      g_tslPeaks[i]   = g_tslPeaks[i+1];
     }
   ArrayResize(g_tslTickets, n-1);
   ArrayResize(g_tslPeaks,   n-1);
  }



//+------------------------------------------------------------------+
void VirtualTSLCheck()
  {
   ulong tickets[];
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(IsManaged(t))
        { int n = ArraySize(tickets); ArrayResize(tickets, n+1); tickets[n] = t; }
     }
   for(int i=0; i<ArraySize(tickets); i++)
     {
      if(!pos.SelectByTicket(tickets[i])) continue;
      string s   = pos.Symbol();
      double pt  = SymbolInfoDouble(s, SYMBOL_POINT);
      if(pt <= 0) continue;
      double bid = SymbolInfoDouble(s, SYMBOL_BID);
      double ask = SymbolInfoDouble(s, SYMBOL_ASK);
      double op  = pos.PriceOpen();
      ENUM_POSITION_TYPE pt2 = pos.PositionType();
      double pts = (pt2 == POSITION_TYPE_BUY) ? (bid - op)/pt : (op - ask)/pt;

      int idx = TslIndexOf(tickets[i]);
      double peak = (idx >= 0) ? g_tslPeaks[idx] : -DBL_MAX;
      if(pts >= InpVirtualTSLStartPts && pts > peak)
        {
         TslSet(tickets[i], pts);
         peak = pts;
        }
      if(idx >= 0 && peak >= InpVirtualTSLStartPts &&
         pts <= peak - InpVirtualTSLDistPts)
        {
         if(trade.PositionClose(tickets[i], (ulong)InpSlippage))
           {
            PrintFormat("Virtual TSL #%I64u: peak=%.0f cur=%.0f pts -> closed", tickets[i], peak, pts);
            Notify(StringFormat("Virtual TSL #%I64u: peak=%.0f cur=%.0f pts", tickets[i], peak, pts));
            TslRemove(tickets[i]);
           }
        }
     }
  }



//+------------------------------------------------------------------+
//| Persistence via GlobalVariables                                  |
//+------------------------------------------------------------------+
void SaveState()
  {
   if(g_gvPrefix == "") return;
   GlobalVariableSet(g_gvPrefix + "MODE",    (double)InpMode);
   GlobalVariableSet(g_gvPrefix + "PAUSED",  g_paused        ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "ESTOP",   g_emergencyStop ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "PEAK_C",  g_peakProfit);
   GlobalVariableSet(g_gvPrefix + "PEAK_B",  g_peakBuyProfit);
   GlobalVariableSet(g_gvPrefix + "PEAK_S",  g_peakSellProfit);
   GlobalVariableSet(g_gvPrefix + "GRID",    g_gridPlaced    ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "LK_PH",   (double)g_lockPhase);
   GlobalVariableSet(g_gvPrefix + "LK_RS",   (g_remainingSide == POSITION_TYPE_BUY) ? 0.0 : 1.0);
   GlobalVariableSet(g_gvPrefix + "LK_PB",   g_lockPeakBuy);
   GlobalVariableSet(g_gvPrefix + "LK_PS",   g_lockPeakSell);
   GlobalVariableSet(g_gvPrefix + "LK_RC",   (double)g_relockCount);
   GlobalVariableSet(g_gvPrefix + "RC_TRIG", g_recoveryTriggered ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "BASE_BAL",g_baselineBalance);
   GlobalVariableSet(g_gvPrefix + "OEAS_DIS",g_otherEAsDisabled  ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "PR_PH",   (double)g_prPhase);
   GlobalVariableSet(g_gvPrefix + "PR_COA",  g_prCloseOldActive ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "PR_COS",  (g_prCloseOldSide == POSITION_TYPE_BUY) ? 0.0 : 1.0);

   // Wipe stale BE/TSL globals for tickets no longer present
   int total = GlobalVariablesTotal();
   string bePrefix  = "RECOVERI_BE_";
   string tslPrefix = "RECOVERI_TSL_";
   for(int i = total-1; i >= 0; i--)
     {
      string n = GlobalVariableName(i);
      if(StringFind(n, bePrefix)  == 0) GlobalVariableDel(n);
      if(StringFind(n, tslPrefix) == 0) GlobalVariableDel(n);
     }
   // Re-write current
   for(int i=0; i<ArraySize(g_beTickets); i++)
      GlobalVariableSet(StringFormat("%s%I64u", bePrefix, g_beTickets[i]), 1.0);
   for(int i=0; i<ArraySize(g_tslTickets); i++)
      GlobalVariableSet(StringFormat("%s%I64u", tslPrefix, g_tslTickets[i]), g_tslPeaks[i]);
  }

ENUM_LOAD_STATUS LoadState()
  {
   if(g_gvPrefix == "") return LS_CLEAN;

   // --- Determine origin mode of stored state ---
   bool modeKnown   = GlobalVariableCheck(g_gvPrefix + "MODE");
   int  savedMode   = modeKnown ? (int)GlobalVariableGet(g_gvPrefix + "MODE") : -1;
   bool modeChanged = modeKnown && (savedMode != (int)InpMode);

   // Detect any pre-existing state at all (for clean-vs-legacy distinction)
   string allKeys[] = {"PAUSED","ESTOP","PEAK_C","PEAK_B","PEAK_S","GRID","BASE_BAL",
                       "LK_PH","LK_RS","LK_PB","LK_PS","LK_RC",
                       "RC_TRIG","OEAS_DIS","PR_PH","PR_COA","PR_COS"};
   bool anyState = false;
   for(int i = 0; i < ArraySize(allKeys); i++)
      if(GlobalVariableCheck(g_gvPrefix + allKeys[i])) { anyState = true; break; }

   // If MODE marker is missing but state exists, treat as legacy/unknown-mode -> mismatch.
   bool legacyState   = !modeKnown && anyState;
   bool ignoreModeKeys = modeChanged || legacyState;

   // --- Always-safe keys: paused/estop/peaks/baseline/grid (mode-agnostic) ---
   if(GlobalVariableCheck(g_gvPrefix + "PAUSED"))   g_paused          = (GlobalVariableGet(g_gvPrefix + "PAUSED") > 0.5);
   if(GlobalVariableCheck(g_gvPrefix + "ESTOP"))    g_emergencyStop   = (GlobalVariableGet(g_gvPrefix + "ESTOP")  > 0.5);
   if(GlobalVariableCheck(g_gvPrefix + "PEAK_C"))   g_peakProfit      = GlobalVariableGet(g_gvPrefix + "PEAK_C");
   if(GlobalVariableCheck(g_gvPrefix + "PEAK_B"))   g_peakBuyProfit   = GlobalVariableGet(g_gvPrefix + "PEAK_B");
   if(GlobalVariableCheck(g_gvPrefix + "PEAK_S"))   g_peakSellProfit  = GlobalVariableGet(g_gvPrefix + "PEAK_S");
   if(GlobalVariableCheck(g_gvPrefix + "GRID"))     g_gridPlaced      = (GlobalVariableGet(g_gvPrefix + "GRID")  > 0.5);
   if(GlobalVariableCheck(g_gvPrefix + "BASE_BAL")) g_baselineBalance = GlobalVariableGet(g_gvPrefix + "BASE_BAL");

   // --- Mode-specific keys: load only if mode matches; otherwise reset to defaults ---
   if(ignoreModeKeys)
     {
      // Wipe stale keys so they don't poison future loads.
      string staleKeys[] = {"LK_PH","LK_RS","LK_PB","LK_PS","LK_RC",
                            "RC_TRIG","OEAS_DIS","PR_PH","PR_COA","PR_COS"};
      for(int i = 0; i < ArraySize(staleKeys); i++)
        {
         string k = g_gvPrefix + staleKeys[i];
         if(GlobalVariableCheck(k)) GlobalVariableDel(k);
        }
      g_lockPhase         = PHASE_IDLE;
      g_remainingSide     = POSITION_TYPE_BUY;
      g_lockPeakBuy       = 0.0;
      g_lockPeakSell      = 0.0;
      g_relockCount       = 0;
      g_recoveryTriggered = false;
      g_otherEAsDisabled  = false;
      g_prPhase           = PR_IDLE;
      g_prCloseOldActive  = false;
      g_prCloseOldSide    = POSITION_TYPE_BUY;
     }
   else
     {
      if(GlobalVariableCheck(g_gvPrefix + "LK_PH"))   g_lockPhase         = (ENUM_LOCK_PHASE)(int)GlobalVariableGet(g_gvPrefix + "LK_PH");
      if(GlobalVariableCheck(g_gvPrefix + "LK_RS"))   g_remainingSide     = (GlobalVariableGet(g_gvPrefix + "LK_RS") > 0.5) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      if(GlobalVariableCheck(g_gvPrefix + "LK_PB"))   g_lockPeakBuy       = GlobalVariableGet(g_gvPrefix + "LK_PB");
      if(GlobalVariableCheck(g_gvPrefix + "LK_PS"))   g_lockPeakSell      = GlobalVariableGet(g_gvPrefix + "LK_PS");
      if(GlobalVariableCheck(g_gvPrefix + "LK_RC"))   g_relockCount       = (int)GlobalVariableGet(g_gvPrefix + "LK_RC");
      if(GlobalVariableCheck(g_gvPrefix + "RC_TRIG")) g_recoveryTriggered = (GlobalVariableGet(g_gvPrefix + "RC_TRIG") > 0.5);
      if(GlobalVariableCheck(g_gvPrefix + "OEAS_DIS"))g_otherEAsDisabled  = (GlobalVariableGet(g_gvPrefix + "OEAS_DIS") > 0.5);
      if(GlobalVariableCheck(g_gvPrefix + "PR_PH"))   g_prPhase           = (ENUM_PR_PHASE)(int)GlobalVariableGet(g_gvPrefix + "PR_PH");
      if(GlobalVariableCheck(g_gvPrefix + "PR_COA"))  g_prCloseOldActive  = (GlobalVariableGet(g_gvPrefix + "PR_COA") > 0.5);
      if(GlobalVariableCheck(g_gvPrefix + "PR_COS"))  g_prCloseOldSide    = (GlobalVariableGet(g_gvPrefix + "PR_COS") > 0.5) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
     }

   // Stamp current mode for the next load (always, including LS_CLEAN -> first run).
   GlobalVariableSet(g_gvPrefix + "MODE", (double)InpMode);

   // --- BE / TSL ticket markers (mode-agnostic, always loaded) ---
   ArrayResize(g_beTickets, 0);
   ArrayResize(g_tslTickets, 0);
   ArrayResize(g_tslPeaks, 0);
   int total = GlobalVariablesTotal();
   for(int i = 0; i < total; i++)
     {
      string n = GlobalVariableName(i);
      ulong  ticket = 0;
      if(StringFind(n, "RECOVERI_BE_") == 0)
        { ticket = (ulong)StringToInteger(StringSubstr(n, 12)); if(PositionSelectByTicket(ticket)) VirtualBeMark(ticket); }
      else if(StringFind(n, "RECOVERI_TSL_") == 0)
        { ticket = (ulong)StringToInteger(StringSubstr(n, 13)); if(PositionSelectByTicket(ticket)) TslSet(ticket, GlobalVariableGet(n)); }
     }

   PrintFormat("State loaded: paused=%d eStop=%d peaks(C/B/S)=%.2f/%.2f/%.2f BE=%d TSL=%d lockPhase=%d remSide=%d relocks=%d trig=%d prPhase=%d prCloseOld=%d/%s savedMode=%d curMode=%d",
               g_paused, g_emergencyStop, g_peakProfit, g_peakBuyProfit, g_peakSellProfit,
               ArraySize(g_beTickets), ArraySize(g_tslTickets),
               (int)g_lockPhase, (int)g_remainingSide, g_relockCount,
               (int)g_recoveryTriggered, (int)g_prPhase,
               (int)g_prCloseOldActive,
               (g_prCloseOldSide == POSITION_TYPE_BUY ? "BUY" : "SELL"),
               savedMode, (int)InpMode);

   //--- Recompute partial-recovery averager counts from open positions ---
   g_prAvgCountBuy = 0;
   g_prAvgCountSell = 0;
   int posTotal = PositionsTotal();
   for(int i = 0; i < posTotal; i++)
     {
      ulong tk = PositionGetTicket(i);
      if(!IsManaged(tk)) continue;
      string cmt = pos.Comment();
      if(StringFind(cmt, "PR-AVG-B") >= 0) g_prAvgCountBuy++;
      if(StringFind(cmt, "PR-AVG-S") >= 0) g_prAvgCountSell++;
     }
   if(g_prAvgCountBuy + g_prAvgCountSell > 0)
      PrintFormat("PR averagers reconstructed: BUY=%d SELL=%d", g_prAvgCountBuy, g_prAvgCountSell);

   // --- Decide return status ---
   if(!modeKnown && !anyState) return LS_CLEAN;
   if(ignoreModeKeys)          return LS_MODE_MISMATCH;
   return LS_LOADED;
  }

//+------------------------------------------------------------------+
//| Reset all runtime flags + erase corresponding GVs.               |
//| Triggered by the "Reset State" panel button or callable from     |
//| code. Keeps PAUSED, ESTOP, BE/TSL markers intact.                |
//+------------------------------------------------------------------+
void DoResetState()
  {
   // Runtime flags -> defaults
   g_lockPhase         = PHASE_IDLE;
   g_remainingSide     = POSITION_TYPE_BUY;
   g_lockPeakBuy       = 0.0;
   g_lockPeakSell      = 0.0;
   g_relockCount       = 0;
   g_prPhase           = PR_IDLE;
   g_prAvgCountBuy     = 0;
   g_prAvgCountSell    = 0;
   g_prLastBarTime     = 0;
   g_prLastBarTimeS    = 0;
   g_prLastTrend       = 0;
   g_prCloseOldActive  = false;
   g_prCloseOldSide    = POSITION_TYPE_BUY;
   g_recoveryTriggered = false;
   g_otherEAsDisabled  = false;
   g_peakProfit        = 0.0;
   g_peakBuyProfit     = 0.0;
   g_peakSellProfit    = 0.0;

   // GVs -> erase the same set
   if(g_gvPrefix != "")
     {
      string keys[] = {"LK_PH","LK_RS","LK_PB","LK_PS","LK_RC",
                       "RC_TRIG","OEAS_DIS","PR_PH",
                       "PR_COA","PR_COS",
                       "PEAK_C","PEAK_B","PEAK_S"};
      for(int i = 0; i < ArraySize(keys); i++)
        {
         string k = g_gvPrefix + keys[i];
         if(GlobalVariableCheck(k)) GlobalVariableDel(k);
        }
     }

   // Re-stamp current mode and persist clean state
   if(InpUsePersistence) SaveState();

   Print("RECOVERI: Reset State - runtime flags cleared (paused/estop/BE/TSL kept).");
   Notify("RECOVERI: state reset (runtime flags cleared)");
  }



//+------------------------------------------------------------------+
//| Unconditional grid of pending limit orders                       |
//+------------------------------------------------------------------+
int CountManagedPending(const ENUM_ORDER_TYPE filterType)
  {
   int count = 0;
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(!OrderSelect(tk)) continue;
      if((string)OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)   != InpMagic) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != filterType) continue;
      count++;
     }
   return count;
  }

double GridLot(const int level)
  {
   double lot = InpGridStartLot * MathPow(InpGridLotMultiplier, MathMax(0, level));
   return NormalizeLot(_Symbol, lot);
  }

void PlaceUnconditionalGrid()
  {
   sym.Name(_Symbol); sym.RefreshRates();
   double pt   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid  = sym.Bid();
   double ask  = sym.Ask();
   if(pt <= 0 || bid <= 0 || ask <= 0)
     { Print("Grid: bad quotes, skip"); g_gridPlaced = false; return; }

   long stopsPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double stopsDist = (double)stopsPts * pt;

   trade.SetExpertMagicNumber(InpMagic);
   int placed = 0;
   for(int i = 1; i <= InpGridLevels; i++)
     {
      double off = i * InpGridStepPoints * pt;
      if(off < stopsDist) off = stopsDist + pt;
      double lot = GridLot(i-1);
      string cmt = StringFormat("%s|GRID-%d", InpComment, i);
      if(InpGridSide == GRID_BOTH || InpGridSide == GRID_BUY)
         if(trade.BuyLimit(lot, NormalizeDouble(ask - off, _Digits), _Symbol, 0, 0, ORDER_TIME_GTC, 0, cmt+"-B"))
            placed++;
      if(InpGridSide == GRID_BOTH || InpGridSide == GRID_SELL)
         if(trade.SellLimit(lot, NormalizeDouble(bid + off, _Digits), _Symbol, 0, 0, ORDER_TIME_GTC, 0, cmt+"-S"))
            placed++;
     }
   PrintFormat("Grid placed: %d orders (levels=%d, step=%d pts, side=%d)",
               placed, InpGridLevels, InpGridStepPoints, (int)InpGridSide);
   // Bug #3 fix: only mark grid as placed if at least one order succeeded
   g_gridPlaced = (placed > 0);
  }



//+------------------------------------------------------------------+
//| Replenish triggered grid levels (re-place limits after fill)     |
//+------------------------------------------------------------------+
void ReplenishGrid()
  {
   if(!InpGridReplaceFilled) return;
   int wantBuy  = (InpGridSide == GRID_BOTH || InpGridSide == GRID_BUY)  ? InpGridLevels : 0;
   int wantSell = (InpGridSide == GRID_BOTH || InpGridSide == GRID_SELL) ? InpGridLevels : 0;
   int haveBuy  = CountManagedPending(ORDER_TYPE_BUY_LIMIT);
   int haveSell = CountManagedPending(ORDER_TYPE_SELL_LIMIT);
   if(haveBuy >= wantBuy && haveSell >= wantSell) return;

   sym.Name(_Symbol); sym.RefreshRates();
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = sym.Bid(), ask = sym.Ask();
   long   stopsPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double stopsDist = (double)stopsPts * pt;

   trade.SetExpertMagicNumber(InpMagic);
   int needB = wantBuy  - haveBuy;
   int needS = wantSell - haveSell;
   for(int i = 1; i <= MathMax(needB, needS); i++)
     {
      double off = i * InpGridStepPoints * pt;
      if(off < stopsDist) off = stopsDist + pt;
      double lot = GridLot(i-1);
      string cmt = StringFormat("%s|GRID-R%d", InpComment, i);
      if(i <= needB)
         trade.BuyLimit(lot,  NormalizeDouble(ask - off, _Digits), _Symbol, 0, 0, ORDER_TIME_GTC, 0, cmt+"-B");
      if(i <= needS)
         trade.SellLimit(lot, NormalizeDouble(bid + off, _Digits), _Symbol, 0, 0, ORDER_TIME_GTC, 0, cmt+"-S");
     }
  }
//+------------------------------------------------------------------+
