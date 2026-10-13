// Shared logger. Writes to NSLog and to a single file so the log does not end up
// duplicated across two paths (which made an earlier report twice as long).
#pragma once
#import <Foundation/Foundation.h>
#include <stdarg.h>
#include <stdio.h>
#include <unistd.h>

static inline NSString *HAOLogPath(void) {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *candidates = @[
            @"/var/tmp/hotspot-autooff.log",
            @"/var/mobile/Library/Logs/hotspot-autooff.log",
            [NSTemporaryDirectory() stringByAppendingPathComponent:@"hotspot-autooff.log"],
        ];
        for (NSString *candidate in candidates) {
            FILE *file = fopen(candidate.fileSystemRepresentation, "a");
            if (!file) continue;
            fclose(file);
            path = candidate;
            break;
        }
    });
    return path;
}

static inline void HAOLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[HotspotAutoOff] %@", message);
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"MM-dd HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"%@ [pid=%d] %@\n",
                      [formatter stringFromDate:NSDate.date], getpid(), message];
    NSString *path = HAOLogPath();
    if (!path) return;
    FILE *file = fopen(path.fileSystemRepresentation, "a");
    if (!file) return;
    fputs(line.UTF8String, file);
    fclose(file);
}
