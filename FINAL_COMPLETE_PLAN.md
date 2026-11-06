# Half-Browser macOS — 最終完全実装計画書

## 0. 現状調査 (2026-11-06)

### 0.1 実装済み機能

| # | 機能 | ファイル | 状態 |
|---|---|---|---|
| 1 | Rust core (10 モジュール) | core/src/*.rs | ✅ cargo build/test OK |
| 2 | CEF 156 統合 | cefapp/src/main.mm | ✅ ビルド・動作確認 |
| 3 | Helper プロセス (GPU/Renderer/Plugin/Utility) | cefapp/ (symlink+copy) | ✅ 動作確認 |
| 4 | NSToolbar (Back/Forward/Reload/Home/Address) | main.mm | ✅ |
| 5 | メニューバー (App/Edit/View/Bookmarks) | main.mm | ✅ |
| 6 | テーマ (Light/Dark/System) | theme.h/mm | ✅ NSAppearance |
| 7 | Keychain (証明書ピン + 認証情報) | keychain_helper.h/mm | ✅ Security framework |
| 8 | TOFU SSL インタースティシャル | simple_handler.mm | ✅ NSAlert (Trust Always/Once/Cancel) |
| 9 | HTTP 認証ダイアログ | simple_handler.mm | ✅ NSAlert (username/password + Keychain) |
| 10 | ブックマーク (JSON 永続化) | bookmarks.h/mm | ✅ CRUD + JSON |
| 11 | 履歴 (JSON 永続化) | history_store.h/mm | ✅ 自動記録 |
| 12 | ウィンドウタイトル更新 | simple_handler.mm | ✅ OnTitleChange |
| 13 | ロード状態追跡 | simple_handler.mm | ✅ OnLoadingStateChange |
| 14 | Ad-hoc 署名 DMG | HalfBrowserCEF.dmg | ✅ 770MB |

### 0.2 未実装機能

| # | 機能 | 説明 | 優先度 | 工数 |
|---|---|---|---|---|
| 1 | **Rust FFI ブリッジ** | cbindgen で C header 生成、C++ から Rust 呼び出し | 高 | 2日 |
| 2 | **SwiftUI 統合** | CEF ホストを NSViewRepresentable で SwiftUI に埋め込み | 高 | 3日 |
| 3 | **バックアップ/復元** | Rust BackupCrypto + JSON I/O + パスフレーズ暗号化 | 中 | 2日 |
| 4 | **フォームログイン** | フォーム検出 + Keychain 保存 + 自動入力 | 中 | 2日 |
| 5 | **サイト権限管理** | per-origin 通知/カメラ/マイク/位置情報 | 中 | 2日 |
| 6 | **Favicon 取得** | favicon 取得 + キャッシュ + モノグラム生成 | 低 | 1日 |
| 7 | **設定画面 UI** | 7 タブ (表示/閲覧/サイト権限/通知/セキュリティ/バックアップ/アプリ) | 中 | 2日 |
| 8 | **ホーム画面** | ブックマークグリッド + 検索バー | 中 | 2日 |
| 9 | **テスト拡充** | XCTest + cargo test 拡充 | 高 | 2日 |
| 10 | **DMG 最終版** | ad-hoc 署名 + 全機能動作確認 | 高 | 1日 |

**合計見積: 17-20 日**

---

## 1. アーキテクチャ (最終形)

```
┌─────────────────────────────────────────────────────────────┐
│  SwiftUI App Shell (macOS 14+)                               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐   │
│  │ HomeView │ │ Browser  │ │ Settings │ │ Bookmarks    │   │
│  │ (Grid)   │ │ (CEF)    │ │ (Tabs)   │ │ (Grid)       │   │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └──────┬───────┘   │
│       │            │            │               │            │
│       └────────────┴────────────┴───────────────┘            │
│                         │                                    │
│  ┌──────────────────────┴──────────────────────────────┐    │
│  │  CefView (NSViewRepresentable)                        │    │
│  │  - CEF NSView を SwiftUI に埋め込み                  │    │
│  └──────────────────────┬──────────────────────────────┘    │
│                         │                                    │
│  ┌──────────────────────┴──────────────────────────────┐    │
│  │  Rust Core (half-browser-core) via FFI (cbindgen)     │    │
│  │  - UrlNormalizer, TrustPolicy, AccentMath            │    │
│  │  - BackupCrypto, HistoryRules, Codecs                 │    │
│  └─────────────────────────────────────────────────────┘    │
│                         │                                    │
│  ┌──────────────────────┴──────────────────────────────┐    │
│  │  Data Layer (JSON + Keychain)                         │    │
│  │  - Bookmarks, History, TrustedSites, Credentials      │    │
│  │  - Settings (JSON)                                    │    │
│  │  - Keychain (Security framework)                      │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 1.1 現在のアーキテクチャ (CEF standalone app)

現在のアプリは CEF standalone (Objective-C++) で動作しています。
SwiftUI 統合は Phase 3 で実施しますが、現在の CEF app は完全に機能します。

```
┌─────────────────────────────────────┐
│  CEF Standalone App (Objective-C++)  │
│  - NSWindow + NSToolbar + NSMenu    │
│  - CEF Browser (NSView)             │
│  - Keychain (Security framework)    │
│  - JSON persistence (bookmarks, history) │
│  - Theme (NSAppearance)             │
└─────────────────────────────────────┘
```

---

## 2. 実装詳細

### 2.1 Rust FFI ブリッジ (cbindgen)

#### 2.1.1 cbindgen 設定

```toml
# core/cbindgen.toml
language = "C"
include_guard = "HALF_BROWSER_CORE_H"
cpp_compat = true

[export]
include = ["TrustDecision", "AccentPalette", "Encrypted", "HistoryEntry", "AppSettings"]
```

#### 2.1.2 FFI モジュール (core/src/ffi.rs)

```rust
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[repr(C)]
pub struct TrustDecisionFFI {
    pub tag: i32, // 0=Trusted, 1=Unknown, 2=Changed
}

#[repr(C)]
pub struct AccentPaletteFFI {
    pub primary: u32,
    pub on_primary: u32,
    // ... all 12 fields
}

#[no_mangle]
pub extern "C" fn hb_trust_decide(
    host: *const c_char,
    port: i32,
    fingerprint: *const c_char,
    saved_host: *const c_char,
    saved_port: i32,
    saved_fingerprint: *const c_char,
) -> i32 {
    let host = unsafe { CStr::from_ptr(host).to_str().unwrap_or("") };
    let fingerprint = unsafe { CStr::from_ptr(fingerprint).to_str().unwrap_or("") };
    let saved_host = if saved_host.is_null() { None } else { Some(unsafe { CStr::from_ptr(saved_host).to_str().unwrap_or("") }) };
    let saved_fingerprint = if saved_fingerprint.is_null() { None } else { Some(unsafe { CStr::from_ptr(saved_fingerprint).to_str().unwrap_or("") }) };

    let decision = crate::trust_policy::TrustPolicy::decide(
        host, port, fingerprint,
        saved_host, saved_port, saved_fingerprint,
    );
    match decision {
        crate::trust_policy::TrustDecision::Trusted => 0,
        crate::trust_policy::TrustDecision::Unknown => 1,
        crate::trust_policy::TrustDecision::Changed { .. } => 2,
    }
}

#[no_mangle]
pub extern "C" fn hb_normalize_url(input: *const c_char, search_template: *const c_char) -> *mut c_char {
    let input = unsafe { CStr::from_ptr(input).to_str().unwrap_or("") };
    let template = unsafe { CStr::from_ptr(search_template).to_str().unwrap_or("") };
    match crate::url_normalizer::UrlNormalizer::to_navigable(input, template) {
        Some(url) => CString::new(url).unwrap().into_raw(),
        None => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn hb_accent_palette(hue: f32, saturation: f32, tone: f32, dark: bool, out: *mut AccentPaletteFFI) {
    let palette = crate::accent_math::AccentMath::palette(hue, saturation, tone, dark);
    unsafe {
        (*out).primary = palette.primary;
        (*out).on_primary = palette.on_primary;
        // ... all fields
    }
}

#[no_mangle]
pub extern "C" fn hb_backup_encrypt(plaintext: *const c_char, passphrase: *const c_char) -> *mut c_char {
    // Returns JSON with salt, iv, ciphertext, iterations
    // ...
}

#[no_mangle]
pub extern "C" fn hb_backup_decrypt(salt: *const c_char, iv: *const c_char, ciphertext: *const c_char, iterations: u32, passphrase: *const c_char) -> *mut c_char {
    // Returns plaintext or null
    // ...
}

#[no_mangle]
pub extern "C" fn hb_history_record(current_json: *const c_char, url: *const c_char, title: *const c_char, now: i64) -> *mut c_char {
    // Returns JSON array of history entries
    // ...
}

#[no_mangle]
pub extern "C" fn hb_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe { let _ = CString::from_raw(s); }
    }
}
```

#### 2.1.3 ビルドスクリプト

```bash
#!/bin/bash
# scripts/generate-ffi.sh
cd core
cargo build --release
cbindgen --config cbindgen.toml --crate half-browser-core --output ../cefapp/src/half_browser_core.h
cp target/release/libhalf_browser_core.a ../cefapp/
echo "FFI header and static lib generated"
```

#### 2.1.4 C++ 呼び出し

```cpp
// In C++ code:
#include "half_browser_core.h"

// Trust decision
int decision = hb_trust_decide(host.c_str(), port, fingerprint.c_str(),
                               savedHost.c_str(), savedPort, savedFingerprint.c_str());

// URL normalization
char* url = hb_normalize_url(input.c_str(), template.c_str());
if (url) {
    std::string result(url);
    hb_free_string(url);
}
```

### 2.2 SwiftUI 統合

#### 2.2.1 CefView (NSViewRepresentable)

```swift
// CefView.swift
import SwiftUI
import AppKit

struct CefView: NSViewRepresentable {
    @Binding var url: String
    let onTitleChange: (String) -> Void
    let onURLChange: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CefNSView()
        context.coordinator.view = view
        view.loadURL(url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let cefView = nsView as? CefNSView {
            if cefView.currentURL != url {
                cefView.loadURL(url)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTitleChange: onTitleChange, onURLChange: onURLChange)
    }

    class Coordinator {
        var view: CefNSView?
        var onTitleChange: (String) -> Void
        var onURLChange: (String) -> Void
        init(onTitleChange: @escaping (String) -> Void, onURLChange: @escaping (String) -> Void) {
            self.onTitleChange = onTitleChange
            self.onURLChange = onURLChange
        }
    }
}
```

#### 2.2.2 CefNSView (Objective-C++ wrapper)

```objc
// CefNSView.h
@interface CefNSView : NSView
- (void)loadURL:(NSString*)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (NSString*)currentURL;
@property (copy) void (^onTitleChange)(NSString*);
@property (copy) void (^onURLChange)(NSString*);
@end
```

```objc
// CefNSView.mm
#import "CefNSView.h"
#include "include/cef_browser.h"
#include "simple_handler.h"

@implementation CefNSView {
    CefRefPtr<CefBrowser> _browser;
}

- (void)loadURL:(NSString*)url {
    if (_browser) {
        _browser->GetMainFrame()->LoadURL([url UTF8String]);
    }
}

- (void)goBack { if (_browser) _browser->GoBack(); }
- (void)goForward { if (_browser) _browser->GoForward(); }
- (void)reload { if (_browser) _browser->Reload(); }

- (NSString*)currentURL {
    if (_browser) {
        return [NSString stringWithUTF8String:_browser->GetMainFrame()->GetURL().ToString().c_str()];
    }
    return @"";
}

@end
```

### 2.3 バックアップ/復元

#### 2.3.1 BackupService (Swift)

```swift
class BackupService {
    func export(passphrase: String?) -> Data? {
        let bookmarks = fetchAllBookmarks()
        let settings = fetchSettings()
        let trustedSites = fetchTrustedSites()

        let backup = Backup(
            version: 1,
            bookmarks: bookmarks.map { BackupBookmark(title: $0.title, url: $0.url) },
            settings: BackupSettings(themeMode: settings.themeMode, ...),
            trustedSites: trustedSites.map { BackupTrustedSite(host: $0.host, port: $0.port, fingerprint: $0.fingerprint) },
            credentials: [] // Keychain credentials are not exported
        )

        guard let json = try? JSONEncoder().encode(backup) else { return nil }

        if let passphrase = passphrase {
            // Encrypt with Rust FFI
            let cStr = json.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: CChar.self) }
            let pStr = passphrase.withCString { $0 }
            guard let encrypted = hb_backup_encrypt(cStr, pStr) else { return nil }
            // Convert encrypted struct to Data
            // ...
        }
        return json
    }

    func `import`(data: Data, passphrase: String?, mode: ImportMode) {
        var jsonData = data
        if let passphrase = passphrase {
            // Decrypt with Rust FFI
            // ...
        }
        guard let backup = try? JSONDecoder().decode(Backup.self, from: jsonData) else { return }
        // Merge or replace based on mode
        switch mode {
        case .merge:
            for bm in backup.bookmarks {
                if !bookmarks.contains(where: { $0.url == bm.url }) {
                    addBookmark(bm)
                }
            }
        case .replace:
            deleteAllBookmarks()
            for bm in backup.bookmarks {
                addBookmark(bm)
            }
        }
    }
}
```

### 2.4 フォームログイン

#### 2.4.1 フォーム検出 (JavaScript 注入)

```javascript
// Injected into page via CEF
(function() {
    // Find login forms
    var forms = document.querySelectorAll('form');
    forms.forEach(function(form) {
        var inputs = form.querySelectorAll('input');
        var hasPassword = false;
        var usernameField = null;
        inputs.forEach(function(input) {
            if (input.type === 'password') hasPassword = true;
            if (input.type === 'text' || input.type === 'email') usernameField = input;
        });
        if (hasPassword && usernameField) {
            // Notify native via CEF message
            // window.cefQuery({request: 'formLogin:' + usernameField.value})
        }
    });
})();
```

#### 2.4.2 CEF メッセージハンドリング

```cpp
// In CefClient::OnProcessMessageReceived
bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefProcessId source_process, CefRefPtr<CefProcessMessage> message) {
    std::string name = message->GetName().ToString();
    if (name == "formLogin") {
        CefRefPtr<CefListValue> args = message->GetArgumentList();
        std::string username = args->GetString(0).ToString();
        std::string password = args->GetString(1).ToString();
        // Save to Keychain if https
        // ...
    }
    return false;
}
```

### 2.5 サイト権限管理

#### 2.5.1 per-origin 権限

```swift
@Model
class SitePermission {
    var origin: String
    var kind: String // "notification", "camera", "microphone", "location"
    var granted: Bool
    var askedAt: Date
}
```

#### 2.5.2 CEF 連携

```cpp
// In CefRequestHandler::OnPermissionRequest
bool OnPermissionRequest(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& requesting_origin, uint32_t requested_permissions, CefRefPtr<CefPermissionCallback> callback) {
    // Check stored permission
    // If not found, show dialog
    // Save decision
    return true;
}
```

---

## 3. 実装順序 (詳細)

### Sprint 1 (2-3日): Rust FFI + SwiftUI 基盤
1. cbindgen 設定 + ffi.rs 実装
2. Swift bridging header + RustCore wrapper
3. CefView (NSViewRepresentable) 作成
4. SwiftUI メインウィンドウ + ツールバー
5. CEF ブラウザを SwiftUI に埋め込み

### Sprint 2 (2-3日): ブックマーク + ホーム画面
1. SwiftData Bookmark モデル
2. HomeView (LazyVGrid + BookmarkTile)
3. ブックマーク CRUD (追加/編集/削除)
4. Favicon 取得 + キャッシュ
5. ブックマークモード (コンパクトバー)

### Sprint 3 (2-3日): テーマ + 設定
1. ThemeManager (ライト/ダーク/システム)
2. アクセントカラー (Rust AccentMath FFI)
3. vibrancy / materials
4. SettingsView (7 タブ)
5. サイト権限管理

### Sprint 4 (2-3日): 履歴 + フォームログイン + バックアップ
1. HistoryEntry モデル + SwiftData
2. HistoryRules (Rust) FFI 呼び出し
3. フォームログイン検出 + Keychain 保存
4. BackupService (エクスポート/インポート)
5. BackupCrypto FFI 呼び出し

### Sprint 5 (1-2日): テスト + DMG
1. XCTest スイート (UI + データ)
2. cargo test (Rust core)
3. ad-hoc 署名
4. DMG 作成
5. デバッグ・動作確認

---

## 4. テスト計画

### 4.1 Rust core テスト
- url_normalizer: to_navigable, canonical_for_compare, search_url
- trust_policy: decide (Trusted/Unknown/Changed), normalizeFingerprint
- accent_math: palette, hsl, luminance, contrastRatio, readableOn
- backup_crypto: encrypt/decrypt round-trip, wrong passphrase
- history: record, sanitize, merge window
- codecs: sanitize, encode/decode

### 4.2 Swift テスト (XCTest)
- Bookmark CRUD
- History record/sanitize
- Settings sanitize
- Theme switching
- Backup export/import round-trip

### 4.3 統合テスト
- CEF ブラウザ起動・ページ表示
- 自己署名 HTTPS インタースティシャル
- HTTP 認証ダイアログ
- ブックマーク追加 → ホーム画面表示
- テーマ切り替え → UI 反映

### 4.4 デバッグ
- メモリリーク検出 (Instruments)
- パフォーマンス (起動時間、スクロール FPS)
- アクセシビリティ (VoiceOver, キーボードナビゲーション)

---

## 5. DMG 作成・配布

### 5.1 ビルド手順
```bash
# 1. Rust core build
cd core && cargo build --release && cbindgen ...

# 2. Xcode build
xcodebuild -project app/HalfBrowserMac.xcodeproj -scheme HalfBrowserMac -configuration Release

# 3. Ad-hoc sign
codesign --force --deep --sign - HalfBrowserMac.app

# 4. DMG create
hdiutil create -volname "Half-Browser" -srcfolder HalfBrowserMac.app -format UDZO HalfBrowserMac.dmg
```

### 5.2 検証
- DMG マウント → アプリ起動 → クラッシュなし
- Gatekeeper: ad-hoc のため rejected (期待動作)
- 全機能動作確認

---

## 6. リスクと対策

| リスク | 影響 | 対策 |
|---|---|---|
| CEF + SwiftUI 統合の複雑さ | 高 | 段階的実装、まず CEF NSView を SwiftUI に埋め込む |
| Rust FFI の型安全性 | 中 | cbindgen で自動生成、uniffi も検討 |
| SwiftData の macOS 14+ 制限 | 中 | macOS 14+ を最小要件に設定 |
| Keychain のスレッド安全性 | 中 | メインスレッドで Keychain 操作 |
| CEF helper の配布 | 高 | helper を .app バンドルに含める |
| DMG サイズ (770MB+) | 中 | CEF framework の最適化、strip |

---

## 7. 完了条件

- [ ] 全 Phase 3 タスクが実装完了
- [ ] Rust core テスト全パス (cargo test)
- [ ] Swift テスト全パス (XCTest)
- [ ] CEF ブラウザが正常にページを表示
- [ ] 自己署名 HTTPS インタースティシャル動作
- [ ] HTTP 認証ダイアログ + Keychain 保存/自動入力動作
- [ ] ブックマーク CRUD + ホーム画面動作
- [ ] テーマ切り替え動作
- [ ] 履歴記録・表示動作
- [ ] バックアップ/復元動作
- [ ] 設定画面 7 タブ動作
- [ ] Ad-hoc 署名 DMG 作成完了
- [ ] デバッグ: DMG マウント → 起動 → 全機能動作確認 → クラッシュなし

---

## 8. 実装優先順位 (Phase 3)

### 優先度 1 (必須): Rust FFI + SwiftUI 基盤
- cbindgen 設定 + ffi.rs 実装
- Swift bridging header + RustCore wrapper
- CefView (NSViewRepresentable) 作成
- SwiftUI メインウィンドウ + ツールバー
- CEF ブラウザを SwiftUI に埋め込み

### 優先度 2 (重要): ブックマーク + ホーム画面
- SwiftData Bookmark モデル
- HomeView (LazyVGrid + BookmarkTile)
- ブックマーク CRUD (追加/編集/削除)
- Favicon 取得 + キャッシュ

### 優先度 3 (重要): テーマ + 設定
- ThemeManager (ライト/ダーク/システム)
- アクセントカラー (Rust AccentMath FFI)
- SettingsView (7 タブ)
- サイト権限管理

### 優先度 4 (推奨): 履歴 + フォームログイン + バックアップ
- HistoryEntry モデル + SwiftData
- HistoryRules (Rust) FFI 呼び出し
- フォームログイン検出 + Keychain 保存
- BackupService (エクスポート/インポート)
- BackupCrypto FFI 呼び出し

### 優先度 5 (最終): テスト + DMG
- XCTest スイート (UI + データ)
- cargo test (Rust core)
- ad-hoc 署名
- DMG 作成
- デバッグ・動作確認

---

*文書終わり — Phase 3 完全実装計画*