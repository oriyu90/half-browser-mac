#import <Cocoa/Cocoa.h>
#include "home_window.h"
#include "bookmarks.h"
#include "favicon_service.h"
#include "localization.h"
#include "url_util.h"
#include "settings_store.h"

static HomeWindowController* g_shared = nil;

@implementation HomeWindowController {
    NSCollectionView* _collectionView;
    NSScrollView* _scrollView;
    NSTextField* _searchField;
    NSFont* _tileFont;
}

+ (instancetype)shared {
    if (!g_shared) {
        g_shared = [[HomeWindowController alloc] init];
    }
    return g_shared;
}

- (instancetype)init {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered
        defer:NO];
    [window setTitle:[NSString stringWithFormat:@"%@ — %@", [NSString stringWithUTF8String:L("app.name").c_str()], [NSString stringWithUTF8String:L("menu.home").c_str()]]];
    [window center];
    self = [super initWithWindow:window];
    if (self) {
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSView* content = [[self window] contentView];

    // Search bar
    _searchField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 550, 760, 28)];
    [_searchField setPlaceholderString:[NSString stringWithUTF8String:L("toolbar.address_placeholder").c_str()]];
    [_searchField setBezelStyle:NSTextFieldRoundedBezel];
    [_searchField setTarget:self];
    [_searchField setAction:@selector(search:)];
    [content addSubview:_searchField];

    // Collection view
    NSCollectionViewFlowLayout* layout = [[NSCollectionViewFlowLayout alloc] init];
    [layout setItemSize:NSMakeSize(100, 120)];
    [layout setMinimumInteritemSpacing:16];
    [layout setMinimumLineSpacing:16];
    [layout setSectionInset:NSEdgeInsetsMake(20, 20, 20, 20)];

    _collectionView = [[NSCollectionView alloc] initWithFrame:NSMakeRect(20, 20, 760, 510)];
    [_collectionView setCollectionViewLayout:layout];
    [_collectionView setDataSource:self];
    [_collectionView registerClass:[NSCollectionViewItem class] forItemWithIdentifier:@"BookmarkItem"];

    _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 20, 760, 510)];
    [_scrollView setDocumentView:_collectionView];
    [_scrollView setHasVerticalScroller:YES];
    [content addSubview:_scrollView];
}

- (void)showHome {
    [self refreshGrid];
    [[self window] makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)refreshGrid {
    // uiScale / fontScale / gridColumns were persisted but never applied, so
    // changing them in Settings had no visible effect. Apply them here, which
    // is the single point every path (launch, bookmark change, settings) goes
    // through.
    AppSettings s = SettingsStore::instance().load();
    [self applyLayoutForSettings:s];
    [_collectionView reloadData];
}

- (void)applyLayoutForSettings:(const AppSettings&)s {
    NSCollectionViewFlowLayout* layout = (NSCollectionViewFlowLayout*)[_collectionView collectionViewLayout];
    if (!layout) return;

    CGFloat scale = s.uiScale > 0 ? s.uiScale : 1.0;
    CGFloat base = 100.0 * scale;
    [layout setItemSize:NSMakeSize(base, base * 1.2)];
    [layout setMinimumInteritemSpacing:16 * scale];
    [layout setMinimumLineSpacing:16 * scale];

    // A fixed column count is expressed by constraining the item width to the
    // available width divided by the column count.
    NSRect bounds = _scrollView ? _scrollView.contentView.bounds : NSMakeRect(0, 0, 760, 510);
    CGFloat available = bounds.size.width - 40;  // section insets
    if (s.gridColumns > 0 && available > 0) {
        CGFloat spacing = 16 * scale * (s.gridColumns - 1);
        CGFloat width = (available - spacing) / s.gridColumns;
        if (width >= 48) {
            [layout setItemSize:NSMakeSize(width, width * 1.2)];
        }
    }

    // Font scale applies to the tile label.
    _tileFont = [NSFont systemFontOfSize:11 * (s.fontScale > 0 ? s.fontScale : 1.0)];
}

- (void)search:(id)sender {
    std::string input = [[_searchField stringValue] UTF8String];
    AppSettings s = SettingsStore::instance().load();
    std::string engine = s.searchEngine;
    std::string searchTemplate = "https://duckduckgo.com/?q=%s";
    if (engine == "google") searchTemplate = "https://www.google.com/search?q=%s";
    else if (engine == "brave") searchTemplate = "https://search.brave.com/search?q=%s";
    else if (engine == "ecosia") searchTemplate = "https://www.ecosia.org/search?q=%s";
    else if (engine == "kagi") searchTemplate = "https://kagi.com/search?q=%s";
    else if (engine == "mojeek") searchTemplate = "https://www.mojeek.com/search?q=%s";

    std::string url = UrlUtil::toNavigable(input, searchTemplate);
    if (url.empty()) return;
    if (self.onOpenURL) self.onOpenURL([NSString stringWithUTF8String:url.c_str()]);
}

// NSCollectionViewDataSource
- (NSInteger)collectionView:(NSCollectionView*)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)BookmarkStore::instance().all().size();
}

