# Battery charge limiter for macOS — design notes

Status: v0.1 built and installed on the target machine (2026-10-15); see README.md for usage. Target machine: MacBook Air M3 (Mac15,12),
macOS 27.0.1, firmware 20457.1.29. UI language: English.

## 1. Scope

Two features only, copied in spirit from Al Dente:

1. **Sailing mode** — charge to an upper limit, then do not top up again until the
   battery has drained to a lower limit. Both limits configurable.
2. **Heat protection** — stop charging while the battery is above a temperature
   threshold, resume with hysteresis.

Plus the boring but essential parts: menu bar only (no Dock icon), starts at login,
restarts if it crashes, survives sleep / lid close, never needs attention.

Out of scope: calibration, forced discharge, schedules, stats, MagSafe LED, Intel Macs.

## 2. What actually works on this machine (measured 2026-10-15)

Checked with a read-only SMC probe and the ObjC runtime, no writes performed.

| Mechanism | Result on firmware 20457.1.29 |
|---|---|
| Legacy SMC keys `CH0B` `CH0C` `CHTE` `CH0I` `BCLM` `CHWA` | do not exist (SMC result 0x84) |
| Firmware limit keys `bfF0` `bfD0` `bfE0`, `CH0J`, `CHLS` | exist but return `kIOReturnNotPrivileged` (0xe00002c1) even for key-info; gated by the private entitlement `com.apple.private.iokit.soc-limit` (per batt README) |
| `CHIE` (cut wall power, run from battery) | exists, writable (needs root). Usable but battery drains while asleep; last resort only |
| **powerd Manual Charge Limit (MCL) via `PowerUI.framework`** | works, **no root, no entitlement** — this is what Al Dente 1.39 uses on macOS 27 |
| Battery temperature | SMC `TB0T`/`TB1T`/`TB2T`, type `flt`, degrees C, readable as a normal user (28.1 C at probe time). `AppleSmartBattery` in IORegistry exposes no `Temperature` here |
| Battery percent / charging state | IORegistry `AppleSmartBattery`: `CurrentCapacity`, `IsCharging`, `ExternalConnected`, `ChargerData.NotChargingReason`; SMC `BRSC` also gives percent |

### How the MCL path works

- Private framework `/System/Library/PrivateFrameworks/PowerUI.framework`,
  class `PowerUISmartChargeClient`, `-initWithClientName:`.
- It is an `NSXPCConnection` to Mach service `com.apple.powerui.smartChargeManager`,
  served by `/usr/libexec/PowerUIAgent` (root, launchd). PowerUIAgent is the *owner*
  of the stored policy, so the limit outlives the client process.
- Relevant selectors (all return BOOL and take `NSError **`):
  `setMCLLimit:error:` (uint8 percent), `enableMCL:`, `disableMCL:`,
  `getMCLLimitWithError:`, `isMCLCurrentlyEnabled:`, `isMCLSupported`,
  `availableChargeLimitsWithError:`, `temporarilyDisableMCL:`,
  `temporarilyEnableCharging:`, `temporarilyOverrideMCLTargetSoC:error:`,
  `isSmartChargingCurrentlyEnabled:` (Optimized Battery Charging),
  `smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:`.
- The System Settings UI only offers `availableChargeLimits` = 80, 85, 90, 95, 100,
  but the daemon accepts other values: right now `getMCLLimit` = **71** while
  Al Dente's configured limit is 60 and the battery sits at 71 %, not charging, on AC.
  So "hold at current level" works below 80. Whether powerd will *charge up to* a
  sub-80 target, or *drain down* to it, is untested (Al Dente's own log strings say
  "PowerUI cannot charge to targets below 80" and "PowerUI discharge requires a target").
- powerd persists the policy in `/Library/Preferences/com.apple.powerd.charging.plist`
  as an NSKeyedArchiver `ChargeCtrlPolicy` { soclimit, reason = manualChargeLimit,
  drain, isEndOfCharge, owner = PowerUIAgent pid, token }.
- Al Dente's privileged helper contains only SMC read/write methods; the PowerUI
  calls are made from the main app as the logged-in user. Confirms no root needed.

### Known behaviour of macOS 27 to design around

