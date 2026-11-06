#import <Cocoa/Cocoa.h>
#include "theme.h"

ThemeManager& ThemeManager::instance() {
    static ThemeManager inst;
    return inst;
}

void ThemeManager::setMode(ThemeMode mode) {
    mode_ = mode;
}

void ThemeManager::applyToWindow(NSWindow* window) {
    switch (mode_) {
        case ThemeMode::Light:
            [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
            [NSApp setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
            break;
        case ThemeMode::Dark:
            [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
            [NSApp setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
            break;
        case ThemeMode::System:
            [window setAppearance:nil];
            [NSApp setAppearance:nil];
            break;
    }
}

std::string ThemeManager::modeString() const {
    switch (mode_) {
        case ThemeMode::Light: return "light";
        case ThemeMode::Dark: return "dark";
        case ThemeMode::System: return "system";
    }
    return "system";
}

ThemeMode ThemeManager::fromString(const std::string& s) {
    if (s == "light") return ThemeMode::Light;
    if (s == "dark") return ThemeMode::Dark;
    return ThemeMode::System;
}