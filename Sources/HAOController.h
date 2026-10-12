#pragma once
#import <Foundation/Foundation.h>

// Polls the Personal Hotspot and closes it after the configured idle period.
@interface HAOController : NSObject
+ (instancetype)shared;
- (void)start;
- (void)stop;
// Runs one evaluation immediately (also used by the polling timer).
- (void)tick;
@end
