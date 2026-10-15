#ifndef MULTITOUCH_BRIDGE_H
#define MULTITOUCH_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
typedef struct { int32_t id; float x; float y; } AGContact;
typedef void (*AGFrameCallback)(uintptr_t registration_token, uint32_t frame, const AGContact *contacts, int count);
typedef void (*AGDeviceTopologyCallback)(void);
typedef struct AGDeviceSnapshot AGDeviceSnapshot;
typedef struct AGCallbackGenerationTable AGCallbackGenerationTable;
typedef struct {
    uint64_t callback_arrivals;
    uint64_t invalid_frame_rejects;
    uint64_t device_snapshot_enumerations;
    uint64_t device_snapshot_successes;
    uint64_t device_snapshot_last_count;
    uint64_t iohid_published_services;
    uint64_t iohid_terminated_services;
    uint64_t touchpad_matches;
    uint64_t usage_pairs_nonmatches;
    uint64_t usage_pairs_invalid;
    uint64_t tracked_touchpad_terminations;
    uint64_t topology_callback_deliveries;
    uint64_t device_registration_calls;
    uint64_t device_stop_calls;
    uint64_t callback_generation_exhaustions;
    uint64_t topology_event_notifications;
    uint64_t topology_observer_failures;
    uint64_t registered_devices;
    uint64_t last_callback_age_nanoseconds;
} AGBridgeDiagnostics;
typedef struct {
    uint64_t event_notifications;
    uint64_t published_services;
    uint64_t terminated_services;
    uint64_t touchpad_matches;
    uint64_t usage_pairs_nonmatches;
    uint64_t usage_pairs_invalid;
    uint64_t tracked_touchpad_terminations;
    uint64_t observer_failures;
} AGDeviceTopologyDiagnostics;
// Returns aggregate counters only; no device identifiers or contact data are exposed.
void AGReadBridgeDiagnostics(AGBridgeDiagnostics *diagnostics);
// Observes HID digitizer/TouchPad topology only; it does not open or read input reports.
int AGStartDeviceTopologyObserver(AGDeviceTopologyCallback callback);
void AGStopDeviceTopologyObserver(void);
void AGReadDeviceTopologyDiagnostics(AGDeviceTopologyDiagnostics *diagnostics);
// Internal test seam: -1 invalid/missing pairs, 0 valid nonmatch, 1 TouchPad match.
int AGClassifyHIDUsagePairs(int usagePairsIsArray, int hasTouchPadMatch, int hasInvalidPair);
void AGReadTopologyCallbackDeliveries(uint64_t *callbackDeliveries);
// Internal test seam: callback slots are monotonic and never recycled during a process lifetime.
AGCallbackGenerationTable *AGCreateCallbackGenerationTable(size_t capacity);
void AGDestroyCallbackGenerationTable(AGCallbackGenerationTable *table);
int AGReserveCallbackGeneration(AGCallbackGenerationTable *table, uintptr_t token, size_t *slot);
uintptr_t AGCallbackGenerationToken(AGCallbackGenerationTable *table, size_t slot);
// Initializes the private bridge; an empty device list is valid and can be refreshed later.
const char *AGStart(AGFrameCallback callback);
// NULL means enumeration failure. A valid empty list is represented by a non-NULL snapshot.
// Stable value identities are reported only when both private getters are available and succeed.
AGDeviceSnapshot *AGCreateDeviceSnapshot(void);
size_t AGDeviceSnapshotCount(const AGDeviceSnapshot *snapshot);
int AGDeviceSnapshotSupportsStableIdentity(const AGDeviceSnapshot *snapshot);
uintptr_t AGDeviceSnapshotHandleAtIndex(const AGDeviceSnapshot *snapshot, size_t index);
const char *AGDeviceSnapshotIdentityAtIndex(const AGDeviceSnapshot *snapshot, size_t index);
void AGReleaseDeviceSnapshot(AGDeviceSnapshot *snapshot);
// Returns zero on successful registration; repeated registration of the same pair is a no-op.
int AGRegisterDevice(uintptr_t handle, uintptr_t registration_token);
void AGUnregisterDevice(uintptr_t handle, uintptr_t registration_token);
// Stops all active device registrations. Call bridge lifecycle operations on the main thread.
void AGStop(void);
#endif
