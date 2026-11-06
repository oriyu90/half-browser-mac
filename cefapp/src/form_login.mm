#import <Cocoa/Cocoa.h>
#include "form_login.h"
#include "keychain_helper.h"
#include <string>

bool FormLoginService::saveCredentials(const std::string& originUrl, const std::string& username, const std::string& password) {
    // Only save for https
    if (originUrl.find("https://") != 0) return false;
    std::string key = "form:" + originUrl;
    return KeychainSaveCredential(key, username, password);
}

bool FormLoginService::loadCredentials(const std::string& originUrl, std::string& username, std::string& password) {
    if (originUrl.find("https://") != 0) return false;
    std::string key = "form:" + originUrl;
    return KeychainLoadCredential(key, username, password);
}

std::string FormLoginService::detectionScript() {
    return R"JS(
(function() {
    if (window.__halfBrowserFormDetection) return;
    window.__halfBrowserFormDetection = true;

    function detectForms() {
        var forms = document.querySelectorAll('form');
        forms.forEach(function(form) {
            if (form.__hbDetected) return;
            var inputs = form.querySelectorAll('input');
            var hasPassword = false;
            var usernameField = null;
            inputs.forEach(function(input) {
                if (input.type === 'password') hasPassword = true;
                if (input.type === 'text' || input.type === 'email') usernameField = input;
            });
            if (hasPassword && usernameField) {
                form.__hbDetected = true;
                form.addEventListener('submit', function() {
                    var passInput = form.querySelector('input[type=password]');
                    if (passInput && usernameField.value && passInput.value) {
                        // Send via console message -> CefDisplayHandler::OnConsoleMessage
                        console.log('__HB_FORM_LOGIN__|' + encodeURIComponent(usernameField.value) + '|' + encodeURIComponent(passInput.value) + '|' + encodeURIComponent(location.origin));
                    }
                });
            }
        });
    }

    detectForms();
    // Re-detect on DOM changes
    var observer = new MutationObserver(function() { detectForms(); });
    observer.observe(document.body, { childList: true, subtree: true });
})();
)JS";
}
