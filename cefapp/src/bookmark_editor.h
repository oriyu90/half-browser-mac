#ifndef BOOKMARK_EDITOR_H
#define BOOKMARK_EDITOR_H
#import <Cocoa/Cocoa.h>

@interface BookmarkEditorController : NSWindowController
+ (instancetype)shared;
- (void)showForTitle:(NSString*)title url:(NSString*)url;
@end
#endif
