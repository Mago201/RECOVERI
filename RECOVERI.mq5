//+------------------------------------------------------------------+
//|                                                     RECOVERI.mq5 |
//|                       Universal MT5 Account Recovery EA          |
//|  v1.20                                                           |
//|  Добавлено в v1.20:                                              |
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
#property version   "1.20"
#property strict
#property description "Universal MT5 Recovery EA - basket recovery from drawdown"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//=== Enums ==========================================================
enum ENUM_RECOVERY_MODE
  {
   MODE_TARGET_PROFIT = 0,    // 0: TargetProfit
   MODE_AVERAGING     = 1,    // 1: Averaging
   MODE_MARTINGALE    = 2,    // 2: Martingale grid
   MODE_HEDGE_LOCK    = 3,    // 3: HedgeLock
   MODE_SMART_CLOSE   = 4     // 4: SmartClose
  };

enum ENUM_MANAGE_SCOPE
  {
   MANAGE_ALL    = 0,         // 0: All positions
   MANAGE_MANUAL = 1,         // 1: Manual only (magic==0)
   MANAGE_OWN    = 2          // 2: Own only (by InpMagic)
  };

enum ENUM_SYMBOL_SCOPE
  {
   SCOPE_CURRENT = 0,         // 0: Current symbol
   SCOPE_ALL     = 1          // 1: All symbols
  };

enum ENUM_TARGET_TYPE
  {
   TARGET_MONEY   = 0,        // 0: Money
   TARGET_PERCENT = 1,        // 1: Percent of balance
   TARGET_PIPS    = 2         // 2: Pips equivalent
  };


enum ENUM_BASKET_MODE
  {
   BASKET_COMBINED = 0,       // 0: Combined BUY+SELL basket
   BASKET_PER_SIDE = 1        // 1: Separate BUY and SELL baskets
  };

enum ENUM_GRID_SIDE
  {
   GRID_BOTH = 0,             // 0: Both sides (BUY_LIMIT below + SELL_LIMIT above)
   GRID_BUY  = 1,             // 1: BUY_LIMIT only (below market)
   GRID_SELL = 2              // 2: SELL_LIMIT only (above market)
  };

//=== Inputs =========================================================
input group "=== Общие ==="
input ENUM_RECOVERY_MODE InpMode          = MODE_TARGET_PROFIT;
input ENUM_MANAGE_SCOPE  InpManageScope   = MANAGE_ALL;
input ENUM_SYMBOL_SCOPE  InpSymbolScope   = SCOPE_CURRENT;
input long               InpMagic         = 20260520;
input string             InpComment       = "RECOVERI";
input int                InpSlippage      = 30;
input double             InpMaxSpreadPts  = 0;

input group "=== Корзина и цель ==="
input ENUM_BASKET_MODE   InpBasketMode    = BASKET_COMBINED;
input ENUM_TARGET_TYPE   InpTargetType    = TARGET_MONEY;
input double             InpTargetProfit  = 10.0;
input bool               InpUseBasketTSL  = false;
input double             InpBasketTSLStart= 20.0;
input double             InpBasketTSLStep = 5.0;

input group "=== Виртуальные TP/SL ==="
input bool               InpUseVirtualTP  = false;
input int                InpVirtualTPPts  = 200;
input bool               InpUseVirtualSL  = false;
input int                InpVirtualSLPts  = 1000;
input bool               InpUseVirtualBE  = false;
input int                InpVirtualBEPts  = 100;

input group "=== Виртуальный трейлинг-стоп (по каждой позиции) ==="
input bool               InpUseVirtualTSL  = false;
input int                InpVirtualTSLStartPts = 200;  // профит для активации трейлинга (пункты)
input int                InpVirtualTSLDistPts  = 100;  // расстояние трейлинга от пика (пункты)

input group "=== Стратегии (Averaging/Martingale) ==="
input double             InpStartLot      = 0.01;
input double             InpLotMultiplier = 1.5;
input double             InpLotAdd        = 0.0;
input int                InpStepPoints    = 300;
input double             InpStepMultiplier= 1.2;
input int                InpMaxTrades     = 10;
input double             InpMaxLot        = 1.0;

input group "=== HedgeLock ==="
input double             InpLockTriggerLoss= 50.0;
input double             InpLockLotFactor = 1.0;


input group "=== Защита счёта ==="
input bool               InpUseEquityStop = false;
input double             InpEquityStopPct = 50.0;
input bool               InpCloseOnly     = false;

input group "=== Фильтр времени ==="
input bool               InpUseTimeFilter = false;
input int                InpStartHour     = 0;
input int                InpEndHour       = 24;
input bool               InpTradeMon      = true;
input bool               InpTradeTue      = true;
input bool               InpTradeWed      = true;
input bool               InpTradeThu      = true;
input bool               InpTradeFri      = true;
input bool               InpTradeSat      = false;
input bool               InpTradeSun      = false;

input group "=== Новостной фильтр (MT5 Calendar) ==="
input bool               InpUseNewsFilter = false;
input bool               InpNewsHigh      = true;
input bool               InpNewsMedium    = false;
input bool               InpNewsLow       = false;
input int                InpNewsMinsBefore= 30;
input int                InpNewsMinsAfter = 30;