- Apple runs its own periodic "micro calibration": after the battery has sat at one
  level for roughly three days, macOS charges it to 100 % and overrides the limit.
  Al Dente has not found a way to prevent it. We detect it and do not fight it.
- Optimized Battery Charging must be off, otherwise two policies compete.
- Al Dente must not run at the same time (two writers of the same MCL).

## 3. Language

**Swift.** The entire surface is ObjC runtime calls into a private framework,
AppKit `NSStatusItem`, IOKit reads, and `SMAppService`. There is no root daemon, no
hot loop, no cross-platform story, so Rust buys nothing here and costs `objc2`
boilerplate for every private selector. Swift runtime ships with the OS; the binary
stays small. Rust remains possible (objc2 + hand-declared selectors + `tray-icon`),
but it is the wrong tool for this shape.

Build without an Xcode project: Swift Package with one executable target plus a
`Makefile` that assembles `Foo.app` (Info.plist with `LSUIElement = true`), ad-hoc
`codesign -s -`. Reproducible from a terminal with Command Line Tools.

## 4. Architecture — one user-level app plus a one-trick root helper

Two processes. The **app** (menu bar, user session) owns all logic. The **helper**
(launchd daemon, root, installed via `SMAppService.daemon`) exposes a single XPC method,
`setChargeLimit(percent)`, which writes `mclLimitValue`/`MCLFeatureState` into root's
`com.apple.smartcharging.topoffprotection` domain and posts
`com.apple.smartcharging.defaultschanged`. It validates the range (1…100), checks the
caller's code-signing identity, and does nothing else. If the helper is unavailable the
app falls back to the XPC path (80…100 only) and shows a warning.

```
 launchd (LaunchAgent, KeepAlive) ──> App (menu bar, user session)
                                        │
        ┌───────────────────────────────┼────────────────────────────┐
        │                               │                            │
  BatteryMonitor                     Policy (pure)               ChargeController
  IORegistry + SMC reads            Sailing + Heat FSM            PowerUI MCL over XPC
  IOPS notifications, wake          inputs -> desired limit       set / get / verify
        │                               │                            │
        └──────────────► Reconciler (every 30 s + on event) ◄────────┘
                         desired == actual ? no-op : re-apply, log
```

- **Policy** is a pure function of `(percent, temperature, externalConnected, config,
  previousState) -> (newState, desiredLimit)`. Unit-tested without hardware.
  - Sailing: state `charging` → MCL = upper. On reaching upper → state `holding`,
    MCL = current percent (prevents top-up). While `holding` and percent falls, keep
    MCL = current percent. When percent ≤ lower → `charging`.
  - Heat: if temp ≥ T_max → `heatHold`, MCL = current percent. Leaves `heatHold` when
    temp ≤ T_max − hysteresis for N minutes, returns to the sailing state.
  - Hard floor: below a safety percent (default 20) always allow charging.
- **Reconciler** is idempotent: read actual MCL from powerd (`getMCLLimit` works for any
  value, including < 80), compare with desired, apply only on difference. Runs on timer, on power-source change, on wake, on config
  change. If XPC fails: exponential backoff, warning glyph in the menu bar.
- **Sleep / lid**: powerd and firmware enforce the stored limit while the app is
  asleep or dead. On wake we just reconcile.
- **Autostart / restart**: `SMAppService.agent(plistName:)` with a bundled LaunchAgent
  plist (`KeepAlive = true`, `RunAtLoad = true`). One-time user approval in
  System Settings > Login Items. launchd restarts the app after a crash.
- **Fail-safe**: normal quit leaves the limit at the sailing upper bound (safe). A
  separate "Quit and restore 100 %" menu item calls `disableMCL` / sets 100.
- **Config**: one JSON file in `~/Library/Application Support/<App>/`.
- **UI**: `NSStatusItem` with a menu only — percent and temperature line, Sailing
  on/off, upper limit submenu, lower limit submenu, heat threshold submenu,
  "Pause for 1 h", "Launch at login", "Quit", "Quit and restore 100 %". No windows.
- **Diagnostics**: `os_log` with a subsystem, plus a tiny `--status` CLI mode that
  prints the same facts the probe printed today.

## 5. Live experiment results (2026-10-15, Al Dente quit, MacBook Air M3, macOS 27.0.1)

