#import <Foundation/Foundation.h>
#include "localization.h"
#include <map>

Localization& Localization::instance() {
    static Localization inst;
    return inst;
}

Localization::Localization() {
    // Follow the OS language by default.
    NSString* preferred = [[NSLocale preferredLanguages] firstObject];
    language_ = ([preferred hasPrefix:@"ja"]) ? "ja" : "en";
    mode_ = "system";
}

void Localization::setLanguage(const std::string& mode) {
    mode_ = mode;
    if (mode == "ja") {
        language_ = "ja";
    } else if (mode == "en") {
        language_ = "en";
    } else {
        NSString* preferred = [[NSLocale preferredLanguages] firstObject];
        language_ = ([preferred hasPrefix:@"ja"]) ? "ja" : "en";
    }
}

namespace {

// English catalog.
const std::map<std::string, std::string>& englishCatalog() {
    static const std::map<std::string, std::string> c = {
        // App / menus
        {"app.name", "Half-Browser"},
        {"menu.about", "About Half-Browser"},
        {"menu.settings", "Settings…"},
        {"menu.quit", "Quit Half-Browser"},
        {"menu.edit", "Edit"},
        {"menu.view", "View"},
        {"menu.bookmarks", "Bookmarks"},
        {"menu.window", "Window"},
        {"menu.help", "Help"},
        {"menu.reload", "Reload"},
        {"menu.theme", "Theme"},
        {"menu.theme.light", "Light"},
        {"menu.theme.dark", "Dark"},
        {"menu.theme.system", "System"},
        {"menu.bookmark_page", "Bookmark This Page"},
        {"menu.show_bookmarks", "Show Bookmarks"},
        {"menu.home", "Home"},
        {"menu.export_backup", "Export Backup…"},
        {"menu.import_backup", "Import Backup…"},
        {"menu.history", "History…"},
        {"menu.clear_history", "Clear History"},
        {"menu.find", "Find…"},
        {"menu.zoom_in", "Zoom In"},
        {"menu.zoom_out", "Zoom Out"},
        {"menu.actual_size", "Actual Size"},

        // Toolbar
        {"toolbar.back", "Back"},
        {"toolbar.forward", "Forward"},
        {"toolbar.reload", "Reload"},
        {"toolbar.home", "Home"},
        {"toolbar.address_placeholder", "Search or enter URL"},

        // SSL interstitial
        {"ssl.title", "Security Warning"},
        {"ssl.unknown_body", "The certificate for %s is not trusted.\n\nSubject: %s\nIssuer: %s\nSHA-256: %s\nError code: %d\n\nDo you want to trust this site?"},
        {"ssl.changed_title", "Certificate Changed!"},
        {"ssl.changed_body", "The certificate for %s has changed.\n\nNew SHA-256: %s\nPinned SHA-256: %s\n\nThis could indicate a security issue.\n\nDo you want to proceed?"},
        {"ssl.trust_always", "Trust Always"},
        {"ssl.proceed_once", "Proceed Once"},
        {"ssl.proceed_anyway", "Proceed Anyway"},
        {"ssl.cancel", "Cancel"},
        {"ssl.unavailable", "(unavailable)"},

        // HTTP auth
        {"auth.title", "Authentication Required"},
        {"auth.body", "Enter credentials for %s:%d\nRealm: %s"},
        {"auth.username", "Username"},
        {"auth.password", "Password"},
        {"auth.ok", "OK"},
        {"auth.cancel", "Cancel"},

        // Permissions
        {"perm.title", "Allow Permission?"},
        {"perm.body", "The site %s wants to use: %s"},
        {"perm.media_title", "Allow Access?"},
        {"perm.media_body", "%s wants to use your %s."},
        {"perm.allow", "Allow"},
        {"perm.allow_once", "Allow Once"},
        {"perm.block", "Block"},
        {"perm.kind.camera", "camera"},
        {"perm.kind.microphone", "microphone"},
        {"perm.kind.notification", "notifications"},
        {"perm.kind.location", "location"},
        {"perm.kind.clipboard", "clipboard"},
        {"perm.kind.unknown", "unknown permission"},

        // Bookmarks
        {"bookmark.added_title", "Bookmark Added"},
        {"bookmark.added_body", "Bookmarked: %s"},
        {"bookmark.none", "No bookmarks"},
        {"bookmark.edit_title", "Edit Bookmark"},
        {"bookmark.field_title", "Title:"},
        {"bookmark.field_url", "URL:"},
        {"bookmark.save", "Save"},
        {"bookmark.delete", "Delete"},
        {"bookmark.cancel", "Cancel"},
        {"bookmark.ok", "OK"},

        // Form login
        {"formlogin.title", "Save Sign-in?"},
        {"formlogin.body", "Remember the sign-in for %s?\n\nUser: %s"},
        {"formlogin.save", "Save"},
        {"formlogin.not_now", "Not Now"},

        // Backup
        {"backup.export_title", "Export Backup"},
        {"backup.export_body", "Enter a passphrase to encrypt the backup (optional):"},
        {"backup.export_button", "Export"},
        {"backup.export_ok", "Backup exported successfully"},
        {"backup.import_title", "Import Backup"},
        {"backup.import_body", "Enter the passphrase (leave empty if not encrypted):"},
        {"backup.import_button", "Import"},
        {"backup.import_ok", "Backup imported successfully"},
        {"backup.failed", "Backup operation failed"},
        {"backup.passphrase_placeholder", "Passphrase (optional)"},

        // Settings
        {"settings.title", "Settings"},
        {"settings.tab.general", "General"},
        {"settings.tab.appearance", "Appearance"},
        {"settings.tab.permissions", "Site Permissions"},
        {"settings.tab.security", "Security"},
        {"settings.tab.backup", "Backup"},
        {"settings.tab.about", "About"},
        {"settings.ui_scale", "UI Scale:"},
        {"settings.font_scale", "Text Scale:"},
        {"settings.grid_columns", "Grid Columns (0 = auto):"},
        {"settings.language", "Language:"},
        {"settings.language.system", "System"},
        {"settings.language.ja", "日本語"},
        {"settings.language.en", "English"},
        {"settings.search_engine", "Search Engine:"},
        {"settings.theme", "Theme:"},
        {"settings.accent_hue", "Accent Hue:"},
        {"settings.accent_saturation", "Accent Saturation:"},
        {"settings.accent_tone", "Accent Brightness:"},
        {"settings.form_autofill", "Fill saved sign-ins on HTTPS pages"},
        {"settings.fetch_icons", "Download site icons for bookmarks"},
        {"settings.permissions_body", "Site permissions are stored per origin in:"},
        {"settings.reset_permissions", "Reset All Permissions"},
        {"settings.reset_permissions_confirm", "This will clear all site permissions. Continue?"},
        {"settings.security_body", "Certificate pins and credentials are stored in the macOS Keychain."},
        {"settings.clear_certs", "Clear All Trusted Certificates"},
        {"settings.clear_certs_confirm", "This will remove all certificate pins. Continue?"},
        {"settings.reset", "Reset"},
        {"settings.clear", "Clear"},
        {"settings.about_title", "Half-Browser for macOS"},
        {"settings.about_version", "Version %s (CEF %s)"},
        {"settings.about_body", "A small Chromium browser with trusted local HTTPS and encrypted HTTP auth."},
        {"settings.history_title", "History"},
        {"settings.history_clear", "Clear History"},
        {"settings.history_empty", "No history yet."},
        {"settings.close", "Close"},
    };
    return c;
}

// Japanese catalog (must cover every English key).
const std::map<std::string, std::string>& japaneseCatalog() {
    static const std::map<std::string, std::string> c = {
        {"app.name", "ハーフブラウザ"},
        {"menu.about", "Half-Browser について"},
        {"menu.settings", "設定…"},
        {"menu.quit", "Half-Browser を終了"},
        {"menu.edit", "編集"},
        {"menu.view", "表示"},
        {"menu.bookmarks", "ブックマーク"},
        {"menu.window", "ウインドウ"},
        {"menu.help", "ヘルプ"},
        {"menu.reload", "再読み込み"},
        {"menu.theme", "テーマ"},
        {"menu.theme.light", "ライト"},
        {"menu.theme.dark", "ダーク"},
        {"menu.theme.system", "システム"},
        {"menu.bookmark_page", "このページをブックマーク"},
        {"menu.show_bookmarks", "ブックマークを表示"},
        {"menu.home", "ホーム"},
        {"menu.export_backup", "バックアップを書き出す…"},
        {"menu.import_backup", "バックアップを読み込む…"},
        {"menu.history", "閲覧履歴…"},
        {"menu.clear_history", "閲覧履歴を消去"},
        {"menu.find", "検索…"},
        {"menu.zoom_in", "拡大"},
        {"menu.zoom_out", "縮小"},
        {"menu.actual_size", "実際のサイズ"},

        {"toolbar.back", "戻る"},
        {"toolbar.forward", "進む"},
        {"toolbar.reload", "再読み込み"},
        {"toolbar.home", "ホーム"},
        {"toolbar.address_placeholder", "URL を入力、または検索"},

        {"ssl.title", "セキュリティ警告"},
        {"ssl.unknown_body", "%s の証明書は信頼されていません。\n\nSubject: %s\n発行者: %s\nSHA-256: %s\nエラーコード: %d\n\nこのサイトを信頼しますか？"},
        {"ssl.changed_title", "証明書が変更されました"},
        {"ssl.changed_body", "%s の証明書が変更されました。\n\n新しい SHA-256: %s\n保存済み SHA-256: %s\n\nセキュリティ上の問題の可能性があります。\n\n続行しますか？"},
        {"ssl.trust_always", "常に信頼"},
        {"ssl.proceed_once", "今回だけ続行"},
        {"ssl.proceed_anyway", "それでも続行"},
        {"ssl.cancel", "キャンセル"},
        {"ssl.unavailable", "（取得できません）"},

        {"auth.title", "認証が必要です"},
        {"auth.body", "%s:%d の認証情報を入力してください\nRealm: %s"},
        {"auth.username", "ユーザー名"},
        {"auth.password", "パスワード"},
        {"auth.ok", "OK"},
        {"auth.cancel", "キャンセル"},

        {"perm.title", "権限を許可しますか？"},
        {"perm.body", "サイト %s が %s の使用を求めています"},
        {"perm.media_title", "アクセスを許可しますか？"},
        {"perm.media_body", "%s が %s の使用を求めています。"},
        {"perm.allow", "許可"},
        {"perm.allow_once", "今回だけ許可"},
        {"perm.block", "ブロック"},
        {"perm.kind.camera", "カメラ"},
        {"perm.kind.microphone", "マイク"},
        {"perm.kind.notification", "通知"},
        {"perm.kind.location", "位置情報"},
        {"perm.kind.clipboard", "クリップボード"},
        {"perm.kind.unknown", "不明な権限"},

        {"bookmark.added_title", "ブックマークに追加しました"},
        {"bookmark.added_body", "追加: %s"},
        {"bookmark.none", "ブックマークはありません"},
        {"bookmark.edit_title", "ブックマークを編集"},
        {"bookmark.field_title", "タイトル:"},
        {"bookmark.field_url", "URL:"},
        {"bookmark.save", "保存"},
        {"bookmark.delete", "削除"},
        {"bookmark.cancel", "キャンセル"},
        {"bookmark.ok", "OK"},

        {"formlogin.title", "サインインを保存しますか？"},
        {"formlogin.body", "%s のサインインを保存しますか？\n\nユーザー: %s"},
        {"formlogin.save", "保存"},
        {"formlogin.not_now", "今はしない"},

        {"backup.export_title", "バックアップを書き出す"},
        {"backup.export_body", "バックアップを暗号化するパスフレーズを入力してください（任意）:"},
        {"backup.export_button", "書き出す"},
        {"backup.export_ok", "バックアップを書き出しました"},
        {"backup.import_title", "バックアップを読み込む"},
        {"backup.import_body", "パスフレーズを入力してください（暗号化なしなら空欄）:"},
        {"backup.import_button", "読み込む"},
        {"backup.import_ok", "バックアップを読み込みました"},
        {"backup.failed", "バックアップの処理に失敗しました"},
        {"backup.passphrase_placeholder", "パスフレーズ（任意）"},

        {"settings.title", "設定"},
        {"settings.tab.general", "一般"},
        {"settings.tab.appearance", "外観"},
        {"settings.tab.permissions", "サイトの権限"},
        {"settings.tab.security", "セキュリティ"},
        {"settings.tab.backup", "バックアップ"},
        {"settings.tab.about", "このアプリ"},
        {"settings.ui_scale", "UI スケール:"},
        {"settings.font_scale", "文字スケール:"},
        {"settings.grid_columns", "グリッド列数（0 = 自動）:"},
        {"settings.language", "言語:"},
        {"settings.language.system", "システム"},
        {"settings.language.ja", "日本語"},
        {"settings.language.en", "English"},
        {"settings.search_engine", "検索エンジン:"},
        {"settings.theme", "テーマ:"},
        {"settings.accent_hue", "アクセントの色相:"},
        {"settings.accent_saturation", "アクセントの彩度:"},
        {"settings.accent_tone", "アクセントの明るさ:"},
        {"settings.form_autofill", "保存したサインインを HTTPS ページで自動入力"},
        {"settings.fetch_icons", "ブックマーク作成時にサイトアイコンを取得"},
        {"settings.permissions_body", "サイトの権限は origin ごとに次へ保存されます:"},
        {"settings.reset_permissions", "すべての権限をリセット"},
        {"settings.reset_permissions_confirm", "すべてのサイト権限を消去します。続行しますか？"},
        {"settings.security_body", "証明書のピンと認証情報は macOS のキーチェーンに保存されます。"},
        {"settings.clear_certs", "信頼した証明書をすべて消去"},
        {"settings.clear_certs_confirm", "すべての証明書ピンを削除します。続行しますか？"},
        {"settings.reset", "リセット"},
        {"settings.clear", "消去"},
        {"settings.about_title", "Half-Browser for macOS"},
        {"settings.about_version", "バージョン %s（CEF %s）"},
        {"settings.about_body", "自己署名 HTTPS と暗号化された HTTP 認証に対応した小さな Chromium ブラウザです。"},
        {"settings.history_title", "閲覧履歴"},
        {"settings.history_clear", "閲覧履歴を消去"},
        {"settings.history_empty", "閲覧履歴はまだありません。"},
        {"settings.close", "閉じる"},
    };
    return c;
}

}  // namespace

std::string Localization::get(const std::string& key) const {
    if (language_ == "ja") {
        const auto& ja = japaneseCatalog();
        auto it = ja.find(key);
        if (it != ja.end()) return it->second;
    }
    const auto& en = englishCatalog();
    auto it = en.find(key);
    if (it != en.end()) return it->second;
    return key;
}
