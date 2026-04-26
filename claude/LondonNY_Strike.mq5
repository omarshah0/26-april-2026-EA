//+------------------------------------------------------------------+
//| LondonNY_Strike.mq5                                              |
//| London-NY Confluence Strike EA                                   |
//| Strategy: H4 EMA trend + M15 liquidity sweep + RSI confluence    |
//| Money Mgmt: Custom Martingale with 1:1.7 RR                      |
//+------------------------------------------------------------------+
#property copyright   "LondonNY Strike Bot"
#property version     "1.00"
#property description "London-NY Confluence Strike with Custom Martingale"

#include "Utils.mqh"
#include "Config.mqh"
#include "Logger.mqh"
#include "RiskManager.mqh"
#include "SignalEngine.mqh"
#include "TradeManager.mqh"

//--- Input: path override (leave blank for default)
input string InpConfigPath = ""; // Config path override (leave blank)

//--- Tracking for config hot-reload
datetime G_LastBarTime  = 0;
datetime G_LastConfigLoad = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=================================================");
   Print("[EA] LondonNY Strike v1.00 initializing...");
   Print("=================================================");

   // Create directory structure
   if(!FolderCreate("LondonNY_Strike", FILE_COMMON))
   {
      int err = GetLastError();
      if(err != 5018) // 5018 = already exists, that's fine
         Print("[EA] Warning: could not create folder. Error: ", err);
   }

   // Load config
   if(!LoadConfig())
   {
      Print("[EA] Failed to load config. Using defaults.");
   }

   // Load/restore state
   if(!LoadState())
   {
      Print("[EA] Failed to load state. Starting fresh.");
   }

   // Initialize indicators
   if(!InitSignalEngine())
   {
      Print("[EA] Signal engine init failed!");
      return INIT_FAILED;
   }

   // Initialize trade manager (restores open position if any)
   InitTradeManager();

   G_LastConfigLoad = UtcNow();

   Print(StringFormat("[EA] Init complete. Bot=%s Window=%02d:%02d-%02d:%02d UTC Steps=%d",
         G_Config.botEnabled ? "ENABLED" : "DISABLED",
         G_Config.startHour, G_Config.startMinute,
         G_Config.stopHour,  G_Config.stopMinute,
         G_Config.stepCount));

   // Display status on chart
   UpdateChartComment();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeinitSignalEngine();
   SaveState();
   Comment(""); // clear chart comment
   Print("[EA] Deinit. State saved.");
}

//+------------------------------------------------------------------+
//| OnTick - main loop                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Hot reload config on new M15 bar
   datetime barTime = iTime(_Symbol, PERIOD_M15, 0);
   if(barTime != G_LastBarTime)
   {
      G_LastBarTime = barTime;
      LoadConfig();
      UpdateChartComment();
   }

   // Step 1: Bot enabled check
   if(!G_Config.botEnabled)
   {
      static datetime lastMsg = 0;
      if(UtcNow() - lastMsg > 60)
      {
         Print("[EA] Bot disabled via config.");
         lastMsg = UtcNow();
      }
      return;
   }

   // Step 2: Time window check
   bool inWindow = IsWithinWindow(G_Config.startHour, G_Config.startMinute,
                                   G_Config.stopHour,  G_Config.stopMinute);

   // Step 3: Monitor open position (runs even outside window)
   if(G_HasActiveTrade)
   {
      int result = MonitorTrade();
      if(result == 2) { OnTPHit(); UpdateChartComment(); return; }
      if(result == 3) { OnSLHit(); UpdateChartComment(); return; }
      if(result == 1) return; // still open, nothing to do
   }

   // Step 4: Outside trading window → do nothing
   if(!inWindow) return;

   // Step 5: Halted state
   if(G_State.botState == STATE_HALTED)
   {
      static datetime lastHaltMsg = 0;
      if(UtcNow() - lastHaltMsg > 300)
      {
         Print("[EA] Bot HALTED. All martingale steps exhausted. Manual reset required.");
         lastHaltMsg = UtcNow();
      }
      return;
   }

   // Step 6: Daily TP target reached
   if(G_State.botState == STATE_DAILY_DONE)
   {
      static datetime lastDoneMsg = 0;
      if(UtcNow() - lastDoneMsg > 300)
      {
         Print("[EA] Daily TP target reached. Done for today.");
         lastDoneMsg = UtcNow();
      }
      return;
   }

   // Step 7: Cooloff check
   if(G_State.botState == STATE_COOLOFF_SHORT || G_State.botState == STATE_COOLOFF_LONG)
   {
      if(!IsCooloffExpired()) return;
      // IsCooloffExpired sets state back to TRADING when done
   }

   // Step 8: Balance safety check
   if(!IsBalanceSafe()) return;

   // Step 9: Look for signal
   TradeSignal sig;
   if(GetSignal(sig))
   {
      OpenTrade(sig);
      UpdateChartComment();
   }
}

//+------------------------------------------------------------------+
//| Chart comment — live dashboard                                    |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
   string step    = G_State.currentStep < G_Config.stepCount
                    ? StringFormat("Step %d (%.1f%%)", G_State.currentStep + 1, G_Config.stepPercent[G_State.currentStep])
                    : "HALTED";
   string stateStr;
   switch(G_State.botState)
   {
      case STATE_TRADING:       stateStr = "TRADING";       break;
      case STATE_COOLOFF_SHORT: stateStr = StringFormat("COOLOFF %dmin", G_Config.cooloffSingleLossMin); break;
      case STATE_COOLOFF_LONG:  stateStr = StringFormat("COOLOFF %dmin", G_Config.cooloffConsecLossMin); break;
      case STATE_HALTED:        stateStr = "HALTED!";       break;
      case STATE_DAILY_DONE:    stateStr = "DAILY DONE";    break;
   }

   string comment = StringFormat(
      "╔══════════════════════════╗\n"
      "║  LondonNY Strike Bot     ║\n"
      "╠══════════════════════════╣\n"
      "║ Bot:     %-15s  ║\n"
      "║ State:   %-15s  ║\n"
      "║ %s             ║\n"
      "║ Daily TPs: %d / %d         ║\n"
      "║ Consec Loss: %d            ║\n"
      "║ Ticket: %-17I64u║\n"
      "║ Window: %02d:%02d - %02d:%02d UTC ║\n"
      "║ Total P/L: %-12.2f  ║\n"
      "╚══════════════════════════╝",
      G_Config.botEnabled ? "ENABLED" : "DISABLED",
      stateStr,
      step,
      G_State.dailyTPCount, G_Config.maxDailyTPs,
      G_State.consecutiveLosses,
      G_State.activeTicket,
      G_Config.startHour, G_Config.startMinute,
      G_Config.stopHour,  G_Config.stopMinute,
      G_State.totalPnL
   );
   Comment(comment);
}

//+------------------------------------------------------------------+
//| Manual reset via chart button or script                           |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN && lparam == 82) // 'R' key
   {
      if(G_State.botState == STATE_HALTED)
      {
         ResetState();
         Print("[EA] Manual reset triggered via 'R' key.");
         UpdateChartComment();
      }
   }
}
//+------------------------------------------------------------------+
