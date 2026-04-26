//+------------------------------------------------------------------+
//| SignalEngine.mqh - London-NY Confluence Strike signal logic       |
//+------------------------------------------------------------------+
#ifndef SIGNAL_ENGINE_MQH
#define SIGNAL_ENGINE_MQH

#include "Utils.mqh"
#include "Config.mqh"

enum SignalType { SIGNAL_NONE = 0, SIGNAL_LONG = 1, SIGNAL_SHORT = -1 };

struct TradeSignal
{
   SignalType type;
   string     symbol;
   double     entryPrice;
   double     slPrice;
   double     tpPrice;
   double     slPips;
};

//--- Handle arrays for indicators per symbol
int    G_HandleEMA50_H4[3];
int    G_HandleEMA200_H4[3];
int    G_HandleEMA50_H1[3];
int    G_HandleRSI_M15[3];

string G_Symbols[3] = {"EURUSD","GBPUSD","USDJPY"};

//--- Initialize indicator handles
bool InitSignalEngine()
{
   for(int i = 0; i < 3; i++)
   {
      G_HandleEMA50_H4[i]  = iMA(G_Symbols[i], PERIOD_H4, 50,  0, MODE_EMA, PRICE_CLOSE);
      G_HandleEMA200_H4[i] = iMA(G_Symbols[i], PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
      G_HandleEMA50_H1[i]  = iMA(G_Symbols[i], PERIOD_H1, 50,  0, MODE_EMA, PRICE_CLOSE);
      G_HandleRSI_M15[i]   = iRSI(G_Symbols[i], PERIOD_M15, 14, PRICE_CLOSE);

      if(G_HandleEMA50_H4[i]  == INVALID_HANDLE ||
         G_HandleEMA200_H4[i] == INVALID_HANDLE ||
         G_HandleEMA50_H1[i]  == INVALID_HANDLE ||
         G_HandleRSI_M15[i]   == INVALID_HANDLE)
      {
         Print("[Signal] Failed to create indicators for ", G_Symbols[i]);
         return false;
      }
   }
   Print("[Signal] Indicators initialized for all 3 pairs.");
   return true;
}

//--- Release handles
void DeinitSignalEngine()
{
   for(int i = 0; i < 3; i++)
   {
      IndicatorRelease(G_HandleEMA50_H4[i]);
      IndicatorRelease(G_HandleEMA200_H4[i]);
      IndicatorRelease(G_HandleEMA50_H1[i]);
      IndicatorRelease(G_HandleRSI_M15[i]);
   }
}

//--- Get single indicator value
double GetIndicatorVal(int handle, int shift = 1)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0) return 0.0;
   return buf[0];
}

//--- Get N indicator values
bool GetIndicatorBuf(int handle, double &buf[], int count = 3)
{
   ArraySetAsSeries(buf, true);
   return CopyBuffer(handle, 0, 0, count, buf) == count;
}

//--- Determine H4 trend bias for a symbol index
// Returns 1 (bullish), -1 (bearish), 0 (no bias)
int GetTrendBias(int idx)
{
   double ema50  = GetIndicatorVal(G_HandleEMA50_H4[idx]);
   double ema200 = GetIndicatorVal(G_HandleEMA200_H4[idx]);
   if(ema50 == 0 || ema200 == 0) return 0;

   double price = SymbolInfoDouble(G_Symbols[idx], SYMBOL_BID);
   if(price > ema50 && price > ema200 && ema50 > ema200) return 1;
   if(price < ema50 && price < ema200 && ema50 < ema200) return -1;
   return 0;
}

//--- Find recent swing high/low on H1 (lookback bars)
double FindSwingHigh(string symbol, int lookback = 20)
{
   double high = 0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyHigh(symbol, PERIOD_H1, 1, lookback, buf) > 0)
   {
      for(int i = 0; i < lookback; i++)
         high = MathMax(high, buf[i]);
   }
   return high;
}

double FindSwingLow(string symbol, int lookback = 20)
{
   double low = DBL_MAX;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyLow(symbol, PERIOD_H1, 1, lookback, buf) > 0)
   {
      for(int i = 0; i < lookback; i++)
         low = MathMin(low, buf[i]);
   }
   return (low == DBL_MAX) ? 0 : low;
}

//--- Check for liquidity sweep: price recently swept beyond key level then reversed
// For longs: price swept below recent swing low then closed back above it on M15
// For shorts: price swept above recent swing high then closed back below it on M15
bool CheckLiquiditySweep(string symbol, int bias, double &sweepLevel)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, PERIOD_M15, 0, 10, rates) < 10) return false;

   double pip = PipSize(symbol);

   if(bias == 1) // looking for long setup
   {
      double swLow = FindSwingLow(symbol, 30);
      if(swLow == 0) return false;
      // Check if any of last 5 candles swept below swLow (at least 1 pip)
      for(int i = 1; i <= 5; i++)
      {
         if(rates[i].low < swLow - pip)
         {
            // And current candle is closing back above swLow
            if(rates[0].close > swLow)
            {
               sweepLevel = swLow;
               return true;
            }
         }
      }
   }
   else if(bias == -1) // looking for short setup
   {
      double swHigh = FindSwingHigh(symbol, 30);
      if(swHigh == 0) return false;
      for(int i = 1; i <= 5; i++)
      {
         if(rates[i].high > swHigh + pip)
         {
            if(rates[0].close < swHigh)
            {
               sweepLevel = swHigh;
               return true;
            }
         }
      }
   }
   return false;
}

