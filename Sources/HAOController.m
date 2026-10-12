#import "HAOController.h"
#import "HAOHotspot.h"
#import "HAOPreferences.h"
#import "HAOSharing.h"
#import "HAOLog.h"

// Poll cadence. The idle threshold is measured in minutes, so 30 s is plenty and
// keeps the ARP scan off the hot path.
static const NSTimeInterval HAOPollInterval = 30.0;

@interface HAOController ()
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) NSTimeInterval idleSince;
@property(nonatomic) BOOL wasActive;
@end

@implementation HAOController

+ (instancetype)shared {
    static HAOController *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [HAOController new]; });
    return shared;
}

- (void)start {
    if (self.timer) return;
    HAOLog(@"monitor: started (poll %.0fs)", HAOPollInterval);
    self.timer = [NSTimer timerWithTimeInterval:HAOPollInterval repeats:YES
        block:^(__unused NSTimer *timer) { [[HAOController shared] tick]; }];
    self.timer.tolerance = 5.0;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self tick];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
    HAOLog(@"monitor: stopped");
}

- (void)tick {
    if (!HAOEnabled()) {
        if (self.wasActive || self.idleSince) HAOLog(@"state: tweak disabled");
        self.wasActive = NO;
        self.idleSince = 0;
        return;
    }
    BOOL active = HAOHotspotIsActive();
    if (!active) {
        if (self.wasActive) HAOLog(@"state: hotspot off");
        self.wasActive = NO;
        self.idleSince = 0;
        return;
    }
    if (!self.wasActive) {
        self.wasActive = YES;
        HAOLog(@"state: hotspot on");
    }
    NSInteger clients = HAOHotspotClientCount();
    if (clients < 0) {
        // Unknown client count must never close a hotspot that may be in use.
        self.idleSince = 0;
        return;
    }
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (clients > 0) {
        if (self.idleSince) HAOLog(@"idle: reset (%ld client(s) connected)", (long)clients);
        self.idleSince = 0;
        return;
    }
    if (!self.idleSince) {
        self.idleSince = now;
        HAOLog(@"idle: started, no client connected");
        return;
    }
    NSTimeInterval idle = now - self.idleSince;
    NSInteger limit = HAOTimeoutMinutes() * 60;
    if (idle < limit) {
        HAOLog(@"idle: %.0fs / %lds", idle, (long)limit);
        return;
    }
    self.idleSince = 0;
    if (HAODryRun()) {
        HAOLog(@"action: dry run, would close the hotspot after %.0fs idle", idle);
        return;
    }
    HAOLog(@"action: closing hotspot after %.0fs idle", idle);
    BOOL submitted = HAOTurnOffHotspot();
    HAOLog(@"action: turn-off submitted=%d", submitted);
}

@end
