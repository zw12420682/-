#import "HAOController.h"
#import "HAODiagnostics.h"
#import "HAOLog.h"
#import <Foundation/Foundation.h>

static void HAOPreferencesChanged(__unused CFNotificationCenterRef center, __unused void *observer,
                                  __unused CFStringRef name, __unused const void *object,
                                  __unused CFDictionaryRef userInfo) {
    [[HAOController shared] tick];
}

static void HAODiagnosticsRequested(__unused CFNotificationCenterRef center, __unused void *observer,
                                    __unused CFStringRef name, __unused const void *object,
                                    __unused CFDictionaryRef userInfo) {
    HAODumpDiagnostics();
}

// SpringBoard only: the tweak owns a polling timer and must not run elsewhere.
__attribute__((constructor)) static void HAOInit(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        HAOLog(@"install: loaded into SpringBoard");
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            HAOPreferencesChanged, CFSTR("local.hotspotautooff/preferences.changed"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            HAODiagnosticsRequested, CFSTR("local.hotspotautooff/diagnostics"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        [[HAOController shared] start];
    });
}
