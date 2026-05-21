//+------------------------------------------------------------------+
//|                                                     RECOVERI.mq5 |
//|              Hedge-Recovery EA with Fragmentation v2.00          |
//|                                                                  |
//|  Strategy:                                                       |
//|   1. Hedge a losing position (CORE) with opposite volume         |
//|   2. Open recovery orders (GRID or ZONE) to claw back the loss   |
//|   3. When recovery basket profit >= cycle target:                |
//|       - close all recovery positions                             |
//|       - partial-close a fragment of HEDGE                        |
//|       - partial-close a fragment of CORE                         |
//|       - bank the cycle profit, increment cycle, repeat           |
//|   4. When CORE is fully closed -> close residual HEDGE -> IDLE   |
//|                                                                  |
//|  Optional Positive Grid: adds recovery orders even on favorable  |
//|  price moves, accelerating recovery.                             |
//|                                                                  |
//|  Requirements: MT5 HEDGING-mode account.                         |
//+------------------------------------------------------------------+
#property copyright "RECOVERI"
#property version   "2.00"
#property strict
#property description "Hedge-and-Recover EA with Fragmentation. Requires MT5 hedging-mode account."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//=== Enums ============================================================
enum ENUM_RECOVERY_MODE
  {
   REC_MODE_GRID = 0,    // 0: GRID  (limits, sideways markets)
   REC_MODE_ZONE = 1     // 1: ZONE  (stops, trending markets)
  };

enum ENUM_TRIGGER_MODE
  {
   TRIG_MANUAL = 0,      // 0: Manual via Activate button
   TRIG_AUTO   = 1       // 1: Auto when loss > InpTriggerLossMoney
  };

enum ENUM_BOT_STATE
  {
   ST_IDLE       = 0,
   ST_HEDGING    = 1,
   ST_RECOVERING = 2,
   ST_PAUSED     = 3,
   ST_EMERGENCY  = 4
  };


//=== Inputs ===========================================================
input group "=== General ==="
input long              InpMagic            = 20260520;
input string            InpComment          = "RECOVERI";
input int               InpSlippage         = 30;
input double            InpMaxSpreadPts     = 0;          // 0 = ignore

input group "=== Activation ==="
input ENUM_TRIGGER_MODE InpTriggerMode      = TRIG_MANUAL;
input double            InpTriggerLossMoney = 5.0;        // for AUTO mode

input group "=== Hedge ==="
input double            InpHedgeRatio       = 1.0;        // hedge volume = core * ratio

input group "=== Recovery ==="
input ENUM_RECOVERY_MODE InpRecoveryMode    = REC_MODE_GRID;
input int               InpRecoveryLevels   = 5;
input int               InpRecoveryStepPts  = 200;
input double            InpRecoveryStartLot = 0.01;
input double            InpRecoveryLotMult  = 1.0;        // 1.0 = uniform, >1 = martingale

input group "=== Positive Grid ==="
input bool              InpUsePositiveGrid     = false;
input int               InpPosGridStepPts      = 100;     // pts of favorable move between adds
input int               InpPosGridMinDistTPPts = 100;     // soft TP-distance gate (% based here)

input group "=== Fragment Closing ==="
input double            InpFragmentLot      = 0.01;       // chunk to peel off core/hedge per cycle
input double            InpCycleProfit      = 1.0;        // net profit per cycle (account currency)

input group "=== Account Protection ==="
input bool              InpUseEquityStop    = false;
input double            InpEquityStopPct    = 50.0;

input group "=== Time / News Filters ==="
input bool              InpUseTimeFilter    = false;
input int               InpStartHour        = 0;
input int               InpEndHour          = 24;
input bool              InpUseNewsFilter    = false;
input bool              InpNewsHigh         = true;
input bool              InpNewsMedium       = false;
input int               InpNewsMinsBefore   = 30;
input int               InpNewsMinsAfter    = 30;


input group "=== Notifications ==="
input bool              InpUseAlert         = true;
input bool              InpUseSound         = false;
input string            InpSoundFile        = "alert.wav";
input bool              InpUsePush          = false;

