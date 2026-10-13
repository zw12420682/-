#import "HAODiagnostics.h"
#import "HAOHotspot.h"
#import "HAOLog.h"

#include <errno.h>
#import <arpa/inet.h>
#include <ifaddrs.h>
#include <mach-o/dyld.h>
#import <net/if.h>
#import <netinet/in.h>
#import <objc/runtime.h>
#include <sys/sysctl.h>

// Classes whose names look related to tethering; the dump shows which of them the
// running build actually has, plus their methods, so the control entry point can
// be picked from evidence instead of guesswork.
static NSArray<NSString *> *HAODiagnosticClassKeywords(void) {
    return @[ @"Hotspot", @"Sharing", @"MiFi", @"Tether", @"SoftAP",
              @"InternetSharing", @"Bridge", @"PersonalHotspot" ];
}

static NSArray<NSString *> *HAODiagnosticImageKeywords(void) {
    return @[ @"Sharing", @"MobileWiFi", @"WiFiKit", @"InternetSharing", @"Tether" ];
}

static void HAODumpInterfaces(void) {
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) {
        HAOLog(@"diag/if: getifaddrs failed (errno=%d)", errno);
        return;
    }
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *byName = [NSMutableDictionary dictionary];
    for (struct ifaddrs *cur = list; cur; cur = cur->ifa_next) {
        if (!cur->ifa_name || !cur->ifa_addr) continue;
        NSString *name = @(cur->ifa_name);
        NSMutableArray<NSString *> *entries = byName[name];
        if (!entries) {
            entries = [NSMutableArray array];
            byName[name] = entries;
        }
        sa_family_t family = cur->ifa_addr->sa_family;
        if (family == AF_INET) {
            char buffer[INET_ADDRSTRLEN] = {0};
            struct sockaddr_in *address = (struct sockaddr_in *)cur->ifa_addr;
            inet_ntop(AF_INET, &address->sin_addr, buffer, sizeof(buffer));
            [entries addObject:[NSString stringWithFormat:@"IPv4=%s flags=0x%08x", buffer, cur->ifa_flags]];
        } else if (family == AF_INET6) {
            [entries addObject:@"IPv6"];
        } else if (family == AF_LINK) {
            [entries addObject:[NSString stringWithFormat:@"LINK flags=0x%08x", cur->ifa_flags]];
        }
    }
    freeifaddrs(list);
    for (NSString *name in [byName.allKeys sortedArrayUsingSelector:@selector(compare:)])
        HAOLog(@"diag/if: %@ -> %@", name, [byName[name] componentsJoinedByString:@", "]);
}

static void HAODumpSharingPreferences(void) {
    NSArray<NSString *> *paths = @[
        @"/var/preferences/SystemConfiguration/com.apple.MobileInternetSharing.plist",
        @"/var/mobile/Library/Preferences/com.apple.MobileInternetSharing.plist",
        @"/var/jb/var/preferences/SystemConfiguration/com.apple.MobileInternetSharing.plist",
    ];
    for (NSString *path in paths) {
        NSDictionary *contents = [NSDictionary dictionaryWithContentsOfFile:path];
        HAOLog(@"diag/plist: %@ readable=%d", path, contents != nil);
        if (contents) HAOLog(@"diag/plist: %@ = %@", path.lastPathComponent, contents);
    }
    CFPropertyListRef all = CFPreferencesCopyMultiple(NULL, CFSTR("com.apple.MobileInternetSharing"),
                                                      kCFPreferencesAnyUser, kCFPreferencesAnyHost);
    HAOLog(@"diag/prefs: anyUser=%@", all ? (__bridge id)all : @"(nil)");
    if (all) CFRelease(all);
    CFPropertyListRef current = CFPreferencesCopyMultiple(NULL, CFSTR("com.apple.MobileInternetSharing"),
                                                          kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    HAOLog(@"diag/prefs: currentUser=%@", current ? (__bridge id)current : @"(nil)");
    if (current) CFRelease(current);
}

static void HAODumpImages(void) {
    NSArray<NSString *> *keywords = HAODiagnosticImageKeywords();
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *raw = _dyld_get_image_name(i);
        if (!raw) continue;
        NSString *path = @(raw);
        for (NSString *keyword in keywords) {
            if ([path rangeOfString:keyword].location == NSNotFound) continue;
            HAOLog(@"diag/image: %@", path);
            break;
        }
    }
}

