#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <string>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_command_line.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_helpers.h"
#include "simple_handler.h"
#include "theme.h"
#include "bookmarks.h"
#include "backup_service.h"
#include "settings_window.h"
#include "home_window.h"
#include "settings_store.h"
#include "localization.h"
#include "history_window.h"
#include "url_util.h"
#include "include/wrapper/cef_library_loader.h"

class MyApp : public CefApp {
public:
    MyApp() {}
    virtual ~MyApp() {}
    IMPLEMENT_REFCOUNTING(MyApp);
};

// Global references for toolbar actions
static CefRefPtr<SimpleHandler> g_handler;
static NSTextField* g_addressField = nullptr;
static NSWindow* g_window = nullptr;
static NSPanel* g_findPanel = nil;
static NSSearchField* g_findField = nil;

@interface ToolbarDelegate : NSObject <NSToolbarDelegate>
@end

@implementation ToolbarDelegate
- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    if ([itemIdentifier isEqualToString:@"Back"]) {
        NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = [NSString stringWithUTF8String:L("toolbar.back").c_str()];
        item.paletteLabel = item.label;
        item.toolTip = item.label;
        item.image = [NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:@"Back"];
        item.target = self;
        item.action = @selector(goBack:);
        return item;
    } else if ([itemIdentifier isEqualToString:@"Forward"]) {
        NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = [NSString stringWithUTF8String:L("toolbar.forward").c_str()];
        item.paletteLabel = item.label;
        item.toolTip = item.label;
        item.image = [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:@"Forward"];
        item.target = self;
        item.action = @selector(goForward:);
        return item;
    } else if ([itemIdentifier isEqualToString:@"Reload"]) {
        NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = [NSString stringWithUTF8String:L("toolbar.reload").c_str()];
        item.paletteLabel = item.label;
        item.toolTip = item.label;
        item.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"Reload"];
        item.target = self;
        item.action = @selector(reload:);
        return item;
    } else if ([itemIdentifier isEqualToString:@"Home"]) {
        NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = [NSString stringWithUTF8String:L("toolbar.home").c_str()];
        item.paletteLabel = item.label;
        item.toolTip = item.label;
        item.image = [NSImage imageWithSystemSymbolName:@"house" accessibilityDescription:@"Home"];
        item.target = self;
        item.action = @selector(goHome:);
        return item;
    } else if ([itemIdentifier isEqualToString:@"Address"]) {
        NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        item.label = @"Address";
        NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 400, 24)];
        field.placeholderString = [NSString stringWithUTF8String:L("toolbar.address_placeholder").c_str()];
        field.bezelStyle = NSTextFieldRoundedBezel;
        field.target = self;
        field.action = @selector(navigate:);
        g_addressField = field;
        item.view = field;
        // NSToolbarItem.minSize/maxSize are deprecated (macOS 12): size the
        // field with Auto Layout instead.
        field.translatesAutoresizingMaskIntoConstraints = NO;
        [[field.widthAnchor constraintGreaterThanOrEqualToConstant:200] setActive:YES];
        [[field.widthAnchor constraintLessThanOrEqualToConstant:600] setActive:YES];
        NSLayoutConstraint* preferred = [field.widthAnchor constraintEqualToConstant:400];
        preferred.priority = NSLayoutPriorityDefaultLow;
        preferred.active = YES;
        [[field.heightAnchor constraintEqualToConstant:24] setActive:YES];
        return item;
    }
    return nil;
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
    return @[@"Back", @"Forward", @"Reload", @"Home", @"Address"];
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
    return @[@"Back", @"Forward", @"Reload", @"Home", @"Address", NSToolbarFlexibleSpaceItemIdentifier, NSToolbarSpaceItemIdentifier];
}

- (void)goBack:(id)sender {
    if (g_handler && g_handler->GetBrowser()) {
        g_handler->GetBrowser()->GoBack();
    }
}

- (void)goForward:(id)sender {
    if (g_handler && g_handler->GetBrowser()) {
        g_handler->GetBrowser()->GoForward();
    }
}

