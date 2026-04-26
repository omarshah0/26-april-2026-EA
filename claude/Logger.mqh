//+------------------------------------------------------------------+
//| Logger.mqh - State persistence & trade log                        |
//+------------------------------------------------------------------+
#ifndef LOGGER_MQH
#define LOGGER_MQH

#include "Utils.mqh"

#define STATE_FILE "LondonNY_Strike\\state.json"
#define LOG_FILE   "LondonNY_Strike\\trades_log.csv"

//--- Bot state enum
enum BotStateEnum
{
   STATE_TRADING        = 0,
   STATE_COOLOFF_SHORT  = 1,  // single loss cooloff
   STATE_COOLOFF_LONG   = 2,  // 3-loss cooloff
   STATE_HALTED         = 3,  // max step exceeded, manual reset required
   STATE_DAILY_DONE     = 4   // max daily TPs hit
};

//--- Persistent state struct
struct BotState
{
   int          currentStep;
   int          dailyTPCount;
   int          consecutiveLosses;
   datetime     lastLossTime;
   datetime     lastTPTime;
   string       lastTradeResult;   // "WIN", "LOSS", "NONE"
   ulong        activeTicket;
   string       tradingDate;       // "YYYY-MM-DD"
   BotStateEnum botState;
   int          totalTrades;
   int          totalWins;
   int          totalLosses;
   double       totalPnL;
};

BotState G_State;

//--- Helper: escape JSON string
string JS(string v) { return "\"" + v + "\""; }
string JI(int v)    { return IntegerToString(v); }
string JD(double v) { return DoubleToString(v, 5); }
string JT(datetime t){ return IntegerToString((long)t); }

//--- Simple JSON value extractor for state file (mirrors Config::JsonGet)
string StateGetVal(const string &raw, string key)
{
   string search = "\"" + key + "\"";
   int pos = StringFind(raw, search);
   if(pos < 0) return "";
   pos += StringLen(search);
   while(pos < StringLen(raw) &&
         (StringGetCharacter(raw, pos) == ' ' ||
          StringGetCharacter(raw, pos) == ':' ||
          StringGetCharacter(raw, pos) == '\t')) pos++;
   if(pos >= StringLen(raw)) return "";

   ushort ch = StringGetCharacter(raw, pos);
   if(ch == '"')
   {
      pos++;
      string r = "";
      while(pos < StringLen(raw) && StringGetCharacter(raw, pos) != '"')
      {
         r += ShortToString(StringGetCharacter(raw, pos));
         pos++;
      }
      return r;
   }

   string r = "";
   while(pos < StringLen(raw))
   {
      ushort c = StringGetCharacter(raw, pos);
      if(c == ',' || c == '}' || c == '\n' || c == '\r') break;
      r += ShortToString(c);
      pos++;
   }
   StringTrimLeft(r);
   StringTrimRight(r);
   return r;
}

//--- Save state to file
bool SaveState()
{
   // ensure directory exists by attempting file creation
   int h = FileOpen(STATE_FILE, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("[Logger] Cannot save state: ", GetLastError());
      return false;
   }

   string stateStr = StringFormat(
      "{\n"
      "  \"CurrentStep\": %d,\n"
      "  \"DailyTPCount\": %d,\n"
      "  \"ConsecutiveLosses\": %d,\n"
      "  \"LastLossTime\": %d,\n"
      "  \"LastTPTime\": %d,\n"
      "  \"LastTradeResult\": \"%s\",\n"
      "  \"ActiveTicket\": %I64u,\n"
      "  \"TradingDate\": \"%s\",\n"
      "  \"BotState\": %d,\n"
      "  \"TotalTrades\": %d,\n"
      "  \"TotalWins\": %d,\n"
      "  \"TotalLosses\": %d,\n"
      "  \"TotalPnL\": %.5f\n"
      "}\n",
      G_State.currentStep,
      G_State.dailyTPCount,
      G_State.consecutiveLosses,
      (long)G_State.lastLossTime,
      (long)G_State.lastTPTime,
      G_State.lastTradeResult,
      G_State.activeTicket,
      G_State.tradingDate,
      (int)G_State.botState,
      G_State.totalTrades,
      G_State.totalWins,
      G_State.totalLosses,
      G_State.totalPnL
   );

   FileWriteString(h, stateStr);
   FileClose(h);
   return true;
}

