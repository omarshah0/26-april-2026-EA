//+------------------------------------------------------------------+
//| Utils.mqh - Helper utilities                                      |
//+------------------------------------------------------------------+
#ifndef UTILS_MQH
#define UTILS_MQH

//--- Time-of-day helpers are stubbed out: the bot is gated only by the
//--- BotEnabled flag in config.json. Flip BotEnabled to true/false to
//--- run/pause the bot manually. The trading-window inputs are ignored.
int      UtcHour()   { return 0; }
int      UtcMinute() { return 0; }
datetime UtcNow()    { return TimeGMT(); }

int  ToMinutes(int hour, int minute) { return hour * 60 + minute; }
int  UtcNowMinutes()                 { return 0; }

//--- Always inside the window — manual control via BotEnabled
bool IsWithinWindow(int startHour, int startMin, int stopHour, int stopMin)
{
   return true;
}

//--- Get pip size for a symbol
double PipSize(string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   // 5-digit brokers: pip = 10 * point; 3-digit (JPY): pip = 10 * point
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
}

//--- Get current spread in pips
double SpreadPips(string symbol)
{
   long spreadPoints = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   return spreadPoints * SymbolInfoDouble(symbol, SYMBOL_POINT) / PipSize(symbol);
}

//--- Normalize lot to broker constraints
double NormalizeLot(string symbol, double lots)
{
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   return NormalizeDouble(lots, 2);
}

//--- Get date string for today (UTC)
string TodayDateStr()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);
}

//--- Check if two timestamps are on the same UTC date
bool SameDay(datetime t1, datetime t2)
{
   MqlDateTime d1, d2;
   TimeToStruct(t1, d1);
   TimeToStruct(t2, d2);
   return (d1.year == d2.year && d1.mon == d2.mon && d1.day == d2.day);
}

//--- Minutes elapsed since a timestamp
int MinutesElapsed(datetime since)
{
   return (int)((UtcNow() - since) / 60);
}

//--- Safe string to double
double SafeDouble(string val, double def = 0.0)
{
   if(StringLen(val) == 0) return def;
   return StringToDouble(val);
}

//--- Safe string to int
int SafeInt(string val, int def = 0)
{
   if(StringLen(val) == 0) return def;
   return (int)StringToInteger(val);
}

#endif
