#import "HAOPreferences.h"

CFStringRef const HAODomain = CFSTR("local.hotspotautooff");

static id HAOValue(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, HAODomain));
}

BOOL HAOEnabled(void) {
    id value = HAOValue(@"Enabled");
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : YES;
}

NSInteger HAOTimeoutMinutes(void) {
    id value = HAOValue(@"TimeoutMinutes");
    NSInteger minutes = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 5;
    if (minutes < 1) minutes = 1;
    if (minutes > 60) minutes = 60;
    return minutes;
}

BOOL HAODryRun(void) {
    id value = HAOValue(@"DryRun");
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}
