#import <Cocoa/Cocoa.h>
#include "vpn_settings_view.h"
#include "vpn_store.h"
#include "vpn_controller.h"
#include "settings_store.h"
#include "localization.h"
#include "half_browser_core.h"
#include <string>

namespace {

NSString* ns(const std::string& s) {
    return [NSString stringWithUTF8String:s.c_str()];
}

/// Maps a `VpnConfigError` code (returned by `hb_vpn_parse`) to a localized
/// message. The Rust side returns 1-based indices in declaration order.
NSString* configErrorMessage(int code) {
    const char* keys[] = {
        "vpn.err.empty",           "vpn.err.too_large",        "vpn.err.missing_interface",
        "vpn.err.missing_peer",    "vpn.err.missing_private",  "vpn.err.invalid_private",
        "vpn.err.missing_public",  "vpn.err.invalid_public",   "vpn.err.invalid_psk",
        "vpn.err.missing_endpoint","vpn.err.invalid_endpoint", "vpn.err.missing_allowed",
        "vpn.err.invalid_allowed", "vpn.err.invalid_address",  "vpn.err.invalid_dns",
        "vpn.err.invalid_port",    "vpn.err.invalid_mtu",      "vpn.err.invalid_keepalive",
        "vpn.err.unknown_key",     "vpn.err.duplicate_section","vpn.err.malformed_line",
    };
    int count = (int)(sizeof(keys) / sizeof(keys[0]));
    if (code >= 1 && code <= count) {
        return ns(L(keys[code - 1]));
    }
    return ns(L("vpn.err.generic"));
}

NSString* reachabilityLabel(VpnReach r) {
    switch (r) {
        case VpnReach::Healthy: return ns(L("vpn.reach.healthy"));
        case VpnReach::Stale: return ns(L("vpn.reach.stale"));
        case VpnReach::Unreachable: return ns(L("vpn.reach.unreachable"));
        case VpnReach::Verifying: return ns(L("vpn.reach.verifying"));
        case VpnReach::TunnelOnly: return ns(L("vpn.reach.tunnel_only"));
        case VpnReach::Unknown:
        default: return ns(L("vpn.reach.unknown"));
    }
}

NSColor* reachabilityColor(VpnReach r) {
    switch (r) {
        case VpnReach::Healthy: return [NSColor systemGreenColor];
        case VpnReach::Stale:
        case VpnReach::Unreachable: return [NSColor systemRedColor];
        case VpnReach::Verifying: return [NSColor systemOrangeColor];
        default: return [NSColor secondaryLabelColor];
    }
}

/// Same shape as the store's ids: 16 random bytes as hex.
std::string newProfileId() {
    unsigned char buf[16];
    arc4random_buf(buf, sizeof(buf));
    static const char* hex = "0123456789abcdef";
    std::string out;
    for (unsigned char c : buf) {
        out += hex[c >> 4];
        out += hex[c & 0xF];
    }
    return out;
}

}  // namespace

@implementation VpnSettingsView {
    NSTextField* _statusLabel;
    NSTextField* _availabilityLabel;
    NSTableView* _table;
    NSMutableArray<NSString*>* _ids;
    NSButton* _connectButton;
    NSButton* _removeButton;
    NSButton* _exportButton;
    NSButton* _autoConnectCheck;
    NSButton* _autoReconnectCheck;
    NSButton* _powerSaverCheck;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _ids = [NSMutableArray array];
        [self buildUI];
        [self reload];
    }
    return self;
}

