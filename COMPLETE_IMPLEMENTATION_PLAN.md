# Half-Browser macOS — 完全実装計画書 (Phase 3: 全残タスク完了)

## 0. 概要

本計画書は、Half-Browser macOS の**全残タスク**を完了させるための完全な実装計画である。
Phase 1 (CEF 統合) と Phase 2 (Keychain + TOFU + HTTP 認証) は完了済み。
本計画では Phase 3 として残りの全機能を実装し、完全なアプリを完成させる。

---

## 1. 残タスク一覧と優先度

| # | タスク | 説明 | 優先度 | 工数見積 |
|---|---|---|---|---|
| 1 | **Rust FFI ブリッジ** | cbindgen で C header 生成、C++/Swift から Rust core を呼び出し | 高 | 2-3日 |
| 2 | **SwiftUI 統合** | CEF ホストを NSViewRepresentable で SwiftUI に埋め込み、SwiftUI で UI 全体を構築 | 高 | 3-5日 |
| 3 | **ブックマーク + ホーム画面** | CRUD + JSON 永続化 + グリッド UI + favicon | 高 | 2-3日 |
| 4 | **テーマ** | ライト/ダーク/システム + アクセントカラー (Rust AccentMath) | 中 | 1-2日 |
| 5 | **履歴 + フォームログイン** | Rust HistoryRules + Keychain + 自動入力 | 中 | 2-3日 |
| 6 | **バックアップ/復元** | Rust BackupCrypto + JSON I/O + パスフレーズ暗号化 | 中 | 1-2日 |
| 7 | **設定画面** | 7 タブ (表示/閲覧/サイト権限/通知/セキュリティ/バックアップ/アプリ) | 中 | 2-3日 |
| 8 | **サイト権限管理** | 通知/カメラ/マイク/位置情報の per-origin 管理 | 低 | 1-2日 |
| 9 | **テスト + DMG** | XCTest + cargo test + ad-hoc 署名 DMG | 高 | 1-2日 |

**合計見積: 15-25 日**

---

## 2. アーキテクチャ (最終形)

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
│  │  - CefBrowser, CefClient, handlers                   │    │
│  └──────────────────────┬──────────────────────────────┘    │
│                         │                                    │
│  ┌──────────────────────┴──────────────────────────────┐    │
│  │  Rust Core (half-browser-core) via FFI (cbindgen)     │    │
│  │  - UrlNormalizer, TrustPolicy, AccentMath            │    │
│  │  - BackupCrypto, HistoryRules, Codecs                 │    │
│  │  - GridPolicy, AuthKey, CredentialKey                │    │
│  └─────────────────────────────────────────────────────┘    │
│                         │                                    │
│  ┌──────────────────────┴──────────────────────────────┐    │
│  │  Data Layer (SwiftData / SQLite + Keychain)           │    │
│  │  - Bookmarks, History, TrustedSites, Credentials      │    │
│  │  - Settings (UserDefaults + SwiftData)                │    │
│  │  - Keychain (Security framework)                      │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 2.1 技術スタック (最終)

| 層 | 技術 | 理由 |
|---|---|---|
| UI | SwiftUI (macOS 14+) | ネイティブ HIG、宣言的 UI |
| ブラウザエンジン | CEF 156 (Chromium 120) | Chromium 互換、証明書/認証コールバック |
| コアロジック | Rust (half-browser-core) | Android core/ の移植、FFI で Swift から呼び出し |
| データ永続化 | SwiftData + Keychain | macOS 14+ ネイティブ、型安全 |
| ビルド | Xcode + Cargo + CMake | ネイティブツールチェーン |
| テスト | XCTest + cargo test | Android の JVM テスト相当 |

---

## 3. プロジェクト構成 (最終)

