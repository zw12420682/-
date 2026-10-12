// Shared diagnostic logger. Writes to NSLog and to the first writable path so the
// result can be inspected with a file manager instead of a live log viewer.
#pragma once
#import <Foundation/Foundation.h>
#include <stdarg.h>
#include <stdio.h>
#include <unistd.h>

static inline NSArray<NSString *> *HAOLogPaths(void) {
    static NSArray<NSString *> *paths = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *writable = [NSMutableArray array];
        NSArray<NSString *> *candidates = @[
            @"/var/tmp/hotspot-autooff.log",
            @"/var/mobile/Library/Logs/hotspot-autooff.log",
            [NSTemporaryDirectory() stringByAppendingPathComponent:@"hotspot-autooff.log"],
        ];
        for (NSString *candidate in candidates) {
            FILE *file = fopen(candidate.fileSystemRepresentation, "a");
            if (!file) continue;
            fclose(file);
            [writable addObject:candidate];
        }
        paths = writable;
    });
    return paths;
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
    for (NSString *path in HAOLogPaths()) {
        FILE *file = fopen(path.fileSystemRepresentation, "a");
        if (!file) continue;
        fputs(line.UTF8String, file);
        fclose(file);
    }
}
