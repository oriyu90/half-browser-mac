#import <Cocoa/Cocoa.h>
#include "settings_window.h"
#import <Security/Security.h>
#include "settings_store.h"
#include "theme.h"
#include "site_permissions.h"
#include "backup_service.h"
#include "localization.h"
#include "history_store.h"
#include "vpn_settings_view.h"

static SettingsWindowController* g_shared = nil;

/// Number of settings tabs (general, appearance, permissions, security, vpn,
/// backup, about).
static const int kTabCount = 7;

@implementation SettingsWindowController {
    NSTabView* _tabView;
}

+ (instancetype)shared {
    if (!g_shared) {
        g_shared = [[SettingsWindowController alloc] init];
    }
    return g_shared;
}

- (instancetype)init {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 480)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
        backing:NSBackingStoreBuffered
        defer:NO];
    [window setTitle:[NSString stringWithUTF8String:L("settings.title").c_str()]];
    [window center];
    self = [super initWithWindow:window];
    if (self) {
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    _tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(20, 20, 520, 410)];
    [_tabView setTabViewType:NSNoTabsNoBorder];

    NSString* titles[] = {
        [NSString stringWithUTF8String:L("settings.tab.general").c_str()],
        [NSString stringWithUTF8String:L("settings.tab.appearance").c_str()],
        [NSString stringWithUTF8String:L("settings.tab.permissions").c_str()],
        [NSString stringWithUTF8String:L("settings.tab.security").c_str()],
        [NSString stringWithUTF8String:L("settings.tab.vpn").c_str()],
        [NSString stringWithUTF8String:L("settings.tab.backup").c_str()],
        [NSString stringWithUTF8String:L("settings.tab.about").c_str()],
    };
    // The VPN pane is index 5; backup and about shift down by one.
    for (int i = 0; i < kTabCount; i++) {
        NSTabViewItem* item = [[NSTabViewItem alloc] initWithIdentifier:@(i)];
        [item setLabel:titles[i]];
        [item setView:[self buildTabView:i]];
        [_tabView addTabViewItem:item];
    }

    NSSegmentedControl* seg = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(20, 440, 520, 28)];
    [seg setSegmentCount:kTabCount];
    for (int i = 0; i < kTabCount; i++) [seg setLabel:titles[i] forSegment:i];
    [seg setSelectedSegment:0];
    [seg setTarget:self];
    [seg setAction:@selector(tabChanged:)];
    [seg setTrackingMode:NSSegmentSwitchTrackingSelectOne];

    NSView* content = [[self window] contentView];
    [content addSubview:seg];
    [content addSubview:_tabView];
}

- (void)tabChanged:(NSSegmentedControl*)sender {
    [_tabView selectTabViewItemAtIndex:[sender selectedSegment]];
}