input group "=== Persistence ==="
input bool              InpUsePersistence   = true;

input group "=== Panel ==="
input bool              InpShowPanel        = true;
input color             InpPanelColor       = clrWhite;
input int               InpPanelFontSize    = 10;

//=== Globals ==========================================================
CTrade        trade;
CPositionInfo pos;
CSymbolInfo   sym;

ENUM_BOT_STATE g_state            = ST_IDLE;
ulong          g_coreTicket       = 0;
ulong          g_hedgeTicket      = 0;
double         g_coreInitVolume   = 0;       // initial core volume snapshot
double         g_lastPosGridPrice = 0;       // last positive-grid trigger price
int            g_cycleNum         = 0;       // current recovery cycle index

string         g_gvPrefix         = "";

#define CMT_HEDGE     "HEDGE"
#define CMT_REC       "REC"

#define BTN_ACTIVATE  "RECOVERI_BTN_ACTIVATE"
#define BTN_STOP      "RECOVERI_BTN_STOP"
#define BTN_PAUSE     "RECOVERI_BTN_PAUSE"
#define LBL_PREFIX    "RECOVERI_LBL_"
#define OBJ_PREFIX    "RECOVERI_"

//=== OnInit ===========================================================
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints((ulong)InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS);


   ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Alert("RECOVERI requires a HEDGING account. Got margin mode = ", mm);
      Print("RECOVERI requires a HEDGING account. Got margin mode = ", mm);
      return INIT_FAILED;
     }

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(InpFragmentLot < minLot)
     {
      Alert("InpFragmentLot=", InpFragmentLot, " < broker min ", minLot);
      return INIT_FAILED;
     }

   g_gvPrefix = StringFormat("RECOVERI_%s_%I64d_", _Symbol, InpMagic);
   if(InpUsePersistence) LoadState();
   if(InpShowPanel) CreatePanel();

   PrintFormat("RECOVERI v2.00 init: state=%s core=#%I64u hedge=#%I64u",
               StateName(g_state), g_coreTicket, g_hedgeTicket);
   return INIT_SUCCEEDED;
  }

//=== OnDeinit =========================================================
void OnDeinit(const int reason)
  {
   if(InpUsePersistence) SaveState();
   ObjectsDeleteAll(0, OBJ_PREFIX);
   ChartRedraw(0);
  }

//=== OnTick ===========================================================
void OnTick()
  {
   if(g_state == ST_EMERGENCY) { UpdatePanel(); return; }

   if(InpUseEquityStop && CheckEquityStop())
     {
      g_state = ST_EMERGENCY;
      CloseAllPositions();
      Notify("EMERGENCY STOP: equity threshold breached");
      SaveStateIf();
      UpdatePanel();
      return;
     }


   if(g_state == ST_PAUSED) { UpdatePanel(); return; }

   // Detect external close of the CORE position
   if((g_state == ST_HEDGING || g_state == ST_RECOVERING) && g_coreTicket != 0)
     {
      if(!PositionSelectByTicket(g_coreTicket))
        {
         Print("CORE closed externally - finalizing");
         Notify("CORE closed externally - finalizing");
         CloseAllRecovery();
         DeleteAllRecoveryPending();
         CloseHedgeFully();
         g_coreTicket = 0; g_hedgeTicket = 0; g_coreInitVolume = 0;
         g_state = ST_IDLE;
         SaveStateIf();
         UpdatePanel();
         return;
        }
     }

   switch(g_state)
     {
      case ST_IDLE:
         if(InpTriggerMode == TRIG_AUTO) AutoTriggerCheck();
         break;
      case ST_HEDGING:
         OpenHedgeStep();
         break;
      case ST_RECOVERING:
         ManageRecovery();
         break;
     }

   UpdatePanel();
  }

