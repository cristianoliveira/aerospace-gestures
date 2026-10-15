#include "MultitouchBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDDeviceKeys.h>
#include <dispatch/dispatch.h>
#include <stdatomic.h>
#include <stdlib.h>

#define MAX_TRACKPAD_SERVICES 128
#define TOPOLOGY_DEBOUNCE_NANOSECONDS (500 * NSEC_PER_MSEC)

typedef struct {
    uint64_t serviceIDs[MAX_TRACKPAD_SERVICES];
    size_t count;
} TrackpadServices;

static IONotificationPortRef notificationPort;
static CFRunLoopSourceRef runLoopSource;
static CFRunLoopRef observerRunLoop;
static io_iterator_t publishedIterator = IO_OBJECT_NULL;
static io_iterator_t terminatedIterator = IO_OBJECT_NULL;
static dispatch_source_t debounceTimer;
static AGDeviceTopologyCallback topologyCallback;
static TrackpadServices activeTrackpadServices;
static int observerStarted;
static _Atomic uint64_t topologyEventNotifications;
static _Atomic uint64_t topologyCallbackDeliveries;
static _Atomic uint64_t topologyObserverFailures;
static _Atomic uint64_t publishedServices;
static _Atomic uint64_t terminatedServices;
static _Atomic uint64_t touchPadMatches;
static _Atomic uint64_t usagePairsNonmatches;
static _Atomic uint64_t usagePairsInvalid;
static _Atomic uint64_t trackedTouchPadTerminations;

static void noteObserverFailure(void) {
    atomic_fetch_add_explicit(&topologyObserverFailures, 1, memory_order_relaxed);
}

static int containsService(uint64_t serviceID) {
    for (size_t i = 0; i < activeTrackpadServices.count; ++i) {
        if (activeTrackpadServices.serviceIDs[i] == serviceID) return 1;
    }
    return 0;
}

static int addService(uint64_t serviceID) {
    if (containsService(serviceID)) return 0;
    if (activeTrackpadServices.count == MAX_TRACKPAD_SERVICES) return -1;
    activeTrackpadServices.serviceIDs[activeTrackpadServices.count++] = serviceID;
    return 1;
}

static int removeService(uint64_t serviceID) {
    for (size_t i = 0; i < activeTrackpadServices.count; ++i) {
        if (activeTrackpadServices.serviceIDs[i] != serviceID) continue;
        activeTrackpadServices.serviceIDs[i] =
            activeTrackpadServices.serviceIDs[--activeTrackpadServices.count];
        return 1;
    }
    return 0;
}

static int numberValue(CFTypeRef value, int *out) {
    return value && CFGetTypeID(value) == CFNumberGetTypeID()
        && CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, out);
}

int AGClassifyHIDUsagePairs(int usagePairsIsArray, int hasTouchPadMatch, int hasInvalidPair) {
    if (!usagePairsIsArray) return -1;
    if (hasTouchPadMatch) return 1;
    return hasInvalidPair ? -1 : 0;
}

static void recordUsagePairsClassification(int classification) {
    if (classification > 0) {
        atomic_fetch_add_explicit(&touchPadMatches, 1, memory_order_relaxed);
    } else if (classification == 0) {
        atomic_fetch_add_explicit(&usagePairsNonmatches, 1, memory_order_relaxed);
    } else {
        atomic_fetch_add_explicit(&usagePairsInvalid, 1, memory_order_relaxed);
    }
}

