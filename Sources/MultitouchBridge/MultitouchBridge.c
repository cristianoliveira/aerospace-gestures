#include "MultitouchBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <uuid/uuid.h>

// Reverse-engineered private ABI; this is not an Apple-supported contract.
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
// Getter signatures come from a reverse-engineered header; availability is runtime-checked.
typedef int32_t OSStatus;
typedef OSStatus (*MTDeviceGetDeviceID)(CFTypeRef, uint64_t *);
typedef OSStatus (*MTDeviceGetGUID)(CFTypeRef, uuid_t *);
typedef struct {
    void *device;
    uintptr_t token;
    size_t callbackSlot;
} DeviceRegistration;
typedef struct {
    uintptr_t handle;
    char identity[64];
} SnapshotDevice;
struct AGCallbackGenerationTable {
    pthread_mutex_t lock;
    size_t capacity;
    size_t next;
    uintptr_t *tokens;
};
struct AGDeviceSnapshot {
    CFArrayRef devices;
    size_t count;
    int supportsStableIdentity;
    SnapshotDevice entries[];
};

static void *framework;
static CFArrayRef (*createList)(void);
static void (*registerCallback)(void *, MTCallback);
static void (*unregisterCallback)(void *, MTCallback);
static void (*startDevice)(void *, int);
static void (*stopDevice)(void *);
static MTDeviceGetDeviceID deviceGetDeviceID;
static MTDeviceGetGUID deviceGetGUID;
static AGFrameCallback receive;
static int bridgeStarted;
static DeviceRegistration *registrations;
static size_t registrationCount;
static size_t registrationCapacity;
static pthread_mutex_t registrationLock = PTHREAD_MUTEX_INITIALIZER;
#define CALLBACK_GENERATION_CAPACITY 4096
static AGCallbackGenerationTable *callbackGenerations;

// A callback slot is never reused: late callbacks retain their original token.
static _Atomic uint64_t callbackArrivals;
static _Atomic uint64_t invalidFrameRejects;
static _Atomic uint64_t deviceRegistrationCalls;
static _Atomic uint64_t deviceStopCalls;
static _Atomic uint64_t callbackGenerationExhaustions;
static _Atomic uint64_t deviceSnapshotEnumerations;
static _Atomic uint64_t registeredDevices;
static _Atomic uint64_t lastCallbackNanoseconds;

static uint64_t monotonicNanoseconds(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 0;
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}

static int rejectFrame(void) {
    atomic_fetch_add_explicit(&invalidFrameRejects, 1, memory_order_relaxed);
    return 0;
}

void AGReadBridgeDiagnostics(AGBridgeDiagnostics *diagnostics) {
    if (!diagnostics) return;
    diagnostics->callback_arrivals = atomic_load_explicit(&callbackArrivals, memory_order_relaxed);
    diagnostics->invalid_frame_rejects = atomic_load_explicit(&invalidFrameRejects, memory_order_relaxed);
    diagnostics->device_registration_calls = atomic_load_explicit(&deviceRegistrationCalls, memory_order_relaxed);
    diagnostics->device_stop_calls = atomic_load_explicit(&deviceStopCalls, memory_order_relaxed);
    diagnostics->callback_generation_exhaustions = atomic_load_explicit(&callbackGenerationExhaustions, memory_order_relaxed);
    diagnostics->device_snapshot_enumerations = atomic_load_explicit(&deviceSnapshotEnumerations, memory_order_relaxed);
    AGReadDeviceTopologyDiagnostics(&diagnostics->topology_event_notifications,
                                    &diagnostics->topology_observer_failures);
    AGReadTopologyCallbackDeliveries(&diagnostics->topology_callback_deliveries);
    diagnostics->registered_devices = atomic_load_explicit(&registeredDevices, memory_order_relaxed);
    uint64_t lastCallback = atomic_load_explicit(&lastCallbackNanoseconds, memory_order_relaxed);
    uint64_t now = monotonicNanoseconds();
    diagnostics->last_callback_age_nanoseconds =
        lastCallback == 0 ? UINT64_MAX : (now >= lastCallback ? now - lastCallback : 0);
}