input group "=== Уведомления ==="
input bool               InpUseAlert      = true;       // всплывающий Alert()
input bool               InpUseSound      = false;      // звук
input string             InpSoundFile     = "alert.wav";
input bool               InpUsePush       = false;      // Push на телефон (Settings -> Notifications)

input group "=== Сохранение состояния ==="
input bool               InpUsePersistence= true;       // сохранять paused/BE/TSL/peaks через GlobalVariables

input group "=== Безусловная сетка (limit-ордера) ==="
input bool               InpUseUncondGrid     = false;
input ENUM_GRID_SIDE     InpGridSide          = GRID_BOTH;
input int                InpGridLevels        = 5;
input int                InpGridStepPoints    = 200;
input double             InpGridStartLot      = 0.01;
input double             InpGridLotMultiplier = 1.0;     // 1.0 = одинаковый лот, >1 = мартингейл-сетка
input bool               InpGridReplaceFilled = false;   // переоткрывать сработавшие уровни
input bool               InpGridAutoRestart   = true;    // после Close All автоматически выставлять сетку заново

input group "=== Панель ==="
input bool               InpShowPanel     = true;
input color              InpPanelColor    = clrWhite;
input int                InpPanelFontSize = 10;

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

// GlobalVariables key prefix (instance-scoped: symbol + magic)
string  g_gvPrefix       = "";

#define BTN_CLOSE_ALL  "RECOVERI_BTN_CLOSE_ALL"
#define BTN_CLOSE_BUY  "RECOVERI_BTN_CLOSE_BUY"
#define BTN_CLOSE_SELL "RECOVERI_BTN_CLOSE_SELL"
#define BTN_PAUSE      "RECOVERI_BTN_PAUSE"
#define BTN_LOCK       "RECOVERI_BTN_LOCK"
#define BTN_RESET      "RECOVERI_BTN_RESET"

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints((ulong)InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS);
   g_gvPrefix = StringFormat("RECOVERI_%s_%I64d_", _Symbol, InpMagic);
   if(InpUsePersistence) LoadState();
   if(InpShowPanel) CreatePanel();
   if(InpUseUncondGrid && !g_gridPlaced) { PlaceUnconditionalGrid(); g_gridPlaced = true; }
   PrintFormat("RECOVERI v1.20 Mode=%d Manage=%d SymScope=%d Basket=%d Magic=%I64d",
               (int)InpMode,(int)InpManageScope,(int)InpSymbolScope,(int)InpBasketMode,InpMagic);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpUsePersistence) SaveState();
   ObjectsDeleteAll(0, g_panelPrefix);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
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

   // Auto-restart unconditional grid after Close All / emergency stop
   if(InpUseUncondGrid && InpGridAutoRestart && !g_gridPlaced && !g_emergencyStop && !g_paused
      && IsTradingAllowed())
     {
      PlaceUnconditionalGrid();
      g_gridPlaced = true;
     }


   BasketState bs;
   BuildBasket(bs);
   ApplyBasketTrailing(bs);

   if(bs.count > 0 && CheckBasketTargets(bs))
      BuildBasket(bs);

   if(!InpCloseOnly && bs.count > 0 && IsTradingAllowed())
     {
      switch(InpMode)
        {
         case MODE_AVERAGING:    DoAveraging(bs);  break;
         case MODE_MARTINGALE:   DoMartingale(bs); break;
         case MODE_HEDGE_LOCK:   DoHedgeLock(bs);  break;
         case MODE_SMART_CLOSE:  DoSmartClose(bs); break;
         case MODE_TARGET_PROFIT: break;
        }
     }
   UpdatePanel(bs);
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == BTN_CLOSE_ALL)       { Print("BTN: Close All");    CloseAllManaged(); }
   else if(sparam == BTN_CLOSE_BUY)  { Print("BTN: Close BUY");    CloseSide(POSITION_TYPE_BUY); }
   else if(sparam == BTN_CLOSE_SELL) { Print("BTN: Close SELL");   CloseSide(POSITION_TYPE_SELL); }
   else if(sparam == BTN_PAUSE)      { g_paused = !g_paused; PrintFormat("BTN: Pause=%s", g_paused?"ON":"OFF"); if(InpUsePersistence) SaveState(); }
   else if(sparam == BTN_LOCK)       { Print("BTN: Lock Now");     ForceLockNow(); }
   else if(sparam == BTN_RESET)      { Print("BTN: Reset Stop");   g_emergencyStop = false; if(InpUsePersistence) SaveState(); }

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   ChartRedraw(0);
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

   // Wipe pending grid orders too, so "Close All" really resets state
   DeleteAllManagedPending();
   g_gridPlaced = false;
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

   // Drop matching-side pending limits as well
   ENUM_ORDER_TYPE pendType = (side == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   DeleteManagedPendingSide(pendType);
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
      if(!CalendarValueHistory(values, from, to, NULL, list[i])) continue;
      int n = ArraySize(values);
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
                     "peak","target","filter","stop"};
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
      case MODE_TARGET_PROFIT: modeName="TargetProfit"; break;
      case MODE_AVERAGING:     modeName="Averaging";    break;
      case MODE_MARTINGALE:    modeName="Martingale";   break;
      case MODE_HEDGE_LOCK:    modeName="HedgeLock";    break;
      case MODE_SMART_CLOSE:   modeName="SmartClose";   break;
     }
   string scopeName = (InpManageScope==MANAGE_ALL ? "ALL"
                       : InpManageScope==MANAGE_MANUAL ? "MANUAL" : "OWN");
   string symScope  = (InpSymbolScope==SCOPE_CURRENT ? _Symbol : "ALL_SYMBOLS");
   string basketName= (InpBasketMode==BASKET_COMBINED ? "COMBINED" : "PER_SIDE");

   double tgtComb = ResolveTargetMoney(bs.buyVolume + bs.sellVolume);
   double tgtBuy  = ResolveTargetMoney(bs.buyVolume);
   double tgtSell = ResolveTargetMoney(bs.sellVolume);
   color profitClr = (bs.profit >= 0) ? clrLime : clrTomato;

   SetLabel("title",  "=== RECOVERI v1.20 ===", clrGold);
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
   GlobalVariableSet(g_gvPrefix + "PAUSED",  g_paused        ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "ESTOP",   g_emergencyStop ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "PEAK_C",  g_peakProfit);
   GlobalVariableSet(g_gvPrefix + "PEAK_B",  g_peakBuyProfit);
   GlobalVariableSet(g_gvPrefix + "PEAK_S",  g_peakSellProfit);
   GlobalVariableSet(g_gvPrefix + "GRID",    g_gridPlaced    ? 1.0 : 0.0);

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

