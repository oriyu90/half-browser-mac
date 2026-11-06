#ifndef SETTINGS_WINDOW_H
#define SETTINGS_WINDOW_H
#import <Cocoa/Cocoa.h>

@interface SettingsWindowController : NSWindowController
+ (instancetype)shared;
- (void)showWindow;
@end
#endif
