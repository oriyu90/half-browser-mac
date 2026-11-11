#import <Cocoa/Cocoa.h>
#include "simple_handler.h"
#include "include/cef_browser.h"
#include "include/cef_frame.h"
#include "include/cef_parser.h"
#include "include/wrapper/cef_helpers.h"
#include "include/cef_ssl_info.h"
#include "keychain_helper.h"
#include "history_store.h"
#include "half_browser_core.h"
#include "form_login.h"
#include "site_permissions.h"
#include "localization.h"
#include "json_util.h"
#include <mutex>
#include <string>
#include <vector>
#include <dispatch/dispatch.h>

CefRefPtr<SimpleHandler> SimpleHandler::instance_ = nullptr;

SimpleHandler::SimpleHandler()
    : is_closing_(false), is_loading_(false), can_go_back_(false), can_go_forward_(false) {}

SimpleHandler::~SimpleHandler() {}

CefRefPtr<SimpleHandler> SimpleHandler::GetInstance() {
    // CefRefPtr assignment is not atomic: guard the check-then-set so two
    // threads can never build (and leak) two handlers.
    static std::mutex mu;
    std::lock_guard<std::mutex> lock(mu);
    if (!instance_) {
        instance_ = new SimpleHandler();
    }
    return instance_;
}

void SimpleHandler::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();
    if (!browser_) {
        browser_ = browser;
    }

    // Keep the CEF view glued to the window's content view so every window
    // shape (resize, full screen, split view) tracks the host correctly.
    NSView* cefView = (NSView*)browser->GetHost()->GetWindowHandle();
    if (!cefView) return;
    NSView* parent = [cefView superview];
    if (!parent) return;
    cefView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [cefView.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [cefView.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor],
        [cefView.topAnchor constraintEqualToAnchor:parent.topAnchor],
        [cefView.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor],
    ]];
}

bool SimpleHandler::DoClose(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();
    is_closing_ = true;
    return false;
}

void SimpleHandler::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();
    if (browser_ == browser) {
        browser_ = nullptr;
    }
}

void SimpleHandler::OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int status_code) {
    if (frame->IsMain()) {
        std::string url = frame->GetURL().ToString();
        // History is recorded in OnTitleChange: the title is only final there.
        // Inject form login detection script
        if (url.find("https://") == 0) {
            frame->ExecuteJavaScript(FormLoginService::detectionScript(), frame->GetURL(), 0);
        }
    }
}

void SimpleHandler::OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, ErrorCode error_code, const CefString& error_text, const CefString& failed_url) {
    // load error
}

void SimpleHandler::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) {
    std::string newTitle = title.ToString();
    title_ = newTitle;

    // Record history once the title is known (OnLoadEnd can arrive first and
    // would store an empty title). Repeat visits of the same URL are merged by
    // HistoryStore::record's 30-minute window, so recording per title change
    // does not duplicate entries.
    if (browser) {
        std::string url = browser->GetMainFrame() ? browser->GetMainFrame()->GetURL().ToString() : std::string();
        if (!url.empty() && url.find("://") != std::string::npos) {
            time_t now = time(nullptr);
            HistoryStore::instance().record(url, newTitle, (long long)now * 1000);
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSView* view = (NSView*)browser->GetHost()->GetWindowHandle();
        NSWindow* window = [view window];
        if (window) {
            [window setTitle:[NSString stringWithUTF8String:title_.c_str()]];
        }
    });
}

void SimpleHandler::OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) {
    if (frame->IsMain()) {
        url_ = url.ToString();
    }
}

void SimpleHandler::OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading, bool canGoBack, bool canGoForward) {
    is_loading_ = isLoading;
    can_go_back_ = canGoBack;
    can_go_forward_ = canGoForward;
}

