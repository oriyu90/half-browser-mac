# Half-Browser macOS — 残タスク実装計画 (Phase 2)

## 1. 残タスク一覧

| # | タスク | 説明 | 優先度 |
|---|---|---|---|
| 1 | Keychain 統合 | 証明書ピン・認証情報の永続化 (Security framework) | 高 |
| 2 | TOFU 判定 | TrustPolicy を C++ に移植 (Rust FFI は Phase 3) | 高 |
| 3 | ブックマーク + ホーム画面 | CRUD + JSON 永続化 + グリッド UI | 高 |
| 4 | テーマ | ライト/ダーク/システム + NSAppearance | 中 |
| 5 | 履歴 + フォームログイン | JSON 永続化 + Keychain | 中 |
| 6 | バックアップ/復元 | JSON I/O + PBKDF2/AES-GCM | 中 |
| 7 | Rust FFI ブリッジ | cbindgen で C header 生成 → C++ から Rust 呼び出し | 低 |
| 8 | SwiftUI 統合 | CEF ホストを NSViewRepresentable で SwiftUI に埋め込み | 低 |

## 2. 実装方針

### 2.1 Keychain 統合
- Security framework の SecItemAdd/SecItemCopyMatching/SecItemDelete を使用
- 証明書ピン: service="half-browser-trust", account=host:port, password=fingerprint
- 認証情報: service="half-browser-credentials", account=scheme://host:port|realm, password=user:pass (暗号化)

### 2.2 TOFU 判定 (C++ 移植)
- Rust TrustPolicy::decide を C++ に移植
- normalizeFingerprint, decide(host, port, fingerprint, saved) → Trusted/Unknown/Changed

### 2.3 ブックマーク
- JSON ファイルに永続化 (~/.half-browser/bookmarks.json)
- NSMenu または NSPopover でブックマーク一覧表示
- ホーム画面は別ウィンドウまたは about:blank ページ

### 2.4 テーマ
- NSAppearance (Aqua/DarkAqua) でウィンドウ外観を切り替え
- ユーザー設定を JSON に保存

### 2.5 履歴
- JSON ファイルに永続化 (~/.half-browser/history.json)
- HistoryRules (Rust) を C++ に移植

### 2.6 バックアップ/復元
- Rust BackupCrypto を C++ に移植 (または Rust FFI)
- JSON エクスポート/インポート

### 2.7 Rust FFI ブリッジ
- cbindgen で C header 生成
- C++ から Rust 関数を呼び出し
- Phase 3 で実施

### 2.8 SwiftUI 統合
- NSViewRepresentable で CEF NSView を SwiftUI に埋め込み
- Phase 3 で実施

## 3. 実装順序
1. Keychain + TOFU (Security framework)
2. ブックマーク CRUD + JSON 永続化
3. 履歴 + JSON 永続化
4. テーマ (ライト/ダーク/システム)
5. バックアップ/復元
6. Rust FFI ブリッジ (cbindgen)
7. SwiftUI 統合

## 4. 技術方針
- Keychain: Security.framework (SecItemAdd/CopyMatching/Delete)
- JSON: nlohmann/json (header-only) または手動パース
- テーマ: NSAppearance + NSApp.appearance
- ブックマーク/履歴: JSON ファイル (~/Library/Application Support/Half-Browser/)