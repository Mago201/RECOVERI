//+------------------------------------------------------------------+
//|                                                     RECOVERI.mq5 |
//|                       Universal MT5 Account Recovery EA         |
//|                                                                  |
//|  Назначение:                                                     |
//|     Универсальный советник для "разруливания" счёта из просадки. |
//|     Берёт под управление существующие позиции (свои/ручные/все)  |
//|     и закрывает их корзиной по выбранной стратегии восстановления|
//|                                                                  |
//|  Стратегии (RecoveryMode):                                       |
//|     0 - TargetProfit : просто ждать, пока сумма по корзине       |
//|                        достигнет TargetProfit, затем закрыть всё |
//|     1 - Averaging    : усреднение в сторону убытка               |
//|                        (доливка одинаковыми лотами по сетке)     |
//|     2 - MartingaleGrid: мартингейл-сетка с множителем            |
//|     3 - HedgeLock    : локирование (хедж) встречной позицией     |
//|     4 - SmartClose   : закрывать прибыльные парами с убыточными  |
//|                        так, чтобы суммарно оставаться в плюсе    |
//+------------------------------------------------------------------+
#property copyright "RECOVERI"
#property link      ""
#property version   "1.00"
#property strict
#property description "Universal MT5 Recovery EA - вытягивает счёт из минуса корзинными методами"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- Перечисления настроек -----------------------------------------
enum ENUM_RECOVERY_MODE
  {
   MODE_TARGET_PROFIT = 0,    // 0: TargetProfit - закрытие корзины по цели
   MODE_AVERAGING     = 1,    // 1: Averaging - усреднение
   MODE_MARTINGALE    = 2,    // 2: MartingaleGrid - мартингейл-сетка
   MODE_HEDGE_LOCK    = 3,    // 3: HedgeLock - локирование
   MODE_SMART_CLOSE   = 4     // 4: SmartClose - умное парное закрытие
  };

enum ENUM_MANAGE_SCOPE
  {
   MANAGE_ALL    = 0,         // 0: Все позиции (любой magic)
   MANAGE_MANUAL = 1,         // 1: Только ручные (magic==0)
   MANAGE_OWN    = 2          // 2: Только свои (по InpMagic)
  };

enum ENUM_SYMBOL_SCOPE
  {
   SCOPE_CURRENT = 0,         // 0: Только текущий символ
   SCOPE_ALL     = 1          // 1: Все символы счёта
  };

enum ENUM_TARGET_TYPE
  {
   TARGET_MONEY   = 0,        // 0: В деньгах счёта
   TARGET_PERCENT = 1,        // 1: В % от баланса
   TARGET_PIPS    = 2         // 2: Эквивалент в пунктах (по средневзв. лоту)
  };

//--- Входные параметры =============================================
input group "=== Общие настройки ==="
input ENUM_RECOVERY_MODE InpMode          = MODE_TARGET_PROFIT; // Режим восстановления
input ENUM_MANAGE_SCOPE  InpManageScope   = MANAGE_ALL;         // Какие позиции управлять
input ENUM_SYMBOL_SCOPE  InpSymbolScope   = SCOPE_CURRENT;      // По каким символам
input long               InpMagic         = 20260520;           // Magic (для своих сделок)
input string             InpComment       = "RECOVERI";         // Комментарий к сделкам
input int                InpSlippage      = 30;                 // Проскальзывание (пунктов)
input double             InpMaxSpreadPts  = 0;                  // Макс. спред (0 = не ограничивать)

input group "=== Цель закрытия корзины ==="
input ENUM_TARGET_TYPE   InpTargetType    = TARGET_MONEY;       // Тип цели
input double             InpTargetProfit  = 10.0;               // Цель прибыли (валюта/%/пункты)
input bool               InpUseBasketTSL  = false;              // Использовать трейлинг корзины
input double             InpBasketTSLStart= 20.0;               // Старт трейлинга (валюта счёта)
input double             InpBasketTSLStep = 5.0;                // Шаг трейлинга (валюта счёта)