```
half-browser-mac/
├── COMPLETE_IMPLEMENTATION_PLAN.md
├── PLAN_MAC.md
├── IMPLEMENTATION_PLAN.md
├── IMPLEMENTATION_PLAN_V2.md
├── README.md
├── core/                          # Rust crate (half-browser-core)
│   ├── Cargo.toml
│   ├── cbindgen.toml              # FFI header generation
│   └── src/
│       ├── lib.rs
│       ├── url_normalizer.rs
│       ├── trust_policy.rs
│       ├── accent_math.rs
│       ├── backup_crypto.rs
│       ├── history.rs
│       ├── codecs.rs
│       ├── grid_policy.rs
│       ├── auth_key.rs
│       ├── credential_key.rs
│       ├── models.rs
│       └── ffi.rs                 # cbindgen exports
├── app/                           # Xcode project (SwiftUI + CEF)
│   ├── HalfBrowserMac.xcodeproj
│   └── HalfBrowserMac/
│       ├── HalfBrowserMacApp.swift
│       ├── ContentView.swift
│       ├── CefView.swift           # NSViewRepresentable
│       ├── Browser/                # Browser view model + toolbar
│       ├── Home/                   # Bookmarks grid
│       ├── Settings/               # Settings tabs
│       ├── Theme/                  # Colors, materials
│       ├── Models/                 # SwiftData models
│       ├── Services/               # Keychain, Backup, etc.
│       └── Resources/
├── cef/                           # CEF SDK (gitignored)
├── cefapp/                        # CEF standalone app (legacy, for testing)
├── scripts/
│   ├── build-core.sh
│   ├── fetch-cef.sh
│   └── generate-ffi.sh
└── tests/
    ├── core-tests/                # Rust tests
    └── app-tests/                 # XCTest
```

---

## 4. Phase 3 実装詳細

### 4.1 Phase 3.1: Rust FFI ブリッジ (cbindgen)

#### 4.1.1 cbindgen 設定

```toml
# core/cbindgen.toml
language = "C"
include_guard = "HALF_BROWSER_CORE_H"
include_version = true
cpp_compat = true

[export]
include = ["TrustDecision", "AccentPalette", "Encrypted", "HistoryEntry"]
```

#### 4.1.2 FFI モジュール (core/src/ffi.rs)

```rust
use crate::trust_policy::TrustPolicy;
use crate::accent_math::AccentMath;
use crate::backup_crypto::BackupCrypto;
use crate::history::HistoryRules;
use crate::url_normalizer::UrlNormalizer;

#[no_mangle]
pub extern "C" fn hb_trust_decide(
    host: *const c_char,
    port: i32,
    fingerprint: *const c_char,
    saved_host: *const c_char,
    saved_port: i32,
    saved_fingerprint: *const c_char,
) -> i32 { // 0=Trusted, 1=Unknown, 2=Changed
    // ... calls TrustPolicy::decide
}

#[no_mangle]
pub extern "C" fn hb_normalize_url(input: *const c_char, search_template: *const c_char) -> *mut c_char {
    // ... calls UrlNormalizer::to_navigable
}

#[no_mangle]
pub extern "C" fn hb_accent_palette(hue: f32, saturation: f32, tone: f32, dark: bool, out: *mut AccentPaletteFFI) {
    // ... calls AccentMath::palette
}

#[no_mangle]
pub extern "C" fn hb_backup_encrypt(plaintext: *const c_char, passphrase: *const c_char) -> *mut EncryptedFFI {
    // ... calls BackupCrypto::encrypt
}

#[no_mangle]
pub extern "C" fn hb_backup_decrypt(salt: *const c_char, iv: *const c_char, ciphertext: *const c_char, iterations: u32, passphrase: *const c_char) -> *mut c_char {
    // ... calls BackupCrypto::decrypt
}

#[no_mangle]
pub extern "C" fn hb_history_record(current_json: *const c_char, url: *const c_char, title: *const c_char, now: i64) -> *mut c_char {
    // ... calls HistoryRules::record, returns JSON
}

#[no_mangle]
pub extern "C" fn hb_free_string(s: *mut c_char) {
    if !s.is_null() { unsafe { drop(Box::from_raw(s)) } }
}
```

#### 4.1.3 ビルドスクリプト (scripts/generate-ffi.sh)

```bash
#!/bin/bash
cd core
cargo build --release
cbindgen --config cbindgen.toml --crate half-browser-core --output ../app/HalfBrowserMac/half_browser_core.h
# Copy static lib
cp target/release/libhalf_browser_core.a ../app/
```