- (void)buildUI {
    CGFloat w = self.bounds.size.width;

    // ---- limitation notice -------------------------------------------------
    // The honest statement of what macOS allows. Shown unconditionally so the
    // user is never left wondering why "Connect" does nothing.
    NSTextField* notice = [self labelWithFrame:NSMakeRect(0, self.bounds.size.height - 56, w, 48)];
    notice.stringValue = ns(L("vpn.mac_limitation"));
    notice.font = [NSFont systemFontOfSize:11];
    notice.textColor = [NSColor secondaryLabelColor];
    notice.maximumNumberOfLines = 4;
    [self addSubview:notice];

    // ---- availability ------------------------------------------------------
    _availabilityLabel = [self labelWithFrame:NSMakeRect(0, self.bounds.size.height - 80, w, 18)];
    _availabilityLabel.font = [NSFont systemFontOfSize:11];
    [self addSubview:_availabilityLabel];

    // ---- status ------------------------------------------------------------
    _statusLabel = [self labelWithFrame:NSMakeRect(0, self.bounds.size.height - 108, w, 20)];
    _statusLabel.font = [NSFont boldSystemFontOfSize:13];
    [self addSubview:_statusLabel];

    // ---- profile table -----------------------------------------------------
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 150, w, self.bounds.size.height - 268)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    _table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    NSTableColumn* nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameCol.title = ns(L("vpn.col_name"));
    nameCol.width = 180;
    [_table addTableColumn:nameCol];
    NSTableColumn* epCol = [[NSTableColumn alloc] initWithIdentifier:@"endpoint"];
    epCol.title = ns(L("vpn.col_endpoint"));
    epCol.width = 240;
    [_table addTableColumn:epCol];
    _table.dataSource = (id<NSTableViewDataSource>)self;
    _table.delegate = (id<NSTableViewDelegate>)self;
    _table.usesAlternatingRowBackgroundColors = YES;
    scroll.documentView = _table;
    [self addSubview:scroll];

    // ---- buttons -----------------------------------------------------------
    CGFloat y = 112;
    NSButton* addPaste = [self buttonWithTitle:L("vpn.add_paste") frame:NSMakeRect(0, y, 130, 28)
                                       action:@selector(addFromPasteboard:)];
    [self addSubview:addPaste];
    NSButton* addFile = [self buttonWithTitle:L("vpn.add_file") frame:NSMakeRect(138, y, 130, 28)
                                      action:@selector(addFromFile:)];
    [self addSubview:addFile];
    _exportButton = [self buttonWithTitle:L("vpn.export") frame:NSMakeRect(276, y, 100, 28)
                                   action:@selector(exportSelected:)];
    [self addSubview:_exportButton];
    _removeButton = [self buttonWithTitle:L("vpn.remove") frame:NSMakeRect(384, y, 100, 28)
                                   action:@selector(removeSelected:)];
    [self addSubview:_removeButton];

    y = 76;
    _connectButton = [self buttonWithTitle:L("vpn.connect") frame:NSMakeRect(0, y, 110, 28)
                                    action:@selector(toggleConnection:)];
    [self addSubview:_connectButton];

    // ---- options -----------------------------------------------------------
    y = 44;
    _autoConnectCheck = [self checkboxWithTitle:L("vpn.auto_connect") frame:NSMakeRect(0, y, 260, 20)
                                         action:@selector(autoConnectChanged:)];
    [self addSubview:_autoConnectCheck];
    _autoReconnectCheck = [self checkboxWithTitle:L("vpn.auto_reconnect") frame:NSMakeRect(0, y - 22, 300, 20)
                                           action:@selector(autoReconnectChanged:)];
    [self addSubview:_autoReconnectCheck];
    _powerSaverCheck = [self checkboxWithTitle:L("vpn.power_saver") frame:NSMakeRect(320, y, 260, 20)
                                        action:@selector(powerSaverChanged:)];
    [self addSubview:_powerSaverCheck];
}

- (NSTextField*)labelWithFrame:(NSRect)frame {
    NSTextField* f = [[NSTextField alloc] initWithFrame:frame];
    f.bezeled = NO;
    f.drawsBackground = NO;
    f.editable = NO;
    f.selectable = NO;
    f.lineBreakMode = NSLineBreakByWordWrapping;
    f.cell.wraps = YES;
    return f;
}

- (NSButton*)buttonWithTitle:(const std::string&)title frame:(NSRect)frame action:(SEL)action {
    NSButton* b = [[NSButton alloc] initWithFrame:frame];
    b.title = ns(title);
    b.bezelStyle = NSBezelStyleRounded;
    b.target = self;
    b.action = action;
    return b;
}

- (NSButton*)checkboxWithTitle:(const std::string&)title frame:(NSRect)frame action:(SEL)action {
    NSButton* b = [[NSButton alloc] initWithFrame:frame];
    [b setButtonType:NSButtonTypeSwitch];
    b.title = ns(title);
    b.target = self;
    b.action = action;
    return b;
}