static uintptr_t tokenForSlot(size_t slot, AGFrameCallback *callback) {
    uintptr_t token = 0;
    pthread_mutex_lock(&registrationLock);
    token = AGCallbackGenerationToken(callbackGenerations, slot);
    if (token != 0) *callback = receive;
    pthread_mutex_unlock(&registrationLock);
    return token;
}

AGCallbackGenerationTable *AGCreateCallbackGenerationTable(size_t capacity) {
    if (capacity == 0 || capacity > SIZE_MAX / sizeof(uintptr_t)) return NULL;
    AGCallbackGenerationTable *table = calloc(1, sizeof(*table));
    if (!table) return NULL;
    table->tokens = calloc(capacity, sizeof(uintptr_t));
    if (!table->tokens || pthread_mutex_init(&table->lock, NULL) != 0) {
        free(table->tokens);
        free(table);
        return NULL;
    }
    table->capacity = capacity;
    return table;
}

void AGDestroyCallbackGenerationTable(AGCallbackGenerationTable *table) {
    if (!table) return;
    pthread_mutex_destroy(&table->lock);
    free(table->tokens);
    free(table);
}

int AGReserveCallbackGeneration(AGCallbackGenerationTable *table, uintptr_t token, size_t *slot) {
    if (!table || !token || !slot) return -1;
    pthread_mutex_lock(&table->lock);
    if (table->next == table->capacity) {
        pthread_mutex_unlock(&table->lock);
        return -1;
    }
    *slot = table->next;
    table->tokens[table->next++] = token;
    pthread_mutex_unlock(&table->lock);
    return 0;
}

uintptr_t AGCallbackGenerationToken(AGCallbackGenerationTable *table, size_t slot) {
    if (!table) return 0;
    pthread_mutex_lock(&table->lock);
    uintptr_t token = slot < table->next ? table->tokens[slot] : 0;
    pthread_mutex_unlock(&table->lock);
    return token;
}

static int onFrameForSlot(size_t slot, void *device, MTTouch *touches, int count, double timestamp, int frame) {
    (void)device;
    (void)timestamp;
    atomic_fetch_add_explicit(&callbackArrivals, 1, memory_order_relaxed);
    uint64_t now = monotonicNanoseconds();
    if (now != 0) atomic_store_explicit(&lastCallbackNanoseconds, now, memory_order_relaxed);
    if (count < 0 || count > 32 || (count && !touches)) return rejectFrame();

    AGFrameCallback callback = NULL;
    uintptr_t token = tokenForSlot(slot, &callback);
    if (token == 0 || !callback) return 0;

    AGContact contacts[32];
    int active = 0;
    for (int i = 0; i < count; ++i) {
        // States 3 and 4 are touching; ignore hover and release records.
        if (touches[i].state != 3 && touches[i].state != 4) continue;
        float x = touches[i].normalized.position.x;
        float y = touches[i].normalized.position.y;
        if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) return rejectFrame();
        contacts[active++] = (AGContact){touches[i].identifier, x, y};
    }
    callback(token, (uint32_t)frame, contacts, active);
    return 0;
}

#define DEFINE_FRAME_TRAMPOLINE(slot) static int frameTrampoline##slot(void *device, MTTouch *touches, int count, double timestamp, int frame) { return onFrameForSlot(slot, device, touches, count, timestamp, frame); }
#define AG_CALLBACK_SLOT(slot) DEFINE_FRAME_TRAMPOLINE(slot)
#include "MultitouchCallbackTrampolines.inc"
#undef AG_CALLBACK_SLOT

#define AG_CALLBACK_SLOT(slot) frameTrampoline##slot,
static MTCallback const callbackTrampolines[CALLBACK_GENERATION_CAPACITY] = {
#include "MultitouchCallbackTrampolines.inc"
};
#undef AG_CALLBACK_SLOT