//=== OnChartEvent =====================================================
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == BTN_ACTIVATE)
     {
      if(g_state == ST_IDLE) ManualActivate();
      else PrintFormat("Activate ignored, state=%s", StateName(g_state));
     }

   else if(sparam == BTN_STOP)
     {
      Print("STOP pressed - closing everything and resetting");
      Notify("Manual STOP - closing all");
      CloseAllPositions();
      g_coreTicket = 0; g_hedgeTicket = 0; g_coreInitVolume = 0;
      g_lastPosGridPrice = 0; g_cycleNum = 0;
      g_state = ST_IDLE;
      SaveStateIf();
     }
   else if(sparam == BTN_PAUSE)
     {
      if(g_state == ST_PAUSED)
        {
         g_state = (g_coreTicket == 0) ? ST_IDLE : ST_RECOVERING;
         Print("RESUMED, state=", StateName(g_state));
        }
      else if(g_state == ST_RECOVERING || g_state == ST_HEDGING)
        {
         g_state = ST_PAUSED;
         Print("PAUSED");
        }
      SaveStateIf();
     }

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   ChartRedraw(0);
  }

//=== Activation =======================================================
void ManualActivate()
  {
   ulong t = FindMostLosingPosition();
   if(t == 0) { Alert("ACTIVATE: no losing non-managed position on ", _Symbol); return; }
   if(!pos.SelectByTicket(t)) return;
   double pnl = pos.Profit() + pos.Swap() + pos.Commission();
   if(pnl >= 0) { Alert("ACTIVATE: position not in loss"); return; }
   AdoptCore(t);
  }

void AutoTriggerCheck()
  {
   if(!IsTradingAllowed()) return;
   ulong t = FindMostLosingPosition();
   if(t == 0) return;
   if(!pos.SelectByTicket(t)) return;
   double loss = pos.Profit() + pos.Swap() + pos.Commission();
   if(loss <= -InpTriggerLossMoney) AdoptCore(t);
  }


void AdoptCore(const ulong ticket)
  {
   if(!pos.SelectByTicket(ticket)) return;
   g_coreTicket       = ticket;
   g_coreInitVolume   = pos.Volume();
   g_state            = ST_HEDGING;
   g_cycleNum         = 0;
   g_lastPosGridPrice = 0;
   PrintFormat("CORE adopted #%I64u %s %s vol=%.2f open=%.5f pnl=%.2f",
               ticket, pos.Symbol(),
               pos.PositionType() == POSITION_TYPE_BUY ? "BUY" : "SELL",
               pos.Volume(), pos.PriceOpen(),
               pos.Profit() + pos.Swap() + pos.Commission());
   Notify(StringFormat("CORE adopted #%I64u, hedging next tick", ticket));
   SaveStateIf();
  }

ulong FindMostLosingPosition()
  {
   ulong worstTk = 0;
   double worstPnl = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong tk = PositionGetTicket(i);
      if(!pos.SelectByTicket(tk)) continue;
      if(pos.Symbol() != _Symbol) continue;
      // skip our own managed positions
      if((long)pos.Magic() == InpMagic) continue;
      double p = pos.Profit() + pos.Swap() + pos.Commission();
      if(p < worstPnl) { worstPnl = p; worstTk = tk; }
     }
   return worstTk;
  }