input group "=== Усреднение / Мартингейл / Сетка ==="
input double             InpStartLot      = 0.01;               // Стартовый лот доливки
input double             InpLotMultiplier = 1.5;                // Множитель лота (мартингейл)
input double             InpLotAdd        = 0.0;                // Прибавка к лоту (линейная)
input int                InpStepPoints    = 300;                // Шаг сетки (в пунктах)
input double             InpStepMultiplier= 1.2;                // Множитель шага сетки
input int                InpMaxTrades     = 10;                 // Макс. кол-во доливок
input double             InpMaxLot        = 1.0;                // Макс. размер одной позиции

input group "=== Локирование (HedgeLock) ==="
input double             InpLockTriggerLoss= 50.0;              // Убыток для локирования (валюта)
input double             InpLockLotFactor = 1.0;                // Доля лота лока от суммарного

input group "=== Защита счёта ==="
input bool               InpUseEquityStop = false;              // Аварийный стоп по equity
input double             InpEquityStopPct = 50.0;               // Стоп при equity ниже % от баланса
input bool               InpCloseOnly     = false;              // Только закрытие (без новых ордеров)

input group "=== Информационная панель ==="
input bool               InpShowPanel     = true;               // Показывать панель
input color              InpPanelColor    = clrWhite;           // Цвет текста панели
input int                InpPanelFontSize = 10;                 // Размер шрифта

//--- Глобальные объекты --------------------------------------------
CTrade         trade;
CPositionInfo  pos;
CSymbolInfo    sym;
CAccountInfo   acc;

//--- Кэш состояния -------------------------------------------------
struct BasketState
  {
   int      count;          // кол-во позиций
   double   buyVolume;      // суммарный объем BUY
   double   sellVolume;     // суммарный объем SELL
   double   buyPriceAvg;    // средневзвешенная цена BUY
   double   sellPriceAvg;   // средневзвешенная цена SELL
   double   profit;         // суммарный плавающий P/L
   double   maxLossLot;     // макс лот среди убыточных
   ulong    worstBuyTicket; // тикет худшего BUY
   ulong    worstSellTicket;// тикет худшего SELL
   datetime lastOpenTime;   // время последней позиции в корзине
   double   lastOpenPriceB; // цена последней BUY
   double   lastOpenPriceS; // цена последней SELL
   double   lastOpenLotB;   // лот последней BUY
   double   lastOpenLotS;   // лот последней SELL
   int      buyCount;
   int      sellCount;
  };

double  g_basketPeakProfit = 0.0;  // пик прибыли для трейлинга корзины
bool    g_emergencyStop    = false;
string  g_panelPrefix      = "RECOVERI_PANEL_";

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints((ulong)InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS);

   if(InpShowPanel)
      CreatePanel();

   PrintFormat("RECOVERI started. Mode=%d, Scope=%d, SymbolScope=%d, Magic=%I64d",
               (int)InpMode, (int)InpManageScope, (int)InpSymbolScope, InpMagic);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, g_panelPrefix);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Main tick                                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Аварийный стоп по equity
   if(CheckEmergencyStop())
     {
      CloseAllManaged();
      return;
     }

   // 2. Сбор состояния корзины
   BasketState bs;
   BuildBasket(bs);

   // 3. Трейлинг корзины
   if(InpUseBasketTSL && bs.count > 0)
     {
      if(bs.profit > g_basketPeakProfit)
         g_basketPeakProfit = bs.profit;

      if(g_basketPeakProfit >= InpBasketTSLStart &&
         bs.profit <= g_basketPeakProfit - InpBasketTSLStep)
        {
         PrintFormat("Basket TSL hit: peak=%.2f cur=%.2f -> close all", g_basketPeakProfit, bs.profit);
         CloseAllManaged();
         g_basketPeakProfit = 0.0;
         UpdatePanel(bs);
         return;
        }
     }
   if(bs.count == 0)
      g_basketPeakProfit = 0.0;

   // 4. Проверка цели закрытия
   if(bs.count > 0 && IsTargetReached(bs))
     {
      PrintFormat("Target reached: profit=%.2f -> close all", bs.profit);
      CloseAllManaged();
      g_basketPeakProfit = 0.0;
      UpdatePanel(bs);
      return;
     }

   // 5. Стратегии восстановления (только если разрешено открывать)
   if(!InpCloseOnly && bs.count > 0)
     {
      switch(InpMode)
        {
         case MODE_TARGET_PROFIT:                  break; // ждём цель
         case MODE_AVERAGING:    DoAveraging(bs);  break;
         case MODE_MARTINGALE:   DoMartingale(bs); break;
         case MODE_HEDGE_LOCK:   DoHedgeLock(bs);  break;
         case MODE_SMART_CLOSE:  DoSmartClose(bs); break;
        }
     }

   UpdatePanel(bs);
  }

