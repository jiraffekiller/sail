# Sail — Design

This document records what Sail does, which macOS mechanism it relies on, the evidence
that mechanism rests on, and why the architecture looks the way it does. It reflects
Sail 0.2.0 (October 2026).

## 1. Goals and non-goals

Sail is a battery charge limiter for Apple Silicon MacBooks with exactly two features:

1. **Sailing mode.** Charge to an upper limit, then do not top the battery up again until
   it has drained to a lower limit. Both limits are user-configurable.
2. **Heat protection.** Pause charging while the battery is above a temperature
   threshold; resume with hysteresis.

Operational requirements, in priority order:

- The limit must hold regardless of the app's state: during sleep, with the lid closed,
  and when the app is not running.
- The app must start at login, survive crashes, and never require attention.
- The implementation must have as few moving parts as possible, so that macOS updates
  break as little as possible and breakage is detected rather than silent.

Non-goals: calibration cycles, scheduled charging, statistics, MagSafe LED control,
Intel Macs, macOS releases before 26.4.

## 2. Platform constraints

### 2.1 Reference environment

All measurements below were taken on a MacBook Air (M3, `Mac15,12`) running macOS 27.0.1
with system firmware 20457.1.29. Methods:

- Read-only enumeration of SMC keys through the `AppleSMC` user client.
- Introspection of `PowerUI.framework` through the Objective-C runtime.
- Controlled writes, each followed by reading back `powerd`'s persisted policy and the
  battery's state from the IORegistry.

### 2.2 Survey of charge-control mechanisms

| Mechanism | Result on firmware 20457.x |
|---|---|
| Legacy SMC keys `CH0B`, `CH0C`, `CHTE`, `CH0I`, `BCLM`, `CHWA` | Absent (SMC result `0x84`, key not found). |
| Firmware limit keys `bfF0`, `bfD0`, `bfE0`, `CH0J`, `CHLS` | Present, but every access including key-info returns `kIOReturnNotPrivileged` (`0xE00002C1`). Gated behind a private entitlement; not usable by third parties. |
| `CHIE` (disable wall power, run from battery) | Present and writable by root. Usable only as a crude substitute: the Mac runs from the battery, and the battery keeps draining during sleep. Not used. |
| `powerd` manual charge limit (MCL) via `PowerUI.framework` | Works. 80–100 % without root or entitlements; any value through root-owned preferences (section 3). **This is the mechanism Sail uses.** |

Battery telemetry is available to any user:

- IORegistry `AppleSmartBattery`: `CurrentCapacity`, `IsCharging`, `ExternalConnected`,
  `Amperage`, `ChargerData.NotChargingReason`.
- SMC `TB0T`, `TB1T`, `TB2T` (type `flt`, °C): battery thermistors. On this firmware the
  IORegistry exposes no `Temperature` property, so the SMC is the only source.

Consequence: Sail supports Apple Silicon Macs on macOS 26.4 or newer, the first release
with a built-in manual charge limit. Older releases and Intel Macs are out of scope by
construction, not by choice.

## 3. The charge-limit mechanism

### 3.1 PowerUI client (user space, no privileges)

- Framework: `/System/Library/PrivateFrameworks/PowerUI.framework`.
- Class: `PowerUISmartChargeClient`, created with `-initWithClientName:`.
- Transport: `NSXPCConnection` to the Mach service `com.apple.powerui.smartChargeManager`,
  served by `/usr/libexec/PowerUIAgent` (root, launchd).
- Selectors used by Sail: `isMCLSupported`, `enableMCL:`, `setMCLLimit:error:` (uint8),
  `getMCLLimitWithError:`, `isMCLCurrentlyEnabled:`,
  `smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:`,
  `isSmartChargingCurrentlyEnabled:` (Optimized Battery Charging).
- Validation: the XPC entry point accepts any integer 80…100 (not only the
  80/85/90/95/100 offered by System Settings) and rejects anything below 80 with
  `PowerUISmartChargingErrorDomain` code 4. `temporarilyOverrideMCLTargetSoC:` has the
  same floor.

### 3.2 Persisted policy (powerd)

`powerd` stores the active policy in `/Library/Preferences/com.apple.powerd.charging.plist`
as an `NSKeyedArchiver`-encoded `ChargeCtrlPolicy`:

```
soclimit: <percent>   reason: manualChargeLimit   drain: true
isEndOfCharge: true   owner: <PowerUIAgent pid>   token: <UUID>
```

