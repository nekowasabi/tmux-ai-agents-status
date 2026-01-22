---
mission_id: facilitator-feature
title: タスク完了後の継続フロー機能
status: planning
progress: 0
phase: planning
tdd_mode: true
blockers: []
created_at: 2026-01-22
updated_at: 2026-01-22
---

# User Operation Flow

## 設計方針
- **能動的呼び出し方式**: 自動ポップアップは誤操作や集中妨害のリスクがあるため不採用
- **通知**: 既存のhooks機能（terminal-notifier等）で実現済み
- **呼び出し**: ユーザーが気づいたときにキーバインドで能動的に

## 通常フロー
```
1. Claude Codeでタスク実行
2. タスク完了 → 既存hooksで通知（terminal-notifier等）
3. ユーザーが通知に気づく（自分のペースで）
4. prefix + n を押す（能動的）
5. ポップアップ表示「次に何をしますか？」
6. アクション選択・実行
```

## 各アクションの動作
| アクション | 動作 |
|-----------|------|
| 🔄 続ける | 元のペインにフォーカス → 通常入力 |
| 🔀 切り替え | select_claude_launcher.sh起動 |
| ➕ 新規 | 元のペインにフォーカス → 通常入力 |
| ✅ 完了 | ポップアップを閉じる |

## キーボード操作
| キー | 動作 |
|------|------|
| `prefix + n` | 次のアクションUI呼び出し |
| `↑` / `↓` | メニュー項目選択 |
| `Enter` | 選択確定 |
| `Esc` | キャンセル |

## 既存機能との一貫性
```bash
prefix + g  → select_claude_launcher.sh  → Claude選択UI（既存）
prefix + n  → facilitator_launcher.sh    → 次のアクションUI（新規）
```

# Commander's Intent

## 目的
Claude Codeのタスク完了後、ユーザーが次のアクションを直感的に選択できるインタラクティブフローを提供する。

## 成功基準
1. tmuxキーバインド（prefix + n）から能動的に起動
2. 現在のセッション情報を収集・表示
3. fzf UIで次のアクションを選択可能
4. プラグイン機構で拡張可能
5. エラーハンドリングが堅牢

## 非機能要件
- 起動時間: 1秒以内
- tmux外では動作しない（サイレントに終了）
- プラグインの動的読み込み対応

# Context

## 背景
現在、Claude Codeのタスク完了後、ユーザーは手動で次のアクションを決定する必要がある。本機能により、以下のワークフローを提供する：

1. タスク完了 → 既存hooksで通知（terminal-notifier等）
2. ユーザーが通知に気づく（自分のペースで）
3. prefix + n を押す（能動的に呼び出し）
4. ポップアップで次のアクション選択
5. 選択されたアクションを実行

## 既存システムとの連携

### tmuxキーバインド
- **設定ファイル**: `claudecode_status.tmux`
- **既存キー**: `prefix + g` (Claude選択)
- **追加キー**: `prefix + n` (次のアクションUI)
- **通知**: 既存hooksで実現済み（terminal-notifier等）

### tmux-claudecode-status プラグイン
- **既存機能**: ステータス表示、セッション追跡、プロセス選択
- **再利用コンポーネント**:
  - `select_claude.sh`: プロセス情報取得（`--list`オプション）
  - `select_claude_launcher.sh`: セレクタUIパターン（参考）
  - `focus_session.sh`: フォーカス管理
  - `shared.sh`: 共有ユーティリティ

### tmux通信パターン
```bash
# ペインにコマンド送信
tmux send-keys -t <pane_id> "コマンド" Enter

# ペイン内容取得
tmux capture-pane -t "$pane_id" -p -S -20

# ポップアップUI
tmux popup -E -w 80% -h 60% "command"

# ペイン選択
tmux select-pane -t "$pane_id"
```

## プロジェクト構造
```
tmux-claudecode-status/
├── claudecode_status.tmux          # TPM入り口
├── scripts/
│   ├── claudecode_status.sh         # メイン：ステータス表示
│   ├── shared.sh                    # 共有ユーティリティ
│   ├── session_tracker.sh           # セッション追跡
│   ├── select_claude.sh             # プロセスセレクタ
│   ├── select_claude_launcher.sh    # セレクタランチャー（参考パターン）
│   ├── focus_session.sh             # フォーカス管理
│   ├── preview_pane.sh              # プレビュー表示
│   └── facilitator/                 # 【新規】
│       ├── facilitator_launcher.sh  # メインエントリポイント
│       ├── context-builder.sh       # コンテキスト収集
│       ├── action-selector.sh       # fzf UI
│       ├── action-executor.sh       # アクション実行
│       ├── session-state.sh         # セッション状態管理
│       └── plugins/                 # プラグイン
│           └── README.md
├── config/
│   └── actions.json                 # 【新規】アクション定義
└── tests/                           # テストスイート
```