//+------------------------------------------------------------------+
//| Подходит ли позиция под управление                              |
//+------------------------------------------------------------------+
bool IsManaged(const ulong ticket)
  {
   if(!pos.SelectByTicket(ticket))
      return false;

   // Фильтр по символу
   if(InpSymbolScope == SCOPE_CURRENT && pos.Symbol() != _Symbol)
      return false;

   // Фильтр по magic
   long m = pos.Magic();
   switch(InpManageScope)
     {
      case MANAGE_MANUAL: if(m != 0)        return false; break;
      case MANAGE_OWN:    if(m != InpMagic) return false; break;
      case MANAGE_ALL:    /* любые */                     break;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Сбор состояния корзины                                           |
//+------------------------------------------------------------------+
void BuildBasket(BasketState &bs)
  {
   ZeroMemory(bs);
   double buySumPV  = 0.0; // sum(price*lot) для BUY
   double sellSumPV = 0.0;
   double worstBuyP = 0.0;
   double worstSellP= 0.0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!IsManaged(ticket))
         continue;

      double vol   = pos.Volume();
      double price = pos.PriceOpen();
      double pft   = pos.Profit() + pos.Swap() + pos.Commission();
      datetime t   = (datetime)pos.Time();

      bs.count++;
      bs.profit += pft;
      if(t > bs.lastOpenTime) bs.lastOpenTime = t;

      if(pos.PositionType() == POSITION_TYPE_BUY)
        {
         bs.buyCount++;
         bs.buyVolume += vol;
         buySumPV     += price * vol;
         if(price > bs.lastOpenPriceB || bs.lastOpenLotB == 0.0)
           {
            bs.lastOpenPriceB = price;
            bs.lastOpenLotB   = vol;
           }
         if(pft < worstBuyP)
           {
            worstBuyP = pft;
            bs.worstBuyTicket = ticket;
           }
        }
      else if(pos.PositionType() == POSITION_TYPE_SELL)
        {
         bs.sellCount++;
         bs.sellVolume += vol;
         sellSumPV     += price * vol;
         if(price < bs.lastOpenPriceS || bs.lastOpenLotS == 0.0)
           {
            bs.lastOpenPriceS = price;
            bs.lastOpenLotS   = vol;
           }
         if(pft < worstSellP)
           {
            worstSellP = pft;
            bs.worstSellTicket = ticket;
           }
        }
     }

   if(bs.buyVolume  > 0) bs.buyPriceAvg  = buySumPV  / bs.buyVolume;
   if(bs.sellVolume > 0) bs.sellPriceAvg = sellSumPV / bs.sellVolume;
  }

//+------------------------------------------------------------------+
//| Цель закрытия корзины достигнута?                                |
//+------------------------------------------------------------------+
bool IsTargetReached(const BasketState &bs)
  {
   double target = InpTargetProfit;

   if(InpTargetType == TARGET_PERCENT)
     {
      target = AccountInfoDouble(ACCOUNT_BALANCE) * InpTargetProfit / 100.0;
     }
   else if(InpTargetType == TARGET_PIPS)
     {
      // эквивалент пунктов через стоимость пункта на текущем символе
      sym.Name(_Symbol);
      sym.RefreshRates();
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double valPerPoint = (tickSz > 0) ? tickVal * (point / tickSz) : 0.0;
      double netLot = MathMax(bs.buyVolume + bs.sellVolume, 0.01);
      target = InpTargetProfit * valPerPoint * netLot;
     }
   return (bs.profit >= target);
  }