The owner is PowerUIAgent, not the client, so the limit outlives the process that set
it and is enforced by firmware while the system sleeps.

### 3.3 Preferences path (root, any value)

PowerUIAgent keeps its own state in root's preferences domain
`com.apple.smartcharging.topoffprotection`
(`/var/root/Library/Preferences/com.apple.smartcharging.topoffprotection.plist`, mode 0600).
The limit is the integer key `mclLimitValue`; `MCLFeatureState = 1` marks MCL as enabled.
Writing those keys and posting the Darwin notification
`com.apple.smartcharging.defaultschanged` makes PowerUIAgent apply the value without the
80 % floor:

```bash
defaults write com.apple.smartcharging.topoffprotection mclLimitValue -int 79
notifyutil -p com.apple.smartcharging.defaultschanged
```

Within seconds `getMCLLimit` reports the new value and `powerd`'s policy follows. This is
the only operation in Sail that requires root, and it is the entire job of the helper
(section 8).

### 3.4 Semantics of a limit

`powerd` steers the battery *to* the limit, in both directions:

- Below the limit it charges, and stops at the limit.
- At the limit it holds (`IsCharging` false, amperage 0).
- Above the limit it **discharges** to the limit (`drain = true` is always set for
  `manualChargeLimit`), cutting adapter input to a few hundred milliwatts.

Observable state signatures:

| Signal | Value | Meaning |
|---|---|---|
| `smartChargingUIState` | 1 | MCL off, or a limit below 80 (the UI layer treats it as off; `powerd` still enforces it) |
| | 13 | charging toward the limit |
| | 14 | at the limit, holding |
| | 16 | discharging toward the limit |
| `ChargerData.NotChargingReason` | `0x01000000` | charging stopped because the limit was reached |

Design consequence: a controller must never set a limit below the current charge level
unless it intends a discharge. "Hold" is expressed as *limit = current percent*.

### 3.5 Prior art

Two existing tools informed the survey. `batt` documents the firmware key gating on
macOS 27 and selects backends by SMC key presence. AlDente 1.39 (the first version
supporting macOS 27) uses the same two paths described above: its main app drives
`PowerUISmartChargeClient` for 80–100 %, and its root helper writes the
`topoffprotection` preferences for lower limits. Both observations were made from the
tools' public binaries and documentation; no code was reused.

## 4. Experimental evidence

Controlled writes performed on the reference environment on 2026-10-15, with no other
charge limiter running. Writes in rows 1–5 were made from an unsigned, unentitled user
process; rows 6–8 as root through `defaults` and `notifyutil`.

| # | Action | Observation |
|---|---|---|
| 1 | `setMCLLimit:74` with MCL disabled | Rejected, error code 4. |
| 2 | `enableMCL:` then `setMCLLimit:80` | Accepted; policy became `soclimit=80 drain=1`. |
| 3 | `setMCLLimit:` 82, 83, 90, 99 | Accepted. Any integer in 80…100 works. |
| 4 | `setMCLLimit:79`, `temporarilyOverrideMCLTargetSoC:74` | Rejected, error code 4. |
| 5 | Battery 75 → 80 with limit 80 | Charged at ~2.8 A, stopped at 80: `NotChargingReason = 0x01000000`, amperage 0 within about a minute. |
| 6 | Battery 82, limit set to 80 | Active discharge at −609 mA, adapter input ~0.3 W, `uiState = 16`. |
| 7 | Battery 82, limit set to 82 | Clean hold: amperage 0, `uiState = 14`. |
| 8 | root: `mclLimitValue = 79`, battery 82 | Accepted below 80: `getMCLLimit` = 79, policy `soclimit=79`, discharge at −605 mA, stopped at 79. |
| 9 | root: `mclLimitValue = 78` at 79 | Policy updated within seconds, discharge resumed (−571 mA), stopped at 78. |
| 10 | root: `mclLimitValue = 79` at 78 | `powerd` charged **up** to a sub-80 target: +3.1 A within 60 s, stopped at 79 with `NotChargingReason = 0x01000000`. |
| 11 | Client process exits | Policy persists; owner is PowerUIAgent. |

Conclusions: one primitive, *set limit n*, covers charging, holding and discharging for
any n in 1…100; the 80 % floor exists only in the XPC entry point; the limit is enforced
by `powerd` and firmware independently of the client.

## 5. Architecture

Two processes, one of them optional:

```
 launchd (SMAppService agent, KeepAlive) ──> Sail.app (menu bar, user session)
                                               │
      ┌────────────────────────────────────────┼─────────────────────────────┐
      │                                        │                             │
 BatteryMonitor                          Policy (pure)                 ChargeController
 IORegistry + SMC reads                  Sailing + heat state machine  setLimit(n):
 power-source notifications, wake        inputs -> desired limit        helper XPC (1…100)
      │                                        │                        or PowerUI XPC (80…100)
      └──────────────► Reconciler (every 30 s and on every event) ◄──────────┘
                       desired == actual ? no-op : write, log

 launchd (LaunchDaemon, on demand) ──> SailHelper (root): setChargeLimit(n)
                                        writes mclLimitValue, posts the notification
```

| Component | Responsibility |
|---|---|
| `SailCore.Policy` | Pure function `(state, config, sample) → (state, desiredLimit, reason)`. No I/O; unit-tested. |
| `BatteryMonitor` | Reads percent, charging flags and temperature; fires on `IOPSNotificationCreateRunLoopSource` events and on wake. |
| `ChargeController` | The single write primitive. Prefers the helper; falls back to the PowerUI client for 80…100 when the helper is absent. Reads the enforced limit back through the PowerUI client. |
| `Reconciler` | Desired-state loop: sample → policy → compare with `powerd` → write only on difference. Exponential back-off (30 s … 10 min) on write failures. Persists the policy state so a restart does not reset a holding battery to charging. |
| `StatusMenu` | Menu bar item: status lines, Sailing toggle, slider rows for both limits, heat toggle and threshold slider, pause, Setup, About, two quit variants. |
| `SetupWindow` | First-run checklist: compatibility, helper install, conflicting settings, launch at login, self-test. |
| `SailHelper` | Root daemon with one XPC method (section 8). |

State is kept in `~/Library/Application Support/Sail/config.json` (settings) and
`state.json` (policy phase).

## 6. Control algorithm

With upper limit U, lower limit L, current charge p and temperature t:

```
heat hold   : t >= Tmax            -> heatHold = true
              t <= Tmax - hyst     -> heatHold = false
phase       : p >= U               -> holding
              p <= L               -> charging

desired limit, first match wins:
  p < safetyFloor (20)             -> U            # an almost empty battery always charges
  heatHold                         -> p            # hold where it is
  paused or Sailing off            -> 100          # let macOS charge to full
  phase == charging                -> U
  phase == holding                 -> p            # follow the battery down, never top up
```

Notes:

- In `holding` the limit tracks the current percent on every change. When the Mac is
  unplugged the battery drains; the limit must follow so that re-plugging does not top it
  up. The phase flips back to `charging` only at L.
- The algorithm never produces a limit below p except in `paused`/`off` (where the limit
  is 100), so it never triggers a discharge. A future "discharge to L" action would simply
  be *set limit L*.
- Heat protection takes precedence over pause and over Sailing being off: it protects the
  battery, not the charging plan.
- Only the safety floor outranks heat protection.

The invariant "desired limit ≥ current percent in normal operation" is covered by a unit
test that sweeps every charge level.

## 7. Reliability and failure handling

- **Enforcement does not depend on the app.** `powerd` and firmware enforce the stored
  limit through sleep, lid close and app crashes. The app only has to be alive to *change*
  the limit at phase transitions.
- **Idempotent loop.** Every tick compares desired and actual; a lost write, a limit
  changed from System Settings, or a crash between two ticks is corrected on the next one.
- **Supervision.** The app runs as a launchd agent with `RunAtLoad` and
  `KeepAlive.SuccessfulExit = false`: restarted after a crash, not after Quit. Exactly one
  instance runs per user; the launchd-spawned copy is authoritative and replaces any
  manually launched copy (section 9).
- **Degraded mode.** Without the helper the PowerUI client still provides 80–100 %; the
  menu and Setup window say so.
- **Fail-safe on exit.** Quit leaves the current limit in `powerd`, which is the safe
  direction (the battery cannot overcharge). "Quit and charge to 100 %" releases it.
- **Conflicts detected, not fought.** The Setup window and menu warn when Optimized Battery
  Charging is on or when another limiter (AlDente, batt) is present. macOS also runs its own
  periodic calibration that charges to 100 % regardless of any limit; Sail does not counter
  it, it holds at the new level and resumes Sailing from there.
- **Self-test.** Writes the current desired limit and waits for `powerd` to report it, so a
  future macOS change in the private API surfaces as a visible failure instead of a
  silently full battery.