//--- Load state from file
bool LoadState()
{
   if(!FileIsExist(STATE_FILE, FILE_COMMON))
   {
      Print("[Logger] No state file found, starting fresh.");
      G_State.currentStep       = 0;
      G_State.dailyTPCount      = 0;
      G_State.consecutiveLosses = 0;
      G_State.lastLossTime      = 0;
      G_State.lastTPTime        = 0;
      G_State.lastTradeResult   = "NONE";
      G_State.activeTicket      = 0;
      G_State.tradingDate       = TodayDateStr();
      G_State.botState          = STATE_TRADING;
      G_State.totalTrades       = 0;
      G_State.totalWins         = 0;
      G_State.totalLosses       = 0;
      G_State.totalPnL          = 0.0;
      SaveState();
      return true;
   }

   int h = FileOpen(STATE_FILE, FILE_READ | FILE_TXT | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("[Logger] Cannot read state: ", GetLastError());
      return false;
   }

   string raw = "";
   while(!FileIsEnding(h))
      raw += FileReadString(h) + "\n";
   FileClose(h);

   G_State.currentStep       = SafeInt(StateGetVal(raw, "CurrentStep"));
   G_State.dailyTPCount      = SafeInt(StateGetVal(raw, "DailyTPCount"));
   G_State.consecutiveLosses = SafeInt(StateGetVal(raw, "ConsecutiveLosses"));
   G_State.lastLossTime      = (datetime)SafeInt(StateGetVal(raw, "LastLossTime"));
   G_State.lastTPTime        = (datetime)SafeInt(StateGetVal(raw, "LastTPTime"));
   G_State.lastTradeResult   = StateGetVal(raw, "LastTradeResult");
   G_State.activeTicket      = (ulong)StringToInteger(StateGetVal(raw, "ActiveTicket"));
   G_State.tradingDate       = StateGetVal(raw, "TradingDate");
   G_State.botState          = (BotStateEnum)SafeInt(StateGetVal(raw, "BotState"));
   G_State.totalTrades       = SafeInt(StateGetVal(raw, "TotalTrades"));
   G_State.totalWins         = SafeInt(StateGetVal(raw, "TotalWins"));
   G_State.totalLosses       = SafeInt(StateGetVal(raw, "TotalLosses"));
   G_State.totalPnL          = SafeDouble(StateGetVal(raw, "TotalPnL"));

   // Check if we need daily reset
   string today = TodayDateStr();
   if(G_State.tradingDate != today)
   {
      Print("[Logger] New day detected. Resetting daily counters.");
      G_State.dailyTPCount      = 0;
      G_State.consecutiveLosses = 0;
      G_State.currentStep       = 0;
      G_State.tradingDate       = today;
      if(G_State.botState == STATE_DAILY_DONE || G_State.botState == STATE_COOLOFF_SHORT || G_State.botState == STATE_COOLOFF_LONG)
         G_State.botState = STATE_TRADING;
      SaveState();
   }

   Print(StringFormat("[Logger] State restored. Step=%d DailyTPs=%d ConsecLoss=%d BotState=%d Ticket=%I64u",
         G_State.currentStep, G_State.dailyTPCount, G_State.consecutiveLosses,
         (int)G_State.botState, G_State.activeTicket));
   return true;
}

//--- Reset state to fresh (manual reset after halt)
void ResetState()
{
   G_State.currentStep       = 0;
   G_State.dailyTPCount      = 0;
   G_State.consecutiveLosses = 0;
   G_State.lastLossTime      = 0;
   G_State.lastTPTime        = 0;
   G_State.lastTradeResult   = "NONE";
   G_State.activeTicket      = 0;
   G_State.tradingDate       = TodayDateStr();
   G_State.botState          = STATE_TRADING;
   SaveState();
   Print("[Logger] State reset to fresh.");
}

//--- Write CSV header if file doesn't exist
void EnsureLogHeader()
{
   if(!FileIsExist(LOG_FILE, FILE_COMMON))
   {
      int h = FileOpen(LOG_FILE, FILE_WRITE | FILE_TXT | FILE_COMMON);
      if(h == INVALID_HANDLE) return;
      FileWriteString(h, "DateTime,Symbol,Direction,Step,StepPct,Lots,Entry,SL,TP,Result,PnL,BalanceAfter,DailyTPCount,ConsecLoss\n");
      FileClose(h);
   }
}

//--- Append a trade record
void LogTrade(
   string symbol, string direction, int step, double stepPct,
   double lots, double entry, double sl, double tp,
   string result, double pnl, double balanceAfter,
   int dailyTPCount, int consecLoss)
{
   EnsureLogHeader();
   int h = FileOpen(LOG_FILE, FILE_READ | FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   string line = StringFormat("%s,%s,%s,%d,%.2f,%.2f,%.5f,%.5f,%.5f,%s,%.2f,%.2f,%d,%d\n",
      TimeToString(TimeGMT(), TIME_DATE | TIME_MINUTES),
      symbol, direction, step, stepPct, lots,
      entry, sl, tp, result, pnl, balanceAfter,
      dailyTPCount, consecLoss);
   FileWriteString(h, line);
   FileClose(h);
}

//--- Print current state summary to log
void PrintStateSummary()
{
   Print(StringFormat("[State] Step=%d(%.1f%%) DailyTP=%d ConsecLoss=%d BotState=%d Ticket=%I64u",
      G_State.currentStep,
      G_State.currentStep < 8 ? G_State.consecutiveLosses : 0,
      G_State.dailyTPCount,
      G_State.consecutiveLosses,
      (int)G_State.botState,
      G_State.activeTicket));
}

#endif