- (NSView*)buildTabView:(int)index {
    NSView* v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 410)];
    AppSettings s = SettingsStore::instance().load();

    switch (index) {
        case 5: {
            // VPN: profile management plus an honest statement of what macOS
            // allows (see docs/plan/v1.9.0-parity.md).
            VpnSettingsView* vpn = [[VpnSettingsView alloc] initWithFrame:NSMakeRect(10, 10, 500, 390)];
            [v addSubview:vpn];
            return v;
        }
        case 0: {
            NSTextField* label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 360, 300, 20)];
            [label setStringValue:[NSString stringWithUTF8String:L("settings.ui_scale").c_str()]];
            [label setBezeled:NO];
            [label setDrawsBackground:NO];
            [label setEditable:NO];
            [v addSubview:label];

            NSSlider* slider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 330, 300, 24)];
            [slider setMinValue:0.8];
            [slider setMaxValue:1.4];
            [slider setDoubleValue:s.uiScale];
            [slider setTarget:self];
            [slider setAction:@selector(uiScaleChanged:)];
            [v addSubview:slider];

            NSTextField* gridLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 290, 300, 20)];
            [gridLabel setStringValue:[NSString stringWithUTF8String:L("settings.grid_columns").c_str()]];
            [gridLabel setBezeled:NO];
            [gridLabel setDrawsBackground:NO];
            [gridLabel setEditable:NO];
            [v addSubview:gridLabel];

            NSPopUpButton* gridPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 260, 200, 24)];
            [gridPopup addItemsWithTitles:@[@"Auto", @"3", @"4", @"5", @"6", @"8"]];
            [gridPopup setTarget:self];
            [gridPopup setAction:@selector(gridColumnsChanged:)];
            [v addSubview:gridPopup];

            NSTextField* langLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 225, 300, 20)];
            [langLabel setStringValue:[NSString stringWithUTF8String:L("settings.language").c_str()]];
            [langLabel setBezeled:NO];
            [langLabel setDrawsBackground:NO];
            [langLabel setEditable:NO];
            [v addSubview:langLabel];

            NSPopUpButton* langPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 195, 200, 24)];
            [langPopup addItemsWithTitles:@[
                [NSString stringWithUTF8String:L("settings.language.system").c_str()],
                [NSString stringWithUTF8String:L("settings.language.ja").c_str()],
                [NSString stringWithUTF8String:L("settings.language.en").c_str()],
            ]];
            if (s.language == "ja") [langPopup selectItemAtIndex:1];
            else if (s.language == "en") [langPopup selectItemAtIndex:2];
            [langPopup setTarget:self];
            [langPopup setAction:@selector(languageChanged:)];
            [v addSubview:langPopup];

            NSTextField* engineLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 160, 300, 20)];
            [engineLabel setStringValue:[NSString stringWithUTF8String:L("settings.search_engine").c_str()]];
            [engineLabel setBezeled:NO];
            [engineLabel setDrawsBackground:NO];
            [engineLabel setEditable:NO];
            [v addSubview:engineLabel];

            NSPopUpButton* enginePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 130, 200, 24)];
            [enginePopup addItemsWithTitles:@[@"Google", @"DuckDuckGo", @"Brave Search", @"Ecosia", @"Kagi Search", @"Mojeek"]];
            {
                NSArray* keys = @[@"google", @"duckduckgo", @"brave", @"ecosia", @"kagi", @"mojeek"];
                NSUInteger idx = [keys indexOfObject:[NSString stringWithUTF8String:s.searchEngine.c_str()]];
                if (idx != NSNotFound) [enginePopup selectItemAtIndex:idx];
            }
            [enginePopup setTarget:self];
            [enginePopup setAction:@selector(searchEngineChanged:)];
            [v addSubview:enginePopup];
            break;
        }
        case 1: {
            NSTextField* themeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 360, 300, 20)];
            [themeLabel setStringValue:[NSString stringWithUTF8String:L("settings.theme").c_str()]];
            [themeLabel setBezeled:NO];
            [themeLabel setDrawsBackground:NO];
            [themeLabel setEditable:NO];
            [v addSubview:themeLabel];

            NSPopUpButton* themePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 330, 200, 24)];
            [themePopup addItemsWithTitles:@[@"System", @"Light", @"Dark"]];
            if (s.themeMode == "light") [themePopup selectItemAtIndex:1];
            else if (s.themeMode == "dark") [themePopup selectItemAtIndex:2];
            [themePopup setTarget:self];
            [themePopup setAction:@selector(themeChanged:)];
            [v addSubview:themePopup];

            NSTextField* accentLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 290, 300, 20)];
            [accentLabel setStringValue:[NSString stringWithUTF8String:L("settings.accent_hue").c_str()]];
            [accentLabel setBezeled:NO];
            [accentLabel setDrawsBackground:NO];
            [accentLabel setEditable:NO];
            [v addSubview:accentLabel];

            NSSlider* hueSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 260, 300, 24)];
            [hueSlider setMinValue:0];
            [hueSlider setMaxValue:360];
            [hueSlider setDoubleValue:s.accentHue];
            [hueSlider setTarget:self];
            [hueSlider setAction:@selector(accentHueChanged:)];
            [v addSubview:hueSlider];
            break;
        }
        case 2: {
            NSTextField* label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 360, 480, 20)];
            [label setStringValue:[NSString stringWithUTF8String:L("settings.permissions_body").c_str()]];
            [label setBezeled:NO];
            [label setDrawsBackground:NO];
            [label setEditable:NO];
            [v addSubview:label];

            NSTextField* pathLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 330, 480, 20)];
            [pathLabel setStringValue:@"~/Library/Application Support/Half-Browser/permissions.json"];
            [pathLabel setBezeled:NO];
            [pathLabel setDrawsBackground:NO];
            [pathLabel setEditable:NO];
            [pathLabel setTextColor:[NSColor secondaryLabelColor]];
            [v addSubview:pathLabel];

            NSButton* resetBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, 280, 200, 32)];
            [resetBtn setTitle:[NSString stringWithUTF8String:L("settings.reset_permissions").c_str()]];
            [resetBtn setBezelStyle:NSBezelStyleRounded];
            [resetBtn setTarget:self];
            [resetBtn setAction:@selector(resetPermissions:)];
            [v addSubview:resetBtn];
            break;
        }
        case 3: {
            NSTextField* label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 360, 480, 20)];
            [label setStringValue:[NSString stringWithUTF8String:L("settings.security_body").c_str()]];
            [label setBezeled:NO];
            [label setDrawsBackground:NO];
            [label setEditable:NO];
            [v addSubview:label];

            NSButton* clearBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, 310, 250, 32)];
            [clearBtn setTitle:[NSString stringWithUTF8String:L("settings.clear_certs").c_str()]];
            [clearBtn setBezelStyle:NSBezelStyleRounded];
            [clearBtn setTarget:self];
            [clearBtn setAction:@selector(clearTrustedCerts:)];
            [v addSubview:clearBtn];
            break;
        }
        case 4: {
            NSButton* exportBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, 360, 200, 32)];
            [exportBtn setTitle:[NSString stringWithUTF8String:L("menu.export_backup").c_str()]];
            [exportBtn setBezelStyle:NSBezelStyleRounded];
            [exportBtn setTarget:self];
            [exportBtn setAction:@selector(exportBackup:)];
            [v addSubview:exportBtn];

            NSButton* importBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, 310, 200, 32)];
            [importBtn setTitle:[NSString stringWithUTF8String:L("menu.import_backup").c_str()]];
            [importBtn setBezelStyle:NSBezelStyleRounded];
            [importBtn setTarget:self];
            [importBtn setAction:@selector(importBackup:)];
            [v addSubview:importBtn];
            break;
        }
        case 6: {
            NSTextField* title = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 360, 480, 24)];
            [title setStringValue:[NSString stringWithUTF8String:L("settings.about_title").c_str()]];
            [title setFont:[NSFont boldSystemFontOfSize:18]];
            [title setBezeled:NO];
            [title setDrawsBackground:NO];
            [title setEditable:NO];
            [v addSubview:title];

            NSTextField* version = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 330, 480, 20)];
            [version setStringValue:[NSString stringWithFormat:[NSString stringWithUTF8String:L("settings.about_version").c_str()], "1.9.0", "156"]];
            [version setBezeled:NO];
            [version setDrawsBackground:NO];
            [version setEditable:NO];
            [v addSubview:version];

            NSTextField* desc = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 290, 480, 40)];
            [desc setStringValue:[NSString stringWithUTF8String:L("settings.about_body").c_str()]];
            [desc setBezeled:NO];
            [desc setDrawsBackground:NO];
            [desc setEditable:NO];
            [v addSubview:desc];
            break;
        }
    }
    return v;
}

