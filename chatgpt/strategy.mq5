//+------------------------------------------------------------------+
//| Forex Martingale EA                                              |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//================ CONFIG =================//
input bool   BotEnabled = true;

input string StartTime = "02:00";
input string EndTime   = "18:00";

input double RR = 1.7;

input int CooldownLossMin = 30;
input int Cooldown3LossMin = 120;

input int MaxTPPerDay = 2;

input double MartingaleSteps[] = {1,1.5,2.5,4,8,12,21,35};

//================ STATE =================//
int currentStep = 0;
int consecutiveLosses = 0;
int dailyTP = 0;

datetime lastTradeTime = 0;
datetime cooldownEnd = 0;

//================ UTIL =================//
bool IsWithinSession()
{
   datetime now = TimeCurrent();
   string today = TimeToString(now, TIME_DATE);
   
   datetime start = StringToTime(today + " " + StartTime);
   datetime end   = StringToTime(today + " " + EndTime);

   return (now >= start && now <= end);
}

bool InCooldown()
{
   return (TimeCurrent() < cooldownEnd);
}

double CalculateLot(double riskPercent, double slPips)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (riskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot = riskAmount / (slPips * tickValue);

   return NormalizeDouble(lot, 2);
}

//================ STRATEGY PLACEHOLDER =================//
bool GetTradeSignal(bool &isBuy, double &sl, double &tp)
{
   // 🔴 PLACE YOUR STRATEGY HERE (simplified placeholder)

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Dummy logic (replace with your real one)
   if(MathRand() % 2 == 0)
   {
      isBuy = true;
      sl = price - 50 * _Point;
      tp = price + (50 * RR) * _Point;
      return true;
   }
   else
   {
      isBuy = false;
      sl = price + 50 * _Point;
      tp = price - (50 * RR) * _Point;
      return true;
   }
}

//================ TRADE HANDLING =================//
bool HasOpenPosition()
{
   return PositionsTotal() > 0;
}

void OpenTrade()
{
   if(currentStep >= ArraySize(MartingaleSteps))
      currentStep = 0;

   double riskPercent = MartingaleSteps[currentStep];

   bool isBuy;
   double sl, tp;

   if(!GetTradeSignal(isBuy, sl, tp))
      return;

   double slPips = MathAbs(SymbolInfoDouble(_Symbol, SYMBOL_BID) - sl) / _Point;

   double lot = CalculateLot(riskPercent, slPips);

   if(isBuy)
      trade.Buy(lot, _Symbol, 0, sl, tp);
   else
      trade.Sell(lot, _Symbol, 0, sl, tp);

   lastTradeTime = TimeCurrent();
}

//================ RESULT HANDLER =================//
void OnTradeClosed(bool win)
{
   if(win)
   {
      currentStep = 0;
      consecutiveLosses = 0;
      dailyTP++;

      if(dailyTP >= MaxTPPerDay)
         BotEnabled = false;
   }
   else
   {
      consecutiveLosses++;
      currentStep++;

      if(consecutiveLosses >= 3)
         cooldownEnd = TimeCurrent() + Cooldown3LossMin * 60;
      else
         cooldownEnd = TimeCurrent() + CooldownLossMin * 60;
   }
}

//================ MAIN LOOP =================//
void OnTick()
{
   if(!BotEnabled) return;
   if(!IsWithinSession()) return;
   if(InCooldown()) return;
   if(dailyTP >= MaxTPPerDay) return;
   if(HasOpenPosition()) return;

   OpenTrade();
}

//================ TRADE EVENT =================//
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
      {
         double profit = trans.profit;

         if(profit > 0)
            OnTradeClosed(true);
         else if(profit < 0)
            OnTradeClosed(false);
      }
   }
}