bool SimpleHandler::OnCertificateError(CefRefPtr<CefBrowser> browser, cef_errorcode_t cert_error, const CefString& request_url, CefRefPtr<CefSSLInfo> ssl_info, CefRefPtr<CefCallback> callback) {
    std::string url = request_url.ToString();

    // Extract host and port from URL. IPv6 literals are bracketed
    // ("https://[::1]:8443/") so only the text after ']' can be a port.
    std::string host = "";
    int port = 443;
    size_t scheme_end = url.find("://");
    if (scheme_end != std::string::npos) {
        size_t host_start = scheme_end + 3;
        size_t path_start = url.find('/', host_start);
        std::string hostport = (path_start != std::string::npos) ? url.substr(host_start, path_start - host_start) : url.substr(host_start);
        std::string portPart;
        if (!hostport.empty() && hostport[0] == '[') {
            size_t close = hostport.find(']');
            if (close != std::string::npos) {
                host = hostport.substr(0, close + 1);  // keep the brackets
                if (close + 1 < hostport.size() && hostport[close + 1] == ':') {
                    portPart = hostport.substr(close + 2);
                }
            } else {
                host = hostport;
            }
        } else {
            size_t colon = hostport.find(':');
            if (colon != std::string::npos) {
                host = hostport.substr(0, colon);
                portPart = hostport.substr(colon + 1);
            } else {
                host = hostport;
            }
        }
        if (!portPart.empty()) {
            char* end = nullptr;
            long parsed = strtol(portPart.c_str(), &end, 10);
            if (end != portPart.c_str() && end && *end == '\0' && parsed > 0 && parsed <= 65535) {
                port = (int)parsed;
            }
        }
    }

    // Fingerprint = lowercase hex SHA-256 of the DER certificate (Android parity).
    std::string fingerprint = "";
    std::string subjectName = "";
    std::string issuerName = "";
    if (ssl_info) {
        CefRefPtr<CefX509Certificate> cert = ssl_info->GetX509Certificate();
        if (cert) {
            CefRefPtr<CefX509CertPrincipal> subject = cert->GetSubject();
            if (subject) subjectName = subject->GetDisplayName().ToString();
            CefRefPtr<CefX509CertPrincipal> issuer = cert->GetIssuer();
            if (issuer) issuerName = issuer->GetDisplayName().ToString();

            CefRefPtr<CefBinaryValue> der = cert->GetDEREncoded();
            if (der && der->GetSize() > 0) {
                std::vector<uint8_t> buf(der->GetSize());
                der->GetData(buf.data(), buf.size(), 0);
                char hex[65] = {0};
                if (hb_sha256_hex(buf.data(), buf.size(), hex)) {
                    fingerprint = std::string(hex);
                }
            }
        }
    }
    // Without a usable certificate we cannot pin safely: never offer "Trust Always".
    bool canPin = !fingerprint.empty();

    // TOFU: use Rust TrustPolicy via FFI
    std::string savedPin = KeychainLoadCertPin(host, port);
    bool hasPin = !savedPin.empty();

    int decision = 1; // Unknown default
    if (hasPin) {
        decision = hb_trust_decide(
            host.c_str(), port, fingerprint.c_str(),
            host.c_str(), port, savedPin.c_str());
    }
    bool pinMatches = (decision == 0); // Trusted

    // CEF only keeps the callback alive for the duration of this call; hold a
    // reference so the async block can still answer it.
    CefRefPtr<CefCallback> cb = callback;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (hasPin && pinMatches) {
            // Trusted: proceed silently
            cb->Continue();
        } else if (hasPin && !pinMatches) {
            // Changed: warn harder
            NSAlert* alert = [[NSAlert alloc] init];
            [alert setMessageText:[NSString stringWithUTF8String:L("ssl.changed_title").c_str()]];
            [alert setInformativeText:[NSString stringWithFormat:[NSString stringWithUTF8String:L("ssl.changed_body").c_str()], host.c_str(), fingerprint.c_str(), savedPin.c_str()]];
            [alert addButtonWithTitle:[NSString stringWithUTF8String:L("ssl.proceed_anyway").c_str()]];
            [alert addButtonWithTitle:[NSString stringWithUTF8String:L("ssl.cancel").c_str()]];
            [alert setAlertStyle:NSAlertStyleCritical];

            NSModalResponse response = [alert runModal];
            if (response == NSAlertFirstButtonReturn) {
                KeychainSaveCertPin(host, port, fingerprint);
                cb->Continue();
            } else {
                cb->Cancel();
            }
        } else {
            // Unknown: show interstitial
            NSAlert* alert = [[NSAlert alloc] init];
            [alert setMessageText:[NSString stringWithUTF8String:L("ssl.title").c_str()]];
            [alert setInformativeText:[NSString stringWithFormat:[NSString stringWithUTF8String:L("ssl.unknown_body").c_str()],
                host.c_str(), subjectName.c_str(), issuerName.c_str(),
                fingerprint.empty() ? L("ssl.unavailable").c_str() : fingerprint.c_str(), cert_error]];
            if (canPin) {
                [alert addButtonWithTitle:[NSString stringWithUTF8String:L("ssl.trust_always").c_str()]];
                [alert addButtonWithTitle:[NSString stringWithUTF8String:L("ssl.proceed_once").c_str()]];
            } else {
                [alert addButtonWithTitle:[NSString stringWithUTF8String:L("ssl.proceed_once").c_str()]];
            }
            [alert addButtonWithTitle:[NSString stringWithUTF8String:L("ssl.cancel").c_str()]];
            [alert setAlertStyle:NSAlertStyleCritical];

            NSModalResponse response = [alert runModal];
            if (canPin && response == NSAlertFirstButtonReturn) {
                KeychainSaveCertPin(host, port, fingerprint);
                cb->Continue();
            } else if ((canPin && response == NSAlertSecondButtonReturn) ||
                       (!canPin && response == NSAlertFirstButtonReturn)) {
                cb->Continue();
            } else {
                cb->Cancel();
            }
        }
    });

    return true;
}