const char *AGStart(AGFrameCallback callback) {
    pthread_mutex_lock(&registrationLock);
    if (bridgeStarted) {
        pthread_mutex_unlock(&registrationLock);
        return "Multitouch listener already started";
    }
    pthread_mutex_unlock(&registrationLock);

    if (!framework) {
        framework = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_NOW);
        if (!framework) return "Cannot load private MultitouchSupport framework on this macOS version";
        createList = dlsym(framework, "MTDeviceCreateList");
        registerCallback = dlsym(framework, "MTRegisterContactFrameCallback");
        unregisterCallback = dlsym(framework, "MTUnregisterContactFrameCallback");
        startDevice = dlsym(framework, "MTDeviceStart");
        stopDevice = dlsym(framework, "MTDeviceStop");
        deviceGetDeviceID = dlsym(framework, "MTDeviceGetDeviceID");
        deviceGetGUID = dlsym(framework, "MTDeviceGetGUID");
        if (!createList || !registerCallback || !unregisterCallback || !startDevice || !stopDevice) {
            dlclose(framework);
            framework = NULL;
            createList = NULL;
            registerCallback = NULL;
            unregisterCallback = NULL;
            startDevice = NULL;
            stopDevice = NULL;
            deviceGetDeviceID = NULL;
            deviceGetGUID = NULL;
            return "Required private multitouch symbols are unavailable on this macOS version";
        }
    }

    if (!callbackGenerations) {
        callbackGenerations = AGCreateCallbackGenerationTable(CALLBACK_GENERATION_CAPACITY);
        if (!callbackGenerations) return "Cannot allocate callback generation table";
    }

    pthread_mutex_lock(&registrationLock);
    receive = callback;
    bridgeStarted = 1;
    pthread_mutex_unlock(&registrationLock);
    return NULL;
}

AGDeviceSnapshot *AGCreateDeviceSnapshot(void) {
    atomic_fetch_add_explicit(&deviceSnapshotEnumerations, 1, memory_order_relaxed);
    if (!bridgeStarted || !createList) return NULL;
    CFArrayRef list = createList();
    if (!list) return NULL;

    CFIndex deviceCount = CFArrayGetCount(list);
    if (deviceCount < 0 || (uint64_t)deviceCount > (SIZE_MAX - sizeof(AGDeviceSnapshot)) / sizeof(SnapshotDevice)) {
        CFRelease(list);
        return NULL;
    }

    size_t count = (size_t)deviceCount;
    AGDeviceSnapshot *snapshot = calloc(1, sizeof(*snapshot) + count * sizeof(SnapshotDevice));
    if (!snapshot) {
        CFRelease(list);
        return NULL;
    }
    snapshot->devices = list;
    snapshot->count = count;
    snapshot->supportsStableIdentity = deviceGetDeviceID && deviceGetGUID;
    for (size_t i = 0; i < count; ++i) {
        void *device = (void *)CFArrayGetValueAtIndex(list, (CFIndex)i);
        snapshot->entries[i].handle = (uintptr_t)device;
        if (snapshot->supportsStableIdentity) {
            uint64_t deviceID = 0;
            uuid_t guid;
            if (deviceGetDeviceID(device, &deviceID) != 0 || deviceGetGUID(device, &guid) != 0) {
                CFRelease(snapshot->devices);
                free(snapshot);
                return NULL;
            }
            char guidString[37];
            uuid_unparse_lower(guid, guidString);
            snprintf(snapshot->entries[i].identity, sizeof(snapshot->entries[i].identity),
                     "guid:%s;id:%016llx", guidString, (unsigned long long)deviceID);
        } else {
            // Preserve one-shot registration on older systems, but do not poll unstable pointers.
            snprintf(snapshot->entries[i].identity, sizeof(snapshot->entries[i].identity), "handle:%p", device);
        }
    }
    return snapshot;
}

size_t AGDeviceSnapshotCount(const AGDeviceSnapshot *snapshot) {
    return snapshot ? snapshot->count : 0;
}

int AGDeviceSnapshotSupportsStableIdentity(const AGDeviceSnapshot *snapshot) {
    return snapshot ? snapshot->supportsStableIdentity : 0;
}

uintptr_t AGDeviceSnapshotHandleAtIndex(const AGDeviceSnapshot *snapshot, size_t index) {
    return snapshot && index < snapshot->count ? snapshot->entries[index].handle : 0;
}

