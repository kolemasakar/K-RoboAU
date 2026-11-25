# Validation

Completed: native MQL4 signal replay (145 unique signals), discovery continuation/SL comparison 56/56, original KAI outcome evaluator comparison 56/56, independent time/Friday/SL sensitivity tests, 80 baseline and 80 weekend-risk portfolio scenarios, MetaEditor 4 compilation of 0.940 (0 errors, 1 warning).

Scripts: replay_original_comparison.py, replay_timed_exit.py, replay_weekend_exit.py, replay_risk_matrix.py, replay_weekend_risk_matrix.py. Historical Friday cutoff inferred retrospectively from M5 archive; not equivalent to verified calendar execution. Portfolio outcomes are OHLC approximations. Pending: native tester lifecycle, actual entry/SL/TP/lot/margin, risk ceilings, daily-data fallback, Friday exit and entry block, failed-close retry, restart/recovery, journal isolation and independent forward validation. No DEMO release yet.
