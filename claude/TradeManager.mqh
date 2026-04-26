//+------------------------------------------------------------------+
//| TradeManager.mqh - Order execution and position monitoring        |
//+------------------------------------------------------------------+
#ifndef TRADE_MANAGER_MQH
#define TRADE_MANAGER_MQH

#include <Trade\Trade.mqh>
#include "Utils.mqh"
#include "Config.mqh"
#include "Logger.mqh"
#include "RiskManager.mqh"
#include "SignalEngine.mqh"

CTrade G_Trade;

// Stored trade info for monitoring
struct ActiveTrade
{
   ulong    ticket;
   string   symbol;
   string   direction;
   double   entryPrice;
   double   slPrice;
   double   tpPrice;
   double   slPips;
   double   lots;
   int      step;
   double   stepPct;
   bool     breakevenMoved;
   double   beLevel;        // price at which we move to breakeven
};

ActiveTrade G_ActiveTrade;
bool        G_HasActiveTrade = false;

//--- Initialize trade manager
void InitTradeManager()
{
   G_Trade.SetExpertMagicNumber(20250101);
   G_Trade.SetDeviationInPoints(10);
   G_Trade.SetTypeFilling(ORDER_FILLING_FOK);

   // Restore active trade from state
   if(G_State.activeTicket > 0)
   {
      if(PositionSelectByTicket(G_State.activeTicket))
      {
         G_HasActiveTrade             = true;
         G_ActiveTrade.ticket         = G_State.activeTicket;
         G_ActiveTrade.symbol         = PositionGetString(POSITION_SYMBOL);
         G_ActiveTrade.direction      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "LONG" : "SHORT";
         G_ActiveTrade.entryPrice     = PositionGetDouble(POSITION_PRICE_OPEN);
         G_ActiveTrade.slPrice        = PositionGetDouble(POSITION_SL);
         G_ActiveTrade.tpPrice        = PositionGetDouble(POSITION_TP);
         G_ActiveTrade.lots           = PositionGetDouble(POSITION_VOLUME);
         G_ActiveTrade.step           = G_State.currentStep;
         G_ActiveTrade.stepPct        = GetCurrentRiskPct();
         G_ActiveTrade.breakevenMoved = false;
         // BE level: halfway between entry and TP
         G_ActiveTrade.beLevel = (G_ActiveTrade.entryPrice + G_ActiveTrade.tpPrice) / 2.0;
         Print("[TradeManager] Restored active trade ticket ", G_State.activeTicket);
      }
      else
      {
         Print("[TradeManager] Stored ticket not found in open positions. Clearing.");
         G_State.activeTicket = 0;
         G_HasActiveTrade     = false;
         SaveState();
      }
   }
}

//--- Open a new trade
bool OpenTrade(TradeSignal &sig)
{
   if(G_HasActiveTrade)
   {
      Print("[TradeManager] Already have active trade, skip.");
      return false;
   }

   double lots = CalcLotSize(sig.symbol, sig.slPips);
   if(lots <= 0)
   {
      Print("[TradeManager] Lot size 0, cannot open.");
      return false;
   }

   bool ok = false;
   if(sig.type == SIGNAL_LONG)
      ok = G_Trade.Buy(lots, sig.symbol, sig.entryPrice, sig.slPrice, sig.tpPrice,
                       StringFormat("LNY_Step%d", G_State.currentStep));
   else
      ok = G_Trade.Sell(lots, sig.symbol, sig.entryPrice, sig.slPrice, sig.tpPrice,
                        StringFormat("LNY_Step%d", G_State.currentStep));

   if(!ok)
   {
      Print(StringFormat("[TradeManager] Order failed: %d %s", G_Trade.ResultRetcode(), G_Trade.ResultRetcodeDescription()));
      return false;
   }

   ulong ticket = G_Trade.ResultDeal();
   if(ticket == 0) ticket = G_Trade.ResultOrder();

   G_HasActiveTrade             = true;
   G_ActiveTrade.ticket         = ticket;
   G_ActiveTrade.symbol         = sig.symbol;
   G_ActiveTrade.direction      = (sig.type == SIGNAL_LONG) ? "LONG" : "SHORT";
   G_ActiveTrade.entryPrice     = sig.entryPrice;
   G_ActiveTrade.slPrice        = sig.slPrice;
   G_ActiveTrade.tpPrice        = sig.tpPrice;
   G_ActiveTrade.slPips         = sig.slPips;
   G_ActiveTrade.lots           = lots;
   G_ActiveTrade.step           = G_State.currentStep;
   G_ActiveTrade.stepPct        = GetCurrentRiskPct();
   G_ActiveTrade.breakevenMoved = false;
   G_ActiveTrade.beLevel        = (sig.entryPrice + sig.tpPrice) / 2.0;

   G_State.activeTicket = ticket;
   SaveState();

   Print(StringFormat("[TradeManager] Opened %s %s Lots=%.2f Entry=%.5f SL=%.5f TP=%.5f Ticket=%I64u",
         sig.symbol, G_ActiveTrade.direction, lots,
         sig.entryPrice, sig.slPrice, sig.tpPrice, ticket));

   if(G_Config.enablePushNotify)
      SendNotification(StringFormat("LNY Bot: %s %s | Step %d (%.1f%%) | Lots %.2f | Entry %.5f",
            sig.symbol, G_ActiveTrade.direction, G_State.currentStep,
            G_ActiveTrade.stepPct, lots, sig.entryPrice));

   return true;
}

