---
mission_id: tmux-claude-summary-001
title: "Claude Code セッション要約・付加情報表示機能"
status: planning
progress: 0
phase: planning
tdd_mode: false
blockers: 0
created_at: "2026-01-22"
updated_at: "2026-01-22"
---

# Commander's Intent

## Purpose
- Claude Code セッション終了時に要約を事前生成し、Ctrl+S でメッセージ送信する際の補足情報として参照できるようにする
- オンデマンド要約の待ち時間を回避し、即座に要約を表示可能にする

## End State
- Stop/SessionEnd フックで要約が自動生成され、`/tmp/claudecode_summary_<pane_id>.txt` に保存される
- fzf セレクタで Ctrl+X を押すと、保存済み要約が popup で表示される
- popup 内でプロンプトを入力して、選択したセッションに送信できる

## Key Tasks
- summary_hook.sh の作成と hooks 登録
- show_summary.sh の作成
- select_claude_launcher.sh への Ctrl+X キーバインド追加
- settings.json への Stop/SessionEnd フック登録

## Constraints
- 既存の ooda hooks システムとは独立して動作すること
- tmux 外での実行時はエラーにならずスキップすること

## Restraints
- haiku モデルを使用して高速・低コストで要約を生成すること
- 既存の Ctrl+S 送信機能を破壊しないこと

---

# Context

## 概要
- Claude Code の返答完了時（Stop）やセッション終了時（SessionEnd）に、tmux ペインの内容を自動要約
- fzf プロセスセレクタで Ctrl+X を押すと、事前生成された要約を popup で表示
- 要約を参照しながら、その場でプロンプトを入力して送信可能

## 必須のルール
- 必ず `CLAUDE.md` を参照し、ルールを守ること
- 不明な点は AskUserQuestion で確認すること
- **シェルスクリプトの品質確保**
  - shellcheck でエラーがないこと
  - 実行権限（chmod +x）を付与すること
  - エラーハンドリングを適切に実装すること

## 開発のゴール
- Ctrl+S でメッセージ送信する際、セッションの現状を素早く把握できる補足情報を提供する
- 要約生成の待ち時間をなくし、即座に情報を参照可能にする

---

# References

| @ref | @target | @test |
|------|---------|-------|
| scripts/send_prompt.sh | scripts/show_summary.sh | 手動テスト |
| scripts/select_claude_launcher.sh (93-124行) | scripts/select_claude_launcher.sh | 手動テスト |
| ~/.claude/settings.json (125-148行) | ~/.claude/settings.json | 手動テスト |
| scripts/preview_pane.sh | ~/.claude/hooks/summary_hook.sh | 手動テスト |

---

# Progress Map

| Process | Status | Progress | Phase | Notes |
|---------|--------|----------|-------|-------|
| Process 1 | planning | ▯▯▯▯▯ 0% | - | summary_hook.sh 作成 |
| Process 2 | planning | ▯▯▯▯▯ 0% | - | show_summary.sh 作成 |
| Process 3 | planning | ▯▯▯▯▯ 0% | - | settings.json 修正 |
| Process 4 | planning | ▯▯▯▯▯ 0% | - | select_claude_launcher.sh 修正 |
| Process 10 | planning | ▯▯▯▯▯ 0% | - | 動作確認テスト |
| Process 100 | planning | ▯▯▯▯▯ 0% | - | エラーハンドリング強化 |
| Process 200 | planning | ▯▯▯▯▯ 0% | - | README 更新 |
| Process 300 | planning | ▯▯▯▯▯ 0% | - | OODA フィードバックループ |
| | | | | |
| **Overall** | **planning** | **▯▯▯▯▯ 0%** | **planning** | **Blockers: 0** |

---

# Processes

## Process 1: summary_hook.sh の作成

<!--@process-briefing
category: implementation
tags: [hooks, claude-cli, tmux]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 実装タスク

- [ ] `~/.claude/hooks/summary_hook.sh` を新規作成

**ファイル内容:**
```bash
#!/usr/bin/env bash
# summary_hook.sh - セッション要約を生成・保存
#
# 実行タイミング: Stop, SessionEnd
# 出力先: /tmp/claudecode_summary_<pane_id>.txt

set -euo pipefail

# tmux pane_id を取得（Claude Code は tmux 内で実行されている前提）
PANE_ID="${TMUX_PANE:-}"

# tmux 外で実行されている場合はスキップ
if [ -z "$PANE_ID" ]; then
    exit 0
fi

# 保存先（特殊文字をアンダースコアに変換）
SUMMARY_FILE="/tmp/claudecode_summary_${PANE_ID//[%:]/_}.txt"
CAPTURE_LINES=100

# ペイン内容を取得
content=$(tmux capture-pane -p -t "$PANE_ID" -S -"$CAPTURE_LINES" 2>/dev/null || true)

if [ -z "$content" ]; then
    exit 0
fi

# claude -p で要約（haiku モデル）
summary=$(echo "$content" | claude -p --model haiku "
以下はClaude Codeセッションの最近の出力です。
3-5行で簡潔に要約してください：
- 現在のタスク状況
- 最後に完了した作業
- 注意点やエラー（あれば）

出力（日本語）:
" 2>/dev/null || echo "要約生成に失敗しました")

# タイムスタンプ付きで保存
{
    echo "# Session Summary"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Pane: $PANE_ID"
    echo "---"
    echo "$summary"
} > "$SUMMARY_FILE"
```

