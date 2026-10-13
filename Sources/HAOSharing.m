#import "HAOSharing.h"
#import "HAOLog.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

static CFStringRef const HAOSharingDomain = CFSTR("com.apple.MobileInternetSharing");

// ------------------------------------------------- WFPersonalHotspotStateMonitor
// Control Center's hotspot button (CCUIConnectivityHotspotViewController, running
// inside SpringBoard) owns a WFPersonalHotspotStateMonitor and drives it through
// -setMISDiscoveryState:immediateDisable:. That selector is what actually stops
// MobileInternetSharing, so it is tried first and the cruder paths only run when
// it is unavailable.
//
// An instance created by the system is preferred over one we allocate, so -init
// and -setPhStateMonitor: are hooked to capture whichever appears first.
static __weak id HAOHotspotStateMonitor;
static id (*HAOOriginalMonitorInit)(id, SEL);
static void (*HAOOriginalSetPhStateMonitor)(id, SEL, id);

static id HAOMonitorInit(id self, SEL command) {
    id result = HAOOriginalMonitorInit ? HAOOriginalMonitorInit(self, command) : nil;
    if (result) HAOHotspotStateMonitor = result;
    return result;
}

static void HAOSetPhStateMonitor(id self, SEL command, id monitor) {
    if (HAOOriginalSetPhStateMonitor) HAOOriginalSetPhStateMonitor(self, command, monitor);
    if (monitor) HAOHotspotStateMonitor = monitor;
}

static void HAOInstallMonitorHooks(void) {
    static BOOL installed = NO;
    if (installed) return;
    Class monitorClass = NSClassFromString(@"WFPersonalHotspotStateMonitor");
    Class controllerClass = NSClassFromString(@"CCUIConnectivityHotspotViewController");
    if (!monitorClass && !controllerClass) return;
    if (monitorClass)
        MSHookMessageEx(monitorClass, @selector(init), (IMP)&HAOMonitorInit, (IMP *)&HAOOriginalMonitorInit);
    if (controllerClass)
        MSHookMessageEx(controllerClass, NSSelectorFromString(@"setPhStateMonitor:"),
                        (IMP)&HAOSetPhStateMonitor, (IMP *)&HAOOriginalSetPhStateMonitor);
    installed = YES;
    HAOLog(@"turnoff/monitor: hooked monitor=%@ controller=%@", monitorClass ?: @"-", controllerClass ?: @"-");
}

static id HAOStateMonitor(void) {
    HAOInstallMonitorHooks();
    if (HAOHotspotStateMonitor) return HAOHotspotStateMonitor;
    Class monitorClass = NSClassFromString(@"WFPersonalHotspotStateMonitor");
    if (!monitorClass) {
        HAOLog(@"turnoff/monitor: WFPersonalHotspotStateMonitor is not loaded");
        return nil;
    }
    @try {
        id created = [[monitorClass alloc] init];
        HAOLog(@"turnoff/monitor: no system instance yet, allocated one");
        return created;
    } @catch (NSException *error) {
        HAOLog(@"turnoff/monitor: alloc/init raised %@", error.reason);
        return nil;
    }
}

static BOOL HAOTurnOffViaStateMonitor(void) {
    id monitor = HAOStateMonitor();
    if (!monitor) return NO;
    SEL selector = NSSelectorFromString(@"setMISDiscoveryState:immediateDisable:");
    if (![monitor respondsToSelector:selector]) {
        HAOLog(@"turnoff/monitor: setMISDiscoveryState:immediateDisable: is missing");
        return NO;
    }
    @try {
        ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(monitor, selector, NO, YES);
        HAOLog(@"turnoff/monitor: setMISDiscoveryState=NO immediateDisable=YES sent");
        return YES;
    } @catch (NSException *error) {
        HAOLog(@"turnoff/monitor: setter raised %@", error.reason);
        return NO;
    }
}

// ---------------------------------------------------------------- SCPreferences
// The whole SCPreferences API is annotated API_UNAVAILABLE(ios) in the SDK, yet
// the sharing daemon still uses that preference domain. Every entry point is
// therefore bound at runtime through dlsym and skipped when a symbol is absent.
typedef void *(*HAOSCPreferencesCreate)(CFAllocatorRef, CFStringRef, CFStringRef);
typedef Boolean (*HAOSCPreferencesSetValue)(void *, CFStringRef, CFPropertyListRef);
typedef Boolean (*HAOSCPreferencesCommit)(void *);
typedef Boolean (*HAOSCPreferencesApply)(void *);

static BOOL HAOTurnOffViaPreferences(void) {
    HAOSCPreferencesCreate create = (HAOSCPreferencesCreate)dlsym(RTLD_DEFAULT, "SCPreferencesCreate");
    HAOSCPreferencesSetValue setValue = (HAOSCPreferencesSetValue)dlsym(RTLD_DEFAULT, "SCPreferencesSetValue");
    HAOSCPreferencesCommit commit = (HAOSCPreferencesCommit)dlsym(RTLD_DEFAULT, "SCPreferencesCommitChanges");
    HAOSCPreferencesApply apply = (HAOSCPreferencesApply)dlsym(RTLD_DEFAULT, "SCPreferencesApplyChanges");
    if (!create || !setValue || !commit || !apply) {
        HAOLog(@"turnoff/prefs: SCPreferences symbols unavailable");
        return NO;
    }
    void *prefs = create(kCFAllocatorDefault, CFSTR("HotspotAutoOff"), HAOSharingDomain);
    if (!prefs) {
        HAOLog(@"turnoff/prefs: SCPreferencesCreate failed");
        return NO;
    }
    Boolean wrote = false;
    CFArrayRef empty = CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
    if (empty) {
        wrote |= setValue(prefs, CFSTR("Hosts"), empty);
        CFRelease(empty);
    }
    wrote |= setValue(prefs, CFSTR("FamilyShare"), kCFBooleanFalse);
    Boolean committed = commit(prefs);
    Boolean applied = apply(prefs);
    CFRelease((CFTypeRef)prefs);
    HAOLog(@"turnoff/prefs: set=%d commit=%d apply=%d", wrote, committed, applied);
    return wrote || committed || applied;
}