//=== Hedge step =======================================================
void OpenHedgeStep()
  {
   if(g_coreTicket == 0) { g_state = ST_IDLE; return; }
   if(!pos.SelectByTicket(g_coreTicket)) { g_state = ST_IDLE; g_coreTicket = 0; return; }
   if(!IsTradingAllowed()) return;
   if(!SpreadOK()) return;

   ENUM_POSITION_TYPE coreType = pos.PositionType();
   double coreVol  = pos.Volume();
   double hedgeVol = NormalizeLot(coreVol * InpHedgeRatio);

   if(hedgeVol <= 0) { Alert("Hedge volume is 0, abort"); g_state = ST_IDLE; return; }

   ENUM_ORDER_TYPE hedgeType = (coreType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   sym.Name(_Symbol); sym.RefreshRates();
   double price = (hedgeType == ORDER_TYPE_BUY) ? sym.Ask() : sym.Bid();
   string cmt = StringFormat("%s|%s", InpComment, CMT_HEDGE);

   bool ok = (hedgeType == ORDER_TYPE_BUY)
             ? trade.Buy(hedgeVol, _Symbol, price, 0, 0, cmt)
             : trade.Sell(hedgeVol, _Symbol, price, 0, 0, cmt);
   if(!ok)
     {
      PrintFormat("HEDGE failed err=%d ret=%d", GetLastError(), trade.ResultRetcode());
      return; // retry next tick
     }

   // In hedging mode the position ID equals the opening order ticket
   g_hedgeTicket = trade.ResultOrder();
   PrintFormat("HEDGE opened #%I64u %s vol=%.2f @ %.5f",
               g_hedgeTicket, hedgeType == ORDER_TYPE_BUY ? "BUY" : "SELL", hedgeVol, price);
   Notify(StringFormat("HEDGE opened #%I64u, starting recovery", g_hedgeTicket));

   g_state = ST_RECOVERING;
   g_cycleNum = 1;
   // Reference price for positive-grid: same side used in TryAddPositiveGrid
   //   BUY hedge -> use Bid (our exit price, rises = favorable)
   //   SELL hedge -> use Ask (our exit price, falls = favorable)
   g_lastPosGridPrice = (hedgeType == ORDER_TYPE_BUY) ? sym.Bid() : sym.Ask();
   SaveStateIf();
  }

//=== Recovery management ==============================================
void ManageRecovery()
  {
   if(g_coreTicket == 0 || g_hedgeTicket == 0) { g_state = ST_IDLE; return; }
   if(!pos.SelectByTicket(g_hedgeTicket))
     {
      Print("HEDGE missing - aborting cycle");
      Notify("HEDGE missing - aborting");
      CloseAllRecovery();
      DeleteAllRecoveryPending();
      g_coreTicket = 0; g_hedgeTicket = 0; g_coreInitVolume = 0;
      g_state = ST_IDLE;
      SaveStateIf();
      return;
     }

   int recCount = CountRecoveryPositions();
   int pendCount = CountRecoveryPending();
   if(recCount == 0 && pendCount == 0)
     {

      if(IsTradingAllowed() && SpreadOK())
         PlaceRecoveryOrders();
     }
   else if(InpUsePositiveGrid)
     {
      TryAddPositiveGrid();
     }

   double cyclePnl = ComputeCyclePnL();
   if(cyclePnl >= InpCycleProfit)
      ExecuteFragmentClose();
  }

void PlaceRecoveryOrders()
  {
   if(!pos.SelectByTicket(g_hedgeTicket)) return;
   ENUM_POSITION_TYPE hedgeType = pos.PositionType();
   sym.Name(_Symbol); sym.RefreshRates();
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = sym.Ask(), bid = sym.Bid();
   long stopsPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double stopsDist = (double)stopsPts * pt;
   trade.SetExpertMagicNumber(InpMagic);

   string cmt = StringFormat("%s|%s-%d", InpComment, CMT_REC, g_cycleNum);
   int placed = 0;
   for(int i = 1; i <= InpRecoveryLevels; i++)
     {
      double off = i * InpRecoveryStepPts * pt;
      if(off < stopsDist) off = stopsDist + pt;
      double lot = NormalizeLot(InpRecoveryStartLot * MathPow(InpRecoveryLotMult, i - 1));
      if(lot <= 0) continue;

      bool ok = false;
      if(InpRecoveryMode == REC_MODE_GRID)
        {
         // Limit orders away from current price in hedge direction
         if(hedgeType == POSITION_TYPE_SELL)
            ok = trade.SellLimit(lot, NormalizeDouble(bid + off, _Digits), _Symbol,
                                 0, 0, ORDER_TIME_GTC, 0, cmt);
         else
            ok = trade.BuyLimit(lot, NormalizeDouble(ask - off, _Digits), _Symbol,
                                0, 0, ORDER_TIME_GTC, 0, cmt);
        }
      else // ZONE: stop orders in hedge direction (trend confirmation)
        {
         if(hedgeType == POSITION_TYPE_SELL)
            ok = trade.SellStop(lot, NormalizeDouble(bid - off, _Digits), _Symbol,
                                0, 0, ORDER_TIME_GTC, 0, cmt);

         else
            ok = trade.BuyStop(lot, NormalizeDouble(ask + off, _Digits), _Symbol,
                               0, 0, ORDER_TIME_GTC, 0, cmt);
        }
      if(ok) placed++;
      else PrintFormat("Recovery L%d failed: err=%d ret=%d", i, GetLastError(), trade.ResultRetcode());
     }
   PrintFormat("Recovery placed %d/%d (%s, cycle=%d)",
               placed, InpRecoveryLevels,
               InpRecoveryMode == REC_MODE_GRID ? "GRID" : "ZONE", g_cycleNum);
  }

void TryAddPositiveGrid()
  {
   if(!pos.SelectByTicket(g_hedgeTicket)) return;
   ENUM_POSITION_TYPE hedgeType = pos.PositionType();
   sym.Name(_Symbol); sym.RefreshRates();
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double curPrice = (hedgeType == POSITION_TYPE_BUY) ? sym.Bid() : sym.Ask();

   // Distance moved in our favor since last positive-grid trigger
   double moved = (hedgeType == POSITION_TYPE_BUY)
                  ? (curPrice - g_lastPosGridPrice) / pt
                  : (g_lastPosGridPrice - curPrice) / pt;
   if(moved < InpPosGridStepPts) return;

   // Soft "min distance to TP" gate: if cycle profit is close to target, skip
   double cyclePnl = ComputeCyclePnL();
   if(InpCycleProfit > 0 && cyclePnl >= InpCycleProfit * 0.8) return;

   if(!IsTradingAllowed() || !SpreadOK()) return;

   double lot = NormalizeLot(InpRecoveryStartLot);
   if(lot <= 0) return;
   string cmt = StringFormat("%s|%s-P%d", InpComment, CMT_REC, g_cycleNum);
   double price = (hedgeType == POSITION_TYPE_BUY) ? sym.Ask() : sym.Bid();

   bool ok = (hedgeType == POSITION_TYPE_BUY)
             ? trade.Buy(lot, _Symbol, price, 0, 0, cmt)
             : trade.Sell(lot, _Symbol, price, 0, 0, cmt);
   if(ok)
     {
      g_lastPosGridPrice = curPrice;
      PrintFormat("PositiveGrid added: %s vol=%.2f @ %.5f (moved=%.0f pts)",
                  hedgeType == POSITION_TYPE_BUY ? "BUY" : "SELL", lot, price, moved);
      SaveStateIf();
     }
  }


double ComputeCyclePnL()
  {
   double total = 0;
   if(pos.SelectByTicket(g_hedgeTicket))
      total += pos.Profit() + pos.Swap() + pos.Commission();
   int n = PositionsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong tk = PositionGetTicket(i);
      if(!pos.SelectByTicket(tk)) continue;
      if(pos.Symbol() != _Symbol) continue;
      if((long)pos.Magic() != InpMagic) continue;
      if(tk == g_hedgeTicket) continue;
      if(StringFind(pos.Comment(), CMT_REC) < 0) continue;
      total += pos.Profit() + pos.Swap() + pos.Commission();
     }
   return total;
  }