//+------------------------------------------------------------------+
//| Закрыть все управляемые позиции                                  |
//+------------------------------------------------------------------+
void CloseAllManaged()
  {
   // Закрываем по тикетам — список собираем заранее, т.к. PositionsTotal меняется
   ulong tickets[];
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(IsManaged(t))
        {
         int n = ArraySize(tickets);
         ArrayResize(tickets, n + 1);
         tickets[n] = t;
        }
     }
   for(int i = 0; i < ArraySize(tickets); i++)
     {
      if(!trade.PositionClose(tickets[i], (ulong)InpSlippage))
         PrintFormat("PositionClose failed for #%I64u err=%d", tickets[i], trade.ResultRetcode());
     }
  }

//+------------------------------------------------------------------+
//| Эмоциональный стоп по equity                                     |
//+------------------------------------------------------------------+
bool CheckEmergencyStop()
  {
   if(!InpUseEquityStop) return false;
   if(g_emergencyStop)   return true;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0) return false;

   double pct = eq / bal * 100.0;
   if(pct <= InpEquityStopPct)
     {
      PrintFormat("EMERGENCY STOP: equity=%.2f balance=%.2f (%.1f%% <= %.1f%%)",
                  eq, bal, pct, InpEquityStopPct);
      g_emergencyStop = true;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Спред в порядке?                                                 |
//+------------------------------------------------------------------+
bool SpreadOK(const string symbol)
  {
   if(InpMaxSpreadPts <= 0) return true;
   long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   return (spread <= InpMaxSpreadPts);
  }

//+------------------------------------------------------------------+
//| Нормализовать лот к ограничениям символа                         |
//+------------------------------------------------------------------+
double NormalizeLot(const string symbol, double lot)
  {
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / step + 0.0000001) * step;
   if(InpMaxLot > 0) lot = MathMin(lot, InpMaxLot);
   return NormalizeDouble(lot, 2);
  }

//+------------------------------------------------------------------+
//| Текущий шаг сетки в пунктах с учётом множителя                   |
//+------------------------------------------------------------------+
int CurrentStepPoints(const int tradesInDirection)
  {
   double s = (double)InpStepPoints * MathPow(InpStepMultiplier, MathMax(0, tradesInDirection - 1));
   return (int)MathMax(1.0, s);
  }

//+------------------------------------------------------------------+
//| Стратегия 1: Усреднение (одинаковый/линейный лот)               |
//+------------------------------------------------------------------+
void DoAveraging(const BasketState &bs)
  {
   if(InpSymbolScope != SCOPE_CURRENT) return; // усреднять имеет смысл по одному символу
   if(!SpreadOK(_Symbol)) return;
   if(bs.count >= InpMaxTrades) return;

   sym.Name(_Symbol); sym.RefreshRates();
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = sym.Bid(), ask = sym.Ask();

   // BUY-сторона: усредняем вниз
   if(bs.buyCount > 0)
     {
      int needStep = CurrentStepPoints(bs.buyCount);
      double trigger = bs.lastOpenPriceB - needStep * point;
      if(ask <= trigger)
        {
         double lot = (InpLotAdd > 0)
                      ? bs.lastOpenLotB + InpLotAdd
                      : MathMax(bs.lastOpenLotB, InpStartLot);
         lot = NormalizeLot(_Symbol, lot);
         OpenPosition(_Symbol, ORDER_TYPE_BUY, lot, "AVG-BUY");
        }
     }

   // SELL-сторона: усредняем вверх
   if(bs.sellCount > 0)
     {
      int needStep = CurrentStepPoints(bs.sellCount);
      double trigger = bs.lastOpenPriceS + needStep * point;
      if(bid >= trigger)
        {
         double lot = (InpLotAdd > 0)
                      ? bs.lastOpenLotS + InpLotAdd
                      : MathMax(bs.lastOpenLotS, InpStartLot);
         lot = NormalizeLot(_Symbol, lot);
         OpenPosition(_Symbol, ORDER_TYPE_SELL, lot, "AVG-SELL");
        }
     }
  }