- (void)reload:(id)sender {
    if (g_handler && g_handler->GetBrowser()) {
        g_handler->GetBrowser()->Reload();
    }
}

- (void)goHome:(id)sender {
    // Same behaviour as the Bookmarks > Home menu item: show the home screen
    // (bookmarks + search) and let it drive navigation through onOpenURL.
    [self showHome:sender];
}

- (void)navigate:(id)sender {
    if (!g_addressField || !g_handler || !g_handler->GetBrowser()) return;

    std::string input = [[g_addressField stringValue] UTF8String];

    // Search template from settings (Android parity: Google, DuckDuckGo, Brave,
    // Ecosia, Kagi, Mojeek; unknown keys fall back to DuckDuckGo).
    AppSettings s = SettingsStore::instance().load();
    std::string engine = s.searchEngine;
    std::string searchTemplate = "https://duckduckgo.com/?q=%s";
    if (engine == "google") searchTemplate = "https://www.google.com/search?q=%s";
    else if (engine == "brave") searchTemplate = "https://search.brave.com/search?q=%s";
    else if (engine == "ecosia") searchTemplate = "https://www.ecosia.org/search?q=%s";
    else if (engine == "kagi") searchTemplate = "https://kagi.com/search?q=%s";
    else if (engine == "mojeek") searchTemplate = "https://www.mojeek.com/search?q=%s";

    // Rejects javascript:, file:, intent: and other non-web schemes.
    std::string url = UrlUtil::toNavigable(input, searchTemplate);
    if (url.empty()) return;

    g_handler->GetBrowser()->GetMainFrame()->LoadURL(url);
}

- (void)setLightTheme:(id)sender {
    ThemeManager::instance().setMode(ThemeMode::Light);
    ThemeManager::instance().applyToWindow(g_window);
    AppSettings s = SettingsStore::instance().load();
    s.themeMode = ThemeManager::instance().modeString();
    SettingsStore::instance().save(s);
}

- (void)setDarkTheme:(id)sender {
    ThemeManager::instance().setMode(ThemeMode::Dark);
    ThemeManager::instance().applyToWindow(g_window);
    AppSettings s = SettingsStore::instance().load();
    s.themeMode = ThemeManager::instance().modeString();
    SettingsStore::instance().save(s);
}

- (void)setSystemTheme:(id)sender {
    ThemeManager::instance().setMode(ThemeMode::System);
    ThemeManager::instance().applyToWindow(g_window);
    AppSettings s = SettingsStore::instance().load();
    s.themeMode = ThemeManager::instance().modeString();
    SettingsStore::instance().save(s);
}

- (void)bookmarkPage:(id)sender {
    if (g_handler && g_handler->GetBrowser()) {
        std::string url = g_handler->GetURL();
        std::string title = g_handler->GetTitle();
        if (!url.empty()) {
            BookmarkStore::instance().add(title.empty() ? url : title, url);
            NSAlert* alert = [[NSAlert alloc] init];
            [alert setMessageText:[NSString stringWithUTF8String:L("bookmark.added_title").c_str()]];
            [alert setInformativeText:[NSString stringWithFormat:[NSString stringWithUTF8String:L("bookmark.added_body").c_str()], (title.empty() ? url : title).c_str()]];
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        }
    }
}

- (void)showBookmarks:(id)sender {
    auto bookmarks = BookmarkStore::instance().all();
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Bookmarks"];
    if (bookmarks.empty()) {
        [menu addItemWithTitle:[NSString stringWithUTF8String:L("bookmark.none").c_str()] action:nil keyEquivalent:@""];
    } else {
        for (auto& b : bookmarks) {
            NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:b.title.c_str()] action:@selector(openBookmark:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = [NSString stringWithUTF8String:b.url.c_str()];
            [menu addItem:item];
        }
    }
    NSPoint loc = NSMakePoint(100, 100);
    [menu popUpMenuPositioningItem:nil atLocation:loc inView:[g_window contentView]];
}

