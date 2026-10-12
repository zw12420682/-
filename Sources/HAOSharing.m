#import "HAOSharing.h"
#import "HAOLog.h"

#import <SystemConfiguration/SystemConfiguration.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static CFStringRef const HAOSharingDomain = CFSTR("com.apple.MobileInternetSharing");

// ---------------------------------------------------------------- SCPreferences
// The sharing daemon owns this preference domain; clearing the shared-host state
// and committing is the closest documented control point from another process.
static BOOL HAOTurnOffViaPreferences(void) {
    SCPreferencesRef prefs = SCPreferencesCreate(kCFAllocatorDefault, CFSTR("HotspotAutoOff"), HAOSharingDomain);
    if (!prefs) {
        HAOLog(@"turnoff/prefs: SCPreferencesCreate failed");
        return NO;
    }
    Boolean wrote = false;
    CFArrayRef empty = CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
    if (empty) {
        wrote |= SCPreferencesSetValue(prefs, CFSTR("Hosts"), empty);
        CFRelease(empty);
    }
    wrote |= SCPreferencesSetValue(prefs, CFSTR("FamilyShare"), kCFBooleanFalse);
    Boolean committed = SCPreferencesCommitChanges(prefs);
    Boolean applied = SCPreferencesApplyChanges(prefs);
    CFRelease(prefs);
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
// Some builds expose the sharing controller inside SpringBoard; probe plausible
// selectors rather than assuming one name.
static BOOL HAOCallSimple(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) return NO;
    NSMethodSignature *sig = [target methodSignatureForSelector:selector];
    if (!sig || sig.numberOfArguments != 2) return NO;
    char ret = sig.methodReturnType[0];
    if (ret != 'v' && ret != 'B' && ret != 'c') return NO;
    @try {
        if (ret == 'v') ((void (*)(id, SEL))objc_msgSend)(target, selector);
        else if (!((BOOL (*)(id, SEL))objc_msgSend)(target, selector)) return NO;
        return YES;
    } @catch (__unused NSException *error) { return NO; }
}

static BOOL HAOTurnOffViaClassProbe(void) {
    NSArray<NSString *> *classNames = @[
        @"MISManager", @"MobileInternetSharing", @"SharingManager",
        @"SCSharingManager", @"WiFiManager",
    ];
    NSArray<NSString *> *selectors = @[
        @"stopSharing", @"stopSharing:", @"setSharingEnabled:", @"setEnabled:",
        @"disableHotspot", @"stopPersonalHotspot", @"setSoftAPEnabled:",
    ];
    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        id target = nil;
        if ([cls respondsToSelector:NSSelectorFromString(@"sharedInstance")])
            target = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
        if (!target && [cls respondsToSelector:NSSelectorFromString(@"sharedManager")])
            target = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedManager"));
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
    BOOL any = NO;
    any |= HAOTurnOffViaClassProbe();
    any |= HAOTurnOffViaSoftAP();
    any |= HAOTurnOffViaPreferences();
    any |= HAOTurnOffViaNotification();
    HAOLog(@"turnoff: chain finished submitted=%d", any);
    return any;
}