All writes were made from an unsigned, unentitled user process (`mcl` CLI in the
scratchpad) through `PowerUISmartChargeClient`.

| # | Experiment | Result |
|---|---|---|
| 1 | `setMCLLimit:74` while MCL disabled | **rejected**, `PowerUISmartChargingErrorDomain` code 4 |
| 1 | `enableMCL:` then `setMCLLimit:80` | **accepted**; powerd policy became `soclimit=80 drain=1 isEndOfCharge=1` |
| 1 | `setMCLLimit:` 82, 83, 90, 99 | **accepted** — any integer in 80…100 works, not just the UI's 80/85/90/95/100 |
| 1 | `setMCLLimit:79`, `temporarilyOverrideMCLTargetSoC:74` | **rejected**, code 4. The XPC entry point enforces a hard floor of 80 |
| 2 | Charge 75 → 80 with limit 80 | Charged at ~2.8 A, stopped at 80. `ChargerData.NotChargingReason` became `0x01000000`, `IsCharging` lagged ~1 min, amperage went to 0 |
| 3 | Battery 82, set limit 80 | powerd **actively discharges** to the target: amperage −609 mA, adapter input fell to ~0.3 W, `uiState=16`. `drain=1` means "discharge down to soclimit", i.e. Al Dente's Discharge feature for free |
| 3 | Battery 82, set limit 82 | Clean **hold**: amperage 0, `uiState=14`, no charge, no drain |
| 4 | Policy after the client process exits | Persists. Owner of the policy is `PowerUIAgent` (root, pid 86757), stored in `/Library/Preferences/com.apple.powerd.charging.plist` |
| 5 | Lid closed 30 min near the limit | **not yet run** (needs the user). Expected to hold, since powerd owns the policy |
| 7 | root: `mclLimitValue=79` + notification, battery 82 | **accepted** below 80: `getMCLLimit`=79, policy `soclimit=79 drain=1`, discharge at −605 mA, stopped cleanly at 79 (amperage 0) |
| 7 | root: `mclLimitValue=78` while at 79 | policy → 78 within seconds, discharge resumed (−571 mA) |
| 7 | root: `mclLimitValue=79` while at 78 | **powerd charges UP to a sub-80 target**: +3119 mA within 60 s, stopped at 79 with `NotChargingReason=0x01000000`. Al Dente's "cannot charge to targets below 80" applies only to the XPC path |
| 6 | State signatures | `smartChargingUIState`: 1 = MCL off, 13 = charging toward MCL, 14 = at MCL / holding, 16 = discharging toward MCL. With a sub-80 limit `uiState` reads 1 (the UI layer treats it as off) while the policy and powerd behave normally. At-limit also sets `NotChargingReason = 0x01000000` |

### Consequences for the design

- **80…100 needs no root at all.** Sailing in that band is purely `setMCLLimit:` calls:
  charge phase → limit = upper; hold phase → limit = current percent (any value
  80…100 is accepted); resume when percent ≤ lower → limit = upper. Heat protection is
  the same hold call.
- **Never set the limit below the current percent unless you want a discharge.**
  `drain=1` is always on in the policy powerd writes for `manualChargeLimit`, so a
  limit under the current level drains the battery to it. That is a feature (optional
  "discharge to limit"), but the Sailing hold must always use `limit = current`.
- **Below 80 requires root, and the mechanism is verified.** The XPC path refuses < 80.
  PowerUIAgent keeps its state in root's preferences domain
  `/var/root/Library/Preferences/com.apple.smartcharging.topoffprotection.plist`
  (mode 0600). The limit is the integer key `mclLimitValue`, with `MCLFeatureState = 1`
  meaning MCL is on. Verified live as root:

  ```bash
  defaults write com.apple.smartcharging.topoffprotection mclLimitValue -int 79
  notifyutil -p com.apple.smartcharging.defaultschanged
  ```

  Within seconds `getMCLLimit` reported 79, powerd's policy became `soclimit=79 drain=1`
  and the battery (at 82) started discharging at −605 mA. So the 80 floor lives only in
  the XPC entry point; PowerUIAgent itself applies any value from its defaults. This is
  exactly what Al Dente's root helper does (`writeDefaultsWithDomain:key:value:user:host:`
  + `postDarwinNotificationWithName:`).
  Charge-up, hold and discharge all work through this key (rows 7 above), so the
  **entire** controller can use one primitive: `setLimit(n)` for any n in 1…100.
  The privileged helper needs exactly one capability: write `mclLimitValue`
  (and `MCLFeatureState = 1`) in root's `com.apple.smartcharging.topoffprotection`
  domain, then post `com.apple.smartcharging.defaultschanged`. Nothing else runs as root.

