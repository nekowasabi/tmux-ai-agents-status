# Mission Lessons: 絞り込み画面起動速度最適化 (2026-03-01)

**Mission**: PLAN.md P1-P300 TDD並列実装 - 絞り込み画面起動速度最適化
**Team**: executor-1 (EXECUTOR-1) + executor-2
**Result**: 全タスク完了 / 全135件テスト通過 / レグレッションなし

---

## L1: tmux popup 内シェルエスケープ

**Severity**: medium
**Category**: code-patterns

### 問題
`tmux popup -E "..."` のコマンド文字列内で変数を使用する場合、複数層のエスケープが必要になる。

### 詳細
```bash
# 誤り: 外側のダブルクォートと内側のシングルクォートが干渉
tmux popup -E "cat $file | fzf --preview='preview.sh $id'"

# 正しい: エスケープを明示的に多重化
tmux popup -E "
    pane_id=\$(echo \"\$selected\" | awk -F'\t' '{print \$NF}')
    echo \"\$key|\$pane_id\" > '$result_file'
"
```

### 教訓
- `\$` で変数展開を遅延（popup内のシェルで評価させる）
- シングルクォート文字列はpopup外で変数を展開し文字列として渡す
- `$(printf '%q' "$var")` でスクリプトパスを安全にエスケープ

---

## L2: bash 3.2 互換性（macOS対応）

**Severity**: medium
**Category**: architecture

### 問題
macOS はデフォルトで bash 3.2 を使用しており、`declare -A`（連想配列）が使えない。

### 詳細
```bash
# bash 4.x+ のみ（macOSでは使用不可）
declare -A emoji_map
emoji_map["running"]="🟢"

# bash 3.2 互換: case文で代替
get_status_emoji() {
    local status="$1"
    case "$status" in
        running)  echo "🟢" ;;
        waiting)  echo "🟡" ;;
        idle)     echo "🔵" ;;
        *)        echo "❓" ;;
    esac
}

# awk内のハッシュで代替（大量マッピング時）
awk 'BEGIN { map["running"]="🟢"; map["idle"]="🔵" } ...'
```

### 教訓
- tmuxプラグインはmacOS bash 3.2を前提に設計すること
- `EPOCHSECONDS` は bash 5.x のみ。`${EPOCHSECONDS:-$(date +%s)}` で互換性確保
- `[[ =~ ]]` は bash 3.2 でも使用可能

---

## L3: atomic write パターン

**Severity**: high
**Category**: code-patterns

### 問題
共有キャッシュファイルへの書き込み中に別プロセスが読み込むと、半端なデータを読む可能性がある。

### 詳細
```bash
# 危険: 直接書き込み（読み込みと競合する）
echo "$data" > /tmp/ai_agent_fzf_prerender

# 安全: tmpファイル経由のatomic move
local tmp_file
tmp_file=$(mktemp /tmp/ai_agent_fzf_prerender.XXXXXX)
echo "$data" > "$tmp_file"
mv -f "$tmp_file" /tmp/ai_agent_fzf_prerender
```

### 教訓
- `mv` は同一ファイルシステム内で原子的操作（inode置き換え）
- tmpファイルはターゲットと同じパーティションに作成する
- 書き込み失敗時は `|| rm -f "$tmp_file"` でクリーンアップ
- このパターンはNginxのgraceful reloadでも使われる標準手法

---

## L4: プリレンダリング高速化パターン

**Severity**: high
**Category**: architecture

### 問題
`select_claude_launcher.sh` 起動時に `shared.sh` + `session_tracker.sh` をsourceしてプロセス情報を収集すると ~300ms の遅延が発生していた。

### 解決策
**バックグラウンドで事前生成 → キー押下時はファイル読込のみ**

```
ai_agent_status.sh (2秒ごと実行)
  └─ write_fzf_prerender() → /tmp/ai_agent_fzf_prerender (TTL: 10s)

select_claude_launcher.sh (キー押下時)
  ├─ [fresh cache] ファイル読込のみ → fzf起動 (~30ms)
  └─ [stale/missing] レガシーフォールバック → source+収集 (~300ms)
```

### 測定結果
- Phase 1前: ~2000ms (画面真っ暗期間あり)
- Phase 1後: ~300ms (プリレンダリング活用)
- Phase 2後: ~30-50ms (tmux native menu使用時)

### 教訓
- ユーザーのアクション（キー押下）より前にデータ収集を完了させる設計が体感速度を大幅改善
- TTLは更新頻度（2秒）を考慮した10秒が適切
- フォールバックパスを常に維持することで堅牢性を確保

---

## L5: 絵文字マッピングの重複

**Severity**: low
**Category**: architecture

### 問題
`scripts/lib/cache_shared.sh` の `write_fzf_prerender()` と `scripts/select_claude.sh` に絵文字マッピング（running→🟢等）が重複している。

### 現状
```bash
# cache_shared.sh の write_fzf_prerender() 内
case "$status" in
    running)  status_emoji="🟢" ;;

# select_claude.sh 内も同様のマッピング
```

### 教訓
- 将来的に `scripts/lib/icons.sh` 等の共通ライブラリに抽出することを推奨
- 現時点では2箇所のみで重複管理コストは低いが、アイコン変更時に漏れが発生しやすい
- **未修正**: スコープ外として記録のみ（今回のミッションでは対応しない）

---

## ミッション全体の振り返り

### 成功要因
1. **TDD徹底**: Red→Green→Refactorを厳守したことで品質を保ちながら並列実装が可能だった
2. **フォールバック設計**: 全てのファストパスにレガシーフォールバックを用意し、壊れにくい設計を実現
3. **チーム並列作業**: executor-1がP1-P4を担当、executor-2がP5-P7とP10を担当して並列性を最大化

### 今後への提言
- `scripts/lib/icons.sh` で絵文字定数の一元管理を検討（L5）
- プリレンダリングのTTL(10秒)はユーザー設定可能にする価値あり
- `select_claude_menu.sh` のdisplay-menu UIにpreview機能を追加できればさらに改善余地あり