# References

## 参照ファイル
- `/Users/ttakeda/repos/tmux-claudecode-status/scripts/select_claude_launcher.sh` - fzf UIパターン
- `/Users/ttakeda/repos/tmux-claudecode-status/scripts/focus_session.sh` - フォーカス管理
- `/Users/ttakeda/repos/tmux-claudecode-status/scripts/shared.sh` - 共有ユーティリティ
- `/Users/ttakeda/repos/tmux-claudecode-status/scripts/select_claude.sh` - プロセス情報取得
- `/Users/ttakeda/repos/tmux-claudecode-status/claudecode_status.tmux` - キーバインド設定

## 実装ファイル（新規作成）
- `/Users/ttakeda/repos/tmux-claudecode-status/scripts/facilitator/facilitator_launcher.sh`
- `/Users/ttakeda/repos/tmux-claudecode-status/scripts/facilitator/context-builder.sh`
- `/Users/ttakeda/repos/tmux-claudecode-status/scripts/facilitator/action-selector.sh`
- `/Users/ttakeda/repos/tmux-claudecode-status/scripts/facilitator/action-executor.sh`
- `/Users/ttakeda/repos/tmux-claudecode-status/scripts/facilitator/session-state.sh`
- `/Users/ttakeda/repos/tmux-claudecode-status/scripts/facilitator/plugins/README.md`
- `/Users/ttakeda/repos/tmux-claudecode-status/config/actions.json`

## テストファイル
- `/Users/ttakeda/repos/tmux-claudecode-status/tests/facilitator/test_facilitator.sh`
- `/Users/ttakeda/repos/tmux-claudecode-status/tests/facilitator/test_context_builder.sh`
- `/Users/ttakeda/repos/tmux-claudecode-status/tests/facilitator/test_action_selector.sh`
- `/Users/ttakeda/repos/tmux-claudecode-status/tests/facilitator/test_action_executor.sh`
- `/Users/ttakeda/repos/tmux-claudecode-status/tests/facilitator/test_session_state.sh`
- `/Users/ttakeda/repos/tmux-claudecode-status/tests/facilitator/test_plugins.sh`
- `/Users/ttakeda/repos/tmux-claudecode-status/tests/facilitator/test_integration.sh`

# Progress Map

```
[Phase 1: 基盤構築] → Process 1-4
  ↓
[Phase 2: コア機能] → Process 5-7
  ↓
[Phase 3: 拡張機能] → Process 8-9
  ↓
[Phase 4: テスト] → Process 10-19
  ↓
[Phase 5: フォローアップ] → Process 50-59
  ↓
[Phase 6: 品質向上] → Process 100-109
  ↓
[Phase 7: ドキュメント] → Process 200-209
  ↓
[Phase 8: OODA] → Process 300
```

# Processes

## Process 1: ディレクトリ構造作成

### Red
- [ ] テスト: `tests/facilitator/test_directory_structure.sh` 作成
  - ディレクトリ存在確認テスト
  - パーミッション確認テスト
  - 想定結果: 全ディレクトリが正しく作成される

### Green
- [ ] `scripts/facilitator/` ディレクトリ作成
- [ ] `scripts/facilitator/plugins/` ディレクトリ作成
- [ ] `config/` ディレクトリ作成（既存の場合はスキップ）
- [ ] `tests/facilitator/` ディレクトリ作成
- [ ] `.gitkeep` ファイル配置（plugins/）

### Refactor
- [ ] ディレクトリ構造をREADME.mdに記載
- [ ] パーミッション最適化（755）

---

## Process 2: facilitator_launcher.sh 基本実装

### Red
- [ ] テスト: `tests/facilitator/test_facilitator_launcher.sh` 作成
  - tmux環境外では即座に終了
  - tmux環境内では後続処理を呼び出す
  - 環境変数 `FACILITATOR_MODE` をサポート
  - タイムアウト処理（デフォルト30秒）
  - 想定結果: 環境に応じて適切に分岐

