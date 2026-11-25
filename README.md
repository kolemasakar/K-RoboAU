# K-RoboAU

RoboAU 1 is a standalone MetaTrader 4 Expert Advisor under development for XAUUSD. It reproduces the verified Strategy A v1.0 breakout/retest/continuation research rules with a fixed 3R target. Current development version: 0.940 (compiled). Approved research configuration: 5% trade risk, 10% daily risk when available, 10% aggregate risk, structural SL distance <= 50 USD, Friday pre-close exit, no position-age limit. Initial release target is DEMO. LIVE permission defaults to false and requires owner action after validation.

No K_AI runtime, Bridge, Python service, SQLite or external provider is required.

- [Specification](docs/SPECIFICATION.md)
- [Roadmap](docs/ROADMAP.md)
- [Operations](docs/OPERATIONS.md)
- [Version](VERSION.md)
- [Validation](tests/README.md)
- [Reports](reports/README.md)
- [2026-11-25 checkpoint](docs/CHECKPOINT_2026-11-25.md)

Development source: [mt4/RoboAU_1.mq4](mt4/RoboAU_1.mq4). Not released for trading.
