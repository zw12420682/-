#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface HAOPreferences : PSListController
@end

@implementation HAOPreferences
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    CFPreferencesAppSynchronize(CFSTR("local.hotspotautooff"));
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)[specifier propertyForKey:@"key"], CFSTR("local.hotspotautooff")));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    CFPreferencesSetAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"],
        (__bridge CFPropertyListRef)value, CFSTR("local.hotspotautooff"));
    CFPreferencesAppSynchronize(CFSTR("local.hotspotautooff"));
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("local.hotspotautooff/preferences.changed"), NULL, NULL, YES);
}
- (void)checkNow {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("local.hotspotautooff/preferences.changed"), NULL, NULL, YES);
}
- (void)exportDiagnostics {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("local.hotspotautooff/diagnostics"), NULL, NULL, YES);
}
@end
