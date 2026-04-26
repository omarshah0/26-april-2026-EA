# LondonNY Strike — MT5 Expert Advisor

A MetaTrader 5 Expert Advisor implementing the **London-NY Confluence Strike** strategy with a custom progressive martingale money management system. Trades EURUSD, GBPUSD, and USDJPY during defined UTC sessions.

---

## Table of Contents

1. [Strategy Overview](#strategy-overview)
2. [Money Management](#money-management)
3. [File Structure](#file-structure)
4. [Installation](#installation)
5. [Configuration](#configuration)
6. [Running Live](#running-live)
7. [Backtesting](#backtesting)
8. [Dashboard & Alerts](#dashboard--alerts)
9. [State & Crash Recovery](#state--crash-recovery)
10. [Manual Controls](#manual-controls)
11. [Risk Warning](#risk-warning)

---

## Strategy Overview

The EA uses a top-down confluence approach across three timeframes.

### Timeframe Stack

| Timeframe | Purpose |
|-----------|---------|
| H4 | Trend bias via EMA 50 & EMA 200 |
| H1 | Swing structure and key S/R levels |
| M15 | Liquidity sweep detection, entry trigger |
| M5 | Precision SL placement reference |

### Entry Conditions (all 3 required)

1. **H4 Trend Filter** — Price must be above both EMA 50 and EMA 200 for longs, below both for shorts. If price is between the EMAs, no trade is taken.
2. **Liquidity Sweep** — Price must have swept beyond a recent swing high or low on M15, trapping breakout traders, then reversed back inside the level.
3. **Rejection Candle** — A pin bar or engulfing candle must form on M15 at the sweep zone.
4. **RSI Confluence** — RSI-14 on M15 must be in an extreme zone (below 40 for longs, above 60 for shorts) or showing divergence.

### Pair-Specific Rules

| Pair | Character | Special Rule |
|------|-----------|-------------|
| EURUSD | Tightest spreads, most mechanical | Avoid 30 min before/after high-impact news |
| GBPUSD | Wide swings, volatile moves | SL widened by extra 2 pips |
| USDJPY | Trend-sticky, risk-sentiment driven | Checked last; requires clean H4 trend |

### Trading Sessions (UTC)

| Session | Pairs | Window |
|---------|-------|--------|
| Asian | USDJPY | 00:00 – 03:00 |
| London Open | EURUSD, GBPUSD | 07:00 – 10:00 |
| NY Open / Overlap | All three | 13:00 – 16:00 |

> The default bot window is **02:00 – 18:00 UTC**, covering all sessions. Adjust in config to restrict to specific sessions.

### Trade Management

- **Entry** — Market order at signal candle close
- **Stop Loss** — 3–5 pips beyond the sweep wick (pair-adjusted)
- **Take Profit** — SL distance × Risk-Reward Ratio (default 1.7)
- **Breakeven** — SL moved to entry + 2 pip buffer when price reaches halfway to TP
- **Max Spread** — Trade skipped if spread exceeds `MaxSpreadPips`

---

## Money Management

### Risk-Reward Ratio

Fixed at **1:1.7** — for every pip risked, 1.7 pips are targeted. Configurable via `RiskRewardRatio` in config.

### Martingale Progression

The EA uses a progressive risk escalation. On each consecutive loss the risk percentage increases. On any TP hit, risk resets back to Step 1.

| Step | Risk % | Triggered After |
|------|--------|----------------|
| 1 | 1.0% | Fresh start / after TP |
| 2 | 1.5% | 1 loss |
| 3 | 2.5% | 2 losses |
| 4 | 4.0% | 3 losses |
| 5 | 8.0% | 4 losses |
| 6 | 12.0% | 5 losses |
| 7 | 21.0% | 6 losses |
| 8 | 35.0% | 7 losses |

Steps and percentages are fully configurable. You can add or remove steps in `config.json` without recompiling.

### Lot Size Calculation

```
Lot Size = (Account Balance × Risk%) / (SL in pips × Pip Value per lot)
```

Lots are normalized to broker minimum, maximum, and step constraints automatically.

### Cooloff Rules

| Trigger | Wait Period |
|---------|-------------|
| Any single loss | 30 minutes (configurable) |
| 3 consecutive losses | 2 hours (configurable) |

### Daily Rules

- Maximum **2 TPs per day** — bot stops taking new trades after 2 wins (configurable)
- Only **1 open position at a time** — next trade only taken after current one closes
- All daily counters reset automatically at UTC midnight

---

## File Structure

```
MT5 Experts Folder
└── LondonNY_Strike/
    ├── LondonNY_Strike.mq5    ← Main EA (attach this to chart)
    ├── Config.mqh             ← Config loader (JSON parser)
    ├── Logger.mqh             ← State persistence & trade log
    ├── RiskManager.mqh        ← Martingale & position sizing
    ├── SignalEngine.mqh       ← Indicator logic & signal generation
    ├── TradeManager.mqh       ← Order execution & monitoring
    └── Utils.mqh              ← Time, pip, and math helpers

MT5 Common Files Folder
└── LondonNY_Strike/
    ├── config.json            ← Live-editable configuration
    ├── state.json             ← Auto-generated persistent state
    └── trades_log.csv         ← Auto-generated trade history
```

---

## Installation

### Step 1 — Locate MT5 Data Folder

Inside MetaTrader 5: **File → Open Data Folder**

### Step 2 — Copy EA Files

Copy the entire `LondonNY_Strike/` folder containing all `.mq5` and `.mqh` files into:

```
[DataFolder]\MQL5\Experts\LondonNY_Strike\
```

### Step 3 — Copy Config File

Create this folder if it does not exist:

```
C:\Users\[YourName]\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LondonNY_Strike\
```

Copy `config.json` into that folder.

### Step 4 — Compile

1. Open **MetaEditor** (press F4 inside MT5)
2. Navigate to your EA folder in the file tree
3. Open `LondonNY_Strike.mq5`
4. Press **F7** to compile
5. Confirm **0 errors** in the Errors tab

### Step 5 — Attach to Chart

1. Open an **EURUSD H1** chart in MT5
2. In the Navigator panel, find `LondonNY_Strike` under Expert Advisors
3. Drag it onto the chart
4. In the EA dialog, check:
   - ✅ Allow live trading
   - ✅ Allow DLL imports
5. Click OK

The chart dashboard should appear in the top-left corner confirming the EA is running.

---

## Configuration

All settings live in `config.json` in the Common Files folder. The EA reloads this file on every new M15 bar — **no recompile needed** for any change.

### Full Config Reference

```json
{
  "BotEnabled": true,
  "StartHour": 2,
  "StartMinute": 0,
  "StopHour": 18,
  "StopMinute": 0,
  "MaxDailyTPs": 2,
  "CooloffSingleLossMin": 30,
  "CooloffConsecLossMin": 120,
  "ConsecLossThreshold": 3,
  "RiskRewardRatio": 1.7,
  "MartingaleSteps": [1.0, 1.5, 2.5, 4.0, 8.0, 12.0, 21.0, 35.0],
  "MaxSpreadPips": 2.0,
  "NewsBufferMinutes": 30,
  "BalanceSafetyThreshold": 100.0,
  "EnablePushNotify": true
}
```

### Parameter Descriptions

| Parameter | Type | Description |
|-----------|------|-------------|
| `BotEnabled` | bool | Master kill switch. Set to `false` to stop all new trades instantly |
| `StartHour` | int | UTC hour to begin scanning for trades (0–23) |
| `StartMinute` | int | UTC minute offset for start time |
| `StopHour` | int | UTC hour to stop scanning for trades |
| `StopMinute` | int | UTC minute offset for stop time |
| `MaxDailyTPs` | int | Stop trading after this many wins in one day |
| `CooloffSingleLossMin` | int | Minutes to wait after any single loss |
| `CooloffConsecLossMin` | int | Minutes to wait after N consecutive losses |
| `ConsecLossThreshold` | int | Number of consecutive losses that triggers long cooloff |
| `RiskRewardRatio` | float | TP distance = SL distance × this value |
| `MartingaleSteps` | array | Risk percentage per step. Add or remove values freely |
| `MaxSpreadPips` | float | Skip trade if current spread exceeds this value |
| `NewsBufferMinutes` | int | Reference only — manual reminder; no auto news filter |
| `BalanceSafetyThreshold` | float | Halt bot if account balance drops below this amount |
| `EnablePushNotify` | bool | Send MT5 push notifications on trade events |

### Common Config Adjustments

**Disable the bot instantly (without removing from chart):**
```json
"BotEnabled": false
```

**Trade London session only:**
```json
"StartHour": 7,
"StartMinute": 0,
"StopHour": 11,
"StopMinute": 0
```

**Add a 9th martingale step:**
```json
"MartingaleSteps": [1.0, 1.5, 2.5, 4.0, 8.0, 12.0, 21.0, 35.0, 50.0]
```

**Remove martingale entirely (flat 1% risk every trade):**
```json
"MartingaleSteps": [1.0]
```

**Shorten cooloff periods:**
```json
"CooloffSingleLossMin": 15,
"CooloffConsecLossMin": 60
```

---

## Running Live

### Recommended Account Type

- **ECN or Raw Spread account** — tighter spreads improve signal quality
- **Leverage** — 1:100 minimum recommended for proper lot sizing at small balances
- **Account currency** — USD preferred; other currencies work but verify pip value calculations

### Broker Requirements

- MT5 compatible broker
- EURUSD, GBPUSD, USDJPY available with 5-digit pricing
- Market execution (not dealing desk)

### Before Going Live

1. Run a backtest over at least 6 months of data (see Backtesting section)
2. Run on a **demo account** for at least 2–4 weeks
3. Verify push notifications are working (MT5 app on phone required)
4. Confirm the chart dashboard is displaying correctly
5. Check `trades_log.csv` is being written after first trade

### Monitoring

The EA is designed to run 24/7 on a VPS. However it only trades within the configured UTC window. You can safely leave it running overnight — it will not take trades outside the window.

---

## Backtesting

### Strategy Tester Settings

| Setting | Recommended Value |
|---------|------------------|
| Expert Advisor | LondonNY_Strike |
| Symbol | EURUSD |
| Period | M15 |
| Model | Every Tick Based on Real Ticks |
| Spread | Current (or fixed at 10–15 points for ECN) |
| Date Range | Minimum 6 months, ideally 1–2 years |
| Deposit | Your intended starting balance |
| Leverage | Match your live account |
| Optimization | Not required for initial test |

### How to Run

1. Press **Ctrl+R** in MT5 to open Strategy Tester
2. Select `Experts\LondonNY_Strike\LondonNY_Strike` from the dropdown
3. Configure the settings above
4. Click **Start**

### Backtest Limitations

| Limitation | Explanation |
|------------|-------------|
| File I/O | State persistence to `state.json` is bypassed in tester sandbox. Martingale and risk logic still work correctly in memory |
| Multi-symbol | MT5 Strategy Tester runs on one chart symbol. The EA will still scan all 3 pairs using historical data if downloaded |
| News filter | The `NewsBufferMinutes` setting is a manual reference — no economic calendar feed is connected |
| Spread simulation | Use real tick data for most accurate spread modeling |

### Downloading Tick Data for Backtesting

In MT5: **Tools → History Center** → Select each pair (EURUSD, GBPUSD, USDJPY) → M15 → Download. Ensure you have at least 1 year of M15 data before running the tester.

### Reading Backtest Results

After the test completes, check the **Report** tab for:

- Total net profit
- Profit factor (aim for above 1.3)
- Maximum drawdown (compare against martingale exposure)
- Win rate (strategy typically runs 45–55%)
- Consecutive losses (validates your martingale step count)

---

## Dashboard & Alerts

### Chart Dashboard

A live status box is displayed in the top-left corner of the chart:

```
╔══════════════════════════╗
║  LondonNY Strike Bot     ║
╠══════════════════════════╣
║ Bot:     ENABLED         ║
║ State:   TRADING         ║
║ Step 1 (1.0%)            ║
║ Daily TPs: 1 / 2         ║
║ Consec Loss: 0           ║
║ Ticket: 12345678         ║
║ Window: 02:00 - 18:00 UTC║
║ Total P/L: 245.80        ║
╚══════════════════════════╝
```

### Push Notifications

Requires MT5 mobile app installed and linked to your account (Tools → Options → Notifications in desktop MT5).

Notifications are sent on:
- Trade opened (symbol, direction, step, lots, entry price)
- TP hit (step reset, daily TP count)
- SL hit (new step, cooloff duration, consecutive loss count)
- Daily target reached
- Martingale exhausted (critical — requires manual reset)
- Balance below safety threshold

Set `"EnablePushNotify": false` in config to disable all notifications.

---

## State & Crash Recovery

The EA writes `state.json` to disk on every state change. If MT5 crashes, the VPS reboots, or your internet drops:

1. MT5 restarts and reattaches the EA automatically (if set to auto-start)
2. On `OnInit()`, the EA reads `state.json` and restores:
   - Current martingale step
   - Daily TP count
   - Consecutive loss count
   - Active trade ticket (re-links to open position)
   - Cooloff timer (checks if cooloff has already expired)

### Trade Log

Every closed trade is appended to `trades_log.csv` with full detail:

```
DateTime, Symbol, Direction, Step, StepPct, Lots, Entry, SL, TP, Result, PnL, BalanceAfter, DailyTPCount, ConsecLoss
```

This file can be opened in Excel for performance analysis.

### Daily Reset

At UTC midnight the EA automatically detects the date change and resets:
- Daily TP counter → 0
- Consecutive loss counter → 0
- Martingale step → 0 (Step 1)
- Bot state → TRADING

The cumulative stats (TotalTrades, TotalWins, TotalLosses, TotalPnL) are never reset — they persist across days.

---

## Manual Controls

### Kill Switch (Immediate)

Edit `config.json` and set `"BotEnabled": false`. The EA checks this on every new M15 bar (within seconds during active market).

### Reset After Martingale Exhaustion

If all martingale steps are lost the EA enters **HALTED** state and stops trading. To reset:

- Press the **R key** on the chart where the EA is attached

Or manually edit `state.json` and set `"CurrentStep": 0` and `"BotState": 0`, then wait for the next tick.

### Adjust Steps Mid-Session

Edit `MartingaleSteps` in `config.json` and save. The EA picks up the new step array on the next M15 bar. If you reduce the number of steps below the current step counter, the EA will halt safely.

---

## Risk Warning

**This EA uses martingale-style position sizing. Consecutive losses cause exponentially larger positions. At Step 8, a single trade risks 35% of your account balance.**

Key risks to understand before deploying:

- A streak of 8 consecutive losses will exhaust all martingale steps and halt the bot
- The 1:1.7 RR partially compensates for the win rate required, but does not eliminate drawdown risk
- Past backtest performance does not guarantee future results
- Always test on a demo account before live deployment
- Never risk money you cannot afford to lose
- Monitor the bot daily, especially the consecutive loss counter

The `BalanceSafetyThreshold` config provides a hard floor — set this to the minimum balance at which you want the bot to stop trading automatically.