//+------------------------------------------------------------------+
//| Стратегия 2: Мартингейл-сетка                                    |
//+------------------------------------------------------------------+
void DoMartingale(const BasketState &bs)
  {
   if(InpSymbolScope != SCOPE_CURRENT) return;
   if(!SpreadOK(_Symbol)) return;
   if(bs.count >= InpMaxTrades) return;

   sym.Name(_Symbol); sym.RefreshRates();
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = sym.Bid(), ask = sym.Ask();

   if(bs.buyCount > 0)
     {
      int needStep = CurrentStepPoints(bs.buyCount);
      double trigger = bs.lastOpenPriceB - needStep * point;
      if(ask <= trigger)
        {
         double lot = bs.lastOpenLotB * InpLotMultiplier;
         if(lot <= 0) lot = InpStartLot;
         lot = NormalizeLot(_Symbol, lot);
         OpenPosition(_Symbol, ORDER_TYPE_BUY, lot, "MG-BUY");
        }
     }

   if(bs.sellCount > 0)
     {
      int needStep = CurrentStepPoints(bs.sellCount);
      double trigger = bs.lastOpenPriceS + needStep * point;
      if(bid >= trigger)
        {
         double lot = bs.lastOpenLotS * InpLotMultiplier;
         if(lot <= 0) lot = InpStartLot;
         lot = NormalizeLot(_Symbol, lot);
         OpenPosition(_Symbol, ORDER_TYPE_SELL, lot, "MG-SELL");
        }
     }
  }

//+------------------------------------------------------------------+
//| Стратегия 3: Локирование                                         |
//+------------------------------------------------------------------+
void DoHedgeLock(const BasketState &bs)
  {
   if(InpSymbolScope != SCOPE_CURRENT) return;
   if(!SpreadOK(_Symbol)) return;
   if(bs.count >= InpMaxTrades) return;

   // Локируем только если есть значительный убыток
   if(bs.profit > -InpLockTriggerLoss) return;

   double netVol = bs.buyVolume - bs.sellVolume; // если >0 -> доминирует BUY
   if(MathAbs(netVol) < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;

   double lockLot = NormalizeLot(_Symbol, MathAbs(netVol) * InpLockLotFactor);
   if(lockLot <= 0) return;

   if(netVol > 0)
      OpenPosition(_Symbol, ORDER_TYPE_SELL, lockLot, "LOCK");
   else
      OpenPosition(_Symbol, ORDER_TYPE_BUY,  lockLot, "LOCK");
  }

//+------------------------------------------------------------------+
//| Стратегия 4: Умное закрытие парами                              |
//|   Идея: ищем пару (прибыльная + убыточная), сумма >= 0,         |
//|   закрываем обе. Повторяем, пока есть такие пары.               |
//+------------------------------------------------------------------+
void DoSmartClose(const BasketState &bs)
  {
   if(bs.count < 2) return;

   ulong  tickets[];
   double profits[];
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(!IsManaged(t)) continue;
      double pft = pos.Profit() + pos.Swap() + pos.Commission();
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      ArrayResize(profits, n + 1);
      tickets[n] = t;
      profits[n] = pft;
     }
   int n = ArraySize(tickets);
   if(n < 2) return;

   // Находим самую прибыльную и самую убыточную
   int bestIdx = 0, worstIdx = 0;
   for(int i = 1; i < n; i++)
     {
      if(profits[i] > profits[bestIdx])  bestIdx  = i;
      if(profits[i] < profits[worstIdx]) worstIdx = i;
     }
   if(bestIdx == worstIdx) return;
   if(profits[bestIdx] <= 0) return; // нечем компенсировать
   if(profits[bestIdx] + profits[worstIdx] < InpTargetProfit) return;

   if(!trade.PositionClose(tickets[bestIdx]))
      PrintFormat("SmartClose: best #%I64u err=%d", tickets[bestIdx], trade.ResultRetcode());
   if(!trade.PositionClose(tickets[worstIdx]))
      PrintFormat("SmartClose: worst #%I64u err=%d", tickets[worstIdx], trade.ResultRetcode());
  }