const char *AGDeviceSnapshotIdentityAtIndex(const AGDeviceSnapshot *snapshot, size_t index) {
    return snapshot && index < snapshot->count ? snapshot->entries[index].identity : NULL;
}

void AGReleaseDeviceSnapshot(AGDeviceSnapshot *snapshot) {
    if (!snapshot) return;
    if (snapshot->devices) CFRelease(snapshot->devices);
    free(snapshot);
}

int AGRegisterDevice(uintptr_t handle, uintptr_t token) {
    if (!handle || !token || !bridgeStarted || !registerCallback || !startDevice) return -1;

    pthread_mutex_lock(&registrationLock);
    for (size_t i = 0; i < registrationCount; ++i) {
        if (registrations[i].device == (void *)handle) {
            int result = registrations[i].token == token ? 0 : -1;
            pthread_mutex_unlock(&registrationLock);
            return result;
        }
    }
    if (registrationCount == registrationCapacity) {
        size_t capacity = registrationCapacity == 0 ? 4 : registrationCapacity * 2;
        if (capacity < registrationCapacity || capacity > SIZE_MAX / sizeof(DeviceRegistration)) {
            pthread_mutex_unlock(&registrationLock);
            return -1;
        }
        DeviceRegistration *grown = realloc(registrations, capacity * sizeof(DeviceRegistration));
        if (!grown) {
            pthread_mutex_unlock(&registrationLock);
            return -1;
        }
        registrations = grown;
        registrationCapacity = capacity;
    }
    size_t callbackSlot = 0;
    if (AGReserveCallbackGeneration(callbackGenerations, token, &callbackSlot) != 0) {
        atomic_fetch_add_explicit(&callbackGenerationExhaustions, 1, memory_order_relaxed);
        pthread_mutex_unlock(&registrationLock);
        return -2;
    }
    registrations[registrationCount++] =
        (DeviceRegistration){(void *)handle, token, callbackSlot};
    MTCallback callback = callbackTrampolines[callbackSlot];
    pthread_mutex_unlock(&registrationLock);

    registerCallback((void *)handle, callback);
    atomic_fetch_add_explicit(&deviceRegistrationCalls, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&registeredDevices, 1, memory_order_relaxed);
    startDevice((void *)handle, 0);
    return 0;
}

void AGUnregisterDevice(uintptr_t handle, uintptr_t token) {
    if (!handle || !token) return;

    pthread_mutex_lock(&registrationLock);
    size_t callbackSlot = SIZE_MAX;
    for (size_t i = 0; i < registrationCount; ++i) {
        if (registrations[i].device == (void *)handle && registrations[i].token == token) {
            callbackSlot = registrations[i].callbackSlot;
            break;
        }
    }
    pthread_mutex_unlock(&registrationLock);
    if (callbackSlot == SIZE_MAX) return;

    stopDevice((void *)handle);
    unregisterCallback((void *)handle, callbackTrampolines[callbackSlot]);

    pthread_mutex_lock(&registrationLock);
    for (size_t i = 0; i < registrationCount; ++i) {
        if (registrations[i].device == (void *)handle && registrations[i].token == token) {
            registrations[i] = registrations[registrationCount - 1];
            registrationCount--;
            break;
        }
    }
    pthread_mutex_unlock(&registrationLock);

    atomic_fetch_add_explicit(&deviceStopCalls, 1, memory_order_relaxed);
    atomic_fetch_sub_explicit(&registeredDevices, 1, memory_order_relaxed);
}

void AGStop(void) {
    pthread_mutex_lock(&registrationLock);
    int started = bridgeStarted;
    pthread_mutex_unlock(&registrationLock);
    if (!started) return;

    while (1) {
        pthread_mutex_lock(&registrationLock);
        if (registrationCount == 0) {
            receive = NULL;
            bridgeStarted = 0;
            pthread_mutex_unlock(&registrationLock);
            break;
        }
        DeviceRegistration registration = registrations[registrationCount - 1];
        pthread_mutex_unlock(&registrationLock);
        AGUnregisterDevice((uintptr_t)registration.device, registration.token);
    }
    // Retain loaded code and callback slots until process exit in case callbacks are still unwinding.
}
