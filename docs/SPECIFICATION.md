# RoboAU 1 specification
Status: owner-approved scope, 2026-11-24. Implementation acceptance pending.

## Provenance
Reference: kolemasakar/K_AI-Trading-System commit 2752077, backtests/multi_strategy_r2/strategy_a_contract.json, backtests/multi_strategy_r3/r3_strategy_contract.json, tools/run_multi_strategy_r2_strategy_a_baseline.py and tools/run_mt4_strategy_a_frozen_outcomes.py. October result report not independently recovered. No separate gold profitability study required.

## Signal
XAUUSD only. Evaluate each new M5 bar using closed chronological windows D1=60, H1=200, M5=300. EMA20 and EMA50 seeded by first period SMA; alpha=2/(n+1). BUY: close>EMA20>EMA50 and EMA20 exceeds value five bars earlier. SELL inverse.
H1 ATR14: average first 14 TR, then Wilder recursion. TR=max(H-L,abs(H-prevClose),abs(L-prevClose)). Latest closed H1 is continuation candidate. Search breakout newest first within last 12 bars, at least two bars before continuation. Level=max high or min low of preceding 20 bars. Breakout close strictly beyond level by 0.10 breakout ATR; directional body. Latest valid retest within next six bars, before continuation: BUY low within level +/-0.15 breakout ATR, close above level; SELL high within band, close below level. Continuation BUY close above retest high, own open and level; SELL inverse. Volume ratio vs preceding 20-bar median (1.5) and impulse body/range (60%) diagnostics only. No D1 ATR reachability gate in verified research path.
M5 confirmation latest closed candle starting at or after H1 continuation close. BUY close above previous five highs and own open, close location (C-L)/(H-L)>=0.70; SELL inverse and location<=0.30. Zero range invalid. Entry next M5 open in research; first available quote in MT4, differences logged. Setup identity symbol/direction/breakout/retest/continuation; durable deduplication required.

## Exit and risk
BUY SL=retest low-0.10 continuation ATR; SELL SL=retest high+0.10 continuation ATR. R=positive distance from actual fill to SL; TP=fill +/-3R. No trailing, partial close or timed exit. Historical model 2016 M5 bars, unresolved censored, STOP_FIRST collision, fees 5 bps and adverse slippage 2 bps per side. Broker costs are observed, not simulated.
GerchikCo DEMO initially; risk ceilings 2% per trade, 5% daily, 10% aggregate. Exact accounting and recovery validation required. Round lot down, check margin and broker limits. Physical SL/TP required. AllowLiveTrading defaults false, owner-controlled; off blocks new entries, retains existing protection. Unknown mode fails closed. Release requires separate acceptance. No credentials in public repo.

## Architecture
One standalone MQL4 EA. No Bridge, Python runtime, SQLite or level indicator dependency. Initial increment analytical only. No execution in initial build.