void LoadState()
  {
   if(g_gvPrefix == "") return;
   if(GlobalVariableCheck(g_gvPrefix + "PAUSED")) g_paused        = (GlobalVariableGet(g_gvPrefix + "PAUSED") > 0.5);
   if(GlobalVariableCheck(g_gvPrefix + "ESTOP"))  g_emergencyStop = (GlobalVariableGet(g_gvPrefix + "ESTOP")  > 0.5);
   if(GlobalVariableCheck(g_gvPrefix + "PEAK_C")) g_peakProfit     = GlobalVariableGet(g_gvPrefix + "PEAK_C");
   if(GlobalVariableCheck(g_gvPrefix + "PEAK_B")) g_peakBuyProfit  = GlobalVariableGet(g_gvPrefix + "PEAK_B");
   if(GlobalVariableCheck(g_gvPrefix + "PEAK_S")) g_peakSellProfit = GlobalVariableGet(g_gvPrefix + "PEAK_S");
   if(GlobalVariableCheck(g_gvPrefix + "GRID"))   g_gridPlaced     = (GlobalVariableGet(g_gvPrefix + "GRID")  > 0.5);

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
   PrintFormat("State loaded: paused=%d eStop=%d peaks(C/B/S)=%.2f/%.2f/%.2f BE=%d TSL=%d",
               g_paused, g_emergencyStop, g_peakProfit, g_peakBuyProfit, g_peakSellProfit,
               ArraySize(g_beTickets), ArraySize(g_tslTickets));
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
     { Print("Grid: bad quotes, skip"); return; }

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

   // Re-anchor: drop remaining pending and re-place full grid from current price.
   // Avoids price-collision with old levels and keeps grid spacing consistent.
   DeleteAllManagedPending();
   PlaceUnconditionalGrid();
  }

//+------------------------------------------------------------------+
//| Pending order helpers                                            |
//+------------------------------------------------------------------+
bool IsManagedPending(const ulong ticket)
  {
   if(!OrderSelect(ticket)) return false;
   if(InpSymbolScope == SCOPE_CURRENT && OrderGetString(ORDER_SYMBOL) != _Symbol) return false;
   long m = OrderGetInteger(ORDER_MAGIC);
   if(InpManageScope == MANAGE_MANUAL && m != 0)        return false;
   if(InpManageScope == MANAGE_OWN    && m != InpMagic) return false;
   return true;
  }

void DeleteAllManagedPending()
  {
   ulong tickets[];
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(!IsManagedPending(tk)) continue;
      int n = ArraySize(tickets); ArrayResize(tickets, n+1); tickets[n] = tk;
     }
   for(int i=0; i<ArraySize(tickets); i++)
      if(!trade.OrderDelete(tickets[i]))
         PrintFormat("OrderDelete #%I64u err=%d", tickets[i], trade.ResultRetcode());
  }

void DeleteManagedPendingSide(const ENUM_ORDER_TYPE pendType)
  {
   ulong tickets[];
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(!IsManagedPending(tk)) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != pendType) continue;
      int n = ArraySize(tickets); ArrayResize(tickets, n+1); tickets[n] = tk;
     }
   for(int i=0; i<ArraySize(tickets); i++)
      if(!trade.OrderDelete(tickets[i]))
         PrintFormat("OrderDelete #%I64u err=%d", tickets[i], trade.ResultRetcode());
  }
//+------------------------------------------------------------------+
