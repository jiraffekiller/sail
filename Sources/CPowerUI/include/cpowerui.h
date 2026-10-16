#ifndef CPOWERUI_H
#define CPOWERUI_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

/// True when PowerUI.framework loaded, PowerUISmartChargeClient exists and reports
/// manual charge limit (MCL) support on the current Mac.
bool cpui_available(void);

/// Current manual charge limit as PowerUIAgent reports it (reflects root's
/// mclLimitValue, any value 1...100) and whether MCL is enabled.
bool cpui_get_limit(uint8_t *limit, bool *enabled);

/// Enable MCL and set the limit through the XPC entry point. PowerUIAgent accepts
/// only 80...100 here; lower values fail with PowerUISmartChargingErrorDomain code 4.
/// Returns 0 on success, negative on failure (message in errbuf).
int cpui_set_limit(uint8_t limit, char *errbuf, size_t errlen);

/// smartChargingUIState (1 off, 13 charging to limit, 14 holding, 16 discharging to limit).
bool cpui_ui_state(unsigned long *state);

/// Optimized Battery Charging (Apple's adaptive 80%) currently enabled.
bool cpui_optimized_charging_enabled(bool *enabled);

#endif