int CountRecoveryPositions()
  {
   int count = 0;
   int n = PositionsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong tk = PositionGetTicket(i);
      if(!pos.SelectByTicket(tk)) continue;
      if(pos.Symbol() != _Symbol) continue;
      if((long)pos.Magic() != InpMagic) continue;
      if(StringFind(pos.Comment(), CMT_REC) < 0) continue;
      count++;
     }
   return count;
  }

int CountRecoveryPending()
  {
   int count = 0;
   int n = OrdersTotal();
   for(int i = 0; i < n; i++)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), CMT_REC) < 0) continue;
      count++;
     }
   return count;
  }


//=== Fragment close ===================================================
void ExecuteFragmentClose()
  {
   PrintFormat("Cycle %d target hit - fragmenting", g_cycleNum);
   Notify(StringFormat("Cycle %d target hit, fragmenting", g_cycleNum));

   // 1) Close all recovery positions and pending recovery orders
   CloseAllRecovery();
   DeleteAllRecoveryPending();

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double fragLot = NormalizeLot(InpFragmentLot);
   if(fragLot <= 0) fragLot = minLot;

   // 2) Partial-close fragment of HEDGE
   if(pos.SelectByTicket(g_hedgeTicket))
     {
      double hVol = pos.Volume();
      double useLot = MathMin(fragLot, hVol);
      // If remainder would be below broker min, close fully
      if(hVol - useLot < minLot - 1e-9) useLot = hVol;
      if(!trade.PositionClosePartial(g_hedgeTicket, useLot, (ulong)InpSlippage))
         PrintFormat("Hedge fragment close failed err=%d ret=%d", GetLastError(), trade.ResultRetcode());
     }

   // 3) Partial-close fragment of CORE
   if(pos.SelectByTicket(g_coreTicket))
     {
      double cVol = pos.Volume();
      double useLot = MathMin(fragLot, cVol);
      if(cVol - useLot < minLot - 1e-9) useLot = cVol;
      if(!trade.PositionClosePartial(g_coreTicket, useLot, (ulong)InpSlippage))
         PrintFormat("Core fragment close failed err=%d ret=%d", GetLastError(), trade.ResultRetcode());
     }

   // 4) Check if CORE is now fully closed
   if(!PositionSelectByTicket(g_coreTicket))
     {
      Print("CORE fully recovered - closing residual hedge, back to IDLE");
      Notify("Recovery COMPLETE");
      if(PositionSelectByTicket(g_hedgeTicket))
         trade.PositionClose(g_hedgeTicket, (ulong)InpSlippage);
      g_coreTicket = 0; g_hedgeTicket = 0; g_coreInitVolume = 0;
      g_lastPosGridPrice = 0; g_cycleNum = 0;
      g_state = ST_IDLE;
     }
   else
     {

      // 5) Continue with next cycle - recovery orders re-placed on next tick
      g_cycleNum++;
      sym.Name(_Symbol); sym.RefreshRates();
      if(pos.SelectByTicket(g_hedgeTicket))
         g_lastPosGridPrice = (pos.PositionType() == POSITION_TYPE_BUY) ? sym.Bid() : sym.Ask();
     }
   SaveStateIf();
  }

