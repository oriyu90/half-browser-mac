#import <Cocoa/Cocoa.h>
#include "cef_view.h"
#include "simple_handler.h"
#include "include/cef_browser.h"
#include "include/cef_frame.h"

@implementation CefView

- (void)loadURL:(NSString*)url {
    auto handler = SimpleHandler::GetInstance();
    if (handler && handler->GetBrowser()) {
        handler->GetBrowser()->GetMainFrame()->LoadURL([url UTF8String]);
    }
}

- (void)goBack {
    auto handler = SimpleHandler::GetInstance();
    if (handler && handler->GetBrowser()) handler->GetBrowser()->GoBack();
}

- (void)goForward {
    auto handler = SimpleHandler::GetInstance();
    if (handler && handler->GetBrowser()) handler->GetBrowser()->GoForward();
}

- (void)reload {
    auto handler = SimpleHandler::GetInstance();
    if (handler && handler->GetBrowser()) handler->GetBrowser()->Reload();
}

- (NSString*)currentURL {
    auto handler = SimpleHandler::GetInstance();
    if (handler) return [NSString stringWithUTF8String:handler->GetURL().c_str()];
    return @"";
}

- (NSString*)currentTitle {
    auto handler = SimpleHandler::GetInstance();
    if (handler) return [NSString stringWithUTF8String:handler->GetTitle().c_str()];
    return @"";
}

@end
