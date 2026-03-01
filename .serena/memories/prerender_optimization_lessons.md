# Prerender Optimization Implementation Lessons
# Recorded: 2026-03-01 (PLAN.md P1-P300 TDD parallel implementation)

## Overview
fzf セレクター画面の起動速度最適化 (~2s → ~100ms) を TDD で実装した際の教訓。

---

## 1. Shell Escaping (tmux popup内)

**問題**: tmux popup の二重引用符文字列内でのシェルエスケープが複雑。
**解決策**:
- 外側: `tmux popup -E ... "..."` (double-quote)
- 内側変数: `\$var` でエスケープ
- ファイルパス: 変数展開前にパスを確定して直接展開 `'$FILE_PATH'`
- fzf テンプレート `{2}` は特別なエスケープ不要（bash の brace expansion と衝突しない）

```bash
# 正しいパターン
tmux popup -E -w 80% -h 60% "
    selected=\$(cat '$PRERENDER_FILE' | fzf --with-nth=1 --delimiter='\t' ...)
    pane_id=\$(echo \"\$selected\" | awk -F'\t' '{print \$NF}')
"
```

---

## 2. macOS bash 3.2 互換性

**禁止事項**:
- `declare -A` (連想配列): bash 4.0+ のみ
- `[[` の一部拡張構文は可（bash 3.2 でも動作）

**代替パターン**:
- 連想配列 → awk 内ハッシュ (`pane_status[key] = value`)
- 絵文字マッピング → if-elif-else チェーンまたは case 文
- `<<<` ヒアストリング → bash 3.2 でも使用可能

```bash
# NG (bash 4.0+)
declare -A emoji_map
emoji_map["iTerm2"]="🍎"

# OK (bash 3.2 互換)
case "$terminal" in
    iTerm2|Terminal) emoji="🍎" ;;
    WezTerm) emoji="⚡" ;;
esac
```

---

## 3. Atomic Write パターン

**目的**: 並行プロセスがファイル読み取り中に破損した状態を読まないよう保護。

```bash
# 正しいパターン: tmp → mv -f
write_to_file() {
    local output="$1" tmp="${output}.tmp"
    generate_content > "$tmp" 2>/dev/null
    mv -f "$tmp" "$output" 2>/dev/null
}
```

**注意**: `mv -f` は同一ファイルシステム内では atomic（Linux/macOS 両対応）。

---

## 4. awk の getline でファイルを連想配列に読み込むパターン

状態キャッシュ (`pane_id|status`) を bash ループではなく awk の BEGIN で読む方が高速。

```awk
BEGIN {
    while ((getline line < status_cache) > 0) {
        n = index(line, "|")
        key = substr(line, 1, n-1)
        val = substr(line, n+1)
        status[key] = val
    }
    close(status_cache)
}
```

---

## 5. fzf --with-nth + --delimiter でデータ隠蔽

```bash
# display_string\tpane_id 形式のファイルを fzf に渡す
# --with-nth=1: 表示は1列目のみ、2列目(pane_id)は非表示
# {2}: preview や --expect の出力で2列目を参照可能
fzf --with-nth=1 --delimiter='\t' \
    --preview='preview_pane.sh {} {2}'
```

これにより AI_AGENT_PANE_DATA 環境変数経由のデータ渡しが不要になる。

---

## 6. TDD での shell スクリプト検証パターン

コード構造テスト（grep/awk による静的解析）が有効:

```bash
# 関数が存在するか
declare -f my_function > /dev/null 2>&1 || fail

# ファイル内に特定パターンがあるか
grep -q 'PANE_ID_ARG' "$script_file" || fail

# 行数が一定以下か（リファクタ完了確認）
[ $(wc -l < "$script") -le 80 ] || fail
```

---

## 7. TTL ベースのキャッシュ鮮度チェック (cross-platform)

```bash
if [[ "$(uname)" == "Darwin" ]]; then
    _mtime=$(stat -f %m "$file" 2>/dev/null || echo 0)
else
    _mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
fi
_age=$(( _now - _mtime ))
[ "$_age" -le "$TTL" ] && use_cache=1
```

---

## 8. 重複の既知問題

絵文字マッピング (iTerm2→🍎 等) が以下2箇所に重複:
- `scripts/lib/cache_shared.sh` (write_fzf_prerender 内 awk)
- `scripts/select_claude.sh` (generate_process_list 内 awk)

将来タスク: `lib/` に共通関数を追加して1箇所に集約。
`write_fzf_prerender` をレンダリングの単一ソースとして確立するアーキテクチャが望ましい。