void CloseAllRecovery()
  {
   ulong tickets[];
   int n = PositionsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong tk = PositionGetTicket(i);
      if(!pos.SelectByTicket(tk)) continue;
      if(pos.Symbol() != _Symbol) continue;
      if((long)pos.Magic() != InpMagic) continue;
      if(StringFind(pos.Comment(), CMT_REC) < 0) continue;
      int sz = ArraySize(tickets); ArrayResize(tickets, sz + 1); tickets[sz] = tk;
     }
   for(int i = 0; i < ArraySize(tickets); i++)
      if(!trade.PositionClose(tickets[i], (ulong)InpSlippage))
         PrintFormat("CloseRec #%I64u err=%d", tickets[i], trade.ResultRetcode());
  }

void DeleteAllRecoveryPending()
  {
   ulong tickets[];
   int n = OrdersTotal();
   for(int i = 0; i < n; i++)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), CMT_REC) < 0) continue;
      int sz = ArraySize(tickets); ArrayResize(tickets, sz + 1); tickets[sz] = tk;
     }
   for(int i = 0; i < ArraySize(tickets); i++)
      if(!trade.OrderDelete(tickets[i]))
         PrintFormat("DelRec #%I64u err=%d", tickets[i], trade.ResultRetcode());
  }

void CloseHedgeFully()
  {
   if(g_hedgeTicket != 0 && PositionSelectByTicket(g_hedgeTicket))
      trade.PositionClose(g_hedgeTicket, (ulong)InpSlippage);
  }


void CloseAllPositions()
  {
   CloseAllRecovery();
   DeleteAllRecoveryPending();
   CloseHedgeFully();
  }

//=== Helpers ==========================================================
double NormalizeLot(double lot)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / step + 1e-9) * step;
   return NormalizeDouble(lot, 2);
  }

bool SpreadOK()
  {
   if(InpMaxSpreadPts <= 0) return true;
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (sp <= InpMaxSpreadPts);
  }