// -------------------------------------------------------------- Darwin notify
static BOOL HAOTurnOffViaNotification(void) {
    static CFStringRef const names[] = {
        CFSTR("com.apple.MobileInternetSharing.stateChanged"),
        CFSTR("com.apple.MobileInternetSharing.preferencesChanged"),
        CFSTR("com.apple.system.config.network_change"),
    };
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    if (!center) return NO;
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        CFNotificationCenterPostNotification(center, names[i], NULL, NULL, YES);
    HAOLog(@"turnoff/notify: posted %zu notifications", sizeof(names) / sizeof(names[0]));
    return YES;
}

// ------------------------------------------------------- in-process class probes
static BOOL HAOCallSimple(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2) return NO;
    char returned = signature.methodReturnType[0];
    if (returned != 'v' && returned != 'B' && returned != 'c') return NO;
    @try {
        if (returned == 'v') ((void (*)(id, SEL))objc_msgSend)(target, selector);
        else if (!((BOOL (*)(id, SEL))objc_msgSend)(target, selector)) return NO;
        return YES;
    } @catch (__unused NSException *error) { return NO; }
}

static BOOL HAOTurnOffViaClassProbe(void) {
    NSArray<NSString *> *classNames = @[
        @"WFPersonalHotspotStateMonitor", @"WFSetPersonalHotspotIntent",
        @"CCUIConnectivityHotspotViewController", @"MISManager", @"SharingManager",
    ];
    NSArray<NSString *> *selectors = @[
        @"stopSharing", @"setSharingEnabled:", @"disableHotspot",
        @"stopPersonalHotspot", @"setSoftAPEnabled:",
    ];
    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        id target = nil;
        if ([cls respondsToSelector:NSSelectorFromString(@"sharedInstance")])
            target = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
        for (NSString *selectorName in selectors) {
            SEL selector = NSSelectorFromString(selectorName);
            if (HAOCallSimple(cls, selector) || HAOCallSimple(target, selector)) {
                HAOLog(@"turnoff/probe: %@ -%@ succeeded", className, selectorName);
                return YES;
            }
        }
    }
    HAOLog(@"turnoff/probe: no in-process sharing controller responded");
    return NO;
}

// ----------------------------------------------------------- MobileWiFi SoftAP
// Last resort: this stops the access point at the Wi-Fi layer without telling the
// sharing daemon, which can leave the Settings switch showing "on". It therefore
// only runs when nothing else worked.
typedef void *(*HAOWiFiManagerCreate)(CFAllocatorRef, int);
typedef CFArrayRef (*HAOWiFiManagerCopyDevices)(void *);
typedef BOOL (*HAOWiFiDeviceSetProperty)(void *, CFStringRef, CFTypeRef);

static BOOL HAOTurnOffViaSoftAP(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY);
    if (!handle) {
        HAOLog(@"turnoff/softap: MobileWiFi unavailable (%s)", dlerror());
        return NO;
    }
    HAOWiFiManagerCreate create = (HAOWiFiManagerCreate)dlsym(handle, "WiFiManagerClientCreate");
    HAOWiFiManagerCopyDevices copyDevices = (HAOWiFiManagerCopyDevices)dlsym(handle, "WiFiManagerClientCopyDevices");
    HAOWiFiDeviceSetProperty setProperty = (HAOWiFiDeviceSetProperty)dlsym(handle, "WiFiDeviceClientSetProperty");
    if (!create || !copyDevices || !setProperty) {
        HAOLog(@"turnoff/softap: MobileWiFi symbols missing");
        dlclose(handle);
        return NO;
    }
    BOOL done = NO;
    @try {
        void *manager = create(kCFAllocatorDefault, 0);
        CFArrayRef devices = manager ? copyDevices(manager) : NULL;
        if (devices) {
            for (CFIndex i = 0; i < CFArrayGetCount(devices); i++) {
                void *device = (void *)CFArrayGetValueAtIndex(devices, i);
                if (setProperty(device, CFSTR("SoftAP"), kCFBooleanFalse)) done = YES;
            }
            CFRelease(devices);
        }
        if (manager) CFRelease(manager);
    } @catch (__unused NSException *error) { done = NO; }
    dlclose(handle);
    HAOLog(@"turnoff/softap: set SoftAP=NO accepted=%d", done);
    return done;
}

BOOL HAOTurnOffHotspot(void) {
    HAOLog(@"turnoff: starting candidate chain");
    if (HAOTurnOffViaStateMonitor()) {
        HAOLog(@"turnoff: chain finished via state monitor");
        return YES;
    }
    BOOL any = NO;
    any |= HAOTurnOffViaClassProbe();
    any |= HAOTurnOffViaPreferences();
    any |= HAOTurnOffViaNotification();
    any |= HAOTurnOffViaSoftAP();
    HAOLog(@"turnoff: chain finished submitted=%d", any);
    return any;
}
