#pragma once
#import <Foundation/Foundation.h>

// Collects everything needed to identify the real Personal Hotspot control path
// on the current build: interfaces, sharing preferences, loaded images and the
// hotspot/sharing classes reachable from inside SpringBoard.
void HAODumpDiagnostics(void);
