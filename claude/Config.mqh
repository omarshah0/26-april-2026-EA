//+------------------------------------------------------------------+
//| Config.mqh - External JSON config loader                          |
//+------------------------------------------------------------------+
#ifndef CONFIG_MQH
#define CONFIG_MQH

#include "Utils.mqh"

#define CONFIG_FILE "LondonNY_Strike\\config.json"
#define MAX_STEPS   10

//--- Global config struct
struct BotConfig
{
   bool     botEnabled;
   int      startHour;
   int      startMinute;
   int      stopHour;
   int      stopMinute;
   int      maxDailyTPs;
   int      cooloffSingleLossMin;
   int      cooloffConsecLossMin;
   int      consecLossThreshold;
   double   riskRewardRatio;
   int      stepCount;
   double   stepPercent[MAX_STEPS];
   double   maxSpreadPips;
   int      newsBufferMinutes;
   double   balanceSafetyThreshold;
   bool     enablePushNotify;
};

BotConfig G_Config;

//--- Simple JSON value extractor (key:"value" or key:value)
string JsonGet(string &json, string key)
{
   string search = "\"" + key + "\"";
   int pos = StringFind(json, search);
   if(pos < 0) return "";

   pos += StringLen(search);
   // skip whitespace and colon
   while(pos < StringLen(json) &&
         (StringGetCharacter(json, pos) == ' '  ||
          StringGetCharacter(json, pos) == '\t' ||
          StringGetCharacter(json, pos) == ':')) pos++;

   if(pos >= StringLen(json)) return "";

   ushort ch = StringGetCharacter(json, pos);

   // quoted string
   if(ch == '"')
   {
      pos++;
      string result = "";
      while(pos < StringLen(json) && StringGetCharacter(json, pos) != '"')
      {
         result += ShortToString(StringGetCharacter(json, pos));
         pos++;
      }
      return result;
   }

   // array — return raw content between [ ]
   if(ch == '[')
   {
      int depth = 0;
      string result = "";
      while(pos < StringLen(json))
      {
         ushort c = StringGetCharacter(json, pos);
         result += ShortToString(c);
         if(c == '[') depth++;
         if(c == ']') { depth--; if(depth == 0) break; }
         pos++;
      }
      result += "]";
      return result;
   }

   // number or boolean — read until delimiter
   string result = "";
   while(pos < StringLen(json))
   {
      ushort c = StringGetCharacter(json, pos);
      if(c == ',' || c == '}' || c == ']' || c == '\n' || c == '\r') break;
      result += ShortToString(c);
      pos++;
   }
   return StringTrimRight(StringTrimLeft(result));
}

//--- Parse array of doubles from "[1.0, 1.5, 2.5]" format
int ParseDoubleArray(string raw, double &arr[], int maxSize)
{
   int count = 0;
   // strip brackets
   StringReplace(raw, "[", "");
   StringReplace(raw, "]", "");
   string parts[];
   int n = StringSplit(raw, ',', parts);
   for(int i = 0; i < n && i < maxSize; i++)
   {
      string v = StringTrimRight(StringTrimLeft(parts[i]));
      if(StringLen(v) > 0)
      {
         arr[count++] = StringToDouble(v);
      }
   }
   return count;
}

//--- Write default config file if not present
void WriteDefaultConfig()
{
   int h = FileOpen(CONFIG_FILE, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("[Config] Cannot create default config: ", GetLastError());
      return;
   }
   FileWriteString(h,
      "{\n"
      "  \"BotEnabled\": true,\n"
      "  \"StartHour\": 2,\n"
      "  \"StartMinute\": 0,\n"
      "  \"StopHour\": 18,\n"
      "  \"StopMinute\": 0,\n"
      "  \"MaxDailyTPs\": 2,\n"
      "  \"CooloffSingleLossMin\": 30,\n"
      "  \"CooloffConsecLossMin\": 120,\n"
      "  \"ConsecLossThreshold\": 3,\n"
      "  \"RiskRewardRatio\": 1.7,\n"
      "  \"MartingaleSteps\": [1.0, 1.5, 2.5, 4.0, 8.0, 12.0, 21.0, 35.0],\n"
      "  \"MaxSpreadPips\": 2.0,\n"
      "  \"NewsBufferMinutes\": 30,\n"
      "  \"BalanceSafetyThreshold\": 100.0,\n"
      "  \"EnablePushNotify\": true\n"
      "}\n"
   );
   FileClose(h);
   Print("[Config] Default config written to: ", CONFIG_FILE);
}

