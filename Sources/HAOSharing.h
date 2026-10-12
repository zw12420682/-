#pragma once
#import <Foundation/Foundation.h>

// Try to switch the Personal Hotspot off. Several private paths are probed in
// turn and every attempt is logged, because the effective one is build specific
// and can only be confirmed on a device (see hotspot-autooff.log).
// Returns YES when at least one path reported success.
BOOL HAOTurnOffHotspot(void);
