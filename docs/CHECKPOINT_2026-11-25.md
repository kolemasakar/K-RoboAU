# RoboAU 1 checkpoint - 2026-11-25

## Approved configuration
XAUUSD M5, Strategy A, 5% trade risk, 10% daily risk when available, 10% aggregate risk, structural stop distance <=50 USD, fixed TP 3R, Friday market exit five minutes before session close, no trade-age limit. BUY and SELL. DEMO only for initial release. Both enable inputs default false; source execution lock active.

## Evidence
- MQL4 signal replay: 145 unique setups, 116 BUY, 29 SELL.
- Original discovery: 56/56 continuation identities and outcome classifications match with original five-minute entry delay and 168-hour/partition censoring. Original result +42.140516R, PF 2.651358, 10 censored. Without censoring and original costs, discovery +6.923933R.
- Independent weekend-close/SL cap simulation: 90 resolved trades, 34 TP, 43 SL, 13 weekend exits; +71.439523R, PF 2.633026, expectancy +0.793772R. No cap: 145 trades, +78.711923R, PF 2.098006.
- Portfolio risk matrix: 80/80 completed; five starting balances, four trade-risk settings, four daily settings. Selected 5/10/10 configuration on historical starting balance 1189.05 USD: 45 trades, net +1536.49 USD, ending 2725.54 USD, return 129.22%, PF 1.731, maximum bar-close equity drawdown 27.34%. Historical research only, not a forward forecast.
- Source 0.940: 4839461a36d736c40f3e8841dd91128230370bdf. MetaEditor 4 compile: 0 errors, 1 MQL5 Market version warning, 92 ms; EX4 96760 bytes.
- Scripts: [original comparison](../tests/replay_original_comparison.py), [time exits](../tests/replay_timed_exit.py), [weekend exits](../tests/replay_weekend_exit.py), [risk matrix](../tests/replay_weekend_risk_matrix.py).

## Limitations and gates
Historical proxy uses last observed Friday M5 bar before >=24-hour gap; 46 observed events (43 at 23:40, 3 exceptional). User accepted proxy for research. Runtime default 23:45 Friday close, 23:40 cutoff is provisional; actual schedule and holidays unverified. Model omits swap, margin constraints and variable spread/slippage. Same dataset used for design and comparison; independent validation pending. Native order lifecycle, risk, recovery, journal, failed close and cutoff acceptance pending. No RC1 or DEMO launch accepted; no LIVE activation. No account identifiers or raw private data published.

## Next step
Native MT4 Strategy Tester acceptance, including fixed schedule vs historical proxy discrepancy, actual lot/margin, SL/TP, cutoff and failed-close behavior; inspect journal isolation and reconciliation. RC1 only after checks and separate DEMO authorization.
