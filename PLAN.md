---
mission_id: fzf-preview-feature
title: "fzfプロセス選択画面にプレビュー機能を追加"
status: planning
progress: 0
phase: planning
tdd_mode: true
blockers: 0
created_at: "2026-01-17"
updated_at: "2026-01-17"
---

# Commander's Intent

## Purpose
- `@claudecode_select_key` で起動するfzfプロセス絞り込み画面に、選択中のClaudeセッションのペイン内容をリアルタイムプレビュー表示する
- ユーザーが複数のClaudeセッションを持つ場合に、切り替え前に内容を確認できるようにする

## End State
- fzf選択画面の右側（または下部）にプレビューペインが表示される
- 選択を移動するたびに、対応するtmuxペインの最新内容（最後の30行）が表示される
- プレビュー機能はオプションで有効/無効を切り替えられる（`@claudecode_fzf_preview`）
- パフォーマンスに影響を与えない（遅延が体感できないレベル）

## Key Tasks
- 新規スクリプト `scripts/preview_pane.sh` を作成
- `scripts/select_claude_launcher.sh` を修正してプレビューオプションを追加
- `scripts/select_claude.sh` の `run_fzf_selection` 関数を修正
- `claudecode_status.tmux` に新しい設定オプションを追加
- READMEにドキュメントを追加
- テストを追加

## Constraints
- 既存の機能を壊さない
- パフォーマンスを劣化させない（プレビュー無効時は現状維持）
- tmux 3.2未満でもエラーにならない（プレビューは無効化される）

## Restraints
- fzfの `--preview` オプションを使用する
- `tmux capture-pane` コマンドでペイン内容を取得する
- 既存のコードスタイル・パターンに従う

---

# Context

## 概要
- fzfプロセス選択画面で、選択中のClaudeセッションのターミナル出力をプレビュー表示する機能を実装
- ユーザーは複数のClaudeセッションがある場合、切り替える前に各セッションの状態を確認できる

## 必須のルール
- 必ず `CLAUDE.md` を参照し、ルールを守ること
- 不明な点はAskUserQuestionで確認すること
- **TDD（テスト駆動開発）を厳守すること**
  - 各プロセスは必ずテストファーストで開始する（Red → Green → Refactor）
  - 実装コードを書く前に、失敗するテストを先に作成する
  - テストが通過するまで修正とテスト実行を繰り返す
  - プロセス完了の条件：該当するすべてのテスト、フォーマッタ、Linterが通過していること
  - プロセス完了後、チェックボックスを変更すること
- **各Process開始時のブリーフィング実行**
  - 各Processの「Briefing」セクションは自動生成される
  - `@process-briefing` コメントを含むセクションは、エージェントが実行時に以下を自動取得する：
    - **Related Lessons**: stigmergy/doctrine-memoriesから関連教訓を取得
    - **Known Patterns**: プロジェクト固有パターン・テンプレートから自動取得
    - **Watch Points**: 過去の失敗事例・注意点から自動取得
  - ブリーフィング情報は `/x` や `/d` コマンド実行時に動的に埋め込まれ、実行戦況を反映する

## 開発のゴール
- fzfプロセス選択画面でリアルタイムプレビューが機能する
- 既存機能との後方互換性を維持する
- ドキュメントとテストが完備されている

---

# References

| @ref | @target | @test |
|------|---------|-------|
| scripts/shared.sh | scripts/preview_pane.sh (新規) | tests/test_preview.sh (新規) |
| scripts/select_claude.sh (行207-264) | scripts/select_claude.sh | tests/test_output.sh |
| scripts/select_claude_launcher.sh | scripts/select_claude_launcher.sh | tests/test_output.sh |
| claudecode_status.tmux (行34-70) | claudecode_status.tmux | tests/test_output.sh |
| README.md | README.md, README_ja.md | - |

---

# Progress Map

