#pragma once
#import <Foundation/Foundation.h>

// UIKit lifecycle adapter, installed when Google Photos launches in either build.
FOUNDATION_EXPORT void GSStartBackupIntegration(void);
// Main-thread lifecycle input; the monitor itself uses only Foundation.
FOUNDATION_EXPORT NSString *const GSUploadMonitorStateDidChangeNotification;
FOUNDATION_EXPORT void GSSetUploadHostForeground(BOOL foreground);
// Nonblocking snapshots, including while daemon/embedded requests are waiting.
FOUNDATION_EXPORT BOOL GSUploadHostForeground(void);
FOUNDATION_EXPORT BOOL GSUploadQueueActive(void);
FOUNDATION_EXPORT NSDictionary *GSUploadMonitorSnapshot(void);
FOUNDATION_EXPORT BOOL GSBackupDimmingEnabled(void);
FOUNDATION_EXPORT void GSSetBackupDimming(BOOL enabled);
