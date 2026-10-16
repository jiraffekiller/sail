// Minimal AppleSMC reader. The user-client ABI (selector 2, 80-byte param struct)
// has been stable since 10.5 and still works on macOS 27 / Apple Silicon.
#include "csmc.h"
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <string.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes; } SMCKeyInfoData;
typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;

enum { kSMCHandleYPCEvent = 2, kSMCReadKey = 5, kSMCGetKeyInfo = 9 };

static io_connect_t g_conn = 0;

static bool ensure_open(void) {
    if (g_conn) return true;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return false;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &g_conn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) { g_conn = 0; return false; }
    return true;
}

static uint32_t key4(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

static bool call(SMCParamStruct *in, SMCParamStruct *out) {
    size_t osz = sizeof(SMCParamStruct);
    memset(out, 0, sizeof(*out));
    kern_return_t kr = IOConnectCallStructMethod(g_conn, kSMCHandleYPCEvent, in, sizeof(*in), out, &osz);
    if (kr != KERN_SUCCESS) {
        // Connection may be stale after sleep/wake or a daemon restart: drop it and retry once.
        IOServiceClose(g_conn); g_conn = 0;
        if (!ensure_open()) return false;
        osz = sizeof(SMCParamStruct);
        memset(out, 0, sizeof(*out));
        kr = IOConnectCallStructMethod(g_conn, kSMCHandleYPCEvent, in, sizeof(*in), out, &osz);
        if (kr != KERN_SUCCESS) return false;
    }
    return out->result == 0;
}

static bool read_key(const char *key, uint32_t expectType, uint32_t expectSize, uint8_t *bytes) {
    if (!key || strlen(key) != 4 || !ensure_open()) return false;
    SMCParamStruct in, out;
    memset(&in, 0, sizeof(in));
    in.key = key4(key);
    in.data8 = kSMCGetKeyInfo;
    if (!call(&in, &out)) return false;
    if (out.keyInfo.dataType != expectType || out.keyInfo.dataSize != expectSize) return false;
    memset(&in, 0, sizeof(in));
    in.key = key4(key);
    in.keyInfo.dataSize = expectSize;
    in.data8 = kSMCReadKey;
    if (!call(&in, &out)) return false;
    memcpy(bytes, out.bytes, expectSize);
    return true;
}

bool csmc_read_float(const char *key, float *out) {
    uint8_t b[4];
    if (!read_key(key, key4("flt "), 4, b)) return false;
    memcpy(out, b, 4);
    return true;
}

bool csmc_read_u8(const char *key, unsigned char *out) {
    uint8_t b[1];
    if (!read_key(key, key4("ui8 "), 1, b)) return false;
    *out = b[0];
    return true;
}
