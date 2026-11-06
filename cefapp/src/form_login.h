#ifndef FORM_LOGIN_H
#define FORM_LOGIN_H
#include <string>

class FormLoginService {
public:
    // Called when a login form is detected. Saves credentials if https.
    static bool saveCredentials(const std::string& originUrl, const std::string& username, const std::string& password);
    // Returns true if credentials were found and auto-filled.
    static bool loadCredentials(const std::string& originUrl, std::string& username, std::string& password);
    // Returns the JavaScript to inject for form detection.
    static std::string detectionScript();
};
#endif