//+------------------------------------------------------------------+
//| Открыть новую позицию (для стратегий)                            |
//+------------------------------------------------------------------+
bool OpenPosition(const string symbol, const ENUM_ORDER_TYPE type, double lot, const string tag)
  {
   if(lot <= 0) return false;
   if(!sym.Name(symbol)) return false;
   sym.RefreshRates();

   double price = (type == ORDER_TYPE_BUY) ? sym.Ask() : sym.Bid();
   string cmt   = StringFormat("%s|%s", InpComment, tag);

   trade.SetExpertMagicNumber(InpMagic);
   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy(lot, symbol, price, 0.0, 0.0, cmt)
             : trade.Sell(lot, symbol, price, 0.0, 0.0, cmt);

   if(!ok)
      PrintFormat("OpenPosition %s %s %.2f failed err=%d ret=%d",
                  symbol, EnumToString(type), lot, GetLastError(), trade.ResultRetcode());
   return ok;
  }

//+------------------------------------------------------------------+
//| Информационная панель                                            |
//+------------------------------------------------------------------+
void CreatePanel()
  {
   string lines[] = {"title", "mode", "scope", "count", "buy", "sell", "profit", "peak", "target", "stop"};
   int y = 20;
   for(int i = 0; i < ArraySize(lines); i++)
     {
      string name = g_panelPrefix + lines[i];
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(0, name, OBJPROP_COLOR, InpPanelColor);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpPanelFontSize);
         ObjectSetString (0, name, OBJPROP_FONT, "Consolas");
         ObjectSetString (0, name, OBJPROP_TEXT, "");
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        }
      y += InpPanelFontSize + 6;
     }
  }

void SetPanelLine(const string key, const string text, color clr = clrNONE)
  {
   string name = g_panelPrefix + key;
   if(ObjectFind(0, name) < 0) return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   if(clr != clrNONE)
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   else
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpPanelColor);
  }

void UpdatePanel(const BasketState &bs)
  {
   if(!InpShowPanel) return;

   string modeName = "";
   switch(InpMode)
     {
      case MODE_TARGET_PROFIT: modeName = "TargetProfit"; break;
      case MODE_AVERAGING:     modeName = "Averaging";    break;
      case MODE_MARTINGALE:    modeName = "Martingale";   break;
      case MODE_HEDGE_LOCK:    modeName = "HedgeLock";    break;
      case MODE_SMART_CLOSE:   modeName = "SmartClose";   break;
     }
   string scopeName = (InpManageScope==MANAGE_ALL ? "ALL"
                       : InpManageScope==MANAGE_MANUAL ? "MANUAL" : "OWN");
   string symScope  = (InpSymbolScope==SCOPE_CURRENT ? _Symbol : "ALL_SYMBOLS");

   double target = InpTargetProfit;
   if(InpTargetType == TARGET_PERCENT)
      target = AccountInfoDouble(ACCOUNT_BALANCE) * InpTargetProfit / 100.0;

   color profitClr = (bs.profit >= 0) ? clrLime : clrTomato;

   SetPanelLine("title",  "=== RECOVERI ===", clrGold);
   SetPanelLine("mode",   StringFormat("Mode  : %s%s", modeName, InpCloseOnly?" [CLOSE-ONLY]":""));
   SetPanelLine("scope",  StringFormat("Scope : %s @ %s", scopeName, symScope));
   SetPanelLine("count",  StringFormat("Trades: %d (max %d)", bs.count, InpMaxTrades));
   SetPanelLine("buy",    StringFormat("BUY   : %d / %.2f lot @ %.5f", bs.buyCount, bs.buyVolume, bs.buyPriceAvg));
   SetPanelLine("sell",   StringFormat("SELL  : %d / %.2f lot @ %.5f", bs.sellCount, bs.sellVolume, bs.sellPriceAvg));
   SetPanelLine("profit", StringFormat("P/L   : %.2f %s", bs.profit, AccountInfoString(ACCOUNT_CURRENCY)), profitClr);
   SetPanelLine("peak",   StringFormat("Peak  : %.2f", g_basketPeakProfit));
   SetPanelLine("target", StringFormat("Target: %.2f", target));
   SetPanelLine("stop",   g_emergencyStop ? "STATUS: EMERGENCY STOP" : "STATUS: OK",
                g_emergencyStop ? clrRed : clrLime);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