#### 4.1.4 Swift バインディング

```swift
// In Swift, use the generated header via bridging header
// HalfBrowserMac-Bridging-Header.h:
// #include "half_browser_core.h"

// Swift wrapper:
class RustCore {
    static func trustDecide(host: String, port: Int, fingerprint: String, savedHost: String?, savedPort: Int, savedFingerprint: String?) -> Int {
        return Int(hb_trust_decide(host, Int32(port), fingerprint, savedHost, Int32(savedPort), savedFingerprint))
    }
    // ...
}
```

### 4.2 Phase 3.2: SwiftUI 統合

#### 4.2.1 CefView (NSViewRepresentable)

```swift
struct CefView: NSViewRepresentable {
    @Binding var url: String
    @Binding var title: String
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    func makeNSView(context: Context) -> NSView {
        // Create CEF browser view
        let view = CefBrowserView()
        context.coordinator.browser = view.createBrowser(url: url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.lastURL != url {
            context.coordinator.browser?.loadURL(url)
            context.coordinator.lastURL = url
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var browser: CefBrowserWrapper?
        var lastURL: String = ""
    }
}
```

#### 4.2.2 CEF NSView Wrapper (Objective-C++)

```objc
// CefBrowserView.h/.mm
@interface CefBrowserView : NSView
- (CefRefPtr<CefBrowser>)createBrowserWithURL:(NSString*)url;
- (void)loadURL:(NSString*)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
@end
```

#### 4.2.3 メインウィンドウ (SwiftUI)

```swift
@main
struct HalfBrowserMacApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
```

### 4.3 Phase 3.3: ブックマーク + ホーム画面

#### 4.3.1 SwiftData モデル

```swift
@Model
class Bookmark {
    var id: UUID
    var title: String
    var url: String
    var monogram: String
    var monogramColor: Int
    var createdAt: Date

    init(title: String, url: String) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.monogram = String(title.prefix(2)).uppercased()
        self.monogramColor = Int.random(in: 0...360)
        self.createdAt = Date()
    }
}
```

#### 4.3.2 ホーム画面 (SwiftUI)

```swift
struct HomeView: View {
    @Query(sort: \Bookmark.createdAt) private var bookmarks: [Bookmark]
    @Environment(\.modelContext) private var modelContext

    let columns = [GridItem(.adaptive(minimum: 100))]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(bookmarks) { bookmark in
                    BookmarkTile(bookmark: bookmark)
                }
                AddBookmarkTile()
            }
            .padding()
        }
    }
}
```

#### 4.3.3 Favicon 取得

```swift
// FaviconService.swift
class FaviconService {
    func fetchFavicon(for url: String) async -> NSImage? {
        guard let url = URL(string: url) else { return nil }
        let faviconURL = url.appendingPathComponent("favicon.ico")
        // ... fetch and cache
    }
}
```

### 4.4 Phase 3.4: テーマ

#### 4.4.1 テーマ定義

```swift
enum ThemeMode: String, CaseIterable {
    case system, light, dark
}

@Observable
class ThemeManager {
    var mode: ThemeMode = .system
    var accentHue: Float = 210.0
    var accentSaturation: Float = 0.8
    var accentTone: Float = 0.5

    var colorScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var accentPalette: AccentPalette {
        // Call Rust FFI: hb_accent_palette
        RustCore.accentPalette(hue: accentHue, saturation: accentSaturation, tone: accentTone, dark: mode == .dark)
    }
}
```

#### 4.4.2 アクセントカラー適用

```swift
// Apply accent color to SwiftUI environment
.environment(\.tint, Color(nsColor: NSColor(calibratedHue: ..., saturation: ..., brightness: ..., alpha: 1)))
```

### 4.5 Phase 3.5: 履歴 + フォームログイン

#### 4.5.1 履歴モデル

```swift
@Model
class HistoryEntry {
    var url: String
    var title: String
    var visitedAt: Date
    var visitCount: Int
}
```

#### 4.5.2 フォームログイン