- (void)reload {
    [_ids removeAllObjects];
    auto profiles = VpnStore::instance().all();
    for (const auto& p : profiles) {
        [_ids addObject:ns(p.id)];
    }
    [_table reloadData];

    VpnController& c = VpnController::instance();
    _availabilityLabel.stringValue = ns(c.availabilityDetail());

    NSString* stateText = nil;
    if (c.state() == VpnConnState::Connected) {
        // Hold the label in a local so its UTF8String stays valid for the
        // duration of the format call (a temporary could be released first).
        NSString* reachText = (c.reachability() == VpnReach::Unknown)
            ? @"" : reachabilityLabel(c.reachability());
        stateText = [NSString stringWithFormat:ns(L("vpn.status_connected")),
                                               [reachText UTF8String]];
        _statusLabel.textColor = reachabilityColor(c.reachability());
    } else if (c.state() == VpnConnState::Connecting) {
        stateText = ns(L("vpn.status_connecting"));
        _statusLabel.textColor = [NSColor systemOrangeColor];
    } else {
        stateText = ns(L("vpn.status_disconnected"));
        _statusLabel.textColor = [NSColor secondaryLabelColor];
    }
    _statusLabel.stringValue = stateText;

    AppSettings s = SettingsStore::instance().load();
    _autoConnectCheck.state = s.vpnAutoConnect ? NSControlStateValueOn : NSControlStateValueOff;
    _autoReconnectCheck.state = s.vpnAutoReconnect ? NSControlStateValueOn : NSControlStateValueOff;
    _powerSaverCheck.state = s.vpnPowerSaver ? NSControlStateValueOn : NSControlStateValueOff;

    // Connecting is only offered when the app can actually do it.
    _connectButton.enabled = c.canConnect() || c.state() == VpnConnState::Connected;
    _connectButton.title = ns(c.state() == VpnConnState::Connected ? L("vpn.disconnect") : L("vpn.connect"));
    _exportButton.enabled = _table.selectedRow >= 0;
    _removeButton.enabled = _table.selectedRow >= 0;
}

// ---------------------------------------------------------------- table

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    return (NSInteger)_ids.count;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_ids.count) return nil;
    NSTableCellView* cell = [tableView makeViewWithIdentifier:column.identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, column.width, 20)];
        cell.identifier = column.identifier;
        NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect(2, 1, column.width - 4, 18)];
        tf.bezeled = NO;
        tf.drawsBackground = NO;
        tf.editable = NO;
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:tf];
        cell.textField = tf;
    }
    VpnProfile p;
    std::string id = [[_ids objectAtIndex:row] UTF8String];
    if (VpnStore::instance().find(id, p)) {
        cell.textField.stringValue = ns([column.identifier isEqualToString:@"name"] ? p.name : p.endpoint);
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    _exportButton.enabled = _table.selectedRow >= 0;
    _removeButton.enabled = _table.selectedRow >= 0;
}

- (NSString*)selectedId {
    NSInteger row = _table.selectedRow;
    if (row < 0 || row >= (NSInteger)_ids.count) return nil;
    return [_ids objectAtIndex:row];
}

// ---------------------------------------------------------------- actions

- (void)addFromPasteboard:(id)sender {
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    NSString* text = [pb stringForType:NSPasteboardTypeString];
    if (text.length == 0) {
        [self showError:ns(L("vpn.err.empty"))];
        return;
    }
    [self importConfigText:[text UTF8String] suggestedName:nil];
}

- (void)addFromFile:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError* err = nil;
    NSString* content = [NSString stringWithContentsOfURL:panel.URL
                                                encoding:NSUTF8StringEncoding
                                                   error:&err];
    if (!content) {
        [self showError:ns(L("vpn.err.unreadable_file"))];
        return;
    }
    [self importConfigText:[content UTF8String] suggestedName:[[panel.URL lastPathComponent] stringByDeletingPathExtension]];
}

