//+------------------------------------------------------------------+
//| RiskManager.mqh - Position sizing & martingale management         |
//+------------------------------------------------------------------+
#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

#include "Utils.mqh"
#include "Config.mqh"
#include "Logger.mqh"

//--- Calculate lot size for current martingale step
// Formula: (Balance * RiskPct/100) / (SL_pips * PipValue)
double CalcLotSize(string symbol, double slPips)
{
   if(G_State.currentStep >= G_Config.stepCount)
   {
      Print("[Risk] Current step ", G_State.currentStep, " exceeds config steps.");
      return 0.0;
   }

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskPct    = G_Config.stepPercent[G_State.currentStep];
   double riskAmount = balance * riskPct / 100.0;

   // Get pip value in account currency
   double tickVal  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double pip      = PipSize(symbol);
   double pipValue = (pip / tickSize) * tickVal; // pip value per 1 lot

   if(pipValue <= 0 || slPips <= 0)
   {
      Print("[Risk] Invalid pipValue or slPips.");
      return 0.0;
   }

   double lots = riskAmount / (slPips * pipValue);
   lots = NormalizeLot(symbol, lots);

   Print(StringFormat("[Risk] Step=%d RiskPct=%.2f%% Balance=%.2f RiskAmt=%.2f SLpips=%.1f PipVal=%.4f Lots=%.2f",
         G_State.currentStep, riskPct, balance, riskAmount, slPips, pipValue, lots));

   return lots;
}

//--- Get current step risk percent
double GetCurrentRiskPct()
{
   if(G_State.currentStep >= G_Config.stepCount) return 0.0;
   return G_Config.stepPercent[G_State.currentStep];
}

//--- Advance to next martingale step on loss
// Returns false if we've run out of steps (halt required)
bool AdvanceMartingaleStep()
{
   G_State.currentStep++;
   if(G_State.currentStep >= G_Config.stepCount)
   {
      Print(StringFormat("[Risk] MARTINGALE EXHAUSTED. Ran through all %d steps. Bot halted.", G_Config.stepCount));
      G_State.botState = STATE_HALTED;
      SaveState();
      return false;
   }
   Print(StringFormat("[Risk] Advancing to step %d (%.2f%% risk)",
         G_State.currentStep, G_Config.stepPercent[G_State.currentStep]));
   return true;
}

//--- Reset to step 0 on win
void ResetMartingaleStep()
{
   Print(StringFormat("[Risk] TP hit. Resetting from step %d back to step 0.", G_State.currentStep));
   G_State.currentStep = 0;
}

//--- Check balance safety
bool IsBalanceSafe()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < G_Config.balanceSafetyThreshold)
   {
      Print(StringFormat("[Risk] BALANCE SAFETY: %.2f below threshold %.2f. Halting.",
            balance, G_Config.balanceSafetyThreshold));
      G_State.botState = STATE_HALTED;
      SaveState();
      return false;
   }
   return true;
}

//--- Determine cooloff state based on loss count
void EnterCooloff()
{
   G_State.lastLossTime = UtcNow();

   if(G_State.consecutiveLosses >= G_Config.consecLossThreshold)
   {
      G_State.botState = STATE_COOLOFF_LONG;
      Print(StringFormat("[Risk] %d consecutive losses. Entering LONG cooloff (%d min).",
            G_State.consecutiveLosses, G_Config.cooloffConsecLossMin));
   }
   else
   {
      G_State.botState = STATE_COOLOFF_SHORT;
      Print(StringFormat("[Risk] Loss recorded. Entering SHORT cooloff (%d min).",
            G_Config.cooloffSingleLossMin));
   }
}

//--- Check if cooloff has expired; return true if trading can resume
bool IsCooloffExpired()
{
   int elapsed = MinutesElapsed(G_State.lastLossTime);

   if(G_State.botState == STATE_COOLOFF_SHORT)
   {
      if(elapsed >= G_Config.cooloffSingleLossMin)
      {
         Print(StringFormat("[Risk] Short cooloff expired (%d min). Resuming trading.", elapsed));
         G_State.botState = STATE_TRADING;
         SaveState();
         return true;
      }
      return false;
   }

   if(G_State.botState == STATE_COOLOFF_LONG)
   {
      if(elapsed >= G_Config.cooloffConsecLossMin)
      {
         Print(StringFormat("[Risk] Long cooloff expired (%d min). Resuming trading.", elapsed));
         G_State.botState = STATE_TRADING;
         SaveState();
         return true;
      }
      return false;
   }

   return true; // not in cooloff
}

#endif
