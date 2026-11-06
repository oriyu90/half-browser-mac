# Half-Browser macOS — 残タスク実装計画

## 1. 現状
- CEF ブラウザアプリ (`cefapp/`) が動作: CEF 初期化・ブラウザウィンドウ表示・自己署名 HTTPS auto-continue
- Rust core (`core/`) に純粋ロジック移植済み (url_normalizer, trust_policy, accent_math, backup_crypto, history, codecs 等)
- SwiftUI シェル (`app/`) は別アプリとして存在 (CEF 未統合)

## 2. 実装タスク (優先順)

### Phase A: CEF + SwiftUI 統合 (最優先)
A1. CefView (NSViewRepresentable) を作成し、CEF ブラウザを SwiftUI に埋め込む
A2. SwiftUI ウィンドウにツールバー (戻る/進む/リロード/ホーム/アドレスバー) を追加
A3. CEF コールバック (title, URL, loading state) を SwiftUI @Published に接続
A4. キーボードショートカット (Cmd+R リロード, Cmd+L アドレスバー)

### Phase B: 自己署名 HTTPS TOFU
B1. OnCertificateError で証明書情報を抽出 (subject, issuer, fingerprint, 有効期限)
B2. TOFU 判定 (TrustPolicy::decide) を C++ から Rust FFI または C++ で実装
B3. インタースティシャルダイアログ (SwiftUI) を表示
B4. 「今回だけ信頼」「常に信頼」の選択 → Keychain にピン保存
B5. 証明書変更時の再警告 (Changed)
B6. 設定画面に信頼済みサイト一覧 + 失効

### Phase C: HTTP 認証 + Keychain
C1. GetAuthCredentials で Keychain を検索
C2. 認証ダイアログ (SwiftUI) を表示
C3. 資格情報を Keychain に暗号化保存 (https のみ)
C4. 自動入力 (同一 scheme+host+port+realm)
C5. 設定画面に保存済み認証情報一覧 + 削除

### Phase D: ブックマーク + ホーム画面
D1. ブックマーク CRUD (SwiftData/SQLite)
D2. ホーム画面 (LazyVGrid + モノグラム + favicon)
D3. ブックマークモード (コンパクトバー)
D4. 外部 URL 受け取り (VIEW Intent 相当)

### Phase E: テーマ + アクセント
E1. ライト/ダーク/システム追従
E2. アクセントカラー (Rust AccentMath を FFI または C++ で移植)
E3. vibrancy / materials

### Phase F: 履歴 + フォームログイン
F1. 閲覧履歴 (Rust HistoryRules)
F2. フォームログイン保存・自動入力

### Phase G: バックアップ/復元
G1. JSON エクスポート (Rust Codecs)
G2. PBKDF2+AES-GCM 暗号化 (Rust BackupCrypto)
G3. インポート (統合/置換)

### Phase H: Rust FFI ブリッジ
H1. uniffi または cbindgen で Swift バインディング生成
H2. Swift から Rust core 関数を呼び出し

## 3. 実装順序
Phase A → B → C → D → E → F → G → H
(Phase H は各 Phase で必要に応じて実施)

## 4. 技術方針
- CEF + SwiftUI 統合: NSViewRepresentable で CEF NSView を SwiftUI に埋め込む
- 状態管理: SwiftUI @StateObject / @Observable (macOS 14+)
- データ永続化: SwiftData (macOS 14+) または SQLite
- Keychain: Security framework
- Rust FFI: cbindgen で C header 生成 → Swift bridging header