/// Validates `text` with the Rust parser (the same rules Android uses) before
/// storing it, so a broken profile can never reach the Keychain.
- (void)importConfigText:(const char*)text suggestedName:(NSString*)suggested {
    char* endpoint = nullptr;
    char* detail = nullptr;
    int code = hb_vpn_parse(text, &endpoint, &detail);
    if (code != 0) {
        NSString* msg = configErrorMessage(code);
        if (detail && detail[0]) {
            msg = [NSString stringWithFormat:@"%@ (%@)", msg, ns(detail)];
        }
        if (detail) hb_free_string(detail);
        if (endpoint) hb_free_string(endpoint);
        [self showError:msg];
        return;
    }
    std::string ep = endpoint ? endpoint : "";
    if (endpoint) hb_free_string(endpoint);
    if (detail) hb_free_string(detail);

    // Ask for a display name, defaulting to the endpoint.
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = ns(L("vpn.name_title"));
    alert.informativeText = ns(L("vpn.name_body"));
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    field.stringValue = suggested.length > 0 ? suggested : ns(ep);
    alert.accessoryView = field;
    [alert addButtonWithTitle:ns(L("common.ok"))];
    [alert addButtonWithTitle:ns(L("common.cancel"))];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    VpnProfile p;
    p.id = newProfileId();
    p.name = [[field stringValue] UTF8String];
    p.configText = text;
    p.endpoint = ep;
    if (!VpnStore::instance().save(p)) {
        [self showError:ns(L("vpn.err.save_failed"))];
        return;
    }
    [self reload];
}

- (void)exportSelected:(id)sender {
    NSString* sid = [self selectedId];
    if (!sid) return;
    std::string config;
    if (!VpnStore::instance().loadConfig([sid UTF8String], config)) {
        [self showError:ns(L("vpn.err.config_unreadable"))];
        return;
    }
    NSSavePanel* panel = [NSSavePanel savePanel];
    VpnProfile p;
    VpnStore::instance().find([sid UTF8String], p);
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%s.conf", p.name.empty() ? "profile" : p.name.c_str()];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSString* content = ns(config);
    NSError* err = nil;
    // The exported text is the user's original config, byte for byte, so the
    // official WireGuard clients accept it unchanged.
    [content writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) [self showError:ns(L("vpn.err.export_failed"))];
}

- (void)removeSelected:(id)sender {
    NSString* sid = [self selectedId];
    if (!sid) return;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = ns(L("vpn.remove_confirm_title"));
    alert.informativeText = ns(L("vpn.remove_confirm_body"));
    [alert addButtonWithTitle:ns(L("vpn.remove"))];
    [alert addButtonWithTitle:ns(L("common.cancel"))];
    alert.alertStyle = NSAlertStyleWarning;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    VpnStore::instance().remove([sid UTF8String]);
    [self reload];
}

- (void)toggleConnection:(id)sender {
    VpnController& c = VpnController::instance();
    if (c.state() == VpnConnState::Connected) {
        c.disconnect();
        [self reload];
        return;
    }
    NSString* sid = [self selectedId];
    std::string id = sid ? [sid UTF8String] : VpnStore::instance().selectedId();
    if (id.empty()) {
        [self showError:ns(L("vpn.err.no_profile"))];
        return;
    }
    std::string err = c.connect(id);
    if (!err.empty()) {
        [self showError:ns(L(err))];
    }
    [self reload];
}

- (void)autoConnectChanged:(id)sender {
    AppSettings s = SettingsStore::instance().load();
    s.vpnAutoConnect = (_autoConnectCheck.state == NSControlStateValueOn);
    SettingsStore::instance().save(s);
}

- (void)autoReconnectChanged:(id)sender {
    AppSettings s = SettingsStore::instance().load();
    s.vpnAutoReconnect = (_autoReconnectCheck.state == NSControlStateValueOn);
    SettingsStore::instance().save(s);
}

- (void)powerSaverChanged:(id)sender {
    AppSettings s = SettingsStore::instance().load();
    s.vpnPowerSaver = (_powerSaverCheck.state == NSControlStateValueOn);
    SettingsStore::instance().save(s);
}

- (void)showError:(NSString*)message {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = ns(L("vpn.error_title"));
    alert.informativeText = message;
    [alert addButtonWithTitle:ns(L("common.ok"))];
    alert.alertStyle = NSAlertStyleWarning;
    [alert runModal];
}

@end
