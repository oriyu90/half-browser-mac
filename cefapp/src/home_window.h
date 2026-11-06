#ifndef HOME_WINDOW_H
#define HOME_WINDOW_H
#import <Cocoa/Cocoa.h>

@interface HomeWindowController : NSWindowController <NSCollectionViewDataSource>
+ (instancetype)shared;
- (void)showHome;
- (void)refreshGrid;
@property (copy) void (^onOpenURL)(NSString* url);
@end
#endif