static int isTouchPadService(io_service_t service) {
    CFMutableDictionaryRef properties = NULL;
    if (IORegistryEntryCreateCFProperties(
            service, &properties, kCFAllocatorDefault, 0) != KERN_SUCCESS) {
        recordUsagePairsClassification(-1);
        noteObserverFailure();
        return -1;
    }

    CFTypeRef pairsValue = CFDictionaryGetValue(properties, CFSTR(kIOHIDDeviceUsagePairsKey));
    if (!pairsValue || CFGetTypeID(pairsValue) != CFArrayGetTypeID()) {
        recordUsagePairsClassification(-1);
        CFRelease(properties);
        noteObserverFailure();
        return -1;
    }

    CFArrayRef pairs = (CFArrayRef)pairsValue;
    int matched = 0;
    int hasInvalidPair = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(pairs); ++i) {
        CFTypeRef pairValue = CFArrayGetValueAtIndex(pairs, i);
        if (!pairValue || CFGetTypeID(pairValue) != CFDictionaryGetTypeID()) {
            hasInvalidPair = 1;
            continue;
        }
        CFDictionaryRef pair = (CFDictionaryRef)pairValue;
        int usagePage = 0, usage = 0;
        if (!numberValue(CFDictionaryGetValue(pair, CFSTR(kIOHIDDeviceUsagePageKey)), &usagePage)
            || !numberValue(CFDictionaryGetValue(pair, CFSTR(kIOHIDDeviceUsageKey)), &usage)) {
            hasInvalidPair = 1;
            continue;
        }
        // HID Digitizer page 0x0d, Touch Pad usage 0x05.
        if (usagePage == 0x0d && usage == 0x05) matched = 1;
    }
    int classification = AGClassifyHIDUsagePairs(1, matched, hasInvalidPair);
    recordUsagePairsClassification(classification);
    CFRelease(properties);
    return classification;
}

static int serviceID(io_service_t service, uint64_t *identifier) {
    return IORegistryEntryGetRegistryEntryID(service, identifier) == KERN_SUCCESS;
}

static void deliverTopologyChange(void *context) {
    (void)context;
    if (!topologyCallback) return;
    atomic_fetch_add_explicit(&topologyCallbackDeliveries, 1, memory_order_relaxed);
    topologyCallback();
}

static void noteTopologyChange(void) {
    if (!debounceTimer || !topologyCallback) return;
    atomic_fetch_add_explicit(&topologyEventNotifications, 1, memory_order_relaxed);
    dispatch_source_set_timer(
        debounceTimer,
        dispatch_time(DISPATCH_TIME_NOW, TOPOLOGY_DEBOUNCE_NANOSECONDS),
        DISPATCH_TIME_FOREVER,
        50 * NSEC_PER_MSEC);
}

static void drainPublished(io_iterator_t iterator, int reportChanges) {
    io_service_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        atomic_fetch_add_explicit(&publishedServices, 1, memory_order_relaxed);
        uint64_t identifier = 0;
        int touchPadMatch = isTouchPadService(service);
        if (touchPadMatch > 0) {
            if (!serviceID(service, &identifier)) {
                noteObserverFailure();
            } else {
                int added = addService(identifier);
                if (added < 0) {
                    noteObserverFailure();
                } else if (reportChanges && added > 0) {
                    noteTopologyChange();
                }
            }
        }
        IOObjectRelease(service);
    }
}

static void drainTerminated(io_iterator_t iterator, int reportChanges) {
    io_service_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        atomic_fetch_add_explicit(&terminatedServices, 1, memory_order_relaxed);
        uint64_t identifier = 0;
        if (!serviceID(service, &identifier)) {
            noteObserverFailure();
        } else if (removeService(identifier)) {
            atomic_fetch_add_explicit(&trackedTouchPadTerminations, 1, memory_order_relaxed);
            if (reportChanges) noteTopologyChange();
        }
        IOObjectRelease(service);
    }
}

static void devicePublished(void *context, io_iterator_t iterator) {
    (void)context;
    drainPublished(iterator, 1);
}

static void deviceTerminated(void *context, io_iterator_t iterator) {
    (void)context;
    drainTerminated(iterator, 1);
}

static void releaseObserverResources(void) {
    topologyCallback = NULL;
    if (debounceTimer) {
        dispatch_source_cancel(debounceTimer);
        dispatch_release(debounceTimer);
        debounceTimer = NULL;
    }
    if (observerRunLoop && runLoopSource) {
        CFRunLoopRemoveSource(observerRunLoop, runLoopSource, kCFRunLoopCommonModes);
    }
    if (publishedIterator != IO_OBJECT_NULL) {
        IOObjectRelease(publishedIterator);
        publishedIterator = IO_OBJECT_NULL;
    }
    if (terminatedIterator != IO_OBJECT_NULL) {
        IOObjectRelease(terminatedIterator);
        terminatedIterator = IO_OBJECT_NULL;
    }
    if (notificationPort) {
        IONotificationPortDestroy(notificationPort);
        notificationPort = NULL;
    }
    runLoopSource = NULL;
    observerRunLoop = NULL;
    activeTrackpadServices.count = 0;
    observerStarted = 0;
}

