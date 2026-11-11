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
#include "site_watch.h"

static SettingsWindowController* g_shared = nil;

/// Number of settings tabs (general, appearance, permissions, security, vpn,
/// backup, about).
static const int kTabCount = 7;

@implementation SettingsWindowController {
    NSTabView* _tabView;
    /// Keeps the site-watch status line current while the window is open.
    NSTimer* _statusTimer;
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
        // NSWindowController is not the window delegate by default; without
        // this, windowWillClose: would never run and the timer would leak.
        [window setDelegate:self];
        [self buildUI];
        // Refresh "last check" in place every 5 s; the timer is invalidated
        // when the window closes so it never outlives the controller.
        _statusTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                        repeats:YES
                                                          block:^(NSTimer* t) {
            (void)t;
            SettingsWindowController* c = [SettingsWindowController shared];
            if (![[c window] isVisible]) return;
            [c refreshSiteWatchStatus];
        }];
    }
    return self;
}

- (void)windowWillClose:(NSNotification*)note {
    (void)note;
    [_statusTimer invalidate];
    _statusTimer = nil;
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
            // General tab. Everything is stacked from the top down with a
            // running `y` cursor so no row can drift into another when a
            // section is inserted; the site-watch block sits at the bottom
            // under a separator where there is free space.
            const CGFloat left = 20;
            const CGFloat width = 460;
            CGFloat y = 360;
            const CGFloat labelH = 20;
            const CGFloat controlH = 24;
            const CGFloat gap = 8;

            NSTextField* label = [self plainLabel:[NSString stringWithUTF8String:L("settings.ui_scale").c_str()] frame:NSMakeRect(left, y, width, labelH)];
            [v addSubview:label];
            y -= 30;

            NSSlider* slider = [[NSSlider alloc] initWithFrame:NSMakeRect(left, y, 300, controlH)];
            [slider setMinValue:0.8];
            [slider setMaxValue:1.4];
            [slider setDoubleValue:s.uiScale];
            [slider setTarget:self];
            [slider setAction:@selector(uiScaleChanged:)];
            [v addSubview:slider];
            y -= 40;

            NSTextField* gridLabel = [self plainLabel:[NSString stringWithUTF8String:L("settings.grid_columns").c_str()] frame:NSMakeRect(left, y, width, labelH)];
            [v addSubview:gridLabel];
            y -= 30;

            NSPopUpButton* gridPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(left, y, 200, controlH)];
            [gridPopup addItemsWithTitles:@[@"Auto", @"3", @"4", @"5", @"6", @"8"]];
            [gridPopup setTarget:self];
            [gridPopup setAction:@selector(gridColumnsChanged:)];
            [v addSubview:gridPopup];
            y -= (controlH + gap + 8);

            NSTextField* langLabel = [self plainLabel:[NSString stringWithUTF8String:L("settings.language").c_str()] frame:NSMakeRect(left, y, width, labelH)];
            [v addSubview:langLabel];
            y -= 30;

            NSPopUpButton* langPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(left, y, 200, controlH)];
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
            y -= (controlH + gap + 8);

            NSTextField* engineLabel = [self plainLabel:[NSString stringWithUTF8String:L("settings.search_engine").c_str()] frame:NSMakeRect(left, y, width, labelH)];
            [v addSubview:engineLabel];
            y -= 30;

            NSPopUpButton* enginePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(left, y, 200, controlH)];
            [enginePopup addItemsWithTitles:@[@"Google", @"DuckDuckGo", @"Brave Search", @"Ecosia", @"Kagi Search", @"Mojeek"]];
            {
                NSArray* keys = @[@"google", @"duckduckgo", @"brave", @"ecosia", @"kagi", @"mojeek"];
                NSUInteger idx = [keys indexOfObject:[NSString stringWithUTF8String:s.searchEngine.c_str()]];
                if (idx != NSNotFound) [enginePopup selectItemAtIndex:idx];
            }
            [enginePopup setTarget:self];
            [enginePopup setAction:@selector(searchEngineChanged:)];
            [v addSubview:enginePopup];
            y -= (controlH + 14);

            // ---- Site watch ------------------------------------------------
            NSBox* rule = [[NSBox alloc] initWithFrame:NSMakeRect(left, y, width, 1)];
            [rule setBoxType:NSBoxSeparator];
            [v addSubview:rule];
            y -= 24;

            NSTextField* watchTitle = [self plainLabel:[NSString stringWithUTF8String:L("watch.title").c_str()] frame:NSMakeRect(left, y, width, labelH)];
            [watchTitle setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
            [v addSubview:watchTitle];
            y -= 26;

            NSButton* watchEnabled = [[NSButton alloc] initWithFrame:NSMakeRect(left, y, width, controlH)];
            [watchEnabled setButtonType:NSButtonTypeSwitch];
            [watchEnabled setTitle:[NSString stringWithUTF8String:L("watch.enabled").c_str()]];
            [watchEnabled setState:s.siteWatchEnabled ? NSControlStateValueOn : NSControlStateValueOff];
            [watchEnabled setTarget:self];
            [watchEnabled setAction:@selector(siteWatchEnabledChanged:)];
            [v addSubview:watchEnabled];
            y -= (controlH + 6);

            NSTextField* intervalLabel = [self plainLabel:[NSString stringWithUTF8String:L("watch.interval").c_str()] frame:NSMakeRect(left, y, 120, labelH)];
            [v addSubview:intervalLabel];

            NSPopUpButton* intervalPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(left + 130, y - 2, 160, controlH)];
            [intervalPopup addItemsWithTitles:@[
                [NSString stringWithUTF8String:L("watch.interval.15").c_str()],
                [NSString stringWithUTF8String:L("watch.interval.30").c_str()],
                [NSString stringWithUTF8String:L("watch.interval.60").c_str()],
                [NSString stringWithUTF8String:L("watch.interval.180").c_str()],
            ]];
            {
                const int minutes[] = {15, 30, 60, 180};
                for (int i = 0; i < 4; i++) {
                    if (minutes[i] == s.siteWatchIntervalMinutes) [intervalPopup selectItemAtIndex:i];
                }
            }
            [intervalPopup setTarget:self];
            [intervalPopup setAction:@selector(siteWatchIntervalChanged:)];
            [v addSubview:intervalPopup];
            y -= (controlH + 4);

            NSButton* wifiOnly = [[NSButton alloc] initWithFrame:NSMakeRect(left, y, width, controlH)];
            [wifiOnly setButtonType:NSButtonTypeSwitch];
            [wifiOnly setTitle:[NSString stringWithUTF8String:L("watch.wifi_only").c_str()]];
            [wifiOnly setState:s.siteWatchWifiOnly ? NSControlStateValueOn : NSControlStateValueOff];
            [wifiOnly setTarget:self];
            [wifiOnly setAction:@selector(siteWatchWifiOnlyChanged:)];
            [v addSubview:wifiOnly];
            y -= (controlH + 2);

            // Last check / last error. Both are single-line labels that are
            // refreshed in place (see refreshSiteWatchStatus) so the layout
            // never reflows while the settings window is open.
            NSTextField* status = [self plainLabel:@"" frame:NSMakeRect(left, y, width, labelH)];
            [status setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
            [status setTextColor:[NSColor secondaryLabelColor]];
            [status setIdentifier:@"watchStatus"];
            [v addSubview:status];
            y -= (labelH + 2);

            NSTextField* note = [self plainLabel:[NSString stringWithUTF8String:L("watch.foreground_only").c_str()] frame:NSMakeRect(left, y, width, labelH)];
            [note setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
            [note setTextColor:[NSColor secondaryLabelColor]];
            [v addSubview:note];
            y -= (labelH + 2);

            [self refreshSiteWatchStatus];
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

/// Build a borderless, non-editable label. `text` is already-localized text
/// (callers pass L("key") or an empty string), not a key.
- (NSTextField*)plainLabel:(NSString*)text frame:(NSRect)frame {
    NSTextField* label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:text];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    return label;
}

/// Update the "last check / last error" line of the general tab in place.
/// Called from the build and from a 5 s timer while the window is visible so
/// a check that finishes in the background shows up without reopening.
- (void)refreshSiteWatchStatus {
    NSTextField* status = nil;
    for (NSView* sub in [[_tabView selectedTabViewItem] view].subviews) {
        if ([[sub identifier] isEqual:@"watchStatus"] && [sub isKindOfClass:[NSTextField class]]) {
            status = (NSTextField*)sub;
            break;
        }
    }
    if (!status) return;

    SiteWatch& watch = SiteWatch::instance();
    NSString* text = nil;
    if (watch.lastCheckMillis() > 0) {
        NSDate* when = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)watch.lastCheckMillis() / 1000.0];
        NSDateFormatter* fmt = [[NSDateFormatter alloc] init];
        [fmt setDateStyle:NSDateFormatterShortStyle];
        [fmt setTimeStyle:NSDateFormatterShortStyle];
        NSString* stamp = [fmt stringFromDate:when];
        text = [NSString stringWithFormat:[NSString stringWithUTF8String:L("watch.last_check").c_str()], stamp];
    } else {
        text = [NSString stringWithUTF8String:L("watch.never_checked").c_str()];
    }
    std::string err = watch.lastError();
    if (!err.empty()) {
        text = [text stringByAppendingFormat:@"  ·  %@",
                [NSString stringWithFormat:[NSString stringWithUTF8String:L("watch.error").c_str()],
                 [NSString stringWithUTF8String:err.c_str()]]];
    }
    [status setStringValue:text];
}

- (void)siteWatchEnabledChanged:(NSButton*)sender {
    AppSettings s = SettingsStore::instance().load();
    s.siteWatchEnabled = [sender state] == NSControlStateValueOn;
    SettingsStore::instance().save(s);
    // applySettings() is what requests notification permission, and only when
    // the switch is on.
    SiteWatch::instance().applySettings();
    if (s.siteWatchEnabled) SiteWatch::instance().checkNow();
    [self refreshSiteWatchStatus];
}

- (void)siteWatchIntervalChanged:(NSPopUpButton*)sender {
    AppSettings s = SettingsStore::instance().load();
    const int minutes[] = {15, 30, 60, 180};
    NSInteger idx = [sender indexOfSelectedItem];
    if (idx < 0 || idx > 3) return;
    s.siteWatchIntervalMinutes = minutes[idx];
    SettingsStore::instance().save(s);
    SiteWatch::instance().applySettings();
}

- (void)siteWatchWifiOnlyChanged:(NSButton*)sender {
    AppSettings s = SettingsStore::instance().load();
    s.siteWatchWifiOnly = [sender state] == NSControlStateValueOn;
    SettingsStore::instance().save(s);
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