//--- Load config from file
bool LoadConfig()
{
   if(!FileIsExist(CONFIG_FILE, FILE_COMMON))
   {
      Print("[Config] Config file not found, writing defaults.");
      WriteDefaultConfig();
   }

   int h = FileOpen(CONFIG_FILE, FILE_READ | FILE_TXT | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("[Config] Failed to open config file: ", GetLastError());
      return false;
   }

   string raw = "";
   while(!FileIsEnding(h))
      raw += FileReadString(h) + "\n";
   FileClose(h);

   // strip comments (lines starting with //)
   string lines[];
   int n = StringSplit(raw, '\n', lines);
   raw = "";
   for(int i = 0; i < n; i++)
   {
      string l = StringTrimLeft(lines[i]);
      if(StringFind(l, "//") == 0) continue;
      raw += lines[i] + "\n";
   }

   G_Config.botEnabled              = (JsonGet(raw, "BotEnabled") == "true");
   G_Config.startHour               = SafeInt(JsonGet(raw, "StartHour"), 2);
   G_Config.startMinute             = SafeInt(JsonGet(raw, "StartMinute"), 0);
   G_Config.stopHour                = SafeInt(JsonGet(raw, "StopHour"), 18);
   G_Config.stopMinute              = SafeInt(JsonGet(raw, "StopMinute"), 0);
   G_Config.maxDailyTPs             = SafeInt(JsonGet(raw, "MaxDailyTPs"), 2);
   G_Config.cooloffSingleLossMin    = SafeInt(JsonGet(raw, "CooloffSingleLossMin"), 30);
   G_Config.cooloffConsecLossMin    = SafeInt(JsonGet(raw, "CooloffConsecLossMin"), 120);
   G_Config.consecLossThreshold     = SafeInt(JsonGet(raw, "ConsecLossThreshold"), 3);
   G_Config.riskRewardRatio         = SafeDouble(JsonGet(raw, "RiskRewardRatio"), 1.7);
   G_Config.maxSpreadPips           = SafeDouble(JsonGet(raw, "MaxSpreadPips"), 2.0);
   G_Config.newsBufferMinutes       = SafeInt(JsonGet(raw, "NewsBufferMinutes"), 30);
   G_Config.balanceSafetyThreshold  = SafeDouble(JsonGet(raw, "BalanceSafetyThreshold"), 100.0);
   G_Config.enablePushNotify        = (JsonGet(raw, "EnablePushNotify") == "true");

   string stepsRaw = JsonGet(raw, "MartingaleSteps");
   G_Config.stepCount = ParseDoubleArray(stepsRaw, G_Config.stepPercent, MAX_STEPS);

   if(G_Config.stepCount == 0)
   {
      // fallback defaults
      double def[] = {1.0, 1.5, 2.5, 4.0, 8.0, 12.0, 21.0, 35.0};
      G_Config.stepCount = 8;
      for(int i = 0; i < 8; i++) G_Config.stepPercent[i] = def[i];
   }

   Print(StringFormat("[Config] Loaded. BotEnabled=%s Steps=%d Window=%02d:%02d-%02d:%02d UTC",
         G_Config.botEnabled ? "YES" : "NO",
         G_Config.stepCount,
         G_Config.startHour, G_Config.startMinute,
         G_Config.stopHour,  G_Config.stopMinute));
   return true;
}

#endif