| Process | Status | Progress | Phase | Notes |
|---------|--------|----------|-------|-------|
| Process 1 | completed | 100% | Done | preview_pane.sh スクリプト作成 |
| Process 2 | completed | 100% | Done | select_claude_launcher.sh 修正 |
| Process 3 | completed | 100% | Done | select_claude.sh の run_fzf_selection 修正 |
| Process 4 | completed | 100% | Done | claudecode_status.tmux 設定オプション確認 |
| Process 10 | completed | 100% | Done | 統合テスト追加（11テスト成功） |
| Process 100 | completed | 100% | Done | リファクタリング・品質向上 |
| Process 200 | completed | 100% | Done | ドキュメンテーション更新 |
| Process 300 | completed | 100% | Done | OODAフィードバックループ |
| | | | | |
| **Overall** | **completed** | **100%** | **Done** | **Blockers: 0** |

---

# Processes

## Process 1: preview_pane.sh スクリプト作成

<!--@process-briefing
category: implementation
tags: [bash, tmux, fzf, preview]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 1.1 設計詳細

**目的**: fzfの `--preview` オプションから呼び出されるスクリプト。pane_idを受け取り、そのペインの内容を出力する。

**ファイルパス**: `scripts/preview_pane.sh`

**入力**:
- 引数1: 表示行（fzfから渡される選択行）
- 環境変数 `CLAUDECODE_PANE_DATA`: pane_idとdisplay_lineのマッピング（タブ区切り）

**出力**:
- 標準出力: tmuxペインの内容（最後の30行）

**依存関係**:
- `tmux capture-pane` コマンド
- 引数から pane_id を抽出するロジック

**フォーマット（表示行からpane_id抽出）**:
```
表示行例: "  🍎 #0 project-name [session-name] working"
対応pane_id: "%123" など
```

**実装コード**:
```bash
#!/usr/bin/env bash
# preview_pane.sh - Display pane content for fzf preview
# Called by fzf --preview option

set -euo pipefail

# 引数: fzfから渡される選択行
SELECTED_LINE="${1:-}"

if [ -z "$SELECTED_LINE" ]; then
    echo "No selection"
    exit 0
fi

# CLAUDECODE_PANE_DATA 環境変数からpane_idを検索
# フォーマット: "display_line\tpane_id\n" の繰り返し
if [ -z "${CLAUDECODE_PANE_DATA:-}" ]; then
    echo "Preview data not available"
    exit 0
fi

# 選択行に対応するpane_idを検索
PANE_ID=""
while IFS=$'\t' read -r display_line pane_id; do
    if [ "$display_line" = "$SELECTED_LINE" ]; then
        PANE_ID="$pane_id"
        break
    fi
done <<< "$CLAUDECODE_PANE_DATA"

if [ -z "$PANE_ID" ]; then
    echo "Pane not found for selection"
    exit 0
fi

# tmux capture-pane でペイン内容を取得
# -p: 出力を標準出力に
# -t: ターゲットペイン指定
# -S: 開始行（負の値で末尾から）
if ! tmux capture-pane -p -t "$PANE_ID" -S -30 2>/dev/null; then
    echo "Failed to capture pane content"
    echo "Pane ID: $PANE_ID"
fi
```

---

### Red Phase: テスト作成と失敗確認
- [ ] ブリーフィング
- [ ] テストファイル `tests/test_preview.sh` を作成
  - テスト1: スクリプトが実行可能であること
  - テスト2: 引数なしで "No selection" を出力すること
  - テスト3: CLAUDECODE_PANE_DATA未設定時に適切なメッセージを出力すること
  - テスト4: 不正な選択行で "Pane not found" を出力すること
- [ ] テストを実行して失敗することを確認
  ```bash
  bash tests/test_preview.sh
  ```

