#include "MultitouchBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <math.h>
#include <stddef.h>

// Reverse-engineered private ABI, not an Apple-supported contract.
// Keep its layout isolated here; Swift never reads private structures.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier, state, fingerID, handID;
    MTVector normalized;
    float size;
    int32_t unknown;
    float angle, majorAxis, minorAxis;
    MTVector absolute;
    int32_t unknown2[2];
    float density;
} MTTouch;
_Static_assert(sizeof(MTTouch) == 96, "Unexpected multitouch ABI size");
_Static_assert(offsetof(MTTouch, normalized) == 32, "Unexpected position offset");

typedef int (*MTCallback)(void *, MTTouch *, int, double, int);
static void *framework;
static CFArrayRef devices;
static AGFrameCallback receive;
static void (*registerCallback)(void *, MTCallback);
static void (*unregisterCallback)(void *, MTCallback);
static void (*startDevice)(void *, int);
static void (*stopDevice)(void *);

static int onFrame(void *device, MTTouch *touches, int count, double timestamp, int frame) {
    (void)timestamp;
    if (count < 0 || count > 32 || (count && !touches)) return 0;
    AGContact contacts[32];
    int active = 0;
    for (int i = 0; i < count; ++i) {
        // States 3 and 4 are touching; ignore hover and release records.
        if (touches[i].state != 3 && touches[i].state != 4) continue;
        float x = touches[i].normalized.position.x;
        float y = touches[i].normalized.position.y;
        if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) return 0;
        contacts[active++] = (AGContact){touches[i].identifier, x, y};
    }
    receive((uintptr_t)device, (uint32_t)frame, contacts, active);
    return 0;
}

const char *AGStart(AGFrameCallback callback) {
    if (devices) return "Multitouch listener already started";
    framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!framework) return "Cannot load private MultitouchSupport framework on this macOS version";
    CFArrayRef (*createList)(void) = dlsym(framework, "MTDeviceCreateList");
    registerCallback = dlsym(framework, "MTRegisterContactFrameCallback");
    unregisterCallback = dlsym(framework, "MTUnregisterContactFrameCallback");
    startDevice = dlsym(framework, "MTDeviceStart");
    stopDevice = dlsym(framework, "MTDeviceStop");
    if (!createList || !registerCallback || !unregisterCallback || !startDevice || !stopDevice) {
        dlclose(framework);
        framework = NULL;
        return "Required private multitouch symbols are unavailable on this macOS version";
    }
    devices = createList();
    if (!devices || CFArrayGetCount(devices) == 0) {
        if (devices) CFRelease(devices);
        devices = NULL;
        dlclose(framework);
        framework = NULL;
        return "No multitouch devices found; connect a trackpad and retry";
    }
    receive = callback;
    for (CFIndex i = 0; i < CFArrayGetCount(devices); ++i) {
        void *device = (void *)CFArrayGetValueAtIndex(devices, i);
        registerCallback(device, onFrame);
        startDevice(device, 0);
    }
    return NULL;
}

void AGStop(void) {
    if (!devices) return;
    for (CFIndex i = 0; i < CFArrayGetCount(devices); ++i) {
        void *device = (void *)CFArrayGetValueAtIndex(devices, i);
        stopDevice(device);
        unregisterCallback(device, onFrame);
    }
    CFRelease(devices);
    devices = NULL;
    // Retain loaded code until process exit: private callbacks may still be unwinding.
}
