#ifndef THEME_H
#define THEME_H
#include <string>

enum class ThemeMode { System, Light, Dark };

class ThemeManager {
public:
    static ThemeManager& instance();
    void setMode(ThemeMode mode);
    ThemeMode mode() const { return mode_; }
    void applyToWindow(NSWindow* window);
    std::string modeString() const;
    static ThemeMode fromString(const std::string& s);

private:
    ThemeManager() : mode_(ThemeMode::System) {}
    ThemeMode mode_;
};

#endif