static int registerNotification(
    const io_name_t notification,
    IOServiceMatchingCallback callback,
    io_iterator_t *iterator) {
    CFMutableDictionaryRef matching = IOServiceMatching("IOHIDDevice");
    if (!matching) return kIOReturnNoMemory;
    return IOServiceAddMatchingNotification(
        notificationPort, notification, matching, callback, NULL, iterator);
}

int AGStartDeviceTopologyObserver(AGDeviceTopologyCallback callback) {
    if (!callback) return -1;
    if (observerStarted) return 0;

    notificationPort = IONotificationPortCreate(kIOMainPortDefault);
    if (!notificationPort) {
        atomic_fetch_add_explicit(&topologyObserverFailures, 1, memory_order_relaxed);
        return -1;
    }
    observerRunLoop = CFRunLoopGetMain();
    runLoopSource = IONotificationPortGetRunLoopSource(notificationPort);
    if (!observerRunLoop || !runLoopSource) {
        releaseObserverResources();
        atomic_fetch_add_explicit(&topologyObserverFailures, 1, memory_order_relaxed);
        return -1;
    }
    CFRunLoopAddSource(observerRunLoop, runLoopSource, kCFRunLoopCommonModes);

    activeTrackpadServices.count = 0;
    if (registerNotification(kIOFirstMatchNotification, devicePublished, &publishedIterator)
            != KERN_SUCCESS
        || publishedIterator == IO_OBJECT_NULL
        || registerNotification(kIOTerminatedNotification, deviceTerminated, &terminatedIterator)
            != KERN_SUCCESS
        || terminatedIterator == IO_OBJECT_NULL) {
        releaseObserverResources();
        atomic_fetch_add_explicit(&topologyObserverFailures, 1, memory_order_relaxed);
        return -1;
    }

    dispatch_source_t timer = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!timer) {
        releaseObserverResources();
        atomic_fetch_add_explicit(&topologyObserverFailures, 1, memory_order_relaxed);
        return -1;
    }
    dispatch_source_set_event_handler_f(timer, deliverTopologyChange);
    dispatch_source_set_timer(timer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
    dispatch_resume(timer);

    debounceTimer = timer;
    topologyCallback = callback;
    observerStarted = 1;
    drainPublished(publishedIterator, 0);
    drainTerminated(terminatedIterator, 1);
    return 0;
}

void AGStopDeviceTopologyObserver(void) {
    if (!observerStarted && !notificationPort) return;
    releaseObserverResources();
}

void AGReadDeviceTopologyDiagnostics(AGDeviceTopologyDiagnostics *diagnostics) {
    if (!diagnostics) return;
    diagnostics->event_notifications = atomic_load_explicit(&topologyEventNotifications, memory_order_relaxed);
    diagnostics->published_services = atomic_load_explicit(&publishedServices, memory_order_relaxed);
    diagnostics->terminated_services = atomic_load_explicit(&terminatedServices, memory_order_relaxed);
    diagnostics->touchpad_matches = atomic_load_explicit(&touchPadMatches, memory_order_relaxed);
    diagnostics->usage_pairs_nonmatches = atomic_load_explicit(&usagePairsNonmatches, memory_order_relaxed);
    diagnostics->usage_pairs_invalid = atomic_load_explicit(&usagePairsInvalid, memory_order_relaxed);
    diagnostics->tracked_touchpad_terminations = atomic_load_explicit(&trackedTouchPadTerminations, memory_order_relaxed);
    diagnostics->observer_failures = atomic_load_explicit(&topologyObserverFailures, memory_order_relaxed);
}

void AGReadTopologyCallbackDeliveries(uint64_t *callbackDeliveries) {
    if (callbackDeliveries)
        *callbackDeliveries = atomic_load_explicit(&topologyCallbackDeliveries, memory_order_relaxed);
}
