#import <Cocoa/Cocoa.h>
#include "bookmark_editor.h"
#include "bookmarks.h"
#include "localization.h"

static BookmarkEditorController* g_shared = nil;

@implementation BookmarkEditorController {
    NSTextField* _titleField;
    NSTextField* _urlField;
    NSString* _originalUrl;
}

+ (instancetype)shared {
    if (!g_shared) {
        g_shared = [[BookmarkEditorController alloc] init];
    }
    return g_shared;
}

- (instancetype)init {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 200)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
        backing:NSBackingStoreBuffered
        defer:NO];
    [window setTitle:[NSString stringWithUTF8String:L("bookmark.edit_title").c_str()]];
    [window center];
    self = [super initWithWindow:window];
    if (self) {
        NSView* content = [window contentView];

        NSTextField* titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 150, 80, 20)];
        [titleLabel setStringValue:[NSString stringWithUTF8String:L("bookmark.field_title").c_str()]];
        [titleLabel setBezeled:NO];
        [titleLabel setDrawsBackground:NO];
        [titleLabel setEditable:NO];
        [content addSubview:titleLabel];

        _titleField = [[NSTextField alloc] initWithFrame:NSMakeRect(100, 148, 300, 24)];
        [content addSubview:_titleField];

        NSTextField* urlLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 110, 80, 20)];
        [urlLabel setStringValue:[NSString stringWithUTF8String:L("bookmark.field_url").c_str()]];
        [urlLabel setBezeled:NO];
        [urlLabel setDrawsBackground:NO];
        [urlLabel setEditable:NO];
        [content addSubview:urlLabel];

        _urlField = [[NSTextField alloc] initWithFrame:NSMakeRect(100, 108, 300, 24)];
        [content addSubview:_urlField];

        NSButton* saveBtn = [[NSButton alloc] initWithFrame:NSMakeRect(220, 60, 100, 32)];
        [saveBtn setTitle:[NSString stringWithUTF8String:L("bookmark.save").c_str()]];
        [saveBtn setBezelStyle:NSBezelStyleRounded];
        [saveBtn setTarget:self];
        [saveBtn setAction:@selector(save:)];
        [content addSubview:saveBtn];

        NSButton* deleteBtn = [[NSButton alloc] initWithFrame:NSMakeRect(320, 60, 100, 32)];
        [deleteBtn setTitle:[NSString stringWithUTF8String:L("bookmark.delete").c_str()]];
        [deleteBtn setBezelStyle:NSBezelStyleRounded];
        [deleteBtn setTarget:self];
        [deleteBtn setAction:@selector(deleteBookmark:)];
        [content addSubview:deleteBtn];

        NSButton* cancelBtn = [[NSButton alloc] initWithFrame:NSMakeRect(120, 60, 100, 32)];
        [cancelBtn setTitle:[NSString stringWithUTF8String:L("bookmark.cancel").c_str()]];
        [cancelBtn setBezelStyle:NSBezelStyleRounded];
        [cancelBtn setTarget:self];
        [cancelBtn setAction:@selector(cancel:)];
        [content addSubview:cancelBtn];
    }
    return self;
}

- (void)showForTitle:(NSString*)title url:(NSString*)url {
    [_titleField setStringValue:title];
    [_urlField setStringValue:url];
    _originalUrl = url;
    [[self window] makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)save:(id)sender {
    std::string title = [[_titleField stringValue] UTF8String];
    std::string url = [[_urlField stringValue] UTF8String];
    if (url.empty()) return;

    // Remove old entry if URL changed
    if (_originalUrl && [_originalUrl length] > 0) {
        BookmarkStore::instance().remove([_originalUrl UTF8String]);
    }
    BookmarkStore::instance().add(title, url);
    [[self window] close];
}

- (void)deleteBookmark:(id)sender {
    if (_originalUrl && [_originalUrl length] > 0) {
        BookmarkStore::instance().remove([_originalUrl UTF8String]);
    }
    [[self window] close];
}

- (void)cancel:(id)sender {
    [[self window] close];
}

@end