bool SimpleHandler::GetAuthCredentials(CefRefPtr<CefBrowser> browser, const CefString& origin_url, bool is_proxy, const CefString& host, int port, const CefString& realm, const CefString& scheme, CefRefPtr<CefAuthCallback> callback) {
    std::string h = host.ToString();
    std::string r = realm.ToString();
    std::string s = scheme.ToString();
    int p = port;

    std::string key = s + "://" + h + ":" + std::to_string(p) + "|" + r;

    std::string savedUser, savedPass;
    if (KeychainLoadCredential(key, savedUser, savedPass)) {
        callback->Continue(CefString(savedUser), CefString(savedPass));
        return true;
    }

    // Hold the callback across the async hop (CEF does not keep it alive), and
    // copy h/r/s/p by value so the block never reads a dead stack frame.
    CefRefPtr<CefAuthCallback> cb = callback;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:[NSString stringWithUTF8String:L("auth.title").c_str()]];
        [alert setInformativeText:[NSString stringWithFormat:[NSString stringWithUTF8String:L("auth.body").c_str()], h.c_str(), p, r.c_str()]];

        NSTextField* userField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
        userField.placeholderString = [NSString stringWithUTF8String:L("auth.username").c_str()];
        NSSecureTextField* passField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
        passField.placeholderString = [NSString stringWithUTF8String:L("auth.password").c_str()];

        NSView* accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 56)];
        [userField setFrame:NSMakeRect(0, 32, 240, 24)];
        [passField setFrame:NSMakeRect(0, 0, 240, 24)];
        [accessory addSubview:userField];
        [accessory addSubview:passField];
        [alert setAccessoryView:accessory];

        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("auth.ok").c_str()]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("ssl.cancel").c_str()]];

        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            std::string username = [[userField stringValue] UTF8String];
            std::string password = [[passField stringValue] UTF8String];
            if (s == "https") {
                KeychainSaveCredential(key, username, password);
            }
            cb->Continue(
                CefString(username),
                CefString(password)
            );
        } else {
            cb->Cancel();
        }
    });

    return true;
}
// ============================================================
// Form login: receive messages from injected JS
// ============================================================
bool SimpleHandler::OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                             CefRefPtr<CefFrame> frame,
                                             CefProcessId source_process,
                                             CefRefPtr<CefProcessMessage> message) {
    CEF_REQUIRE_UI_THREAD();
    if (!message) return false;

    std::string name = message->GetName().ToString();
    if (name != "formLogin") return false;

    CefRefPtr<CefListValue> args = message->GetArgumentList();
    if (!args || args->GetSize() < 3) return true;

    std::string username = args->GetString(0).ToString();
    std::string password = args->GetString(1).ToString();
    std::string originUrl = args->GetString(2).ToString();

    if (username.empty() || password.empty()) return true;

    // Ask the user whether to remember
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:[NSString stringWithUTF8String:L("formlogin.title").c_str()]];
        [alert setInformativeText:[NSString stringWithFormat:[NSString stringWithUTF8String:L("formlogin.body").c_str()], originUrl.c_str(), username.c_str()]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("formlogin.save").c_str()]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("formlogin.not_now").c_str()]];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            FormLoginService::saveCredentials(originUrl, username, password);
        }
    });

    return true;
}

// ============================================================
// Site permissions: media access (camera / microphone)
// ============================================================
bool SimpleHandler::OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser,
                                                   CefRefPtr<CefFrame> frame,
                                                   const CefString& requesting_origin,
                                                   uint32_t requested_permissions,
                                                   CefRefPtr<CefMediaAccessCallback> callback) {
    std::string origin = requesting_origin.ToString();

    // CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE (1<<1) is the camera,
    // CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE (1<<0) is the microphone.
    bool hasCamera = (requested_permissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) != 0;
    bool hasMic = (requested_permissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) != 0;
    std::string kind = hasCamera ? "camera" : (hasMic ? "microphone" : "media");

    // Hold the callback across the async hop (CEF does not keep it alive).
    CefRefPtr<CefMediaAccessCallback> cb = callback;

    // Check stored decision
    if (SitePermissionStore::instance().isGranted(origin, "camera") ||
        SitePermissionStore::instance().isGranted(origin, "microphone")) {
        // Already granted for this origin
        if (SitePermissionStore::instance().isGranted(origin, kind)) {
            cb->Continue(requested_permissions);
            return true;
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:[NSString stringWithUTF8String:L("perm.media_title").c_str()]];
        [alert setInformativeText:[NSString stringWithFormat:[NSString stringWithUTF8String:L("perm.media_body").c_str()], origin.c_str(), L("perm.kind." + kind).c_str()]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("perm.allow").c_str()]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("perm.block").c_str()]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("perm.allow_once").c_str()]];

        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            SitePermissionStore::instance().set(origin, kind, true);
            cb->Continue(requested_permissions);
        } else if (response == NSAlertThirdButtonReturn) {
            cb->Continue(requested_permissions);
        } else {
            SitePermissionStore::instance().set(origin, kind, false);
            cb->Cancel();
        }
    });
    return true;
}

