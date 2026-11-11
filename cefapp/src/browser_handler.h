#ifndef BROWSER_HANDLER_H
#define BROWSER_HANDLER_H

#include "include/cef_client.h"
#include "include/cef_download_handler.h"
#include "include/cef_jsdialog_handler.h"
#include "include/cef_display_handler.h"
#include "include/cef_find_handler.h"
#include "include/cef_browser.h"
#include <string>

/// Handlers for the browser features that the Android build has and the
/// original macOS port did not: downloads, JS dialogs (alert/confirm/prompt),
/// the beforeunload prompt, fullscreen video and in-page find.
///
/// Kept in its own translation unit so it can be attached to `SimpleHandler`
/// without growing that file further. Every dialog goes through
/// `hb::js_guard::DialogBudget` (ported from Android) so a hostile page cannot
/// lock the UI with a dialog storm.
class BrowserHandler : public CefDownloadHandler,
                       public CefJSDialogHandler,
                       public CefDisplayHandler,
                       public CefFindHandler {
public:
    BrowserHandler();
    ~BrowserHandler() override;

    // ---- CefDownloadHandler ----
    bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                          CefRefPtr<CefDownloadItem> download_item,
                          const CefString& suggested_name,
                          CefRefPtr<CefBeforeDownloadCallback> callback) override;
    void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefDownloadItem> download_item,
                           CefRefPtr<CefDownloadItemCallback> callback) override;

    // ---- CefJSDialogHandler ----
    bool OnJSDialog(CefRefPtr<CefBrowser> browser,
                    const CefString& origin_url,
                    JSDialogType dialog_type,
                    const CefString& message_text,
                    const CefString& default_prompt_text,
                    CefRefPtr<CefJSDialogCallback> callback,
                    bool& suppress_message) override;
    bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser,
                              const CefString& message_text,
                              bool is_reload,
                              CefRefPtr<CefJSDialogCallback> callback) override;
    void OnResetDialogState(CefRefPtr<CefBrowser> browser) override;

    // ---- CefDisplayHandler (fullscreen) ----
    void OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) override;

    // ---- CefFindHandler ----
    void OnFindResult(CefRefPtr<CefBrowser> browser,
                      int identifier,
                      int count,
                      const CefRect& selectionRect,
                      int activeMatchOrdinal,
                      bool finalUpdate) override;

    /// True when the dialog budget has suppressed something (diagnostics).
    bool HasSuppressedDialogs() const;

private:
    IMPLEMENT_REFCOUNTING(BrowserHandler);

    // Per-document dialog budget; reset on navigation via OnResetDialogState.
    struct BudgetHolder;
    BudgetHolder* budget_;
};

#endif  // BROWSER_HANDLER_H