- [ ] 実行権限を付与: `chmod +x ~/.claude/hooks/summary_hook.sh`

### 完了条件
- [ ] ファイルが作成されている
- [ ] 実行権限が付与されている
- [ ] shellcheck でエラーがない

✅ **Process Complete**

---

## Process 2: show_summary.sh の作成

<!--@process-briefing
category: implementation
tags: [tmux, popup, fzf]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 実装タスク

- [ ] `/home/takets/repos/tmux-claudecode-status/scripts/show_summary.sh` を新規作成

**ファイル内容:**
```bash
#!/usr/bin/env bash
# show_summary.sh - 保存済み要約を popup で表示
#
# 引数: pane_id
# 動作: 要約を表示し、オプションでプロンプトを送信

set -euo pipefail

PANE_ID="$1"
SUMMARY_FILE="/tmp/claudecode_summary_${PANE_ID//[%:]/_}.txt"
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 要約ファイルの存在確認
if [ ! -f "$SUMMARY_FILE" ]; then
    tmux display-message "No summary available for this session"
    exit 0
fi

# popup で表示（送信入力オプション付き）
# send_prompt.sh のパターンを参考に実装
tmux popup -E -w 80% -h 50% -T " Session Summary (Enter to send, ESC to close) " bash -c "
    cat '$SUMMARY_FILE'
    echo ''
    echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    echo 'Enter prompt to send (or press ESC to close):'
    printf '> '
    read -r input
    if [ -n \"\$input\" ]; then
        printf '%s' \"\$input\" | tmux load-buffer -
        tmux paste-buffer -t '$PANE_ID'
        tmux send-keys -t '$PANE_ID' Enter
    fi
"
```

- [ ] 実行権限を付与: `chmod +x scripts/show_summary.sh`

### 完了条件
- [ ] ファイルが作成されている
- [ ] 実行権限が付与されている
- [ ] shellcheck でエラーがない

✅ **Process Complete**

---

## Process 3: settings.json への hooks 登録

<!--@process-briefing
category: implementation
tags: [hooks, settings, json]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 実装タスク

- [ ] `~/.claude/settings.json` の Stop セクションに summary_hook を追加

**修正箇所: Stop セクション（125-138行目付近）**

現在の構造:
```json
"Stop": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "sh -c 'python3 $HOME/.claude/hooks/ooda_stop.py'"
      }
    ]
  },
  {
    "hooks": [
      {
        "type": "command",
        "command": "node $HOME/.claude/hooks/stop-send-notification.js"
      }
    ]
  }
]
```

追加する内容（配列に新しいオブジェクトを追加）:
```json
{
  "hooks": [
    {
      "type": "command",
      "command": "sh -c '$HOME/.claude/hooks/summary_hook.sh'"
    }
  ]
}
```

- [ ] `~/.claude/settings.json` の SessionEnd セクションに summary_hook を追加

**修正箇所: SessionEnd セクション（140-148行目付近）**

現在の構造:
```json
"SessionEnd": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "sh -c 'python3 $HOME/.claude/hooks/ooda_session_end.py'"
      }
    ]
  }
]
```

追加する内容（配列に新しいオブジェクトを追加）:
```json
{
  "hooks": [
    {
      "type": "command",
      "command": "sh -c '$HOME/.claude/hooks/summary_hook.sh'"
    }
  ]
}
```

### 完了条件
- [ ] Stop セクションに summary_hook が追加されている
- [ ] SessionEnd セクションに summary_hook が追加されている
- [ ] JSON が valid であること（jq で検証）

✅ **Process Complete**

---

## Process 4: select_claude_launcher.sh の修正

<!--@process-briefing
category: implementation
tags: [fzf, keybind, launcher]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 実装タスク

- [ ] fzf の --expect オプションに ctrl-x を追加

**修正箇所: 93-97行目**

変更前:
```bash
selected_output=$(cat '$TEMP_DATA' | fzf --height=100% --reverse \
    --prompt='Select Claude: ' \
    --header='Enter: Switch | Ctrl+S: Send Prompt' \
    --expect=ctrl-s \
    $PREVIEW_OPT)
```

変更後:
```bash
selected_output=$(cat '$TEMP_DATA' | fzf --height=100% --reverse \
    --prompt='Select Claude: ' \
    --header='Enter: Switch | Ctrl+S: Send | Ctrl+X: Summary' \
    --expect=ctrl-s,ctrl-x \
    $PREVIEW_OPT)
```

- [ ] キー処理のロジックに ctrl-x のケースを追加

**修正箇所: 118-124行目**