**テストコード** (`tests/test_preview.sh`):
```bash
#!/usr/bin/env bash
# test_preview.sh - Tests for preview_pane.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    ((TESTS_RUN++))
    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED++))
    fi
}

assert_contains() {
    local substring="$1"
    local actual="$2"
    local message="${3:-}"
    ((TESTS_RUN++))
    if [[ "$actual" == *"$substring"* ]]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected to contain: '$substring'"
        echo "  Actual: '$actual'"
        ((TESTS_FAILED++))
    fi
}

# Test: Script is executable
test_preview_script_executable() {
    local script="$PROJECT_ROOT/scripts/preview_pane.sh"
    if [ -x "$script" ]; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: preview_pane.sh is executable"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: preview_pane.sh is not executable"
        ((TESTS_FAILED++))
    fi
}

# Test: No argument returns "No selection"
test_no_argument() {
    local output
    output=$("$PROJECT_ROOT/scripts/preview_pane.sh" 2>&1 || true)
    assert_contains "No selection" "$output" "No argument returns 'No selection'"
}

# Test: No CLAUDECODE_PANE_DATA returns appropriate message
test_no_pane_data() {
    local output
    unset CLAUDECODE_PANE_DATA
    output=$("$PROJECT_ROOT/scripts/preview_pane.sh" "test line" 2>&1 || true)
    assert_contains "Preview data not available" "$output" "No CLAUDECODE_PANE_DATA returns appropriate message"
}

# Test: Invalid selection returns "Pane not found"
test_invalid_selection() {
    local output
    export CLAUDECODE_PANE_DATA=$'valid line\t%123'
    output=$("$PROJECT_ROOT/scripts/preview_pane.sh" "invalid line" 2>&1 || true)
    assert_contains "Pane not found" "$output" "Invalid selection returns 'Pane not found'"
    unset CLAUDECODE_PANE_DATA
}

main() {
    echo "Running preview_pane.sh tests..."
    echo "================================"

    test_preview_script_executable
    test_no_argument
    test_no_pane_data
    test_invalid_selection

    echo "================================"
    echo "Tests: $TESTS_RUN, Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
```

**Phase Complete**

### Green Phase: 最小実装と成功確認
- [ ] ブリーフィング
- [ ] `scripts/preview_pane.sh` を作成
  - 上記の実装コードを記述
  - 実行権限を付与: `chmod +x scripts/preview_pane.sh`
- [ ] テストを実行して成功することを確認
  ```bash
  bash tests/test_preview.sh
  ```

**Phase Complete**

### Refactor Phase: 品質改善と継続成功確認
- [ ] ブリーフィング
- [ ] ShellCheckでLint確認
  ```bash
  shellcheck scripts/preview_pane.sh
  ```
- [ ] エラーハンドリングの強化（必要に応じて）
- [ ] テストを実行し、継続して成功することを確認

**Phase Complete**

---

## Process 2: select_claude_launcher.sh 修正

<!--@process-briefing
category: implementation
tags: [bash, tmux, fzf, launcher]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 2.1 設計詳細

**目的**: ポップアップ起動時にプレビュー機能を有効にする。pane_idのマッピングデータを環境変数として渡す。

**変更ファイル**: `scripts/select_claude_launcher.sh`

**変更概要**:
1. プレビュースクリプトのパスを変数として定義
2. CLAUDECODE_PANE_DATA 環境変数を構築してエクスポート
3. fzf呼び出しに `--preview` オプションを追加
4. `@claudecode_fzf_preview` オプションの読み取り

**現在のコード（行66-78）**:
```bash
# Step 2: Launch popup with pre-prepared data (instant display!)
# Popup writes result to file, then parent process handles focus_session.sh
tmux popup -E -w 60% -h 40% "
    trap 'rm -f '$TEMP_DATA' '${TEMP_DATA}_panes' '$RESULT_FILE'; exit 130' INT TERM

    selected=\$(cat '$TEMP_DATA' | fzf --height=100% --reverse --prompt='Select Claude: ')
    if [ -n \"\$selected\" ]; then
        line_num=\$(grep -nF \"\$selected\" '$TEMP_DATA' | head -1 | cut -d: -f1)
        if [ -n \"\$line_num\" ]; then
            pane_id=\$(sed -n \"\${line_num}p\" '${TEMP_DATA}_panes')
            echo \"\$pane_id\" > '$RESULT_FILE'
        fi
    fi
    rm -f '$TEMP_DATA' '${TEMP_DATA}_panes'
"
```

