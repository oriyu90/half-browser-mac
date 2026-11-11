#import <Cocoa/Cocoa.h>
#include "browser_handler.h"
#include "half_browser_core.h"
#include "localization.h"
#include "json_util.h"
#include "settings_store.h"
#include "include/wrapper/cef_helpers.h"
#include <chrono>
#include <functional>
#include <string>
#include <vector>

namespace {

/// Wall clock in epoch milliseconds (the unit the Rust rules use).
int64_t nowMillis() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

NSString* ns(const std::string& s) {
    return [NSString stringWithUTF8String:s.c_str()];
}

/// The Downloads folder, falling back to the home directory.
NSString* downloadsDirectory() {
    NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(
        NSDownloadsDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) return paths.firstObject;
    return NSHomeDirectory();
}

/// A unique destination for `name` inside `dir`, so a second download of the
/// same file does not silently overwrite the first.
NSString* uniquePath(NSString* dir, NSString* name) {
    NSString* base = [name stringByDeletingPathExtension];
    NSString* ext = [name pathExtension];
    NSString* candidate = [dir stringByAppendingPathComponent:name];
    int n = 1;
    while ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
        NSString* suffixed = [NSString stringWithFormat:@"%@ (%d)", base, n];
        candidate = ext.length > 0
            ? [dir stringByAppendingPathComponent:[suffixed stringByAppendingPathExtension:ext]]
            : [dir stringByAppendingPathComponent:suffixed];
        n++;
        if (n > 9999) break;
    }
    return candidate;
}

}  // namespace

// The budget is allocated once and shared by every dialog this handler shows.
// It is reset per document (OnResetDialogState) so navigation gives the new
// page a fresh allowance, matching the Android DialogBudget lifetime.
struct BrowserHandler::BudgetHolder {
    HbDialogBudget* budget = nullptr;
    /// A dialog is currently on screen. NSAlert::runModal nests if a second
    /// one starts before the first returns, which leaves an unhandled dialog
    /// behind and freezes the page until the user closes everything. Dialogs
    /// are therefore serialized: a second one is queued, not shown.
    bool showing = false;
    /// Pending dialogs, oldest first. Each entry owns a CefRefPtr.
    std::vector<std::function<void()>> pending;
    BudgetHolder() : budget(hb_dialog_budget_new()) {}
    ~BudgetHolder() { hb_dialog_budget_free(budget); }

    /// Runs `show` when no dialog is on screen, otherwise defers it.
    void enqueue(std::function<void()> show) {
        if (showing) {
            pending.push_back(std::move(show));
            return;
        }
        showing = true;
        show();
    }

    /// Called by the dialog that just finished; starts the next one.
    void finished() {
        if (pending.empty()) {
            showing = false;
            return;
        }
        auto next = std::move(pending.front());
        pending.erase(pending.begin());
        // Still `showing`, so a dialog opened from the next one is queued too.
        next();
    }
};

BrowserHandler::BrowserHandler() : budget_(new BudgetHolder()) {}

BrowserHandler::~BrowserHandler() {
    delete budget_;
    budget_ = nullptr;
}

bool BrowserHandler::HasSuppressedDialogs() const {
    return budget_ && hb_dialog_budget_blocked(budget_->budget) > 0;
}

// ============================================================
// Downloads
// ============================================================

bool BrowserHandler::OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                                      CefRefPtr<CefDownloadItem> download_item,
                                      const CefString& suggested_name,
                                      CefRefPtr<CefBeforeDownloadCallback> callback) {
    CEF_REQUIRE_UI_THREAD();
    if (!callback) return false;

    std::string suggested = suggested_name.ToString();
    if (suggested.empty()) suggested = "download";

    // Keep the CefRefPtr alive inside the block: CEF may release the callback
    // as soon as this method returns, and the block runs later on the UI queue.
    CefRefPtr<CefBeforeDownloadCallback> cb = callback;
    NSString* name = ns(suggested);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSSavePanel* panel = [NSSavePanel savePanel];
        panel.title = ns(L("download.save_title"));
        panel.nameFieldStringValue = name;
        panel.canCreateDirectories = YES;
        panel.directoryURL = [NSURL fileURLWithPath:downloadsDirectory()];

        if ([panel runModal] == NSModalResponseOK && [panel URL]) {
            NSString* path = [[panel URL] path];
            cb->Continue([path UTF8String], false);
        } else {
            // The user cancelled: continuing with an empty path cancels the
            // download, which is the documented behaviour.
            cb->Continue("", false);
        }
    });
    return true;
}

void BrowserHandler::OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefDownloadItem> download_item,
                                       CefRefPtr<CefDownloadItemCallback> callback) {
    CEF_REQUIRE_UI_THREAD();
    if (!download_item) return;

    if (download_item->IsComplete()) {
        std::string path = download_item->GetFullPath().ToString();
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert* alert = [[NSAlert alloc] init];
            [alert setMessageText:ns(L("download.done_title"))];
            [alert setInformativeText:[NSString stringWithFormat:ns(L("download.done_body")),
                                                                path.c_str()]];
            [alert addButtonWithTitle:ns(L("common.ok"))];
            [alert runModal];
        });
    } else if (download_item->IsCanceled()) {
        // Nothing to report: the user cancelled it.
    }
}

// ============================================================
// JS dialogs (alert / confirm / prompt)
// ============================================================