- CEF の OnBeforeBrowse または JavaScript 注入でフォーム検出
- Keychain に資格情報を保存 (https のみ)
- 次回訪問時に自動入力

### 4.6 Phase 3.6: バックアップ/復元

#### 4.6.1 エクスポート

```swift
class BackupService {
    func export(passphrase: String?) -> Data? {
        let bookmarks = fetchAllBookmarks()
        let settings = fetchSettings()
        let trustedSites = fetchTrustedSites()
        let credentials = fetchCredentials() // Keychain

        let backup = Backup(
            version: 1,
            bookmarks: bookmarks,
            settings: settings,
            trustedSites: trustedSites,
            credentials: credentials
        )

        let json = try? JSONEncoder().encode(backup)
        if let passphrase = passphrase {
            // Encrypt with Rust BackupCrypto
            return RustCore.backupEncrypt(plaintext: json, passphrase: passphrase)
        }
        return json
    }
}
```

#### 4.6.2 インポート

```swift
    func import(data: Data, passphrase: String?, mode: ImportMode) {
        // Decrypt if needed
        // Parse JSON
        // Merge or replace based on mode
    }
```

### 4.7 Phase 3.7: 設定画面

#### 4.7.1 7 タブ構成

```swift
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintbrush") }
            SitePermissionsSettings().tabItem { Label("Site Permissions", systemImage: "lock.shield") }
            NotificationsSettings().tabItem { Label("Notifications", systemImage: "bell") }
            SecuritySettings().tabItem { Label("Security", systemImage: "shield") }
            BackupSettings().tabItem { Label("Backup", systemImage: "arrow.up.arrow.down") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}
```

### 4.8 Phase 3.8: サイト権限管理

#### 4.8.1 per-origin 権限

```swift
@Model
class SitePermission {
    var origin: String
    var kind: String // "notification", "camera", "microphone", "location"
    var granted: Bool
}
```

#### 4.8.2 CEF 連携

- CEF の OnPermissionRequest callback で権限を確認
- SwiftData に保存、次回訪問時に自動適用

---

## 5. 実装順序 (詳細)

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

## 6. テスト計画

### 6.1 Rust core テスト
- url_normalizer: to_navigable, canonical_for_compare, search_url
- trust_policy: decide (Trusted/Unknown/Changed), normalizeFingerprint
- accent_math: palette, hsl, luminance, contrastRatio, readableOn
- backup_crypto: encrypt/decrypt round-trip, wrong passphrase
- history: record, sanitize, merge window
- codecs: sanitize, encode/decode

### 6.2 Swift テスト (XCTest)
- Bookmark CRUD
- History record/sanitize
- Settings sanitize
- Theme switching
- Backup export/import round-trip

### 6.3 統合テスト
- CEF ブラウザ起動・ページ表示
- 自己署名 HTTPS インタースティシャル
- HTTP 認証ダイアログ
- ブックマーク追加 → ホーム画面表示
- テーマ切り替え → UI 反映

### 6.4 デバッグ
- メモリリーク検出 (Instruments)
- パフォーマンス (起動時間、スクロール FPS)
- アクセシビリティ (VoiceOver, キーボードナビゲーション)

---

## 7. DMG 作成・配布

### 7.1 ビルド手順
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

### 7.2 検証
- DMG マウント → アプリ起動 → クラッシュなし
- Gatekeeper: ad-hoc のため rejected (期待動作)
- 全機能動作確認

---

## 8. リスクと対策

| リスク | 影響 | 対策 |
|---|---|---|
| CEF + SwiftUI 統合の複雑さ | 高 | 段階的実装、まず CEF NSView を SwiftUI に埋め込む |
| Rust FFI の型安全性 | 中 | cbindgen で自動生成、uniffi も検討 |
| SwiftData の macOS 14+ 制限 | 中 | macOS 14+ を最小要件に設定 |
| Keychain のスレッド安全性 | 中 | メインスレッドで Keychain 操作 |
| CEF helper の配布 | 高 | helper を .app バンドルに含める |
| DMG サイズ (770MB+) | 中 | CEF framework の最適化、strip |

---

## 9. 完了条件

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

*文書終わり — Phase 3 完全実装計画*