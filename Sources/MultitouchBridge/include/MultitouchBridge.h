#ifndef MULTITOUCH_BRIDGE_H
#define MULTITOUCH_BRIDGE_H
#include <stdint.h>
typedef struct { int32_t id; float x; float y; } AGContact;
typedef void (*AGFrameCallback)(uintptr_t device, const AGContact *contacts, int count);
// Returns NULL on success, otherwise a static diagnostic. Call start/stop on main thread.
const char *AGStart(AGFrameCallback callback);
void AGStop(void);
#endif