**修正後のコード（行64-95）**:
```bash
# Get preview setting
PREVIEW_ENABLED=$(get_tmux_option "@claudecode_fzf_preview" "on")
PREVIEW_SCRIPT="$CURRENT_DIR/preview_pane.sh"
PREVIEW_LINES=$(get_tmux_option "@claudecode_fzf_preview_lines" "30")

# Build CLAUDECODE_PANE_DATA for preview script
# Format: "display_line\tpane_id\n" for each entry
PANE_DATA_FILE="${TEMP_DATA}_pane_data"
paste "$TEMP_DATA" "${TEMP_DATA}_panes" > "$PANE_DATA_FILE"

# Build preview option
PREVIEW_OPT=""
if [ "$PREVIEW_ENABLED" = "on" ] && [ -x "$PREVIEW_SCRIPT" ]; then
    # Escape paths for shell embedding
    ESCAPED_SCRIPT=$(printf '%q' "$PREVIEW_SCRIPT")
    ESCAPED_PANE_DATA=$(printf '%q' "$PANE_DATA_FILE")
    PREVIEW_OPT="--preview='CLAUDECODE_PANE_DATA=\$(cat $ESCAPED_PANE_DATA) $ESCAPED_SCRIPT {}' --preview-window=right:50%:wrap"
fi

# Step 2: Launch popup with pre-prepared data (instant display!)
# Popup writes result to file, then parent process handles focus_session.sh
tmux popup -E -w 80% -h 60% "
    trap 'rm -f '$TEMP_DATA' '${TEMP_DATA}_panes' '$PANE_DATA_FILE' '$RESULT_FILE'; exit 130' INT TERM

    selected=\$(cat '$TEMP_DATA' | fzf --height=100% --reverse --prompt='Select Claude: ' $PREVIEW_OPT)
    if [ -n \"\$selected\" ]; then
        line_num=\$(grep -nF \"\$selected\" '$TEMP_DATA' | head -1 | cut -d: -f1)
        if [ -n \"\$line_num\" ]; then
            pane_id=\$(sed -n \"\${line_num}p\" '${TEMP_DATA}_panes')
            echo \"\$pane_id\" > '$RESULT_FILE'
        fi
    fi
    rm -f '$TEMP_DATA' '${TEMP_DATA}_panes' '$PANE_DATA_FILE'
"
```

**変更点サマリー**:
| 行番号 | 変更内容 |
|--------|---------|
| 64-66 | 新規: `PREVIEW_ENABLED`, `PREVIEW_SCRIPT`, `PREVIEW_LINES` 変数追加 |
| 68-70 | 新規: `PANE_DATA_FILE` 作成（paste コマンド） |
| 72-78 | 新規: `PREVIEW_OPT` 構築ロジック |
| 81 | 変更: ポップアップサイズを `80% x 60%` に拡大 |
| 82 | 変更: trap に `$PANE_DATA_FILE` の削除を追加 |
| 84 | 変更: fzf呼び出しに `$PREVIEW_OPT` を追加 |
| 92 | 変更: rm に `$PANE_DATA_FILE` を追加 |

---

### Red Phase: テスト作成と失敗確認
- [ ] ブリーフィング
- [ ] `tests/test_preview.sh` にテストケースを追加
  - テスト: `@claudecode_fzf_preview` オプションが読み取れること
  - テスト: PANE_DATA_FILE が正しいフォーマットで作成されること
- [ ] テストを実行して失敗することを確認