### Green
- [ ] `scripts/facilitator/facilitator_launcher.sh` 作成
  ```bash
  #!/usr/bin/env bash
  # facilitator_launcher.sh - メインエントリポイント

  set -euo pipefail

  # 定数
  readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  readonly FACILITATOR_TIMEOUT="${FACILITATOR_TIMEOUT:-30}"
  readonly FACILITATOR_MODE="${FACILITATOR_MODE:-interactive}"

  # tmux環境チェック
  is_tmux_session() {
      [[ -n "${TMUX:-}" ]]
  }

  # メイン処理
  main() {
      # tmux外では何もしない
      if ! is_tmux_session; then
          exit 0
      fi

      # サイレントモードでは何もしない
      if [[ "$FACILITATOR_MODE" == "silent" ]]; then
          exit 0
      fi

      # 現在のペインID取得
      local pane_id
      pane_id=$(tmux display-message -p '#{pane_id}')

      # コンテキスト収集
      local context_json
      context_json=$("$SCRIPT_DIR/context-builder.sh" "$pane_id")

      # アクション選択
      local action_id
      action_id=$(echo "$context_json" | "$SCRIPT_DIR/action-selector.sh")

      # アクション実行
      if [[ -n "$action_id" ]]; then
          "$SCRIPT_DIR/action-executor.sh" "$action_id" "$pane_id" "$context_json"
      fi
  }

  [[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
  ```
- [ ] 実行権限付与（`chmod +x`）

### Refactor
- [ ] エラーハンドリング強化
- [ ] ロギング機構追加（デバッグモード）
- [ ] シェルチェック（shellcheck）実行

---

## Process 3: action-selector.sh 実装

### Red
- [ ] テスト: `tests/facilitator/test_action_selector.sh` 作成
  - 固定メニュー表示テスト（4項目）
  - fzf選択結果の正しい出力
  - キャンセル時は空文字列を返す
  - tmux popup表示確認
  - 想定結果: action_id が正しく出力される

### Green
- [ ] `scripts/facilitator/action-selector.sh` 作成
  ```bash
  #!/usr/bin/env bash
  # action-selector.sh - fzf UIでアクション選択

  set -euo pipefail

  readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  readonly TEMP_DIR="${TMPDIR:-/tmp}/facilitator.$$"

  # 一時ファイル準備
  mkdir -p "$TEMP_DIR"
  trap 'rm -rf "$TEMP_DIR"' EXIT

  readonly MENU_FILE="$TEMP_DIR/menu.txt"
  readonly RESULT_FILE="$TEMP_DIR/result.txt"

  # 固定メニュー作成
  create_menu() {
      cat > "$MENU_FILE" <<EOF
  🔄 continue    | このプロジェクトで続ける
  🔀 switch-session | 別のClaudeに切り替え
  ➕ new-task   | 新規タスクを開始
  ✅ end        | 完了
  EOF
  }

  # fzf UI表示
  show_selector() {
      tmux popup -E -w 60% -h 40% "
          selected=\$(cat '$MENU_FILE' | fzf \
              --height=100% \
              --reverse \
              --border \
              --prompt='次のアクションを選択: ' \
              --header='Claude Code タスク完了' \
              --delimiter=' ' \
              --with-nth=1,2 \
              --preview='echo {3..}' \
              --preview-window=down:3:wrap)

          if [[ -n \"\$selected\" ]]; then
              echo \"\$selected\" | awk '{print \$2}' > '$RESULT_FILE'
          fi
      "
  }

  # メイン処理
  main() {
      create_menu
      show_selector

      if [[ -f "$RESULT_FILE" ]]; then
          cat "$RESULT_FILE"
      fi
  }

  [[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
  ```
- [ ] 実行権限付与

### Refactor
- [ ] fzfオプション最適化（カラースキーム）
- [ ] キーバインド追加（Ctrl-c: キャンセル）
- [ ] エラーハンドリング（fzf未インストール時）

---

## Process 4: action-executor.sh 実装

### Red
- [ ] テスト: `tests/facilitator/test_action_executor.sh` 作成
  - `continue`: ペインフォーカス実行確認
  - `switch-session`: select_claude_launcher.sh 呼び出し確認
  - `new-task`: ペインフォーカス実行確認
  - `end`: 正常終了確認
  - 未知のaction_id: エラーハンドリング確認
  - 想定結果: 各アクションが正しく実行される

### Green
- [ ] `scripts/facilitator/action-executor.sh` 作成
  ```bash
  #!/usr/bin/env bash
  # action-executor.sh - アクション実行

  set -euo pipefail

  readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  readonly PARENT_SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"

  # ビルトインハンドラ
  action_continue() {
      local pane_id="$1"
      tmux select-pane -t "$pane_id"
  }

  action_switch_session() {
      "$PARENT_SCRIPT_DIR/select_claude_launcher.sh"
  }

  action_new_task() {
      local pane_id="$1"
      tmux select-pane -t "$pane_id"
      # 将来: プロンプトテンプレート表示など
  }

  action_end() {
      exit 0
  }

  # メイン処理
  main() {
      local action_id="$1"
      local pane_id="${2:-}"
      local context_json="${3:-}"

      case "$action_id" in
          continue)
              action_continue "$pane_id"
              ;;
          switch-session)
              action_switch_session
              ;;
          new-task)
              action_new_task "$pane_id"
              ;;
          end)
              action_end
              ;;
          *)
              echo "Unknown action: $action_id" >&2
              exit 1
              ;;
      esac
  }

  [[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
  ```