- (void)uiScaleChanged:(NSSlider*)sender {
    AppSettings s = SettingsStore::instance().load();
    s.uiScale = [sender doubleValue];
    SettingsStore::instance().save(s);
}

- (void)gridColumnsChanged:(NSPopUpButton*)sender {
    AppSettings s = SettingsStore::instance().load();
    int cols[] = {0, 3, 4, 5, 6, 8};
    s.gridColumns = cols[[sender indexOfSelectedItem]];
    SettingsStore::instance().save(s);
}

- (void)themeChanged:(NSPopUpButton*)sender {
    AppSettings s = SettingsStore::instance().load();
    NSInteger idx = [sender indexOfSelectedItem];
    s.themeMode = idx == 1 ? "light" : (idx == 2 ? "dark" : "system");
    SettingsStore::instance().save(s);
    ThemeMode mode = ThemeManager::fromString(s.themeMode);
    ThemeManager::instance().setMode(mode);
    ThemeManager::instance().applyToWindow([self window]);
}

- (void)languageChanged:(NSPopUpButton*)sender {
    AppSettings s = SettingsStore::instance().load();
    NSInteger idx = [sender indexOfSelectedItem];
    s.language = idx == 1 ? "ja" : (idx == 2 ? "en" : "system");
    SettingsStore::instance().save(s);
    Localization::instance().setLanguage(s.language);
    // Rebuild the UI so labels switch immediately.
    for (NSView* sub in [[[self window] contentView] subviews]) {
        [sub removeFromSuperview];
    }
    [self buildUI];
    [[self window] makeKeyAndOrderFront:nil];
}

