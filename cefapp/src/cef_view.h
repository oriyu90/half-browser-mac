#ifndef CEF_VIEW_H
#define CEF_VIEW_H
#import <Cocoa/Cocoa.h>

// SwiftUI-compatible NSView wrapper for CEF browser
@interface CefView : NSView
@property (copy) void (^onTitleChange)(NSString*);
@property (copy) void (^onURLChange)(NSString*);
@property (copy) void (^onLoadStateChange)(BOOL isLoading, BOOL canGoBack, BOOL canGoForward);
- (void)loadURL:(NSString*)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (NSString*)currentURL;
- (NSString*)currentTitle;
@end
#endif
