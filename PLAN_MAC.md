# Half-Browser macOS Port — 実装計画書

- 文書ID: HB-MAC-PLAN-001
- 版: 0.1（ドラフト）
- 作成日: 2026-11-05
- 対象: Android Half-Browser (v1.5.1) の macOS ネイティブ完全移植
- ソース: `/Users/user/places/適当/work/half-browser` (Android, Kotlin/Compose)
- 目標: 軽量・Half-Browser 風の鮮明なUI・macOS ネイティブアプリ級の動作快適性

---

## 1. 目的と目標

### 1.1 目標
1. **完全移植**: Android Half-Browser v1.5.1 の全機能を macOS で再現する（タブ1枚・自己署名 HTTPS TOFU・暗号化 HTTP 認証・ブックマーク・テーマ・バックアップ等）。
2. **軽量**: メモリ・CPU・起動時間でネイティブ級。Electron/Tauri の WebView 二重化を避け、CEF を直接埋め込む。
3. **Half-Browser 風の鮮明な UI**: 純黒ダーク + 白文字、アクセントカラー、8pt グリッド、SF Symbols、vibrancy、continuous corner radius。
4. **macOS ネイティブアプリ級の動作快適性**: AppKit/SwiftUI のネイティブウィンドウ・メニュー・キーボードショートカット・VoiceOver・ダークモード連動。

### 1.2 非目標（v1.0 Mac）
- タブ/複数ウィンドウ（Android 同様に単一タブ）
- 拡張機能・広告ブロック
- 同期・アカウント
- mTLS クライアント証明書

---

## 2. 技術スタック

| 層 | 技術 | 理由 |
|---|---|---|
| UI | SwiftUI + AppKit (NSViewRepresentable で CEF ホスト) | ネイティブ HIG 準拠、軽量 |
| ブラウザエンジン | CEF (Chromium Embedded Framework) | Chromium 互換、証明書/認証コールバック提供 |
| コアロジック | Rust (crate: `half-browser-core`) | Android の `core/` (純粋ロジック) の移植先。テスト容易・FFI で Swift から呼出 |
| データ永続化 | SwiftData / SQLite (CoreData) + Keychain | Android の EncryptedSharedPreferences 相当 |
| ビルド | Xcode + Cargo + CEF SDK | ネイティブツールチェーン |
| テスト | XCTest (Swift) + cargo test (Rust) | Android の JVM テスト相当 |

### 2.1 アーキテクチャ方針

```
┌─────────────────────────────────────────────┐
│  SwiftUI / AppKit Shell (macOS native)       │
│  - Window chrome, toolbar, sidebar           │
│  - Settings, bookmarks grid, dialogs         │
├─────────────────────────────────────────────┤
│  CEF Host (NSViewRepresentable)              │
│  - CefBrowser, CefClient, handlers           │
│  - SSL/Auth/Nav/Download callbacks            │
├─────────────────────────────────────────────┤
│  Rust Core (half-browser-core)               │
│  - UrlNormalizer, TrustPolicy, Codecs        │
│  - BookmarkIcons, GridPolicy, AuthKey        │
│  - Backup/BackupCrypto, AccentMath           │
│  - FFI bridge to Swift (cbindgen/uniffi)     │
└─────────────────────────────────────────────┘
```

依存の向き: `UI → CEF Host → Rust Core`。Rust Core は OS 非依存（Android の `core/` と同原則）。

---

## 3. 機能パリティマトリクス (Android → Mac)

| Android 機能 | Mac 対応 | 実装方針 |
|---|---|---|
| URL 入力・検索・戻る/進む・リロード・共有 | ✅ | CEF NavigationController + SwiftUI toolbar |
| 自己署名 HTTPS インタースティシャル + TOFU ピン | ✅ | CEF OnCertificateError + カスタムダイアログ |
| Basic/Digest 認証ダイアログ + 暗号化保存 + 自動入力 | ✅ | CEF GetAuthCredentials + Keychain |
| ダーク/ライト/システム + 動的カラー | ✅ | SwiftUI colorScheme + NSAppearance |
| ホーム（ブックマークグリッド、モノグラム） | ✅ | SwiftUI LazyVGrid + vibrancy |
| 外部 URL 受け取り (VIEW) | ✅ | NSAppleEventManager / URL scheme |
| ホーム画面ショートカット | ⚠️ | Dock menu / Spotlight 代替 (低優先) |
| 適応レイアウト + UI/文字スケール | ✅ | SwiftUI Dynamic Type + @ScaledMetric |
| 上部バー（ブックマークモード/通常モード） | ✅ | SwiftUI toolbar |
| クラッシュ安全性・メモリ安全性 | ✅ | Rust core + CEF sandbox |
| JVM テスト | ✅ | XCTest + cargo test |
| 閲覧履歴 (v1.2) | ✅ | SQLite + SwiftUI List |
| フォームログイン保存 (v1.3) | ✅ | CEF form detection + Keychain |
| ファイル添付・カメラ (v1.1) | ⚠️ | NSOpenPanel / AVCaptureDevice |
| サイト通知 (v1.1) | ⚠️ | UNUserNotificationCenter |
| バックアップ/復元 (v1.2) | ✅ | JSON + PBKDF2/AES-GCM (Rust) |
| アクセントカラー (v1.2) | ✅ | SwiftUI tint + AccentMath (Rust) |
| コンパクトバー (v1.5) | ✅ | SwiftUI toolbar variant |
| Web 通知ポリフィル (v1.5) | ⚠️ | JavaScript 注入 + UNNotification |
| サイト権限管理 (v1.5) | ✅ | CEF permission callbacks + SwiftData |
| ダーク読み込みマスク (v1.5.1) | ✅ | SwiftUI overlay |

