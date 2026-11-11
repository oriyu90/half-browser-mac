#ifndef HISTORY_WINDOW_H
#define HISTORY_WINDOW_H

#import <Cocoa/Cocoa.h>

/// The browsing-history window: a searchable list with per-entry delete and a
/// "clear all" action. Android has the same screen; the macOS port only had a
/// menu item that did nothing.
@interface HistoryWindowController : NSWindowController
+ (instancetype)shared;
- (void)showWindow;
@end

#endif  // HISTORY_WINDOW_H