- (void)openBookmark:(id)sender {
    NSMenuItem* item = (NSMenuItem*)sender;
    NSString* url = (NSString*)item.representedObject;
    if (url && g_handler && g_handler->GetBrowser()) {
        g_handler->GetBrowser()->GetMainFrame()->LoadURL([url UTF8String]);
    }
}

- (void)showSettings:(id)sender {
    [[SettingsWindowController shared] showWindow];
}

- (void)showHome:(id)sender {
    HomeWindowController* home = [HomeWindowController shared];
    home.onOpenURL = ^(NSString* url) {
        if (g_handler && g_handler->GetBrowser()) {
            g_handler->GetBrowser()->GetMainFrame()->LoadURL([url UTF8String]);
        }
        [[home window] orderOut:nil];
    };
    [home showHome];
}

- (void)exportBackup:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithUTF8String:L("backup.export_title").c_str()]];
    [alert setInformativeText:[NSString stringWithUTF8String:L("backup.export_body").c_str()]];

    NSSecureTextField* passField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    passField.placeholderString = [NSString stringWithUTF8String:L("backup.passphrase_placeholder").c_str()];
    [alert setAccessoryView:passField];
    [alert addButtonWithTitle:[NSString stringWithUTF8String:L("backup.export_button").c_str()]];
    [alert addButtonWithTitle:@"Cancel"];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        std::string pass = [[passField stringValue] UTF8String];
        std::string path = BackupService::defaultPath();
        if (BackupService::exportBackup(path, pass).empty()) {
            NSAlert* done = [[NSAlert alloc] init];
            [done setMessageText:[NSString stringWithUTF8String:L("backup.export_ok").c_str()]];
            [done setInformativeText:[NSString stringWithFormat:@"Saved to: %s", path.c_str()]];
            [done addButtonWithTitle:@"OK"];
            [done runModal];
        } else {
            NSAlert* err = [[NSAlert alloc] init];
            [err setMessageText:[NSString stringWithUTF8String:L("backup.failed").c_str()]];
            [err addButtonWithTitle:@"OK"];
            [err runModal];
        }
    }
}

- (void)importBackup:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeJSON];
    if ([panel runModal] != NSModalResponseOK) return;

    NSString* path = [[panel URL] path];
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithUTF8String:L("backup.import_title").c_str()]];
    [alert setInformativeText:[NSString stringWithUTF8String:L("backup.import_body").c_str()]];
    NSSecureTextField* passField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    [alert setAccessoryView:passField];
    [alert addButtonWithTitle:[NSString stringWithUTF8String:L("backup.import_button").c_str()]];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        std::string pass = [[passField stringValue] UTF8String];
        if (BackupService::importBackup([path UTF8String], pass, false).empty()) {
            NSAlert* done = [[NSAlert alloc] init];
            [done setMessageText:[NSString stringWithUTF8String:L("backup.import_ok").c_str()]];
            [done addButtonWithTitle:@"OK"];
            [done runModal];
        }
    }
}
// ---- Find / zoom / history (v1.9.0) -------------------------------------

- (void)showFind:(id)sender {
    if (!g_handler || !g_handler->GetBrowser()) return;
    if (!g_findPanel) {
        g_findPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 360, 52)
            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow)
            backing:NSBackingStoreBuffered defer:NO];
        g_findPanel.title = [NSString stringWithUTF8String:L("find.title").c_str()];
        g_findPanel.floatingPanel = YES;

        NSView* content = g_findPanel.contentView;
        g_findField = [[NSSearchField alloc] initWithFrame:NSMakeRect(12, 14, 240, 24)];
        g_findField.placeholderString = [NSString stringWithUTF8String:L("find.placeholder").c_str()];
        g_findField.target = self;
        g_findField.action = @selector(findChanged:);
        [content addSubview:g_findField];

        NSButton* prev = [[NSButton alloc] initWithFrame:NSMakeRect(258, 13, 44, 26)];
        prev.title = [NSString stringWithUTF8String:L("find.previous").c_str()];
        prev.bezelStyle = NSBezelStyleRounded;
        prev.target = self;
        prev.action = @selector(findPrevious:);
        [content addSubview:prev];

        NSButton* next = [[NSButton alloc] initWithFrame:NSMakeRect(304, 13, 44, 26)];
        next.title = [NSString stringWithUTF8String:L("find.next").c_str()];
        next.bezelStyle = NSBezelStyleRounded;
        next.target = self;
        next.action = @selector(findNext:);
        [content addSubview:next];
    }
    [g_findPanel makeKeyAndOrderFront:nil];
    [g_findPanel center];
    [g_findPanel makeFirstResponder:g_findField];
}