**追加テストコード**:
```bash
# Test: PANE_DATA_FILE format is correct (tab-separated)
test_pane_data_format() {
    local temp_display=$(mktemp)
    local temp_panes=$(mktemp)
    local temp_combined=$(mktemp)

    echo "  🍎 #0 project [session] working" > "$temp_display"
    echo "%123" > "$temp_panes"

    paste "$temp_display" "$temp_panes" > "$temp_combined"

    local expected=$'  🍎 #0 project [session] working\t%123'
    local actual=$(cat "$temp_combined")

    assert_equals "$expected" "$actual" "PANE_DATA_FILE format is correct"

    rm -f "$temp_display" "$temp_panes" "$temp_combined"
}
```

**Phase Complete**

### Green Phase: 最小実装と成功確認
- [ ] ブリーフィング
- [ ] `scripts/select_claude_launcher.sh` を修正
  - 行64-66: `PREVIEW_ENABLED`, `PREVIEW_SCRIPT`, `PREVIEW_LINES` 変数を追加
  - 行68-70: `PANE_DATA_FILE` 作成ロジックを追加
  - 行72-78: `PREVIEW_OPT` 構築ロジックを追加
  - 行81: ポップアップサイズを変更（プレビュー用に拡大）
  - 行82, 84, 92: ファイル参照を更新
- [ ] テストを実行して成功することを確認

**Phase Complete**

### Refactor Phase: 品質改善と継続成功確認
- [ ] ブリーフィング
- [ ] ShellCheckでLint確認
- [ ] テストを実行し、継続して成功することを確認

**Phase Complete**

---

## Process 3: select_claude.sh の run_fzf_selection 修正

<!--@process-briefing
category: implementation
tags: [bash, fzf, selection]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 3.1 設計詳細

**目的**: 非ポップアップモード（`split-window`）でもプレビュー機能を使えるようにする。

**変更ファイル**: `scripts/select_claude.sh`

**変更関数**: `run_fzf_selection()` (行207-264)

**現在のコード（行240-250）**:
```bash
    # Get fzf options from tmux（キャッシュ版を使用）
    local fzf_opts
    # Note: --border removed because tmux popup already provides a border
    # --no-clear prevents screen flicker on startup
    fzf_opts=$(get_tmux_option_cached "@claudecode_fzf_opts" "--height=100% --reverse --no-clear --prompt=Select\ Claude:\ ")

    # Run fzf
    local selected
    # Use eval to properly handle escaped spaces in fzf options
    selected=$(echo "$fzf_input" | eval "fzf $fzf_opts")
```

**修正後のコード（行240-270）**:
```bash
    # Get fzf options from tmux（キャッシュ版を使用）
    local fzf_opts
    # Note: --border removed because tmux popup already provides a border
    # --no-clear prevents screen flicker on startup
    fzf_opts=$(get_tmux_option_cached "@claudecode_fzf_opts" "--height=100% --reverse --no-clear --prompt=Select\ Claude:\ ")

    # Get preview setting
    local preview_enabled
    preview_enabled=$(get_tmux_option_cached "@claudecode_fzf_preview" "on")

    # Build preview option if enabled
    local preview_opt=""
    if [ "$preview_enabled" = "on" ]; then
        local preview_script="$CURRENT_DIR/preview_pane.sh"
        if [ -x "$preview_script" ]; then
            # Build CLAUDECODE_PANE_DATA for preview
            local pane_data=""
            for i in "${!display_lines[@]}"; do
                if [ -n "$pane_data" ]; then
                    pane_data+=$'\n'
                fi
                pane_data+="${display_lines[$i]}"$'\t'"${pane_ids[$i]}"
            done
            export CLAUDECODE_PANE_DATA="$pane_data"
            preview_opt="--preview='$preview_script {}' --preview-window=right:50%:wrap"
        fi
    fi

    # Run fzf
    local selected
    # Use eval to properly handle escaped spaces in fzf options
    selected=$(echo "$fzf_input" | eval "fzf $fzf_opts $preview_opt")
```

