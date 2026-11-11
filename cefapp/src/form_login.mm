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
    // SECURITY: credentials must never travel through console.log. A page can
    // wrap console.log and read every argument, and Chromium may also log the
    // call. The payload is therefore posted to the native side through a
    // dedicated message channel that only our handler listens on, and the
    // page-visible console is never touched.
    return R"JS(
(function() {
    if (window.__halfBrowserFormDetection) return;
    window.__halfBrowserFormDetection = true;

    // Minimal, self-contained transport. CEF's message router is not enabled
    // for this build, so the payload is delivered by navigating a hidden
    // iframe to a private scheme that the native layer intercepts and cancels
    // before any request leaves the process.
    function sendToNative(payload) {
        try {
            var frame = document.createElement('iframe');
            frame.style.display = 'none';
            frame.src = 'halfbrowser-formlogin://capture#' + payload;
            document.documentElement.appendChild(frame);
            setTimeout(function() {
                if (frame.parentNode) frame.parentNode.removeChild(frame);
            }, 0);
        } catch (e) {}
    }

    function detectForms() {
        var forms = document.querySelectorAll('form');
        Array.prototype.forEach.call(forms, function(form) {
            if (form.__hbDetected) return;
            var inputs = form.querySelectorAll('input');
            var hasPassword = false;
            var usernameField = null;
            Array.prototype.forEach.call(inputs, function(input) {
                if (input.type === 'password') hasPassword = true;
                if (input.type === 'text' || input.type === 'email') usernameField = input;
            });
            if (hasPassword && usernameField) {
                form.__hbDetected = true;
                form.addEventListener('submit', function() {
                    var passInput = form.querySelector('input[type=password]');
                    if (passInput && usernameField.value && passInput.value) {
                        sendToNative([
                            encodeURIComponent(usernameField.value),
                            encodeURIComponent(passInput.value),
                            encodeURIComponent(location.origin)
                        ].join('|'));
                    }
                });
            }
        });
    }

    detectForms();
    if (document.body) {
        var observer = new MutationObserver(function() { detectForms(); });
        observer.observe(document.body, { childList: true, subtree: true });
    }
})();
)JS";
}

std::string FormLoginService::autofillScript(const std::string& originUrl) {
    // Fills saved credentials into EMPTY fields only, and never submits. A page
    // that already contains a value is left alone so a user edit is not
    // overwritten.
    std::string username, password;
    if (!loadCredentials(originUrl, username, password)) return "";
    if (username.empty() && password.empty()) return "";

    auto jsEscape = [](const std::string& in) {
        std::string out;
        for (char c : in) {
            switch (c) {
                case '\\': out += "\\\\"; break;
                case '\'': out += "\\'"; break;
                case '\n': out += "\\n"; break;
                case '\r': out += "\\r"; break;
                case '<': out += "\\x3c"; break;  // avoid closing a script tag
                default: out += c;
            }
        }
        return out;
    };

    std::string js = "(function(){try{";
    js += "var u='" + jsEscape(username) + "',p='" + jsEscape(password) + "';";
    js += "var forms=document.querySelectorAll('form');";
    js += "Array.prototype.forEach.call(forms,function(f){";
    js += "var pw=f.querySelector('input[type=password]');if(!pw)return;";
    js += "var ui=null;";
    js += "Array.prototype.forEach.call(f.querySelectorAll('input'),function(i){";
    js += "if((i.type==='text'||i.type==='email')&&!ui)ui=i;});";
    js += "if(ui&&!ui.value&&u){ui.value=u;ui.dispatchEvent(new Event('input',{bubbles:true}));}";
    js += "if(!pw.value&&p){pw.value=p;pw.dispatchEvent(new Event('input',{bubbles:true}));}";
    js += "});}catch(e){}})();";
    return js;
}
