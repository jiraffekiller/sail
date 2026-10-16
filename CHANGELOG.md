# Changelog

## 0.2.0 — 2026-10-16

First public version.

- Sailing mode: charge to an upper limit, hold, recharge only below a lower limit.
- Heat protection with hysteresis, battery temperature from the SMC.
- Any limit from 1 to 100 % through a one-method root helper; 80–100 % without it.
- Menu bar only, sliders in the menu, About panel, app icon.
- Setup window: compatibility checks, helper install, conflicting-settings warnings,
  launch at login, self-test.
- launchd-supervised: starts at login, restarts after a crash, the limit survives sleep,
  lid close and the app not running.