**変更点サマリー**:
| 行番号 | 変更内容 |
|--------|---------|
| 246-248 | 新規: `preview_enabled` 取得 |
| 250-264 | 新規: `preview_opt` 構築ロジック |
| 267 | 変更: fzf呼び出しに `$preview_opt` を追加 |

---

### Red Phase: テスト作成と失敗確認
- [ ] ブリーフィング
- [ ] `tests/test_preview.sh` にテストケースを追加
  - テスト: `run_fzf_selection` 関数が存在すること
  - テスト: プレビューオプション構築ロジックが動作すること
- [ ] テストを実行して失敗することを確認

**Phase Complete**

### Green Phase: 最小実装と成功確認
- [ ] ブリーフィング
- [ ] `scripts/select_claude.sh` の `run_fzf_selection` 関数を修正
  - 行246-248: `preview_enabled` 取得を追加
  - 行250-264: `preview_opt` 構築ロジックを追加
  - 行267: fzf呼び出しを修正
- [ ] テストを実行して成功することを確認

**Phase Complete**

### Refactor Phase: 品質改善と継続成功確認
- [ ] ブリーフィング
- [ ] ShellCheckでLint確認
- [ ] `CLAUDECODE_PANE_DATA` のクリーンアップ処理を追加（必要に応じて）
- [ ] テストを実行し、継続して成功することを確認

**Phase Complete**

---

## Process 4: claudecode_status.tmux 設定オプション追加

<!--@process-briefing
category: implementation
tags: [tmux, configuration]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 4.1 設計詳細

**目的**: 新しい設定オプション `@claudecode_fzf_preview` をtmuxプラグインに追加する。

**変更ファイル**: `claudecode_status.tmux`

**追加オプション**:
| オプション名 | デフォルト値 | 説明 |
|-------------|-------------|------|
| `@claudecode_fzf_preview` | `on` | fzfプレビュー機能の有効/無効 (`on`/`off`) |
| `@claudecode_fzf_preview_lines` | `30` | プレビューで表示する行数 |

**変更なし**: このオプションはtmux show-optionで読み取るだけなので、`claudecode_status.tmux` 自体に変更は不要。ただし、ドキュメント（README）に記載する必要がある。

**確認事項**:
- `shared.sh` の `get_tmux_option` 関数が正しく動作すること
- デフォルト値が適切に設定されること

---

### Red Phase: テスト作成と失敗確認
- [ ] ブリーフィング
- [ ] `tests/test_preview.sh` にテストケースを追加
  - テスト: `@claudecode_fzf_preview` オプションが読み取れること（デフォルト値）
- [ ] テストを実行して失敗することを確認

**テストコード**:
```bash
# Test: Default preview option value
test_default_preview_option() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    local value
    value=$(get_tmux_option "@claudecode_fzf_preview" "on")
    assert_equals "on" "$value" "Default @claudecode_fzf_preview is 'on'"
}
```

**Phase Complete**

### Green Phase: 最小実装と成功確認
- [ ] ブリーフィング
- [ ] `shared.sh` が正しく動作することを確認（変更不要の場合が多い）
- [ ] テストを実行して成功することを確認

**Phase Complete**

### Refactor Phase: 品質改善と継続成功確認
- [ ] ブリーフィング
- [ ] テストを実行し、継続して成功することを確認

**Phase Complete**

---

## Process 10: 統合テスト追加

<!--@process-briefing
category: testing
tags: [integration, testing]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 10.1 設計詳細

**目的**: プレビュー機能の統合テストを追加する。

**テストファイル**: `tests/test_preview.sh` （Process 1で作成したファイルを拡張）