- (void)findChanged:(id)sender {
    [self runFind:YES];
}

- (void)findNext:(id)sender {
    [self runFind:YES];
}

- (void)findPrevious:(id)sender {
    [self runFind:NO];
}

- (void)runFind:(BOOL)forward {
    if (!g_handler || !g_handler->GetBrowser() || !g_findField) return;
    std::string text = [[g_findField stringValue] UTF8String];
    // An empty query clears the highlight instead of searching for "".
    g_handler->GetBrowser()->GetHost()->Find(text, forward, false, 1);
}

- (void)zoomIn:(id)sender {
    if (!g_handler || !g_handler->GetBrowser()) return;
    double level = g_handler->GetBrowser()->GetHost()->GetZoomLevel();
    g_handler->GetBrowser()->GetHost()->SetZoomLevel(level + 0.5);
}

- (void)zoomOut:(id)sender {
    if (!g_handler || !g_handler->GetBrowser()) return;
    double level = g_handler->GetBrowser()->GetHost()->GetZoomLevel();
    g_handler->GetBrowser()->GetHost()->SetZoomLevel(level - 0.5);
}

- (void)zoomReset:(id)sender {
    if (!g_handler || !g_handler->GetBrowser()) return;
    g_handler->GetBrowser()->GetHost()->SetZoomLevel(0);
}

- (void)showHistory:(id)sender {
    [[HistoryWindowController shared] showWindow];
}

@end

static ToolbarDelegate* g_toolbarDelegate = nil;

int RunSelfTests();