---

## 4. プロジェクト構成

```
half-browser-mac/
├── PLAN_MAC.md
├── README.md
├── core/                          # Rust crate (half-browser-core)
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── url_normalizer.rs
│       ├── trust_policy.rs
│       ├── codecs.rs
│       ├── accent_math.rs
│       ├── backup_crypto.rs
│       ├── grid_policy.rs
│       ├── auth_key.rs
│       ├── history_rules.rs
│       └── ffi.rs                 # cbindgen/uniffi exports
├── app/                           # Xcode project (SwiftUI)
│   ├── HalfBrowserMac.xcodeproj
│   └── HalfBrowserMac/
│       ├── HalfBrowserApp.swift
│       ├── ContentView.swift
│       ├── Browser/                # CEF host + browser VM
│       ├── Home/                   # Bookmarks grid
│       ├── Settings/
│       ├── Theme/
│       └── Resources/
├── cef/                           # CEF SDK (downloaded, gitignored)
├── scripts/
│   ├── build-core.sh
│   └── fetch-cef.sh
└── tests/
    ├── core-tests/                # Rust tests
    └── app-tests/                 # XCTest
```

---

## 5. マイルストーン

### M0: 環境構築 (1-2日)
- [ ] Rust toolchain 確認 (✓ cargo 1.99.1)
- [ ] CEF SDK ダウンロード (macOS arm64)
- [ ] Xcode プロジェクト作成
- [ ] Cargo workspace 初期化

### M1: Rust Core 移植 (3-5日)
- [ ] UrlNormalizer (URL 正規化・検索判定)
- [ ] TrustPolicy (証明書 TOFU 判定)
- [ ] Codecs (JSON encode/decode + sanitize)
- [ ] AccentMath (HSL→ARGB・コントラスト)
- [ ] BackupCrypto (PBKDF2+AES-GCM)
- [ ] GridPolicy / AuthKey / HistoryRules
- [ ] FFI ブリッジ (uniffi または cbindgen)
- [ ] cargo test 全パス

### M2: CEF 統合 (5-7日)
- [ ] CEF SDK 組み込み
- [ ] CefBrowser ホスト (NSView)
- [ ] SSL エラーハンドラ (OnCertificateError)
- [ ] HTTP 認証ハンドラ (GetAuthCredentials)
- [ ] ナビゲーション・タイトル・進捗
- [ ] ダウンロード・ファイル選択
- [ ] レンダラクラッシュ処理

### M3: SwiftUI UI シェル (5-7日)
- [ ] ウィンドウ・ツールバー・サイドバー
- [ ] ホーム (ブックマークグリッド)
- [ ] ブラウザ画面 (CEF ホスト + ツールバー)
- [ ] 設定画面 (7 タブ)
- [ ] テーマ (ライト/ダーク/システム、アクセント)
- [ ] vibrancy / materials / SF Symbols

### M4: 機能統合 (5-7日)
- [ ] 自己署名 HTTPS インタースティシャル
- [ ] HTTP 認証ダイアログ + Keychain 保存
- [ ] ブックマーク CRUD + favicon
- [ ] 履歴
- [ ] フォームログイン保存
- [ ] バックアップ/復元

### M5: 仕上げ・テスト・配布 (3-5日)
- [ ] XCTest スイート
- [ ] アクセシビリティ (VoiceOver, キーボード)
- [ ] パフォーマンス最適化 (起動・メモリ・スクロール)
- [ ] コード署名・公证 (notarization)
- [ ] DMG 配布

合計推定: 22-33 日

---

## 6. リスク

| リスク | 影響 | 対策 |
|---|---|---|
| CEF SDK サイズ (数百MB) | 配布サイズ増 | minimal CEF build、strip |
| CEF + SwiftUI のスレッド安全性 | クラッシュ | CEF UI スレッド規約厳守 |
| Rust FFI のオーバーヘッド | パフォーマンス | uniffi で型安全なバインディング |
| 自己署名証明書の CEF コールバック | 複雑 | OnCertificateError でカスタムダイアログ |
| macOS 公証 (notarization) | 配布遅延 | 早期に証明書取得・テスト |
| CEF バージョンと Chromium の乖離 | 互換性 | ピン留めバージョンで固定 |

---

## 7. 次のアクション

1. CEF SDK をダウンロード (scripts/fetch-cef.sh)
2. Rust core crate を初期化 (cargo new)
3. Xcode プロジェクトを作成
4. M1 の UrlNormalizer から移植開始