bool CheckEquityStop()
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0) return false;
   double pct = eq / bal * 100.0;
   return (pct <= InpEquityStopPct);
  }

bool IsTradingAllowed()
  {
   if(!IsTimeAllowed()) return false;
   if(IsNewsBlocked()) return false;
   return true;
  }

bool IsTimeAllowed()
  {
   if(!InpUseTimeFilter) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
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
   for(int i = 0; i < 2; i++)
     {
      if(list[i] == "") continue;
      MqlCalendarValue values[];
      if(!CalendarValueHistory(values, from, to, NULL, list[i])) continue;
      int n = ArraySize(values);
      for(int k = 0; k < n; k++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[k].event_id, ev)) continue;
         if(ev.importance == CALENDAR_IMPORTANCE_HIGH     && InpNewsHigh)   return true;
         if(ev.importance == CALENDAR_IMPORTANCE_MODERATE && InpNewsMedium) return true;
        }
     }
   return false;
  }

void Notify(const string text)
  {
   string tag = StringFormat("[RECOVERI %s] %s", _Symbol, text);
   if(InpUseAlert) Alert(tag);
   if(InpUseSound && InpSoundFile != "") PlaySound(InpSoundFile);
   if(InpUsePush) SendNotification(tag);
  }

string StateName(const ENUM_BOT_STATE s)
  {
   switch(s)
     {
      case ST_IDLE:        return "IDLE";
      case ST_HEDGING:     return "HEDGING";
      case ST_RECOVERING:  return "RECOVERING";
      case ST_PAUSED:      return "PAUSED";
      case ST_EMERGENCY:   return "EMERGENCY";
     }

   return "?";
  }

//=== Persistence ======================================================
void SaveStateIf() { if(InpUsePersistence) SaveState(); }

void SaveState()
  {
   GlobalVariableSet(g_gvPrefix + "STATE", (double)g_state);
   GlobalVariableSet(g_gvPrefix + "CORE",  (double)g_coreTicket);
   GlobalVariableSet(g_gvPrefix + "HEDGE", (double)g_hedgeTicket);
   GlobalVariableSet(g_gvPrefix + "CIVOL", g_coreInitVolume);
   GlobalVariableSet(g_gvPrefix + "LPGP",  g_lastPosGridPrice);
   GlobalVariableSet(g_gvPrefix + "CYCLE", (double)g_cycleNum);
  }

void LoadState()
  {
   if(GlobalVariableCheck(g_gvPrefix + "STATE")) g_state            = (ENUM_BOT_STATE)(int)GlobalVariableGet(g_gvPrefix + "STATE");
   if(GlobalVariableCheck(g_gvPrefix + "CORE"))  g_coreTicket       = (ulong)GlobalVariableGet(g_gvPrefix + "CORE");
   if(GlobalVariableCheck(g_gvPrefix + "HEDGE")) g_hedgeTicket      = (ulong)GlobalVariableGet(g_gvPrefix + "HEDGE");
   if(GlobalVariableCheck(g_gvPrefix + "CIVOL")) g_coreInitVolume   = GlobalVariableGet(g_gvPrefix + "CIVOL");
   if(GlobalVariableCheck(g_gvPrefix + "LPGP"))  g_lastPosGridPrice = GlobalVariableGet(g_gvPrefix + "LPGP");
   if(GlobalVariableCheck(g_gvPrefix + "CYCLE")) g_cycleNum         = (int)GlobalVariableGet(g_gvPrefix + "CYCLE");

   // Sanity: stale tickets after restart -> reset to IDLE
   if(g_state == ST_HEDGING || g_state == ST_RECOVERING)
     {
      if(g_coreTicket == 0 || !PositionSelectByTicket(g_coreTicket))
        {
         Print("LoadState: stale core ticket - resetting to IDLE");
         g_state = ST_IDLE;
         g_coreTicket = 0; g_hedgeTicket = 0; g_coreInitVolume = 0;
        }
     }
  }

