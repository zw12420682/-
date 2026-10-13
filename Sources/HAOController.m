#import "HAOController.h"
#import "HAOHotspot.h"
#import "HAOPreferences.h"
#import "HAOSharing.h"
#import "HAOLog.h"

// Adaptive cadence: the neighbour scan is only worth running while the hotspot is
// up. When it is down every check costs a single if_nametoindex syscall, so the
// timer backs off to once a minute; while up it polls every 30 s. The timer is
// one-shot and rescheduled, so the cadence can follow the hotspot state, and the
// tolerance lets the kernel coalesce the wakeup with other timers.
static const NSTimeInterval HAOPollIntervalActive = 30.0;
static const NSTimeInterval HAOPollIntervalDormant = 60.0;

@interface HAOController ()
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) NSTimeInterval idleSince;
@property(nonatomic) BOOL wasActive;
@property(nonatomic) BOOL running;
@end

@implementation HAOController

+ (instancetype)shared {
    static HAOController *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [HAOController new]; });
    return shared;
}

- (void)start {
    if (self.running) return;
    self.running = YES;
    HAOLog(@"monitor: started (poll %.0fs active / %.0fs dormant)", HAOPollIntervalActive, HAOPollIntervalDormant);
    [self tick];
}

- (void)stop {
    self.running = NO;
    [self.timer invalidate];
    self.timer = nil;
    HAOLog(@"monitor: stopped");
}

- (void)scheduleNext {
    [self.timer invalidate];
    self.timer = nil;
    if (!self.running) return;
    NSTimeInterval interval = self.wasActive ? HAOPollIntervalActive : HAOPollIntervalDormant;
    self.timer = [NSTimer timerWithTimeInterval:interval repeats:NO
        block:^(__unused NSTimer *timer) { [[HAOController shared] tick]; }];
    self.timer.tolerance = interval * 0.2;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)tick {
    [self.timer invalidate];
    self.timer = nil;
    [self evaluate];
    [self scheduleNext];
}

- (void)evaluate {
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
        HAOLog(@"state: hotspot on (%@)", HAOHotspotActiveBridge() ?: @"?");
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
    if (idle < limit) return;
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