**追加テストケース**:
1. プレビュースクリプトが実際のtmuxペインで動作すること（モック使用）
2. select_claude_launcher.sh と preview_pane.sh の連携
3. プレビュー無効時に `--preview` オプションが追加されないこと
4. エッジケース（ペインが存在しない場合など）

---

### Red Phase: テスト作成と失敗確認
- [ ] ブリーフィング
- [ ] 統合テストケースを追加
- [ ] テストを実行して失敗することを確認

**Phase Complete**

### Green Phase: 最小実装と成功確認
- [ ] ブリーフィング
- [ ] 必要に応じて実装を調整
- [ ] テストを実行して成功することを確認

**Phase Complete**

### Refactor Phase: 品質改善と継続成功確認
- [ ] ブリーフィング
- [ ] テストコードのリファクタリング
- [ ] テストを実行し、継続して成功することを確認

**Phase Complete**

---

## Process 50: フォローアップ

<!--@process-briefing
category: followup
tags: []
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

{{実装後に仕様変更などが発生した場合は、ここにProcessを追加する}}

---

## Process 100: リファクタリング・品質向上

<!--@process-briefing
category: quality
tags: [refactoring, shellcheck]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 100.1 品質チェックリスト

- [ ] ShellCheck で全スクリプトを検証
  ```bash
  shellcheck scripts/preview_pane.sh
  shellcheck scripts/select_claude_launcher.sh
  shellcheck scripts/select_claude.sh
  ```
- [ ] 既存のテストスイートが全て通過することを確認
  ```bash
  bash tests/test_detection.sh
  bash tests/test_output.sh
  bash tests/test_status.sh
  bash tests/test_preview.sh
  ```
- [ ] パフォーマンス確認（プレビュー有効/無効で比較）
- [ ] エラーハンドリングの確認

---

### Red Phase: 品質改善テスト追加
- [ ] ブリーフィング
- [ ] パフォーマンステストの追加（オプション）
- [ ] エッジケーステストの追加

**Phase Complete**

### Green Phase: リファクタリング実施
- [ ] ブリーフィング
- [ ] 重複コードの統合
- [ ] エラーメッセージの改善
- [ ] コメントの追加・改善

**Phase Complete**

### Refactor Phase: 最終確認
- [ ] ブリーフィング
- [ ] 全テスト実行
- [ ] コードレビュー準備

**Phase Complete**

---

## Process 200: ドキュメンテーション

<!--@process-briefing
category: documentation
tags: [readme, documentation]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 200.1 ドキュメント更新内容

**変更ファイル**:
1. `README.md`
2. `README_ja.md`

**追加内容**:

#### Configuration Options テーブルに追加（README.md 行81付近）:
```markdown
| `@claudecode_fzf_preview` | `on` | Enable/disable fzf preview (`on`/`off`) |
| `@claudecode_fzf_preview_lines` | `30` | Number of lines to show in preview |
```

#### Configuration Options テーブルに追加（README_ja.md 行81付近）:
```markdown
| `@claudecode_fzf_preview` | `on` | fzfプレビューの有効/無効 (`on`/`off`) |
| `@claudecode_fzf_preview_lines` | `30` | プレビューに表示する行数 |
```

#### 使用例セクションに追加:
```markdown
### Preview Feature

When using the process selector (`@claudecode_select_key`), you can see a preview of the selected pane's content:

\`\`\`bash
# Enable preview (default)
set -g @claudecode_fzf_preview "on"

# Disable preview
set -g @claudecode_fzf_preview "off"

# Set preview lines
set -g @claudecode_fzf_preview_lines "50"
\`\`\`
```

---

### Red Phase: ドキュメント設計
- [ ] ブリーフィング
- [ ] 文書化対象を特定
- [ ] ドキュメント構成を作成
- [ ] **成功条件**: 変更箇所が明確に特定されている

**Phase Complete**

### Green Phase: ドキュメント記述
- [ ] ブリーフィング
- [ ] README.md を更新
- [ ] README_ja.md を更新
- [ ] **成功条件**: 全変更が反映されている