//=== Panel ============================================================
void CreatePanel()
  {
   string lines[] = {"title", "state", "mode", "core", "hedge", "cycle", "cyclepl", "posgrid"};
   int y = 20;
   for(int i = 0; i < ArraySize(lines); i++)
     {
      MakeLabel(lines[i], 10, y);
      y += InpPanelFontSize + 6;
     }

   int btnY = y + 6, bw = 110, bh = 24, gap = 6;
   MakeButton(BTN_ACTIVATE, 10,           btnY,           bw, bh, "Activate",     clrSeaGreen,  clrWhite);
   MakeButton(BTN_PAUSE,    10 + bw + gap, btnY,          bw, bh, "Pause",        clrSlateGray, clrWhite);
   MakeButton(BTN_STOP,     10,            btnY + bh + gap, bw, bh, "Stop / Reset", clrFireBrick, clrWhite);
  }

void MakeLabel(const string key, const int x, const int y)
  {
   string n = LBL_PREFIX + key;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, n, OBJPROP_COLOR, InpPanelColor);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, InpPanelFontSize);
      ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
      ObjectSetString(0, n, OBJPROP_TEXT, "");
      ObjectSetInteger(0, n, OBJPROP_BACK, false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
     }
  }

void MakeButton(const string name, const int x, const int y, const int w, const int h,
                const string text, const color bg, const color fg)
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
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }
  }


void SetLbl(const string key, const string text, color clr = clrNONE)
  {
   string n = LBL_PREFIX + key;
   if(ObjectFind(0, n) < 0) return;
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr == clrNONE ? InpPanelColor : clr);
  }

void UpdatePanel()
  {
   if(!InpShowPanel) return;
   color stClr = (g_state == ST_RECOVERING || g_state == ST_HEDGING) ? clrLime
                 : (g_state == ST_PAUSED) ? clrOrange
                 : (g_state == ST_EMERGENCY) ? clrRed : InpPanelColor;

   SetLbl("title", "=== RECOVERI v2.00 ===", clrGold);
   SetLbl("state", "State: " + StateName(g_state), stClr);
   SetLbl("mode",  StringFormat("Mode: %s | Trigger: %s",
                                 InpRecoveryMode == REC_MODE_GRID ? "GRID" : "ZONE",
                                 InpTriggerMode == TRIG_MANUAL ? "MANUAL" : "AUTO"));

   if(g_coreTicket != 0 && pos.SelectByTicket(g_coreTicket))
      SetLbl("core", StringFormat("Core #%I64u %s %.2f/%.2f @ %.5f  P/L %.2f",
                                   g_coreTicket,
                                   pos.PositionType() == POSITION_TYPE_BUY ? "BUY" : "SELL",
                                   pos.Volume(), g_coreInitVolume, pos.PriceOpen(),
                                   pos.Profit() + pos.Swap() + pos.Commission()));
   else
      SetLbl("core", "Core: -");

   if(g_hedgeTicket != 0 && pos.SelectByTicket(g_hedgeTicket))
      SetLbl("hedge", StringFormat("Hedge #%I64u %s %.2f @ %.5f  P/L %.2f",
                                    g_hedgeTicket,
                                    pos.PositionType() == POSITION_TYPE_BUY ? "BUY" : "SELL",
                                    pos.Volume(), pos.PriceOpen(),
                                    pos.Profit() + pos.Swap() + pos.Commission()));
   else
      SetLbl("hedge", "Hedge: -");

   SetLbl("cycle", StringFormat("Cycle #%d  RecPos: %d  RecPend: %d",
                                 g_cycleNum, CountRecoveryPositions(), CountRecoveryPending()));
   double cpl = ComputeCyclePnL();
   color cClr = (cpl >= 0) ? clrLime : clrTomato;
   SetLbl("cyclepl", StringFormat("Cycle P/L: %.2f / target %.2f", cpl, InpCycleProfit), cClr);
   SetLbl("posgrid", StringFormat("PositiveGrid: %s  last=%.5f",
                                   InpUsePositiveGrid ? "ON" : "OFF", g_lastPosGridPrice));

   ObjectSetString(0, BTN_PAUSE, OBJPROP_TEXT, g_state == ST_PAUSED ? "Resume" : "Pause");
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