// ============================================================
// Form login: receive detection via console message
// ============================================================
bool SimpleHandler::OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                                     cef_log_severity_t level,
                                     const CefString& message,
                                     const CefString& source,
                                     int line) {
    std::string msg = message.ToString();
    const std::string prefix = "__HB_FORM_LOGIN__|";
    if (msg.compare(0, prefix.size(), prefix) != 0) return false;

    // Format: __HB_FORM_LOGIN__|username|password|origin (each URL-encoded)
    std::string rest = msg.substr(prefix.size());
    std::vector<std::string> parts;
    size_t start = 0;
    while (true) {
        size_t pos = rest.find('|', start);
        if (pos == std::string::npos) {
            parts.push_back(rest.substr(start));
            break;
        }
        parts.push_back(rest.substr(start, pos - start));
        start = pos + 1;
    }
    if (parts.size() < 3) return true;

    // URL-decode (JsonUtil validates the hex digits, so a malformed "%zz"
    // sequence is passed through instead of throwing).
    std::string username = JsonUtil::urlDecode(parts[0]);
    std::string password = JsonUtil::urlDecode(parts[1]);
    std::string origin = JsonUtil::urlDecode(parts[2]);

    if (username.empty() || password.empty()) return true;
    if (origin.find("https://") != 0) return true;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:[NSString stringWithUTF8String:L("formlogin.title").c_str()]];
        [alert setInformativeText:[NSString stringWithFormat:[NSString stringWithUTF8String:L("formlogin.body").c_str()], origin.c_str(), username.c_str()]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("formlogin.save").c_str()]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("formlogin.not_now").c_str()]];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            FormLoginService::saveCredentials(origin, username, password);
        }
    });
    return true;
}

// ============================================================
// Site permissions: generic permission prompts (notifications, geolocation, ...)
// ============================================================
bool SimpleHandler::OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser,
                                           uint64_t prompt_id,
                                           const CefString& requesting_origin,
                                           uint32_t requested_permissions,
                                           CefRefPtr<CefPermissionPromptCallback> callback) {
    std::string origin = requesting_origin.ToString();

    // Map CEF permission bits to our kind string
    std::string kind = "unknown";
    if (requested_permissions & CEF_PERMISSION_TYPE_NOTIFICATIONS) {
        kind = "notification";
    } else if (requested_permissions & CEF_PERMISSION_TYPE_GEOLOCATION) {
        kind = "location";
    } else if (requested_permissions & CEF_PERMISSION_TYPE_CAMERA_STREAM) {
        kind = "camera";
    } else if (requested_permissions & CEF_PERMISSION_TYPE_MIC_STREAM) {
        kind = "microphone";
    } else if (requested_permissions & CEF_PERMISSION_TYPE_CLIPBOARD) {
        kind = "clipboard";
    }

    // Hold the callback across the async hop (CEF does not keep it alive).
    CefRefPtr<CefPermissionPromptCallback> cb = callback;

    // Check stored decision
    if (SitePermissionStore::instance().isGranted(origin, kind)) {
        cb->Continue(CEF_PERMISSION_RESULT_ACCEPT);
        return true;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:[NSString stringWithUTF8String:L("perm.title").c_str()]];
        [alert setInformativeText:[NSString stringWithFormat:[NSString stringWithUTF8String:L("perm.body").c_str()], origin.c_str(), L("perm.kind." + kind).c_str()]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("perm.allow").c_str()]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("perm.block").c_str()]];
        [alert addButtonWithTitle:[NSString stringWithUTF8String:L("perm.allow_once").c_str()]];

        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            SitePermissionStore::instance().set(origin, kind, true);
            cb->Continue(CEF_PERMISSION_RESULT_ACCEPT);
        } else if (response == NSAlertThirdButtonReturn) {
            cb->Continue(CEF_PERMISSION_RESULT_ACCEPT);
        } else {
            SitePermissionStore::instance().set(origin, kind, false);
            cb->Continue(CEF_PERMISSION_RESULT_DENY);
        }
    });
    return true;
}