- **Private API risk.** `PowerUI.framework` is the same component System Settings uses,
  which makes it the most stable private surface available, but it is not a contract.
  Every call goes through the Objective-C runtime with `respondsToSelector:` checks, so a
  removed selector degrades into an error rather than a crash.

## 8. Privileged helper

The helper exposes one XPC method, `setChargeLimit(percent)`, which validates 1…100,
writes `mclLimitValue` and `MCLFeatureState` into root's
`com.apple.smartcharging.topoffprotection` domain, synchronises preferences and posts
`com.apple.smartcharging.defaultschanged`. Two read-only methods report the stored value
and the helper version. Nothing else runs as root.

Installation is the classic LaunchDaemon layout: binary in
`/Library/PrivilegedHelperTools`, plist in `/Library/LaunchDaemons`, started on demand
through `MachServices`. `SMAppService.daemon` was considered and rejected for 0.x: it
depends on the Login Items approval flow and behaves unpredictably with ad-hoc signed
bundles, while the plist layout works identically on every supported machine. The cost is
one administrator prompt at install time (triggered from the Setup window through the
system authorisation dialog, or `make install-helper`) and a generic icon for the helper's
entry in Login Items.

Security model: the helper accepts connections only from a client whose code signature
carries Sail's bundle identifier (`NSXPCConnection.setCodeSigningRequirement`). Release
builds are ad-hoc signed, so this is a courtesy check rather than a boundary; the worst a
local attacker could achieve through the helper is a charge limit between 1 and 100 %.

## 9. Launch at login

The agent plist ships inside the bundle (`Contents/Library/LaunchAgents`) and is
registered with `SMAppService.agent`. Background Task Management then classifies the job
as an *agent* belonging to the app, and System Settings › Login Items shows it under
"Sail" with the app icon. A plist dropped into `~/Library/LaunchAgents` is classified as a
*legacy agent* and shown with a generic executable icon; `AssociatedBundleIdentifiers`
fixes only the displayed name.

The launchd-spawned instance is recognised by the `--agent` argument from the plist or by
launchd's `XPC_SERVICE_NAME` environment variable. On start it terminates any other
running instance and takes over; a manually launched instance exits if an agent is
already running.

Migration note: when replacing a legacy plist agent with the same label, the legacy job
must be unloaded synchronously before `register()`. An unload that races the
registration removes the new job as well, and registering while the stale Background
Task Management record still exists fails with "Operation not permitted".

## 10. Language and build

- **Swift**, AppKit for the menu, SwiftUI for the Setup window. The whole surface is
  Objective-C runtime calls, AppKit, IOKit and ServiceManagement; a non-Apple language
  would add bridging cost without removing any dependency.
- **Objective-C and C bridges** (`CPowerUI`, `CSMC`) isolate the private framework and the
  SMC ABI behind small C headers with explicit error reporting.
- **Swift Package, no Xcode project.** `make` assembles the bundle, copies the launchd
  plists and scripts, and ad-hoc signs it. The same steps run in GitHub Actions on a
  macOS 26 runner for every push and for tagged releases.
- **Ad-hoc signing, no notarisation.** Users open the first launch through
  System Settings › Privacy & Security › Open Anyway. Notarised builds would need an Apple
  Developer ID; the mechanism itself does not.

## 11. Known limitations and open questions

- Requires Apple Silicon and macOS 26.4 or newer; nothing can be done for older firmware.
- macOS's periodic calibration overrides the limit by design (section 7).
- The helper's Login Items entry keeps a generic icon (section 8).
- Not yet verified: that PowerUIAgent re-reads `mclLimitValue` after a reboot without any
  write (expected, since it is PowerUIAgent's own persisted state), and the exact signals
  visible during macOS's calibration run.
- Debugging note: `log` is a zsh builtin; use `/usr/bin/log show --predicate
  'subsystem == "com.jiraffekiller.sail"'`.

## 12. References

- AlDente (AppHouseKitchen) — release notes for 1.39 describing the rebuilt macOS 27
  backend; binaries inspected for the PowerUI and preferences paths.
- batt (charlie0129) — SMC backends, firmware compatibility matrix, documentation of the
  `com.apple.private.iokit.soc-limit` gating on macOS 27.
- OpenDente (killerk3emstar) — Swift menu bar limiter built on the legacy SMC keys.
- Apple, "About Optimized Battery Charging and Charge Limit on Mac" (support article
  102338).