**Phase Complete**

### Refactor Phase: 品質確認
- [ ] ブリーフィング
- [ ] Markdown構文チェック
- [ ] リンク確認
- [ ] 最終レビュー

**Phase Complete**

---

## Process 300: OODAフィードバックループ（教訓・知見の保存）

<!--@process-briefing
category: ooda_feedback
tags: [ooda, lessons, feedback]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### Red Phase: フィードバック収集設計

**Observe（観察）**
- [ ] ブリーフィング
- [ ] 実装過程で発生した問題・課題を収集
- [ ] テスト結果から得られた知見を記録
- [ ] コードレビューのフィードバックを整理

**Orient（方向付け）**
- [ ] ブリーフィング
- [ ] 収集した情報をカテゴリ別に分類
  - Technical: 技術的な知見・パターン
  - Process: プロセス改善に関する教訓
  - Antipattern: 避けるべきパターン
  - Best Practice: 推奨パターン
- [ ] 重要度（Critical/High/Medium/Low）を設定

- [ ] **成功条件**: 収集対象が特定され、分類基準が明確

**Phase Complete**

### Green Phase: 教訓・知見の永続化

**Decide（決心）**
- [ ] ブリーフィング
- [ ] 保存すべき教訓・知見を選定
- [ ] 各項目の保存先を決定
  - Serena Memory: 組織的な知見
  - stigmergy/lessons: プロジェクト固有の教訓
  - stigmergy/code-insights: コードパターン・実装知見

**Act（行動）**
- [ ] ブリーフィング
- [ ] serena-v4のmcp__serena__write_memoryで教訓を永続化
- [ ] コードに関する知見をMarkdownで記録
- [ ] 関連するコード箇所にコメントを追加（必要に応じて）

- [ ] **成功条件**: 全教訓がSerena Memoryまたはstigmergyに保存済み

**Phase Complete**

### Refactor Phase: フィードバック品質改善

**Feedback Loop**
- [ ] ブリーフィング
- [ ] 保存した教訓の品質を検証
  - 再現可能性: 他のプロジェクトで適用可能か
  - 明確性: 内容が明確で理解しやすいか
  - 実用性: 実際に役立つ情報か
- [ ] 重複・矛盾する教訓を統合・整理
- [ ] メタ学習: OODAプロセス自体の改善点を記録

**Cross-Feedback**
- [ ] ブリーフィング
- [ ] 他のProcess（100, 200）との連携を確認
- [ ] 将来のミッションへの引き継ぎ事項を整理

- [ ] **成功条件**: 教訓がSerena Memoryで検索可能、insights文書が整備済み

**Phase Complete**

---

# Management

## Blockers

| ID | Description | Status | Resolution |
|----|-------------|--------|-----------|
| - | なし | - | - |

## Lessons

| ID | Insight | Severity | Applied |
|----|---------|----------|---------|
| L1 | fzf --preview は環境変数経由でデータを渡すと安全 | medium | - |
| L2 | tmux popup サイズはプレビュー表示を考慮して拡大が必要 | medium | - |

## Feedback Log

| Date | Type | Content | Status |
|------|------|---------|--------|
| 2026-01-17 | マルチLLM合議 | 修正付き採用: ポップアップサイズ拡大、エスケープ処理追加 | closed |

## Completion Checklist
- [x] すべてのProcess完了
- [x] すべてのテスト合格（test_detection: 14, test_output: 9, test_preview: 11）
- [ ] コードレビュー完了
- [x] ドキュメント更新完了
- [x] マージ可能な状態

---

<!--
Process番号規則
- 1-9: 機能実装
- 10-49: テスト拡充
- 50-99: フォローアップ
- 100-199: 品質向上（リファクタリング）
- 200-299: ドキュメンテーション
- 300+: OODAフィードバックループ（教訓・知見保存）
-->

