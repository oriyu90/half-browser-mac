#ifndef LOCALIZATION_H
#define LOCALIZATION_H
#include <string>

/// Minimal key-based localization with Japanese and English catalogs.
/// Every user-visible string in the app goes through L(key).
class Localization {
public:
    static Localization& instance();

    /// Set the UI language. Accepts "ja", "en" or "system" (follows the OS).
    void setLanguage(const std::string& mode);
    std::string currentLanguage() const { return language_; }
    std::string languageMode() const { return mode_; }

    /// Look up a key; falls back to English, then to the key itself.
    std::string get(const std::string& key) const;

private:
    Localization();
    std::string mode_ = "system";
    std::string language_ = "en";
};

/// Convenience macro.
#define L(key) Localization::instance().get(key)

#endif