bool BrowserHandler::OnJSDialog(CefRefPtr<CefBrowser> browser,
                                const CefString& origin_url,
                                JSDialogType dialog_type,
                                const CefString& message_text,
                                const CefString& default_prompt_text,
                                CefRefPtr<CefJSDialogCallback> callback,
                                bool& suppress_message) {
    CEF_REQUIRE_UI_THREAD();
    if (!callback) return false;

    // A hostile page can call alert() in a loop; the dialog is app UI, so
    // without a budget the page could freeze the browser. The policy is the
    // Rust port of the Android DialogBudget so both platforms agree.
    if (!hb_dialog_budget_allow(budget_->budget, nowMillis())) {
        suppress_message = true;
        return false;  // let CEF treat it as suppressed
    }

    CefRefPtr<CefJSDialogCallback> cb = callback;
    std::string message = message_text.ToString();
    std::string defaultText = default_prompt_text.ToString();
    std::string origin = origin_url.ToString();

    BudgetHolder* holder = budget_;
    dispatch_async(dispatch_get_main_queue(), ^{
        holder->enqueue([=]() {
        NSAlert* alert = [[NSAlert alloc] init];
        NSString* title = nil;
        switch (dialog_type) {
            case JSDIALOGTYPE_ALERT: title = ns(L("jsdialog.alert_title")); break;
            case JSDIALOGTYPE_CONFIRM: title = ns(L("jsdialog.confirm_title")); break;
            case JSDIALOGTYPE_PROMPT: title = ns(L("jsdialog.prompt_title")); break;
            default: title = ns(L("jsdialog.alert_title")); break;
        }
        [alert setMessageText:title];
        [alert setInformativeText:ns(message)];

        NSTextField* promptField = nil;
        if (dialog_type == JSDIALOGTYPE_PROMPT) {
            promptField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
            promptField.stringValue = ns(defaultText);
            [alert setAccessoryView:promptField];
            [alert addButtonWithTitle:ns(L("common.ok"))];
            [alert addButtonWithTitle:ns(L("common.cancel"))];
        } else if (dialog_type == JSDIALOGTYPE_CONFIRM) {
            [alert addButtonWithTitle:ns(L("common.ok"))];
            [alert addButtonWithTitle:ns(L("common.cancel"))];
        } else {
            [alert addButtonWithTitle:ns(L("common.ok"))];
        }

        // Show which site is asking: a page must not be able to impersonate
        // the app's own dialogs.
        if (!origin.empty()) {
            [alert setInformativeText:[NSString stringWithFormat:@"%@\n\n— %@",
                                                                ns(message), ns(origin)]];
        }

        NSModalResponse response = [alert runModal];
        bool accepted = (response == NSAlertFirstButtonReturn);
        if (dialog_type == JSDIALOGTYPE_PROMPT) {
            std::string text = accepted ? std::string([[promptField stringValue] UTF8String]) : "";
            cb->Continue(accepted, text);
        } else if (dialog_type == JSDIALOGTYPE_CONFIRM) {
            cb->Continue(accepted, "");
        } else {
            cb->Continue(true, "");
        }
        holder->finished();
        });
    });
    return true;
}

bool BrowserHandler::OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser,
                                          const CefString& message_text,
                                          bool is_reload,
                                          CefRefPtr<CefJSDialogCallback> callback) {
    CEF_REQUIRE_UI_THREAD();
    if (!callback) return false;

    // A beforeunload handler that re-registers on every prompt makes the page
    // impossible to leave. Cap it, exactly like the Android DialogBudget.
    if (!hb_dialog_budget_allow_before_unload(budget_->budget)) {
        callback->Continue(true, "");
        return true;
    }

    CefRefPtr<CefJSDialogCallback> cb = callback;
    std::string message = message_text.ToString();
    BudgetHolder* holder = budget_;
    dispatch_async(dispatch_get_main_queue(), ^{
        holder->enqueue([=]() {
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:ns(L("jsdialog.beforeunload_title"))];
        [alert setInformativeText:message.empty() ? ns(L("jsdialog.beforeunload_body"))
                                                  : ns(message)];
        [alert addButtonWithTitle:ns(L("jsdialog.leave"))];
        [alert addButtonWithTitle:ns(L("jsdialog.stay"))];
        NSModalResponse response = [alert runModal];
        cb->Continue(response == NSAlertFirstButtonReturn, "");
        holder->finished();
        });
    });
    return true;
}

void BrowserHandler::OnResetDialogState(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();
    // A new document gets a fresh allowance.
    hb_dialog_budget_reset(budget_->budget);
}

// ============================================================
// Fullscreen video
// ============================================================

void BrowserHandler::OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) {
    CEF_REQUIRE_UI_THREAD();
    dispatch_async(dispatch_get_main_queue(), ^{
        NSView* view = browser ? (NSView*)browser->GetHost()->GetWindowHandle() : nil;
        NSWindow* window = [view window];
        if (!window) return;
        bool isFull = (([window styleMask] & NSWindowStyleMaskFullScreen) != 0);
        if (fullscreen && !isFull) {
            [window toggleFullScreen:nil];
        } else if (!fullscreen && isFull) {
            [window toggleFullScreen:nil];
        }
    });
}

// ============================================================
// In-page find
// ============================================================

void BrowserHandler::OnFindResult(CefRefPtr<CefBrowser> browser,
                                  int identifier,
                                  int count,
                                  const CefRect& selectionRect,
                                  int activeMatchOrdinal,
                                  bool finalUpdate) {
    CEF_REQUIRE_UI_THREAD();
    if (!finalUpdate) return;
    // Report the match count in the window title area via a transient label is
    // overkill; log it so the Find panel can be wired up later without a
    // behavioural surprise.
    NSLog(@"find: %d/%d", activeMatchOrdinal, count);
}
