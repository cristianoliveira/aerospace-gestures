#ifndef MULTITOUCH_BRIDGE_H
#define MULTITOUCH_BRIDGE_H
#include <stdint.h>
typedef struct { int32_t id; float x; float y; } AGContact;
typedef void (*AGFrameCallback)(uintptr_t device, uint32_t frame, const AGContact *contacts, int count);
typedef struct {
    uint64_t callback_arrivals;
    uint64_t invalid_frame_rejects;
    uint64_t device_registration_calls;
    uint64_t device_stop_calls;
    uint64_t registered_devices;
    uint64_t last_callback_age_nanoseconds;
} AGBridgeDiagnostics;
// Returns aggregate counters only; no device identifiers or contact data are exposed.
void AGReadBridgeDiagnostics(AGBridgeDiagnostics *diagnostics);
// Returns NULL on success, otherwise a static diagnostic. Call start/stop on main thread.
const char *AGStart(AGFrameCallback callback);
void AGStop(void);
#endif
