#pragma once
#import <Foundation/Foundation.h>

// Preference domain shared by the tweak and the preference bundle.
extern CFStringRef const HAODomain;

// YES when the tweak is switched on. Defaults to YES.
BOOL HAOEnabled(void);
// Idle minutes before the hotspot is closed. Clamped to 1...60, default 5.
NSInteger HAOTimeoutMinutes(void);
// When YES the tweak only logs what it would do (device-side debugging aid).
BOOL HAODryRun(void);