static void HAODumpClasses(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        HAOLog(@"diag/class: objc_getClassList returned %d", count);
        return;
    }
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
    if (!classes) return;
    count = objc_getClassList(classes, count);
    NSArray<NSString *> *keywords = HAODiagnosticClassKeywords();
    NSInteger matched = 0;
    for (int i = 0; i < count; i++) {
        NSString *name = @(class_getName(classes[i]));
        BOOL hit = NO;
        for (NSString *keyword in keywords) {
            if ([name rangeOfString:keyword].location != NSNotFound) {
                hit = YES;
                break;
            }
        }
        if (!hit) continue;
        matched++;
        HAOLog(@"diag/class: %@", name);
        unsigned int instanceCount = 0;
        Method *instanceMethods = class_copyMethodList(classes[i], &instanceCount);
        for (unsigned int m = 0; m < instanceCount && m < 30; m++)
            HAOLog(@"diag/class:   -%@", NSStringFromSelector(method_getName(instanceMethods[m])));
        if (instanceMethods) free(instanceMethods);
        unsigned int classCount = 0;
        Method *classMethods = class_copyMethodList(object_getClass(classes[i]), &classCount);
        for (unsigned int m = 0; m < classCount && m < 15; m++)
            HAOLog(@"diag/class:   +%@", NSStringFromSelector(method_getName(classMethods[m])));
        if (classMethods) free(classMethods);
    }
    free(classes);
    HAOLog(@"diag/class: %ld matching classes out of %d", (long)matched, count);
}

// The daemon that owns the hotspot is not necessarily reachable from SpringBoard;
// list candidate processes so a second tweak filter can be aimed at it.
static void HAODumpProcesses(void) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size == 0) {
        HAOLog(@"diag/proc: enumeration failed (errno=%d)", errno);
        return;
    }
    struct kinfo_proc *procs = malloc(size);
    if (!procs) return;
    if (sysctl(mib, 4, procs, &size, NULL, 0) != 0) {
        HAOLog(@"diag/proc: read failed (errno=%d)", errno);
        free(procs);
        return;
    }
    size_t count = size / sizeof(struct kinfo_proc);
    NSArray<NSString *> *keywords = @[ @"shar", @"mifi", @"tether", @"internet", @"wifi" ];
    for (size_t i = 0; i < count; i++) {
        const char *raw = procs[i].kp_proc.p_comm;
        if (!raw || raw[0] == '\0') continue;
        NSString *process = @(raw);
        for (NSString *keyword in keywords) {
            if ([process rangeOfString:keyword options:NSCaseInsensitiveSearch].location == NSNotFound)
                continue;
            HAOLog(@"diag/proc: pid=%d comm=%s", procs[i].kp_proc.p_pid, raw);
            break;
        }
    }
    free(procs);
    HAOLog(@"diag/proc: %zu processes scanned", count);
}

void HAODumpDiagnostics(void) {
    HAOLog(@"diag: ===== begin =====");
    HAOLog(@"diag: hotspotActive=%d bridge=%@ clientCount=%ld",
           HAOHotspotIsActive(), HAOHotspotActiveBridge() ?: @"(none)", (long)HAOHotspotClientCount());
    HAODumpInterfaces();
    HAODumpSharingPreferences();
    HAODumpProcesses();
    HAODumpImages();
    HAODumpClasses();
    HAOLog(@"diag: ===== end =====");
}