### Control algorithm (final)

One primitive, `setLimit(n)`, where n is what powerd should steer the battery to:
above n it discharges, below n it charges, at n it holds. Sailing with upper U, lower L:

```
state charging : setLimit(U)            # charge up; powerd stops at U
   on percent >= U            -> holding
state holding  : setLimit(percent)      # follow the battery down, never top up
   on percent <= L            -> charging
heat override  : setLimit(percent) while temp >= Tmax, until temp <= Tmax - hyst
hard floor     : if percent < 20 -> setLimit(U) regardless
```

`holding` must track the current percent on every change (when unplugged the battery
drains; the limit must follow so that re-plugging does not top up). Because
`drain=1` is always on, `setLimit` must never be given a value below the current
percent unless a discharge is wanted. An optional "Discharge to L now" item is just
`setLimit(L)`.

The helper is only required when the desired value is < 80. For 80…100 the app can
use the XPC path directly, which gives a working degraded mode if the helper is
missing or broken.
- Legacy SMC and `bfD0/bfE0` paths are dead on this firmware and are not worth a backend.

### Still open

1. Lid-close test (user): plug in, limit at current percent, close lid 30 min, compare.
2. Apple's periodic calibration to 100 %: watch `uiState` / `NotChargingReason` when it
   happens, so the app can recognise it instead of fighting it. The root domain's
   `timeline.archive` showed a `FullyCharged` event at 100 % on 2026-10-14, so it happens.
3. Whether PowerUIAgent re-reads `mclLimitValue` on its own after a reboot (expected: yes,
   it is its own persisted state) — verify once the helper exists.

## 6. Implementation notes (v0.1)

- Swift Package, no Xcode project: `Sail` (AppKit menu bar app), `SailHelper` (root
  daemon), `SailCore` (policy + XPC protocol, unit-tested), `CSMC` and `CPowerUI`
  (C/ObjC bridges). `make install` deploys to /Applications, installs the helper with sudo
  and enables the LaunchAgent.
- Helper is installed the classic way (binary in /Library/PrivilegedHelperTools, plist in
  /Library/LaunchDaemons, on-demand via MachServices) rather than SMAppService, so it does
  not depend on the Login Items approval flow or on a Developer ID signature. Its Login
  Items entry therefore keeps a generic icon; `AssociatedBundleIdentifiers` only fixes the name.
- The app is supervised by a LaunchAgent registered through `SMAppService.agent` with the
  plist inside the bundle (`Contents/Library/LaunchAgents`), `RunAtLoad` and
  `KeepAlive.SuccessfulExit = false`: restarted after a crash, not after Quit. Registering
  through SMAppService (rather than dropping a plist into ~/Library/LaunchAgents) is what
  makes System Settings > Login Items show the job under the app with its icon; plist-file
  agents are classified "legacy" by backgroundtaskmanagementd and get a generic icon. The
  launchd copy runs with `--agent` and takes over from any manually launched copy.
- Gotcha: unloading a legacy agent with the same label must finish before `register()`;
  a detached `launchctl bootout` racing the registration removes the new job too, and
  registering while the stale BTM record still exists fails with "Operation not permitted".
- Verified live: helper XPC round trip, limit write 79 -> 80 through the reconciler within
  12 s of launch, agent handoff, restart after `kill -9`.
- Gotcha: `log` is a zsh builtin; use `/usr/bin/log show --predicate 'subsystem == "com.jiraffekiller.sail"'`.

## 7. Reference projects

- Al Dente 1.39.4 (installed here) — the PowerUI backend strings were the key hint.
- charlie0129/batt — SMC backends, firmware matrix, the macOS 27 gating note.
- killerk3emstar/OpenDente — Swift menu bar limiter using the old SMC keys.