- (NSCollectionViewItem*)collectionView:(NSCollectionView*)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath*)indexPath {
    NSCollectionViewItem* item = [collectionView makeItemWithIdentifier:@"BookmarkItem" forIndexPath:indexPath];
    auto bookmarks = BookmarkStore::instance().all();
    if (indexPath.item < (NSInteger)bookmarks.size()) {
        auto& b = bookmarks[indexPath.item];
        [item setRepresentedObject:[NSString stringWithUTF8String:b.url.c_str()]];
        if (item.textField) {
            [item.textField setStringValue:[NSString stringWithUTF8String:b.title.c_str()]];
            [item.textField setAlignment:NSTextAlignmentCenter];
            // Text scale from Settings (1.0 when unset).
            [item.textField setFont:_tileFont ? _tileFont : [NSFont systemFontOfSize:11]];
        }
        if (item.imageView) {
            std::string favicon = FaviconService::fetchFavicon(b.url);
            if (!favicon.empty()) {
                NSImage* img = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:favicon.c_str()]];
                if (img) [item.imageView setImage:img];
            } else {
                // Not cached yet: show the monogram immediately and kick off a
                // background fetch so the grid never blocks on the network.
                //
                // The completion must NOT capture the item: NSCollectionView
                // releases items that scroll out of view, and the fetch can
                // take up to 10 s, so a captured pointer would be a
                // use-after-free (and testing it with `target.collectionView`
                // is itself the illegal access). Capture only the URL and look
                // the item up again on the main thread.
                std::string faviconUrl = b.url;
                NSCollectionView* owner = _collectionView;
                FaviconService::fetchFaviconAsync(faviconUrl, [owner, faviconUrl](std::string path) {
                    if (path.empty() || !owner) return;
                    // Re-resolve the row by URL: the grid may have been
                    // reordered or reloaded while the fetch was in flight.
                    auto current = BookmarkStore::instance().all();
                    NSInteger row = -1;
                    for (size_t i = 0; i < current.size(); ++i) {
                        if (current[i].url == faviconUrl) { row = (NSInteger)i; break; }
                    }
                    if (row < 0 || row >= [owner numberOfItemsInSection:0]) return;
                    NSCollectionViewItem* live =
                        [owner itemAtIndexPath:[NSIndexPath indexPathForItem:row inSection:0]];
                    if (!live) return;  // not currently on screen: nothing to update
                    NSImage* img = [[NSImage alloc] initWithContentsOfFile:
                        [NSString stringWithUTF8String:path.c_str()]];
                    if (img) [live.imageView setImage:img];
                });
                // Monogram fallback
                std::string mono = FaviconService::monogramFor(b.title);
                NSImage* img = [[NSImage alloc] initWithSize:NSMakeSize(64, 64)];
                [img lockFocus];
                [[NSColor colorWithCalibratedHue:0.6 saturation:0.6 brightness:0.7 alpha:1.0] setFill];
                [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, 64, 64) xRadius:12 yRadius:12] fill];
                NSDictionary* attrs = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:24], NSForegroundColorAttributeName: [NSColor whiteColor]};
                NSString* monoStr = [NSString stringWithUTF8String:mono.c_str()];
                NSSize size = [monoStr sizeWithAttributes:attrs];
                [monoStr drawAtPoint:NSMakePoint((64 - size.width) / 2, (64 - size.height) / 2) withAttributes:attrs];
                [img unlockFocus];
                [item.imageView setImage:img];
            }
        }
    }
    return item;
}

@end