- [ ] 実行権限付与

### Refactor
- [ ] エラーハンドリング強化
- [ ] ロギング追加
- [ ] ドライランモード追加（`--dry-run`）

---

## Process 5: context-builder.sh 実装

### Red
- [ ] テスト: `tests/facilitator/test_context_builder.sh` 作成
  - 現在のセッション情報取得
  - 他のClaudeセッション情報取得
  - Git状態取得（clean/dirty）
  - JSON形式出力確認
  - 想定結果: 有効なJSONが出力される

### Green
- [ ] `scripts/facilitator/context-builder.sh` 作成
  ```bash
  #!/usr/bin/env bash
  # context-builder.sh - コンテキスト収集

  set -euo pipefail

  readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  readonly PARENT_SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"

  # 現在のセッション情報取得
  get_current_session() {
      local pane_id="$1"
      local session_name project_path cwd

      session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}')
      cwd=$(tmux display-message -p -t "$pane_id" '#{pane_current_path}')
      project_path=$(basename "$cwd")

      cat <<EOF
  {
    "pane_id": "$pane_id",
    "session_name": "$session_name",
    "project": "$project_path",
    "cwd": "$cwd"
  }
  EOF
  }

  # 他のClaudeセッション情報取得
  get_other_sessions() {
      if [[ -x "$PARENT_SCRIPT_DIR/select_claude.sh" ]]; then
          "$PARENT_SCRIPT_DIR/select_claude.sh" --list 2>/dev/null || echo "[]"
      else
          echo "[]"
      fi
  }

  # Git状態取得
  get_git_status() {
      local cwd="$1"

      if [[ -d "$cwd/.git" ]]; then
          cd "$cwd" || return
          if git diff-index --quiet HEAD -- 2>/dev/null; then
              echo "clean"
          else
              echo "dirty"
          fi
      else
          echo "not_a_repo"
      fi
  }

  # メイン処理
  main() {
      local pane_id="$1"
      local current_session other_sessions git_status

      current_session=$(get_current_session "$pane_id")
      other_sessions=$(get_other_sessions)

      local cwd
      cwd=$(echo "$current_session" | grep -o '"cwd": "[^"]*"' | cut -d'"' -f4)
      git_status=$(get_git_status "$cwd")

      cat <<EOF
  {
    "current_session": $current_session,
    "other_sessions": $other_sessions,
    "git_status": "$git_status"
  }
  EOF
  }

  [[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
  ```
- [ ] 実行権限付与

### Refactor
- [ ] JSON出力をjqで検証（オプショナル）
- [ ] エラーハンドリング強化
- [ ] パフォーマンス最適化（並列実行）

---

## Process 6: actions.json 動的読み込み

### Red
- [ ] テスト: `tests/facilitator/test_actions_json.sh` 作成
  - JSONファイル読み込み確認
  - アクションリスト生成確認
  - 不正なJSONでエラー
  - 想定結果: 動的メニュー生成成功

### Green
- [ ] `config/actions.json` 作成
  ```json
  {
    "version": "1.0",
    "actions": [
      {
        "id": "continue",
        "label": "このプロジェクトで続ける",
        "icon": "🔄",
        "type": "builtin"
      },
      {
        "id": "switch-session",
        "label": "別のClaudeに切り替え",
        "icon": "🔀",
        "type": "builtin"
      },
      {
        "id": "new-task",
        "label": "新規タスクを開始",
        "icon": "➕",
        "type": "builtin"
      },
      {
        "id": "end",
        "label": "完了",
        "icon": "✅",
        "type": "builtin"
      }
    ],
    "plugins": {
      "enabled": true,
      "directory": "plugins"
    }
  }
  ```
- [ ] `action-selector.sh` を更新
  - actions.jsonからメニュー生成
  - jq使用（フォールバック: awkで解析）

### Refactor
- [ ] JSON schema検証
- [ ] デフォルト値のフォールバック処理
- [ ] 設定ファイルパスをカスタマイズ可能に

---

## Process 7: プラグイン機構