//--- Check for rejection candle on M15 (pin bar or engulfing)
bool CheckRejectionCandle(string symbol, int bias)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, PERIOD_M15, 1, 3, rates) < 3) return false;

   MqlRates c = rates[0]; // last closed candle
   MqlRates p = rates[1]; // previous candle
   double   body   = MathAbs(c.close - c.open);
   double   range  = c.high - c.low;
   if(range == 0) return false;
   double   upperWick = c.high - MathMax(c.open, c.close);
   double   lowerWick = MathMin(c.open, c.close) - c.low;

   // Pin bar for long: lower wick > 2/3 of range, small body
   if(bias == 1)
   {
      bool pinBar    = (lowerWick > range * 0.55) && (body < range * 0.35);
      bool engulfing = (c.close > c.open) && (c.close > p.open) && (c.open < p.close) && (body > MathAbs(p.close - p.open));
      return (pinBar || engulfing);
   }
   // Pin bar for short: upper wick > 2/3 of range, small body
   if(bias == -1)
   {
      bool pinBar    = (upperWick > range * 0.55) && (body < range * 0.35);
      bool engulfing = (c.close < c.open) && (c.close < p.open) && (c.open > p.close) && (body > MathAbs(p.close - p.open));
      return (pinBar || engulfing);
   }
   return false;
}

//--- Check RSI divergence or extreme on M15
bool CheckRSICondition(int rsiHandle, int bias)
{
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(rsiHandle, 0, 1, 5, rsi) < 5) return false;

   double current = rsi[0];
   double prev    = rsi[1];
   double prev2   = rsi[2];

   if(bias == 1)
   {
      // Oversold (RSI < 40) or bullish divergence (RSI making higher low while price lower low)
      if(current < 40.0) return true;
      // Simple divergence: RSI rising while we just had a sweep
      if(current > prev && prev < prev2) return true;
   }
   if(bias == -1)
   {
      // Overbought (RSI > 60) or bearish divergence
      if(current > 60.0) return true;
      if(current < prev && prev > prev2) return true;
   }
   return false;
}

//--- Calculate SL in pips based on pair-specific rules
double CalcSLPips(string symbol, int bias, double entryPrice)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   CopyRates(symbol, PERIOD_M15, 1, 1, rates);

   double candleRange = rates[0].high - rates[0].low;
   double pip         = PipSize(symbol);
   double slPips;

   if(bias == 1)
      slPips = (entryPrice - (rates[0].low - 3 * pip)) / pip;
   else
      slPips = ((rates[0].high + 3 * pip) - entryPrice) / pip;

   // GBPUSD: add 2 pip buffer
   if(symbol == "GBPUSD") slPips += 2.0;
   // Minimum 5 pips, maximum 30 pips
   slPips = MathMax(slPips, 5.0);
   slPips = MathMin(slPips, 30.0);
   return slPips;
}

//--- Main: scan all symbols for a valid signal
bool GetSignal(TradeSignal &sig)
{
   for(int i = 0; i < 3; i++)
   {
      string symbol = G_Symbols[i];

      // Spread check
      double spread = SpreadPips(symbol);
      if(spread > G_Config.maxSpreadPips)
      {
         // Print(StringFormat("[Signal] %s spread %.1f > %.1f, skip", symbol, spread, G_Config.maxSpreadPips));
         continue;
      }

      // H4 trend bias
      int bias = GetTrendBias(i);
      if(bias == 0) continue;

      // Liquidity sweep on M15
      double sweepLevel = 0;
      if(!CheckLiquiditySweep(symbol, bias, sweepLevel)) continue;

      // Rejection candle on M15
      if(!CheckRejectionCandle(symbol, bias)) continue;

      // RSI condition on M15
      if(!CheckRSICondition(G_HandleRSI_M15[i], bias)) continue;

      // All 3 conditions met — build signal
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double pip = PipSize(symbol);

      double entry = (bias == 1) ? ask : bid;
      double slPips = CalcSLPips(symbol, bias, entry);
      double tpPips = slPips * G_Config.riskRewardRatio;

      sig.type       = (bias == 1) ? SIGNAL_LONG : SIGNAL_SHORT;
      sig.symbol     = symbol;
      sig.entryPrice = entry;
      sig.slPips     = slPips;
      sig.slPrice    = (bias == 1) ? entry - slPips * pip : entry + slPips * pip;
      sig.tpPrice    = (bias == 1) ? entry + tpPips * pip : entry - tpPips * pip;

      Print(StringFormat("[Signal] %s %s Entry=%.5f SL=%.5f TP=%.5f SLpips=%.1f",
            symbol, (bias==1)?"LONG":"SHORT", entry, sig.slPrice, sig.tpPrice, slPips));
      return true;
   }
   return false;
}

#endif
