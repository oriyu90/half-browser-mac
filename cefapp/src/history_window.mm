#import <Cocoa/Cocoa.h>
#include "history_window.h"
#include "history_store.h"
#include "localization.h"
#include <ctime>
#include <string>
#include <vector>

namespace {

NSString* ns(const std::string& s) {
    return [NSString stringWithUTF8String:s.c_str()];
}

/// Formats an epoch-millis timestamp using the user's locale.
NSString* formatTime(long long millis) {
    if (millis <= 0) return @"";
    NSDate* date = [NSDate dateWithTimeIntervalSince1970:(double)millis / 1000.0];
    NSDateFormatter* f = [[NSDateFormatter alloc] init];
    f.dateStyle = NSDateFormatterMediumStyle;
    f.timeStyle = NSDateFormatterShortStyle;
    return [f stringFromDate:date];
}

}  // namespace

static HistoryWindowController* g_history = nil;

@implementation HistoryWindowController {
    NSTableView* _table;
    NSSearchField* _search;
    std::vector<HistoryEntry> _rows;
}

+ (instancetype)shared {
    if (!g_history) {
        g_history = [[HistoryWindowController alloc] init];
    }
    return g_history;
}

- (instancetype)init {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 480)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered
        defer:NO];
    window.title = ns(L("history.title"));
    window.minSize = NSMakeSize(480, 320);
    [window center];
    self = [super initWithWindow:window];
    if (self) {
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSView* content = self.window.contentView;
    NSRect bounds = content.bounds;

    _search = [[NSSearchField alloc] initWithFrame:NSMakeRect(12, bounds.size.height - 44, bounds.size.width - 24, 28)];
    _search.placeholderString = ns(L("history.search"));
    _search.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _search.target = self;
    _search.action = @selector(searchChanged:);
    [content addSubview:_search];

    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 52, bounds.size.width - 24, bounds.size.height - 104)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;

    _table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    for (NSString* ident in @[@"title", @"url", @"visited"]) {
        NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:ident];
        col.width = [ident isEqualToString:@"title"] ? 240 : ([ident isEqualToString:@"url"] ? 320 : 120);
        if ([ident isEqualToString:@"title"]) col.title = ns(L("history.col_title"));
        else if ([ident isEqualToString:@"url"]) col.title = ns(L("history.col_url"));
        else col.title = ns(L("history.col_visited"));
        [_table addTableColumn:col];
    }
    _table.dataSource = (id<NSTableViewDataSource>)self;
    _table.delegate = (id<NSTableViewDelegate>)self;
    _table.usesAlternatingRowBackgroundColors = YES;
    _table.allowsMultipleSelection = NO;
    scroll.documentView = _table;
    [content addSubview:scroll];

    NSButton* clear = [[NSButton alloc] initWithFrame:NSMakeRect(12, 12, 150, 28)];
    clear.title = ns(L("history.clear"));
    clear.bezelStyle = NSBezelStyleRounded;
    clear.target = self;
    clear.action = @selector(clearAll:);
    clear.autoresizingMask = NSViewMaxYMargin;
    [content addSubview:clear];

    NSButton* remove = [[NSButton alloc] initWithFrame:NSMakeRect(170, 12, 110, 28)];
    remove.title = ns(L("history.delete"));
    remove.bezelStyle = NSBezelStyleRounded;
    remove.target = self;
    remove.action = @selector(deleteSelected:);
    remove.autoresizingMask = NSViewMaxYMargin;
    [content addSubview:remove];

    NSButton* close = [[NSButton alloc] initWithFrame:NSMakeRect(bounds.size.width - 110, 12, 98, 28)];
    close.title = ns(L("history.close"));
    close.bezelStyle = NSBezelStyleRounded;
    close.target = self;
    close.action = @selector(closeWindow:);
    close.keyEquivalent = @"\033";
    close.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [content addSubview:close];
}

- (void)showWindow {
    [self reload];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)reload {
    _rows.clear();
    std::string query = _search ? [[_search stringValue] UTF8String] : "";
    for (const auto& e : HistoryStore::instance().all()) {
        if (!query.empty()) {
            // Case-insensitive substring match on title or URL.
            auto lower = [](std::string s) {
                for (auto& c : s) c = (char)tolower((unsigned char)c);
                return s;
            };
            std::string hay = lower(e.title + " " + e.url);
            if (hay.find(lower(query)) == std::string::npos) continue;
        }
        _rows.push_back(e);
    }
    [_table reloadData];
}

- (void)searchChanged:(id)sender {
    [self reload];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    return (NSInteger)_rows.size();
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rows.size()) return nil;
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
    const auto& e = _rows[(size_t)row];
    if ([column.identifier isEqualToString:@"title"]) {
        cell.textField.stringValue = e.title.empty() ? ns(e.url) : ns(e.title);
    } else if ([column.identifier isEqualToString:@"url"]) {
        cell.textField.stringValue = ns(e.url);
    } else {
        cell.textField.stringValue = formatTime(e.visitedAt);
    }
    return cell;
}

- (void)deleteSelected:(id)sender {
    NSInteger row = _table.selectedRow;
    if (row < 0 || row >= (NSInteger)_rows.size()) return;
    HistoryStore::instance().removeUrl(_rows[(size_t)row].url);
    [self reload];
}

- (void)clearAll:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = ns(L("history.clear"));
    alert.informativeText = ns(L("history.clear_confirm"));
    [alert addButtonWithTitle:ns(L("history.clear"))];
    [alert addButtonWithTitle:ns(L("common.cancel"))];
    alert.alertStyle = NSAlertStyleWarning;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    HistoryStore::instance().clear();
    [self reload];
}

- (void)closeWindow:(id)sender {
    [self.window orderOut:nil];
}

@end
