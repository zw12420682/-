#import "HAOHotspot.h"
#import "HAOLog.h"

#import <ifaddrs.h>
#include <errno.h>
#include <stddef.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <net/route.h>
#import <netinet/in.h>
#include <string.h>
#import <sys/socket.h>
#import <sys/sysctl.h>

NSString * const HAOHotspotInterface = @"bridge0";

// sockaddr entries inside a routing message are padded to 4-byte boundaries.
#define HAO_ROUND4(n) (((n) > 0) ? (1 + (((n) - 1) | 3)) : 4)

BOOL HAOHotspotIsActive(void) {
    const char *name = HAOHotspotInterface.UTF8String;
    if (if_nametoindex(name) == 0) return NO;
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0 || list == NULL) return NO;
    BOOL active = NO;
    for (struct ifaddrs *cur = list; cur; cur = cur->ifa_next) {
        if (!cur->ifa_name || strcmp(cur->ifa_name, name) != 0) continue;
        if (!cur->ifa_addr || cur->ifa_addr->sa_family != AF_INET) continue;
        if ((cur->ifa_flags & IFF_UP) == 0) continue;
        active = YES;
        break;
    }
    freeifaddrs(list);
    return active;
}

NSInteger HAOHotspotClientCount(void) {
    int mib[6] = { CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO };
    size_t needed = 0;
    if (sysctl(mib, 6, NULL, &needed, NULL, 0) != 0 || needed == 0) {
        HAOLog(@"clients: neighbour table size unavailable (errno=%d)", errno);
        return -1;
    }
    char *buffer = malloc(needed);
    if (!buffer) return -1;
    if (sysctl(mib, 6, buffer, &needed, NULL, 0) != 0) {
        HAOLog(@"clients: neighbour table read failed (errno=%d)", errno);
        free(buffer);
        return -1;
    }
    NSInteger count = 0;
    const size_t nameLength = strlen(HAOHotspotInterface.UTF8String);
    const char *name = HAOHotspotInterface.UTF8String;
    char *limit = buffer + needed;
    for (char *cursor = buffer; cursor + sizeof(struct rt_msghdr) <= limit; ) {
        struct rt_msghdr *rtm = (struct rt_msghdr *)cursor;
        if (rtm->rtm_msglen == 0) break;
        // Walk the address list; the link-layer entry carries the interface name.
        char *sa = cursor + sizeof(struct rt_msghdr);
        for (int bit = 0; bit < RTAX_MAX && sa + sizeof(struct sockaddr) <= cursor + rtm->rtm_msglen; bit++) {
            if ((rtm->rtm_addrs & (1 << bit)) == 0) continue;
            struct sockaddr *addr = (struct sockaddr *)sa;
            size_t length = addr->sa_len;
            if (length == 0) break;
            if (bit == RTAX_GATEWAY && addr->sa_family == AF_LINK &&
                length >= offsetof(struct sockaddr_dl, sdl_data)) {
                struct sockaddr_dl *link = (struct sockaddr_dl *)addr;
                size_t linkLength = offsetof(struct sockaddr_dl, sdl_data) + link->sdl_nlen;
                if (length >= linkLength && link->sdl_nlen == nameLength &&
                    memcmp(link->sdl_data, name, nameLength) == 0) {
                    count++;
                }
            }
            sa += HAO_ROUND4(length);
        }
        cursor += rtm->rtm_msglen;
    }
    free(buffer);
    return count;
}