- (void)searchEngineChanged:(NSPopUpButton*)sender {
    AppSettings s = SettingsStore::instance().load();
    NSArray* keys = @[@"google", @"duckduckgo", @"brave", @"ecosia", @"kagi", @"mojeek"];
    s.searchEngine = [[keys objectAtIndex:[sender indexOfSelectedItem]] UTF8String];
    SettingsStore::instance().save(s);
}

- (void)accentHueChanged:(NSSlider*)sender {
    AppSettings s = SettingsStore::instance().load();
    s.accentHue = [sender doubleValue];
    SettingsStore::instance().save(s);
}

- (void)resetPermissions:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithUTF8String:L("settings.reset_permissions").c_str()]];
    [alert setInformativeText:[NSString stringWithUTF8String:L("settings.reset_permissions_confirm").c_str()]];
    [alert addButtonWithTitle:[NSString stringWithUTF8String:L("settings.reset").c_str()]];
    [alert addButtonWithTitle:[NSString stringWithUTF8String:L("ssl.cancel").c_str()]];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        std::string fp = std::string(getenv("HOME")) + "/Library/Application Support/Half-Browser/permissions.json";
        [[@"[]" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[NSString stringWithUTF8String:fp.c_str()] atomically:YES];
    }
}

- (void)clearTrustedCerts:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithUTF8String:L("settings.clear_certs").c_str()]];
    [alert setInformativeText:[NSString stringWithUTF8String:L("settings.clear_certs_confirm").c_str()]];
    [alert addButtonWithTitle:[NSString stringWithUTF8String:L("settings.clear").c_str()]];
    [alert addButtonWithTitle:[NSString stringWithUTF8String:L("ssl.cancel").c_str()]];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSDictionary* query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: @"half-browser-trust",
        };
        SecItemDelete((__bridge CFDictionaryRef)query);
    }
}

- (void)exportBackup:(id)sender {
    NSSavePanel* panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:@"half-browser-backup.json"];
    if ([panel runModal] != NSModalResponseOK) return;

    NSString* path = [[panel URL] path];
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithUTF8String:L("backup.export_title").c_str()]];
    [alert setInformativeText:[NSString stringWithUTF8String:L("backup.export_body").c_str()]];
    NSSecureTextField* passField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    [alert setAccessoryView:passField];
    [alert addButtonWithTitle:[NSString stringWithUTF8String:L("backup.export_button").c_str()]];
    [alert addButtonWithTitle:[NSString stringWithUTF8String:L("ssl.cancel").c_str()]];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        std::string pass = [[passField stringValue] UTF8String];
        if (BackupService::exportBackup([path UTF8String], pass).empty()) {
            NSAlert* done = [[NSAlert alloc] init];
            [done setMessageText:[NSString stringWithUTF8String:L("backup.export_ok").c_str()]];
            [done addButtonWithTitle:[NSString stringWithUTF8String:L("auth.ok").c_str()]];
            [done runModal];
        }
    }
}

- (void)importBackup:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    if ([panel runModal] != NSModalResponseOK) return;

    NSString* path = [[panel URL] path];
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithUTF8String:L("backup.import_title").c_str()]];
    [alert setInformativeText:[NSString stringWithUTF8String:L("backup.import_body").c_str()]];
    NSSecureTextField* passField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    [alert setAccessoryView:passField];
    [alert addButtonWithTitle:[NSString stringWithUTF8String:L("backup.import_button").c_str()]];
    [alert addButtonWithTitle:[NSString stringWithUTF8String:L("ssl.cancel").c_str()]];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        std::string pass = [[passField stringValue] UTF8String];
        if (BackupService::importBackup([path UTF8String], pass, false).empty()) {
            NSAlert* done = [[NSAlert alloc] init];
            [done setMessageText:[NSString stringWithUTF8String:L("backup.import_ok").c_str()]];
            [done addButtonWithTitle:[NSString stringWithUTF8String:L("auth.ok").c_str()]];
            [done runModal];
        }
    }
}

- (void)showWindow {
    [[self window] makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

@end
