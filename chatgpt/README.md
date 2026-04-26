# Forex Martingale EA (MT5)

## Overview
This project is a MetaTrader 5 Expert Advisor (EA) designed for automated intraday trading on:

- EURUSD  
- GBPUSD  
- USDJPY  

The system combines a session-based breakout strategy with a controlled martingale risk model and strict trade management rules.

---

## Core Features

- Single trade at a time  
- Fixed Risk-to-Reward ratio (1:1.7)  
- Configurable martingale progression  
- Session-based trading (UTC controlled)  
- Cooldown system after losses  
- Daily profit cap (stop after 2 wins)  
- Persistent state handling (planned)  
- Modular architecture for future upgrades  

---

## Trading Logic

### Strategy Flow
1. Detect trade signal (strategy module)  
2. Calculate position size based on martingale step  
3. Execute trade with SL and TP  
4. Wait for outcome (no overlapping trades)  
5. Adjust step based on result:  
   - Win → Reset to step 1  
   - Loss → Move to next step  

---

## Risk Management

### Risk-to-Reward
- Fixed RR: **1 : 1.7**

### Martingale Steps (Default)
```
[1, 1.5, 2.5, 4, 8, 12, 21, 35]
```

### Rules
- Each loss increases risk to next level  
- Any TP resets sequence  
- Max step configurable  

---

## Cooldown System

- After 1 loss → 30 minutes cooldown  
- After 3 consecutive losses → 2 hours cooldown  
- Cooldown resets after a winning trade  

---

## Trading Session

- Start: **02:00 UTC**  
- End: **18:00 UTC**  
- Trades are only opened within this window  
- Active trades are allowed to finish outside session  

---

## Daily Limits

- Maximum **2 Take Profits per day**  
- Trading stops for the day after reaching limit  
- Resets at new UTC day  

---

## Configuration

All parameters are configurable via EA inputs:

### General
- Enable/Disable bot  
- Trading pairs  
- Session timing  

### Risk
- RR ratio  
- Martingale steps  
- Max steps  

### Cooldown
- After loss delay  
- After consecutive losses delay  

### Limits
- Max trades per day  
- Daily TP cap  

---

## Installation

1. Open MetaTrader 5  
2. Go to:  
   ```
   File → Open Data Folder → MQL5 → Experts
   ```  
3. Place EA file (.mq5) inside  
4. Restart MT5  
5. Attach EA to chart  

---

## How to Run

1. Open chart (EURUSD, GBPUSD, or USDJPY)  
2. Drag EA onto chart  
3. Enable:  
   - AutoTrading  
   - Allow Algo Trading  
4. Adjust inputs as needed  

---

## Backtesting

### Steps
1. Open Strategy Tester (Ctrl + R)  
2. Select EA  
3. Choose:  
   - Symbol: One pair at a time  
   - Model: Every Tick  
   - Timeframe: M5 recommended  
4. Set historical period (1–2 years minimum)  
5. Run test  

---

## Metrics to Evaluate

- Max drawdown ⚠️  
- Consecutive losses  
- Profit factor  
- Equity curve stability  

---

## Important Risk Warning

This EA uses an aggressive martingale-based position sizing model.

- Risk increases significantly after consecutive losses  
- Final steps may risk a large portion of the account  
- Extended losing streaks can lead to major drawdowns  

**Use with caution and proper capital management.**

---

## Future Improvements

- Real liquidity sweep detection logic  
- News filter integration  
- Spread filter  
- Trade dashboard (UI panel)  
- Telegram notifications  
- VPS deployment guide  
- Persistent state file (crash recovery)  

---

## Disclaimer

This software is for educational and experimental purposes only.  
Trading forex involves significant risk and may not be suitable for all investors.