変更前:
```bash
if [ "$key" = "ctrl-s" ]; then
    "$CURRENT_DIR/send_prompt.sh" "$pane_id"
else
    "$CURRENT_DIR/focus_session.sh" "$pane_id"
fi
```

変更後:
```bash
if [ "$key" = "ctrl-s" ]; then
    "$CURRENT_DIR/send_prompt.sh" "$pane_id"
elif [ "$key" = "ctrl-x" ]; then
    "$CURRENT_DIR/show_summary.sh" "$pane_id"
else
    "$CURRENT_DIR/focus_session.sh" "$pane_id"
fi
```

### 完了条件
- [ ] --expect に ctrl-x が追加されている
- [ ] --header に Ctrl+X: Summary が表示される
- [ ] ctrl-x キーで show_summary.sh が呼び出される

✅ **Process Complete**

---

## Process 10: 動作確認テスト

<!--@process-briefing
category: testing
tags: [manual-test, integration]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### テスト項目

- [ ] **hooks 動作確認**
  ```bash
  # Claude Code で何か作業後
  ls -la /tmp/claudecode_summary_*.txt
  cat /tmp/claudecode_summary_*.txt
  ```
  - 要約ファイルが生成されていることを確認
  - 内容が適切な要約になっていることを確認

- [ ] **popup 表示確認**
  ```bash
  # fzf セレクタを起動し、Ctrl+X を押す
  ~/.tmux/plugins/tmux-claudecode-status/scripts/select_claude_launcher.sh
  ```
  - popup が表示されることを確認
  - 要約内容が表示されることを確認

- [ ] **送信機能確認**
  - popup でテキスト入力 → Enter
  - 対象ペインにテキストが送信されることを確認

- [ ] **エラーケース確認**
  - 要約ファイルが存在しない場合、適切なメッセージが表示されることを確認
  - tmux 外での実行時、エラーにならないことを確認

### 完了条件
- [ ] すべてのテスト項目が PASS

✅ **Process Complete**

---

## Process 100: エラーハンドリング強化

<!--@process-briefing
category: quality
tags: [error-handling, robustness]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### 品質向上タスク

- [ ] summary_hook.sh のエラーハンドリング確認
  - claude CLI が失敗した場合のフォールバック
  - tmux capture-pane が失敗した場合の処理

- [ ] show_summary.sh のエラーハンドリング確認
  - popup 内でのエラー処理
  - ファイル読み込み失敗時の処理

- [ ] shellcheck による静的解析
  ```bash
  shellcheck ~/.claude/hooks/summary_hook.sh
  shellcheck scripts/show_summary.sh
  ```

### 完了条件
- [ ] shellcheck でエラーがない
- [ ] エッジケースで適切にエラーハンドリングされる

✅ **Process Complete**

---

## Process 200: ドキュメンテーション

<!--@process-briefing
category: documentation
tags: [readme, docs]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### ドキュメント更新タスク

- [ ] README.md に Ctrl+X 機能を追加
  - 機能説明
  - 使用方法
  - 設定オプション（将来の拡張用）

- [ ] README_ja.md に同様の内容を追加

### 完了条件
- [ ] README.md が更新されている
- [ ] README_ja.md が更新されている

✅ **Process Complete**

---

## Process 300: OODA フィードバックループ

<!--@process-briefing
category: ooda_feedback
tags: [lessons, feedback]
-->

### Briefing (auto-generated)
**Related Lessons**: (auto-populated from stigmergy)
**Known Patterns**: (auto-populated from patterns)
**Watch Points**: (auto-populated from failure_cases)

---

### Observe（観察）
- [ ] 実装過程で発生した問題を記録
- [ ] 予想外の挙動を記録

### Orient（状況判断）
- [ ] 問題の根本原因を分析
- [ ] パターンを特定

### Decide（意思決定）
- [ ] 今後の改善策を決定
- [ ] 教訓を文書化

### Act（実行）
- [ ] 教訓を stigmergy に保存
- [ ] 次回の実装に活かせる形で記録

### 完了条件
- [ ] 教訓が記録されている
- [ ] 改善策が文書化されている

✅ **Process Complete**

---

# Management

## Blockers

| ID | Description | Status | Resolution |
|----|-------------|--------|-----------|
| - | なし | - | - |

## Lessons

| ID | Insight | Severity | Applied |
|----|---------|----------|---------|
| L1 | hooks から TMUX_PANE で pane_id を取得可能 | medium | ☐ |
| L2 | load-buffer + paste-buffer で複雑な入力に対応 | medium | ☐ |

## Feedback Log

| Date | Type | Content | Status |
|------|------|---------|--------|
| 2026-01-22 | requirement | 要件定義完了、実装計画作成 | closed |

## Completion Checklist
- [ ] すべての Process 完了
- [ ] すべてのテスト合格
- [ ] ドキュメント更新完了
- [ ] マージ可能な状態

---

<!--
Process番号ガイドライン:
- 1-9: 機能実装
- 10-49: テスト拡充
- 50-99: フォローアップ（仕様変更対応）
- 100-199: 品質向上
- 200-299: ドキュメンテーション
- 300+: OODAフィードバックループ
-->
