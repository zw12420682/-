#pragma once
#import <Foundation/Foundation.h>

// YES while the Wi-Fi Personal Hotspot is up (the system bridge interface exists,
// is running and holds an IPv4 address).
BOOL HAOHotspotIsActive(void);

// Number of clients currently attached to the hotspot, taken from the ARP table
// of the hotspot bridge. Returns -1 when the table cannot be read; callers must
// treat -1 as "unknown" and never close the hotspot on an unknown count.
NSInteger HAOHotspotClientCount(void);

// Interface name used by the Wi-Fi hotspot bridge (exposed for logging/tests).
extern NSString * const HAOHotspotInterface;
