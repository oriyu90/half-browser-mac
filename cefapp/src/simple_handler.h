#ifndef SIMPLE_HANDLER_H
#define SIMPLE_HANDLER_H

#include "include/cef_client.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_display_handler.h"
#include "include/cef_request_handler.h"
#include "include/cef_auth_callback.h"
#include "include/cef_callback.h"
#include "include/cef_ssl_info.h"
#include "include/cef_process_message.h"
#include "include/cef_values.h"
#include "include/cef_permission_handler.h"
#include "include/cef_dialog_handler.h"
#include "browser_handler.h"
#include <string>

class SimpleHandler : public CefClient,
                      public CefLifeSpanHandler,
                      public CefLoadHandler,
                      public CefDisplayHandler,
                      public CefRequestHandler,
                      public CefPermissionHandler,
                      public CefDialogHandler {
public:
    SimpleHandler();
    ~SimpleHandler() override;

    // CefClient
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
    CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
    CefRefPtr<CefDialogHandler> GetDialogHandler() override { return this; }
    CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return browser_features_; }
    CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return browser_features_; }
    CefRefPtr<CefFindHandler> GetFindHandler() override { return browser_features_; }
    // Note: fullscreen is reported through CefDisplayHandler, which this class
    // already returns; BrowserHandler::OnFullscreenModeChange is forwarded from
    // OnFullscreenModeChange below.

    // CefLifeSpanHandler
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
    bool DoClose(CefRefPtr<CefBrowser> browser) override;
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;

    // CefLoadHandler
    void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, TransitionType transition_type) override;
    void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int status_code) override;
    void OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, ErrorCode error_code, const CefString& error_text, const CefString& failed_url) override;

    // CefDisplayHandler
    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override;
    void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) override;
    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading, bool canGoBack, bool canGoForward) override;
    bool OnConsoleMessage(CefRefPtr<CefBrowser> browser, cef_log_severity_t level, const CefString& message, const CefString& source, int line) override;
    void OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) override;

    // CefRequestHandler - SSL
    bool OnCertificateError(CefRefPtr<CefBrowser> browser, cef_errorcode_t cert_error, const CefString& request_url, CefRefPtr<CefSSLInfo> ssl_info, CefRefPtr<CefCallback> callback) override;

    // CefRequestHandler - navigation interception (form-login transport)
    bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefRequest> request,
                        bool user_gesture,
                        bool is_redirect) override;

    // CefRequestHandler - Auth
    bool GetAuthCredentials(CefRefPtr<CefBrowser> browser, const CefString& origin_url, bool is_proxy, const CefString& host, int port, const CefString& realm, const CefString& scheme, CefRefPtr<CefAuthCallback> callback) override;

    // CefClient - message handling (form login detection)
    bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                  CefRefPtr<CefFrame> frame,
                                  CefProcessId source_process,
                                  CefRefPtr<CefProcessMessage> message) override;

    // CefPermissionHandler
    bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser,
                                        CefRefPtr<CefFrame> frame,
                                        const CefString& requesting_origin,
                                        uint32_t requested_permissions,
                                        CefRefPtr<CefMediaAccessCallback> callback) override;

    bool OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser,
                                uint64_t prompt_id,
                                const CefString& requesting_origin,
                                uint32_t requested_permissions,
                                CefRefPtr<CefPermissionPromptCallback> callback) override;

    // CefDialogHandler - <input type="file">
    bool OnFileDialog(CefRefPtr<CefBrowser> browser,
                      FileDialogMode mode,
                      const CefString& title,
                      const CefString& default_file_path,
                      const std::vector<CefString>& accept_filters,
                      const std::vector<CefString>& accept_extensions,
                      const std::vector<CefString>& accept_descriptions,
                      CefRefPtr<CefFileDialogCallback> callback) override;

    // Accessors
    CefRefPtr<CefBrowser> GetBrowser() { return browser_; }
    std::string GetTitle() { return title_; }
    std::string GetURL() { return url_; }
    bool IsLoading() { return is_loading_; }
    bool CanGoBack() { return can_go_back_; }
    bool CanGoForward() { return can_go_forward_; }

    static CefRefPtr<SimpleHandler> GetInstance();

private:
    IMPLEMENT_REFCOUNTING(SimpleHandler);

    static CefRefPtr<SimpleHandler> instance_;

    CefRefPtr<CefBrowser> browser_;
    /// Downloads, JS dialogs, fullscreen and find live in their own object so
    /// this class stays focused on navigation, certificates and auth.
    CefRefPtr<BrowserHandler> browser_features_;
    bool is_closing_;
    std::string title_;
    std::string url_;
    bool is_loading_;
    bool can_go_back_;
    bool can_go_forward_;
};

#endif  // SIMPLE_HANDLER_H_