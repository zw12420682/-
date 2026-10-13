#pragma once
#import <Foundation/Foundation.h>

// Name of the bridge interface that carries the Wi-Fi hotspot, or nil when no
// hotspot bridge is present. The index is NOT fixed (iOS 16 uses bridge100, not
// bridge0), so it is discovered from the live interface list.
NSString *HAOHotspotActiveBridge(void);

// YES while a hotspot bridge is up with an IPv4 address.
BOOL HAOHotspotIsActive(void);

// Number of clients attached to the hotspot, from the ARP table of the hotspot
// bridge. Returns -1 when the count cannot be determined; callers must treat -1
// as "unknown" and never close the hotspot then.
NSInteger HAOHotspotClientCount(void);