### Red
- [ ] テスト: `tests/facilitator/test_plugins.sh` 作成
  - プラグインメタデータ抽出
  - プラグイン動的読み込み
  - プラグイン実行確認
  - エラーハンドリング（不正なプラグイン）
  - 想定結果: プラグインがメニューに追加され実行可能

### Green
- [ ] `scripts/facilitator/plugins/README.md` 作成
  ```markdown
  # Facilitator Plugins

  ## プラグイン仕様

  プラグインは以下のメタデータを含むシェルスクリプトです：

  ```bash
  #!/usr/bin/env bash
  # @plugin-id: example
  # @plugin-label: サンプル
  # @plugin-icon: 🧪
  # @plugin-description: サンプルプラグイン

  main() {
      local pane_id="$1"
      local context_json="$2"

      # プラグイン処理
      echo "Example plugin executed"
  }

  [[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
  ```

  ## 引数
  - `$1`: 現在のペインID
  - `$2`: コンテキストJSON

  ## 配置場所
  `scripts/facilitator/plugins/*.sh`
  ```
- [ ] サンプルプラグイン作成: `scripts/facilitator/plugins/example.sh`
- [ ] `action-selector.sh` を更新
  - プラグインディレクトリスキャン
  - メタデータ抽出（grep）
  - メニューに動的追加
- [ ] `action-executor.sh` を更新
  - プラグイン実行ハンドラ追加

### Refactor
- [ ] プラグインバリデーション
- [ ] プラグインエラー時のフォールバック
- [ ] プラグイン設定ファイル（有効/無効切り替え）

---

## Process 8: session-state.sh 実装

### Red
- [x] テスト: `tests/facilitator/test_session_state.sh` 作成
  - 状態保存確認
  - 状態読み込み確認
  - 状態一覧取得確認
  - 古い状態のクリーンアップ確認
  - 想定結果: 状態が正しく永続化される

### Green
- [x] `scripts/facilitator/session-state.sh` 作成
  ```bash
  #!/usr/bin/env bash
  # session-state.sh - セッション状態管理

  set -euo pipefail

  readonly STATE_DIR="$HOME/.claude/facilitator-states"

  # ディレクトリ初期化
  init_state_dir() {
      mkdir -p "$STATE_DIR"
  }

  # 状態保存
  session_state_save() {
      local session_id="$1"
      local json_content="$2"

      init_state_dir
      echo "$json_content" > "$STATE_DIR/${session_id}.json"
  }

  # 状態読み込み
  session_state_load() {
      local session_id="$1"

      if [[ -f "$STATE_DIR/${session_id}.json" ]]; then
          cat "$STATE_DIR/${session_id}.json"
      else
          echo "{}"
      fi
  }

  # 状態一覧
  session_state_list() {
      init_state_dir
      find "$STATE_DIR" -name "*.json" -type f
  }

  # 古い状態のクリーンアップ
  session_state_cleanup() {
      local days="${1:-7}"

      init_state_dir
      find "$STATE_DIR" -name "*.json" -type f -mtime "+${days}" -delete
  }

  # メイン処理
  main() {
      local command="$1"
      shift

      case "$command" in
          save)
              session_state_save "$@"
              ;;
          load)
              session_state_load "$@"
              ;;
          list)
              session_state_list
              ;;
          cleanup)
              session_state_cleanup "$@"
              ;;
          *)
              echo "Usage: $0 {save|load|list|cleanup}" >&2
              exit 1
              ;;
      esac
  }

  [[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
  ```
- [ ] 実行権限付与

### Refactor
- [ ] 自動クリーンアップ（facilitator.sh起動時）
- [ ] 状態ファイルの暗号化（オプショナル）
- [ ] エクスポート/インポート機能

---

## Process 9: 統合テスト・キーバインド設定

### Red
- [x] テスト: `tests/facilitator/test_integration.sh` 作成
  - エンドツーエンドフロー確認
  - キーバインド起動からアクション実行まで
  - 各アクションの動作確認
  - エラーケースの確認
  - 想定結果: 全フローが正常に動作

### Green
- [x] `claudecode_status.tmux` にキーバインド追加
  ```bash
  # 既存のキーバインド
  select_key=$(get_tmux_option "@claudecode_select_key" "g")
  tmux bind-key "$select_key" run-shell "$scripts_dir/select_claude_launcher.sh"

  # 新規追加: 次のアクションUI
  next_action_key=$(get_tmux_option "@claudecode_next_action_key" "n")
  tmux bind-key "$next_action_key" run-shell "$scripts_dir/facilitator/facilitator_launcher.sh"
  ```
- [x] tmuxオプション追加
  ```bash
  # 次のアクションUIのキーバインド（デフォルト: n）
  set -g @claudecode_next_action_key "n"

  # 機能の有効/無効
  set -g @claudecode_facilitator "on"

  # タイムアウト（秒）
  set -g @claudecode_facilitator_timeout "30"
  ```
- [x] 統合テスト実行

### Refactor
- [ ] キーバインド設定の自動インストールスクリプト
- [ ] アンインストールスクリプト
- [ ] バージョン管理（設定ファイル）

---

## Process 10: facilitator.sh ユニットテスト

### Red
- [ ] テストケース拡充
  - タイムアウト処理
  - 中断処理（Ctrl-C）
  - 並列実行時の競合

### Green
- [ ] テスト実装

### Refactor
- [ ] テストヘルパー関数抽出
- [ ] モック機構整備

---

## Process 11: context-builder.sh ユニットテスト

### Red
- [ ] テストケース拡充
  - Gitリポジトリなしの場合
  - サブモジュール含むリポジトリ
  - シンボリックリンク経由のパス

### Green
- [ ] テスト実装

### Refactor
- [ ] エッジケースカバレッジ向上

---

## Process 12: action-selector.sh ユニットテスト

### Red
- [ ] テストケース拡充
  - fzf未インストール時
  - カスタムキーバインド
  - プレビュー表示

### Green
- [ ] テスト実装

### Refactor
- [ ] UIテスト自動化（expect使用）

---

## Process 13: action-executor.sh ユニットテスト

### Red
- [ ] テストケース拡充
  - プラグイン実行失敗時
  - 不正なpane_id
  - 権限エラー

### Green
- [ ] テスト実装

### Refactor
- [ ] リトライ機構追加

---

## Process 14: session-state.sh ユニットテスト

### Red
- [ ] テストケース拡充
  - 同時書き込み競合
  - ディスク容量不足
  - 不正なJSON

### Green
- [ ] テスト実装

### Refactor
- [ ] ロック機構追加（flock）

---

## Process 15: プラグインシステムユニットテスト

### Red
- [ ] テストケース拡充
  - メタデータ不正
  - プラグイン実行権限なし
  - プラグイン無限ループ

### Green
- [ ] テスト実装

### Refactor
- [ ] タイムアウト機構（プラグイン実行）

---

## Process 16: エラーハンドリングテスト

### Red
- [ ] 全コンポーネントのエラーパス確認
- [ ] 異常系テストケース作成

### Green
- [ ] テスト実装

### Refactor
- [ ] エラーメッセージ標準化

---

## Process 17: パフォーマンステスト

### Red
- [ ] 起動時間測定（目標: 1秒以内）
- [ ] メモリ使用量測定
- [ ] 並列実行時の負荷測定

### Green
- [ ] ベンチマークスクリプト作成

### Refactor
- [ ] ボトルネック最適化

---

## Process 18: 互換性テスト

### Red
- [ ] 各tmuxバージョンでテスト（2.x, 3.x）
- [ ] macOS / Linux 両環境でテスト
- [ ] bash 3.x / 4.x / 5.x でテスト

### Green
- [ ] CI/CDパイプライン構築

### Refactor
- [ ] 互換性レイヤー追加

---

## Process 19: セキュリティテスト

### Red
- [ ] コマンドインジェクション確認
- [ ] パストラバーサル確認
- [ ] 権限昇格確認

### Green
- [ ] セキュリティスキャン（shellcheck）

### Refactor
- [ ] サニタイジング強化

---

## Process 50: エッジケース対応

### Red
- [ ] エッジケース一覧作成
  - ネストしたtmuxセッション
  - SSH経由のtmux
  - tmux-in-docker

### Green
- [ ] 各エッジケースの対応実装

### Refactor
- [ ] ドキュメント更新（既知の制限）

---

## Process 51: エラーメッセージ改善

### Red
- [ ] エラーメッセージレビュー
- [ ] ユーザビリティテスト

### Green
- [ ] わかりやすいエラーメッセージに改善
- [ ] トラブルシューティングガイド作成

### Refactor
- [ ] 多言語対応（オプショナル）

---

## Process 52: ロギング機構強化

### Red
- [ ] ログレベル定義（DEBUG, INFO, WARN, ERROR）
- [ ] ログローテーション仕様

### Green
- [ ] ロギングライブラリ実装
- [ ] 各コンポーネントにロギング追加

### Refactor
- [ ] ログ解析ツール作成

---

## Process 53: 設定ファイル拡張

### Red
- [ ] 設定項目一覧作成
  - タイムアウト
  - デフォルトアクション
  - プラグイン有効/無効

### Green
- [ ] `~/.config/facilitator/config.json` 対応
- [ ] 設定バリデーション

### Refactor
- [ ] 設定マイグレーション機構

---

## Process 54: デバッグモード追加

### Red
- [ ] デバッグ出力仕様
- [ ] トレース機構仕様

### Green
- [ ] `FACILITATOR_DEBUG=1` 対応
- [ ] 詳細ログ出力

### Refactor
- [ ] デバッグヘルパースクリプト

---

## Process 55: バックワード互換性確保

### Red
- [ ] 既存機能への影響確認
- [ ] 破壊的変更の洗い出し

### Green
- [ ] 互換性レイヤー実装

### Refactor
- [ ] 非推奨機能のマーキング

---

## Process 56: クリーンアップ処理強化

### Red
- [ ] リソースリーク確認
- [ ] 一時ファイル削除確認

### Green
- [ ] trapハンドラ強化
- [ ] クリーンアップスクリプト

### Refactor
- [ ] ガベージコレクション機構

---

## Process 57: 復旧機構実装

### Red
- [ ] 障害シナリオ作成
- [ ] 復旧手順定義

### Green
- [ ] 自動復旧スクリプト
- [ ] 状態復元機能

### Refactor
- [ ] 障害検知機構

---

## Process 58: ドライランモード拡張

### Red
- [ ] ドライラン出力仕様
- [ ] 副作用のシミュレーション

### Green
- [ ] `--dry-run` 全コンポーネント対応

### Refactor
- [ ] ドライランレポート生成

---

## Process 59: ヘルプ・使い方ガイド

### Red
- [ ] ヘルプメッセージ仕様
- [ ] 使用例一覧

### Green
- [ ] `--help` オプション実装
- [ ] マニュアルページ作成

### Refactor
- [ ] インタラクティブチュートリアル

---

## Process 100: コードリファクタリング

### Red
- [ ] コード品質メトリクス測定
  - 循環的複雑度
  - 関数行数
  - 重複コード

### Green
- [ ] 関数分割
- [ ] 共通処理の抽出

### Refactor
- [ ] 命名規則統一
- [ ] コメント整備

---

## Process 101: パフォーマンス最適化

### Red
- [ ] ボトルネック特定
- [ ] ベンチマーク基準値設定

### Green
- [ ] 並列処理導入
- [ ] キャッシュ機構

### Refactor
- [ ] 不要な処理削除

---

## Process 102: 依存関係最適化

### Red
- [ ] 依存パッケージ一覧
- [ ] 必須/オプショナル分類

### Green
- [ ] オプショナル依存の遅延ロード
- [ ] フォールバック実装

### Refactor
- [ ] 依存関係ドキュメント

---

## Process 103: エラーハンドリング統一

### Red
- [ ] エラーハンドリングパターン確認
- [ ] 一貫性のないエラー処理の洗い出し

### Green
- [ ] エラーハンドリングライブラリ
- [ ] 統一的なエラー処理

### Refactor
- [ ] エラーコード体系整備

---

## Process 104: テストカバレッジ向上

### Red
- [ ] カバレッジ測定（目標: 80%以上）
- [ ] 未テストコードの特定

### Green
- [ ] テストケース追加

### Refactor
- [ ] テストデータ管理

---

## Process 105: CI/CD パイプライン構築

### Red
- [ ] CI/CD要件定義
- [ ] テスト自動化戦略

### Green
- [ ] GitHub Actions設定
- [ ] 自動テスト実行

### Refactor
- [ ] デプロイ自動化

---

## Process 106: バージョン管理戦略

### Red
- [ ] セマンティックバージョニング適用
- [ ] 変更履歴管理

### Green
- [ ] CHANGELOGファイル作成
- [ ] バージョンタグ運用

### Refactor
- [ ] リリースノート自動生成

---

## Process 107: 国際化対応

### Red
- [ ] メッセージ外部化
- [ ] 言語ファイル設計

### Green
- [ ] i18n機構実装（オプショナル）

### Refactor
- [ ] 多言語テスト

---

## Process 108: アクセシビリティ向上

### Red
- [ ] スクリーンリーダー対応確認
- [ ] カラーブラインド対応確認

### Green
- [ ] 色覚補正対応
- [ ] 音声フィードバック

### Refactor
- [ ] ユーザビリティテスト

---

## Process 109: モニタリング・分析

### Red
- [ ] メトリクス定義
  - 使用頻度
  - アクション選択率
  - エラー率

### Green
- [ ] メトリクス収集機構（opt-in）

### Refactor
- [ ] ダッシュボード作成

---

## Process 200: README.md 作成

### Red
- [ ] README構成確認
  - インストール
  - 使い方
  - 設定
  - トラブルシューティング

### Green
- [ ] `/Users/ttakeda/repos/tmux-claudecode-status/README.md` 更新
  - Facilitator機能セクション追加
  - スクリーンショット追加
  - 設定例追加

### Refactor
- [ ] バッジ追加（CI status, version）

---

## Process 201: プラグイン開発ガイド

### Red
- [ ] 開発ガイド構成
  - プラグイン仕様
  - サンプルコード
  - ベストプラクティス

### Green
- [ ] `scripts/facilitator/plugins/DEVELOPMENT.md` 作成

### Refactor
- [ ] プラグインテンプレート提供

---

## Process 202: アーキテクチャドキュメント

### Red
- [ ] アーキテクチャ図作成
  - コンポーネント図
  - シーケンス図
  - データフロー図

### Green
- [ ] `docs/ARCHITECTURE.md` 作成

### Refactor
- [ ] Mermaid図の追加

---

## Process 203: API ドキュメント

### Red
- [ ] 公開API一覧
- [ ] 内部API一覧

### Green
- [ ] `docs/API.md` 作成

### Refactor
- [ ] コード内ドキュメント同期

---

## Process 204: トラブルシューティングガイド

### Red
- [ ] よくある問題一覧
- [ ] 解決手順

### Green
- [ ] `docs/TROUBLESHOOTING.md` 作成

### Refactor
- [ ] FAQ追加

---

## Process 205: 設定リファレンス

### Red
- [ ] 全設定項目の列挙
- [ ] デフォルト値の記載

### Green
- [ ] `docs/CONFIGURATION.md` 作成

### Refactor
- [ ] 設定例の追加

---

## Process 206: CONTRIBUTING.md

### Red
- [ ] コントリビューションガイドライン
- [ ] コードスタイル
- [ ] プルリクエストプロセス

### Green
- [ ] `CONTRIBUTING.md` 作成

### Refactor
- [ ] Issue/PRテンプレート

---

## Process 207: CHANGELOGメンテナンス

### Red
- [ ] 変更履歴フォーマット統一
- [ ] リリースノート作成

### Green
- [ ] `CHANGELOG.md` 更新

### Refactor
- [ ] 自動生成スクリプト

---

## Process 208: デモ・スクリーンキャスト作成

### Red
- [ ] デモシナリオ作成
- [ ] スクリーンキャストツール選定

### Green
- [ ] デモ動画作成
- [ ] GIF作成

### Refactor
- [ ] YouTubeアップロード（オプショナル）

---

## Process 209: ドキュメントサイト構築

### Red
- [ ] ドキュメントサイト要件
- [ ] 静的サイトジェネレータ選定

### Green
- [ ] GitHub Pages設定
- [ ] ドキュメントサイト公開

### Refactor
- [ ] 検索機能追加

---

## Process 300: OODA フィードバック

### Red
- [ ] 振り返りフレームワーク準備
  - Observe: 何を観察したか
  - Orient: どう解釈したか
  - Decide: 何を決定したか
  - Act: 何を実行したか

### Green
- [ ] プロジェクト振り返り実施
- [ ] 教訓の文書化
  - 成功要因
  - 失敗要因
  - 改善点

### Refactor
- [ ] 次期プロジェクトへの知見継承
- [ ] `stigmergy/briefings/facilitator-lessons-learned.md` 作成
- [ ] チーム共有セッション

---

# メタ情報

## 実装優先度
1. **Phase 1-3（Process 1-9）**: 最優先 - コア機能実装
2. **Phase 4（Process 10-19）**: 高優先 - 品質保証
3. **Phase 5-6（Process 50-109）**: 中優先 - 安定化・品質向上
4. **Phase 7（Process 200-209）**: 中優先 - ドキュメント整備
5. **Phase 8（Process 300）**: 完了時 - 振り返り

## 想定工数
- Phase 1-3: 8-12時間
- Phase 4: 6-8時間
- Phase 5-6: 10-15時間
- Phase 7: 4-6時間
- Phase 8: 2-3時間

**合計**: 30-44時間

## リスク
1. **tmuxバージョン互換性**: 複数バージョンでのテスト必須
2. **プラグイン品質**: サンドボックス化検討
3. **パフォーマンス**: 大量セッション時の負荷確認

## 成功基準
- [ ] 全ユニットテスト通過
- [ ] 統合テスト通過
- [ ] 起動時間 < 1秒
- [ ] ドキュメント完備
- [ ] プラグイン3個以上作成（サンプル含む）