//--- Move SL to breakeven
void MoveToBreakeven(string symbol, ulong ticket, double bePrice, string direction)
{
   double point   = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double buffer  = 2.0 * PipSize(symbol); // 2 pip buffer past entry

   double newSL = (direction == "LONG") ? G_ActiveTrade.entryPrice + buffer
                                        : G_ActiveTrade.entryPrice - buffer;
   if(G_Trade.PositionModify(ticket, newSL, G_ActiveTrade.tpPrice))
   {
      G_ActiveTrade.breakevenMoved = true;
      G_ActiveTrade.slPrice        = newSL;
      Print(StringFormat("[TradeManager] Breakeven set at %.5f for ticket %I64u", newSL, ticket));
   }
}

//--- Monitor open position — call on every tick
// Returns: 1 = trade still open, 2 = TP hit, 3 = SL hit, 0 = no trade
int MonitorTrade()
{
   if(!G_HasActiveTrade) return 0;

   // Check if position still exists
   if(!PositionSelectByTicket(G_ActiveTrade.ticket))
   {
      // Position closed — determine if TP or SL
      double closePrice = 0;
      double pnl        = 0;

      // Look at deal history
      HistorySelectByPosition(G_ActiveTrade.ticket);
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong dTicket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(dTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            closePrice = HistoryDealGetDouble(dTicket, DEAL_PRICE);
            pnl        = HistoryDealGetDouble(dTicket, DEAL_PROFIT) +
                         HistoryDealGetDouble(dTicket, DEAL_SWAP)   +
                         HistoryDealGetDouble(dTicket, DEAL_COMMISSION);
            break;
         }
      }

      bool isWin = false;
      if(G_ActiveTrade.direction == "LONG")
         isWin = (closePrice >= G_ActiveTrade.tpPrice - PipSize(G_ActiveTrade.symbol));
      else
         isWin = (closePrice <= G_ActiveTrade.tpPrice + PipSize(G_ActiveTrade.symbol));

      // Log the trade
      LogTrade(G_ActiveTrade.symbol, G_ActiveTrade.direction,
               G_ActiveTrade.step, G_ActiveTrade.stepPct,
               G_ActiveTrade.lots, G_ActiveTrade.entryPrice,
               G_ActiveTrade.slPrice, G_ActiveTrade.tpPrice,
               isWin ? "WIN" : "LOSS", pnl,
               AccountInfoDouble(ACCOUNT_BALANCE),
               G_State.dailyTPCount, G_State.consecutiveLosses);

      G_HasActiveTrade     = false;
      G_State.activeTicket = 0;
      G_State.totalTrades++;
      G_State.totalPnL    += pnl;

      if(isWin)
      {
         G_State.totalWins++;
         return 2; // TP hit
      }
      else
      {
         G_State.totalLosses++;
         return 3; // SL hit
      }
   }

   // Position still open — check breakeven
   if(!G_ActiveTrade.breakevenMoved)
   {
      double bid = SymbolInfoDouble(G_ActiveTrade.symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(G_ActiveTrade.symbol, SYMBOL_ASK);

      bool beTriggered = false;
      if(G_ActiveTrade.direction == "LONG"  && bid >= G_ActiveTrade.beLevel) beTriggered = true;
      if(G_ActiveTrade.direction == "SHORT" && ask <= G_ActiveTrade.beLevel) beTriggered = true;

      if(beTriggered)
         MoveToBreakeven(G_ActiveTrade.symbol, G_ActiveTrade.ticket,
                         G_ActiveTrade.beLevel, G_ActiveTrade.direction);
   }

   return 1; // still open
}

//--- Handle TP result
void OnTPHit()
{
   G_State.dailyTPCount++;
   G_State.consecutiveLosses = 0;
   G_State.lastTradeResult   = "WIN";
   G_State.lastTPTime        = UtcNow();
   ResetMartingaleStep();

   if(G_State.dailyTPCount >= G_Config.maxDailyTPs)
   {
      G_State.botState = STATE_DAILY_DONE;
      Print(StringFormat("[TradeManager] Daily TP target (%d) reached. Stopping for today.", G_Config.maxDailyTPs));
      if(G_Config.enablePushNotify)
         SendNotification(StringFormat("LNY Bot: Daily target hit (%d TPs). Done for today.", G_Config.maxDailyTPs));
   }
   else
   {
      G_State.botState = STATE_TRADING;
      if(G_Config.enablePushNotify)
         SendNotification(StringFormat("LNY Bot: TP HIT! Step reset to 0. Daily TPs: %d/%d",
               G_State.dailyTPCount, G_Config.maxDailyTPs));
   }
   SaveState();
}

//--- Handle SL result
void OnSLHit()
{
   G_State.consecutiveLosses++;
   G_State.lastTradeResult = "LOSS";

   bool canContinue = AdvanceMartingaleStep();
   if(canContinue)
   {
      EnterCooloff();
      if(G_Config.enablePushNotify)
         SendNotification(StringFormat("LNY Bot: SL hit. Step now %d (%.1f%%). Cooloff: %s. ConsecLoss: %d",
               G_State.currentStep,
               G_Config.stepPercent[G_State.currentStep],
               G_State.botState == STATE_COOLOFF_LONG ? "2hr" : "30min",
               G_State.consecutiveLosses));
   }
   else
   {
      if(G_Config.enablePushNotify)
         SendNotification("LNY Bot: MARTINGALE EXHAUSTED. Manual reset required!");
   }
   SaveState();
}

#endif
