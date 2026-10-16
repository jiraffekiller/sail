// Bridge to the private PowerUI.framework. Everything goes through the ObjC runtime so
// nothing here needs headers Apple does not ship. Selectors verified on macOS 27.0.1.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>
#include "cpowerui.h"

static id g_client = nil;

static id client(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW);
        if (!h) return;
        Class cls = objc_getClass("PowerUISmartChargeClient");
        if (!cls) return;
        SEL initSel = sel_registerName("initWithClientName:");
        if (!class_respondsToSelector(cls, initSel)) return;
        id obj = [cls alloc];
        g_client = ((id (*)(id, SEL, id))objc_msgSend)(obj, initSel, @"Sail");
    });
    return g_client;
}

static bool responds(id obj, const char *name) {
    return obj && [obj respondsToSelector:sel_registerName(name)];
}

static void put_error(char *buf, size_t len, const char *prefix, NSError *err) {
    if (!buf || !len) return;
    snprintf(buf, len, "%s: %s", prefix, err ? err.description.UTF8String : "unknown error");
}

bool cpui_available(void) {
    id c = client();
    if (!responds(c, "isMCLSupported")) return false;
    return ((BOOL (*)(id, SEL))objc_msgSend)(c, sel_registerName("isMCLSupported")) != NO;
}

bool cpui_get_limit(uint8_t *limit, bool *enabled) {
    id c = client();
    if (!responds(c, "getMCLLimitWithError:") || !responds(c, "isMCLCurrentlyEnabled:")) return false;
    NSError *err = nil;
    uint8_t l = ((uint8_t (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("getMCLLimitWithError:"), &err);
    if (err) return false;
    err = nil;
    unsigned long en = ((unsigned long (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("isMCLCurrentlyEnabled:"), &err);
    if (err) return false;
    if (limit) *limit = l;
    if (enabled) *enabled = en != 0;
    return true;
}

int cpui_set_limit(uint8_t limit, char *errbuf, size_t errlen) {
    id c = client();
    if (!responds(c, "enableMCL:") || !responds(c, "setMCLLimit:error:")) {
        if (errbuf && errlen) snprintf(errbuf, errlen, "PowerUI client unavailable");
        return -1;
    }
    NSError *err = nil;
    BOOL ok = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("enableMCL:"), &err);
    if (!ok) { put_error(errbuf, errlen, "enableMCL failed", err); return -2; }
    err = nil;
    ok = ((BOOL (*)(id, SEL, uint8_t, NSError **))objc_msgSend)(c, sel_registerName("setMCLLimit:error:"), limit, &err);
    if (!ok) { put_error(errbuf, errlen, "setMCLLimit failed", err); return -3; }
    return 0;
}

bool cpui_ui_state(unsigned long *state) {
    id c = client();
    const char *name = "smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:";
    if (!responds(c, name)) return false;
    unsigned long st = 0, cl = 0; BOOL ov = NO; NSError *err = nil;
    BOOL ok = ((BOOL (*)(id, SEL, unsigned long *, unsigned long *, BOOL *, NSError **))objc_msgSend)(
        c, sel_registerName(name), &st, &cl, &ov, &err);
    if (!ok || err) return false;
    if (state) *state = st;
    return true;
}

bool cpui_optimized_charging_enabled(bool *enabled) {
    id c = client();
    if (!responds(c, "isSmartChargingCurrentlyEnabled:")) return false;
    NSError *err = nil;
    unsigned long en = ((unsigned long (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("isSmartChargingCurrentlyEnabled:"), &err);
    if (err) return false;
    if (enabled) *enabled = en != 0;
    return true;
}