int main(int argc, char* argv[]) {
    @autoreleasepool {
        for (int i = 1; i < argc; ++i) {
            if (std::string(argv[i]) == "--self-test") {
                return RunSelfTests();
            }
        }
        CefScopedLibraryLoader library_loader;
        if (!library_loader.LoadInMain()) {
            return 1;
        }

        CefMainArgs main_args(argc, argv);

        int exit_code = CefExecuteProcess(main_args, nullptr, nullptr);
        if (exit_code >= 0) {
            return exit_code;
        }

        void* sandbox_info = nullptr;

        CefSettings settings;
        settings.no_sandbox = 1;

        CefRefPtr<CefApp> app(new MyApp());

        if (!CefInitialize(main_args, settings, app, sandbox_info)) {
            return CefGetExitCode();
        }

        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        // Restore persisted language and theme before building any UI.
        {
            AppSettings saved = SettingsStore::instance().load();
            Localization::instance().setLanguage(saved.language);
            ThemeManager::instance().setMode(ThemeManager::fromString(saved.themeMode));
        }

        // Create window with toolbar
        NSRect frame = NSMakeRect(100, 100, 1200, 800);
        g_window = [[NSWindow alloc] initWithContentRect:frame
            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable)
            backing:NSBackingStoreBuffered
            defer:NO];

        // Restore the last window frame; keep it on-screen for any display shape.
        {
            NSString* saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"HBWindowFrame"];
            if (saved.length > 0) {
                NSRect r = NSRectFromString(saved);
                NSRect screen = [[NSScreen mainScreen] visibleFrame];
                if (r.size.width >= 400 && r.size.height >= 300 &&
                    NSIntersectsRect(r, screen)) {
                    [g_window setFrame:r display:NO];
                }
            }
            g_window.minSize = NSMakeSize(480, 320);
        }
        [g_window setTitle:[NSString stringWithUTF8String:L("app.name").c_str()]];
        ThemeManager::instance().applyToWindow(g_window);
        [g_window makeKeyAndOrderFront:nil];

        // Add toolbar
        g_toolbarDelegate = [[ToolbarDelegate alloc] init];
        NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"HalfBrowserToolbar"];
        toolbar.delegate = g_toolbarDelegate;
        toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        [g_window setToolbar:toolbar];

        // Create CEF browser
        CefWindowInfo window_info;
        CefRect bounds;
        bounds.x = 0; bounds.y = 0; bounds.width = 1200; bounds.height = 740;
        window_info.SetAsChild((CefWindowHandle)[g_window contentView], bounds);

        CefBrowserSettings browser_settings;
        g_handler = SimpleHandler::GetInstance();

        // Start blank: the home screen is what the user sees first, and picking
        // an entry there loads it into this browser.
        CefBrowserHost::CreateBrowser(window_info, g_handler, "about:blank", browser_settings, nullptr, nullptr);

        // Set up menu bar
        NSMenu* mainMenu = [[NSMenu alloc] init];
        NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
        NSMenu* appMenu = [[NSMenu alloc] initWithTitle:[NSString stringWithUTF8String:L("app.name").c_str()]];
        [appMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.about").c_str()] action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
        [appMenu addItem:[NSMenuItem separatorItem]];
        [appMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.settings").c_str()] action:@selector(showSettings:) keyEquivalent:@","];
        NSMenuItem* settingsItem = [appMenu itemWithTitle:[NSString stringWithUTF8String:L("menu.settings").c_str()]];
        settingsItem.target = g_toolbarDelegate;
        [appMenu addItem:[NSMenuItem separatorItem]];
        [appMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.quit").c_str()] action:@selector(terminate:) keyEquivalent:@"q"];
        [appMenuItem setSubmenu:appMenu];
        [mainMenu addItem:appMenuItem];

        NSMenuItem* editMenuItem = [[NSMenuItem alloc] init];
        NSMenu* editMenu = [[NSMenu alloc] initWithTitle:[NSString stringWithUTF8String:L("menu.edit").c_str()]];
        [editMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.cut").c_str()] action:@selector(cut:) keyEquivalent:@"x"];
        [editMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.copy").c_str()] action:@selector(copy:) keyEquivalent:@"c"];
        [editMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.paste").c_str()] action:@selector(paste:) keyEquivalent:@"v"];
        [editMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.select_all").c_str()] action:@selector(selectAll:) keyEquivalent:@"a"];
        [editMenuItem setSubmenu:editMenu];
        [mainMenu addItem:editMenuItem];

        NSMenuItem* viewMenuItem = [[NSMenuItem alloc] init];
        NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:[NSString stringWithUTF8String:L("menu.view").c_str()]];
        [viewMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.reload").c_str()] action:@selector(reload:) keyEquivalent:@"r"];
        NSMenuItem* reloadItem = [viewMenu itemWithTitle:[NSString stringWithUTF8String:L("menu.reload").c_str()]];
        reloadItem.target = g_toolbarDelegate;

        // Find and zoom: the entries existed in the localized catalog but were
        // never added to the menu, so the features were unreachable.
        [viewMenu addItem:[NSMenuItem separatorItem]];
        [viewMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.find").c_str()] action:@selector(showFind:) keyEquivalent:@"f"];
        NSMenuItem* findItem = [viewMenu itemWithTitle:[NSString stringWithUTF8String:L("menu.find").c_str()]];
        findItem.target = g_toolbarDelegate;

        NSMenuItem* zoomMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:L("menu.zoom").c_str()] action:nil keyEquivalent:@""];
        NSMenu* zoomMenu = [[NSMenu alloc] initWithTitle:[NSString stringWithUTF8String:L("menu.zoom").c_str()]];
        [zoomMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.zoom_in").c_str()] action:@selector(zoomIn:) keyEquivalent:@"+"];
        [zoomMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.zoom_out").c_str()] action:@selector(zoomOut:) keyEquivalent:@"-"];
        [zoomMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.actual_size").c_str()] action:@selector(zoomReset:) keyEquivalent:@"0"];
        for (NSMenuItem* it in zoomMenu.itemArray) it.target = g_toolbarDelegate;
        [zoomMenuItem setSubmenu:zoomMenu];
        [viewMenu addItem:zoomMenuItem];

        NSMenuItem* themeMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:L("menu.theme").c_str()] action:nil keyEquivalent:@""];
        NSMenu* themeMenu = [[NSMenu alloc] initWithTitle:[NSString stringWithUTF8String:L("menu.theme").c_str()]];
        [themeMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.theme.light").c_str()] action:@selector(setLightTheme:) keyEquivalent:@""];
        [themeMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.theme.dark").c_str()] action:@selector(setDarkTheme:) keyEquivalent:@""];
        [themeMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.theme.system").c_str()] action:@selector(setSystemTheme:) keyEquivalent:@""];
        [themeMenuItem setSubmenu:themeMenu];
        [viewMenu addItem:themeMenuItem];

        [viewMenuItem setSubmenu:viewMenu];
        [mainMenu addItem:viewMenuItem];

        NSMenuItem* bookmarksMenuItem = [[NSMenuItem alloc] init];
        NSMenu* bookmarksMenu = [[NSMenu alloc] initWithTitle:[NSString stringWithUTF8String:L("menu.bookmarks").c_str()]];
        [bookmarksMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.bookmark_page").c_str()] action:@selector(bookmarkPage:) keyEquivalent:@"d"];
        NSMenuItem* bookmarkItem = [bookmarksMenu itemWithTitle:[NSString stringWithUTF8String:L("menu.bookmark_page").c_str()]];
        bookmarkItem.target = g_toolbarDelegate;
        [bookmarksMenu addItem:[NSMenuItem separatorItem]];
        [bookmarksMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.show_bookmarks").c_str()] action:@selector(showBookmarks:) keyEquivalent:@""];
        NSMenuItem* showItem = [bookmarksMenu itemWithTitle:[NSString stringWithUTF8String:L("menu.show_bookmarks").c_str()]];
        showItem.target = g_toolbarDelegate;
        [bookmarksMenu addItem:[NSMenuItem separatorItem]];
        [bookmarksMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.home").c_str()] action:@selector(showHome:) keyEquivalent:@""];
        NSMenuItem* homeItem = [bookmarksMenu itemWithTitle:[NSString stringWithUTF8String:L("menu.home").c_str()]];
        homeItem.target = g_toolbarDelegate;
        [bookmarksMenu addItem:[NSMenuItem separatorItem]];
        [bookmarksMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.history").c_str()] action:@selector(showHistory:) keyEquivalent:@"y"];
        NSMenuItem* historyItem = [bookmarksMenu itemWithTitle:[NSString stringWithUTF8String:L("menu.history").c_str()]];
        historyItem.target = g_toolbarDelegate;
        [bookmarksMenu addItem:[NSMenuItem separatorItem]];
        [bookmarksMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.export_backup").c_str()] action:@selector(exportBackup:) keyEquivalent:@""];
        NSMenuItem* exportItem = [bookmarksMenu itemWithTitle:[NSString stringWithUTF8String:L("menu.export_backup").c_str()]];
        exportItem.target = g_toolbarDelegate;
        [bookmarksMenu addItemWithTitle:[NSString stringWithUTF8String:L("menu.import_backup").c_str()] action:@selector(importBackup:) keyEquivalent:@""];
        NSMenuItem* importItem = [bookmarksMenu itemWithTitle:[NSString stringWithUTF8String:L("menu.import_backup").c_str()]];
        importItem.target = g_toolbarDelegate;
        [bookmarksMenuItem setSubmenu:bookmarksMenu];
        [mainMenu addItem:bookmarksMenuItem];

        [NSApp setMainMenu:mainMenu];

        // Show the home screen at launch (the browser itself sits on about:blank).
        [g_toolbarDelegate showHome:nil];

        // Persist geometry when the app terminates.
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification* note) {
            if (g_window) {
                [[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect([g_window frame])
                                                          forKey:@"HBWindowFrame"];
            }
        }];

        [NSApp run];

        CefShutdown();
    }
    return 0;
}
