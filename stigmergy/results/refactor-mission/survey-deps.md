# Dependency & Configuration Survey Report
**Project**: tmux-claudecode-status  
**Mission**: refactor-mission  
**Scope**: External dependencies, environment variables, temp files, platform-specific code  
**Generated**: 2026-02-03

---

## EXECUTIVE SUMMARY

The project is a **tmux statusline plugin** written in pure Bash (Bash 3.2+ compatible) that monitors Claude Code processes and displays their activity status with terminal emojis. It has:
- **11 shell scripts** (scripts/ + tests/)
- **No compiled dependencies** - fully shell-based
- **Heavy reliance on**: tmux, ps/pgrep, awk, stat
- **Platform complexity**: macOS (primary), Linux, WSL with platform-specific detection logic

### Key Refactoring Targets
1. **Massive shared.sh** (1224 lines) - needs modularization
2. **Batch caching system** - complex awk/shell orchestration
3. **Terminal detection** - multiple fallback paths (3 methods on macOS + WSL)
4. **Process tree traversal** - repetitive ppid/comm lookups

---

## EXTERNAL COMMAND DEPENDENCIES

### Required System Commands

| Command | Usage | Locations | Frequency |
|---------|-------|-----------|-----------|
| **tmux** | Session/pane/client info, popup UI | All scripts | CRITICAL - on every invocation |
| **ps** | Process tree (pid/ppid/comm) | shared.sh, session_tracker.sh | CRITICAL - batch cache phase |
| **awk** | Data transformation, filtering | shared.sh (heavily), all others | CRITICAL - core data processing |
| **stat** | File modification times (mtime) | shared.sh, select_claude_launcher.sh | HIGH - activity detection |
| **grep** | Pattern matching, text filtering | All scripts, WSL detection | HIGH |
| **pgrep** | Process name search | session_tracker.sh (fallback) | MEDIUM - fallback only |
| **sed** | Text substitution | shared.sh (cache reads) | MEDIUM |
| **cut** | Field extraction | All scripts | MEDIUM |
| **head/tail** | Line selection | All scripts | MEDIUM |
| **printf** | String formatting | All scripts | MEDIUM |
| **basename** | Path extraction | select_claude_launcher.sh | LOW |
| **cat** | File reading | All scripts | MEDIUM |
| **sort** | Data sorting | claudecode_status.sh, shared.sh | MEDIUM |
| **tr** | Character translation | All scripts | MEDIUM |
| **date** | Timestamp fallback | shared.sh (when EPOCHSECONDS unavailable) | LOW |
| **mkdir/rm/cp** | Temp file management | shared.sh (batch init/cleanup) | MEDIUM |
| **xargs** | Batch processing | shared.sh (stat calls) | MEDIUM |
| **fzf** | Interactive selection UI | select_claude_launcher.sh | Required for launcher |
| **osascript** | macOS app activation | focus_session.sh | macOS only |
| **powershell.exe** | WSL environment detection | focus_session.sh | WSL only |

### Command Complexity Analysis

**High-Risk Dependencies** (used in performance-critical paths):
- **ps/awk combo** in `init_batch_cache()` - parallelized but complex
- **stat** with platform-specific flags (`-f` on macOS, `-c` on Linux)
- **awk** - 20+ multi-stage awk scripts for data transformation

---

## ENVIRONMENT VARIABLES

### Project-Specific Variables (@claudecode_* tmux options)

Stored in tmux global scope (`tmux set-option -g`):

| Variable | Type | Default | Purpose | Sources |
|----------|------|---------|---------|---------|
| `@claudecode_working_dot` | emoji | 🤖 | Icon for active Claude Code | claudecode_status.sh |
| `@claudecode_idle_dot` | emoji | 🔔 | Icon for idle Claude Code | claudecode_status.sh |
| `@claudecode_working_color` | tmux-color | (none) | Color for working status | claudecode_status.sh |
| `@claudecode_idle_color` | tmux-color | (none) | Color for idle status | claudecode_status.sh |
| `@claudecode_separator` | string | (space) | Between session entries | claudecode_status.sh |
| `@claudecode_left_sep` | string | (empty) | Left border | claudecode_status.sh |
| `@claudecode_right_sep` | string | (empty) | Right border | claudecode_status.sh |
| `@claudecode_show_terminal` | on/off | on | Display terminal emoji | claudecode_status.sh |
| `@claudecode_show_pane` | on/off | on | Display pane number | claudecode_status.sh |
| `@claudecode_working_threshold` | seconds | 30 | Activity detection window | claudecode_status.sh, session_tracker.sh |
| `@claudecode_terminal_iterm` | emoji | 🍎 | iTerm2 identifier | shared.sh terminal detection |
| `@claudecode_terminal_wezterm` | emoji | ⚡ | WezTerm identifier | shared.sh terminal detection |
| `@claudecode_terminal_ghostty` | emoji | 👻 | Ghostty identifier | shared.sh terminal detection |
| `@claudecode_terminal_windows` | emoji | 🪟 | Windows Terminal identifier | shared.sh terminal detection |
| `@claudecode_terminal_vscode` | emoji | 📝 | VS Code identifier | shared.sh terminal detection |
| `@claudecode_terminal_alacritty` | emoji | 🔲 | Alacritty identifier | shared.sh terminal detection |
| `@claudecode_terminal_unknown` | emoji | ❓ | Unknown terminal identifier | shared.sh terminal detection |
| `@claudecode_fzf_preview` | on/off | on | Enable fzf preview pane | select_claude_launcher.sh |
| `@claudecode_fzf_preview_position` | string | down | fzf preview placement | select_claude_launcher.sh |
| `@claudecode_fzf_preview_size` | string | 50% | fzf preview window size | select_claude_launcher.sh |

### Runtime Environment Variables

| Variable | Source | Usage |
|----------|--------|-------|
| `CLAUDECODE_WORKING_THRESHOLD` | Exported by claudecode_status.sh | Threshold for activity detection |
| `CLAUDECODE_CPU_THRESHOLD` | session_tracker.sh (unused in current code) | CPU threshold (not implemented) |
| `EPOCHSECONDS` | Bash 4.0+ built-in | High-precision timestamp (fallback to `date +%s`) |
| `TMPDIR` | System (not explicitly used) | Implicit temp directory |
| `WT_SESSION` | Windows Terminal (WSL) | Terminal detection in WSL |
| `VSCODE_IPC_HOOK_CLI` | VS Code (WSL) | Terminal detection in WSL |
| `ALACRITTY_SOCKET` / `ALACRITTY_LOG` | Alacritty (WSL) | Terminal detection in WSL |
| `TERM_PROGRAM` | Terminal app (Linux) | Terminal identification |
| `FAST_MODE` | shared.sh internal | Lightweight mode for select_claude.sh |

---

## TEMPORARY FILE SYSTEM

### Cache Structure

All temp files use **PID suffix** (`$$`) for process isolation:

```
/tmp/
├── claudecode_status_cache_<PID>     # Main status output (2-sec TTL)
├── claudecode_result_<PID>            # Launcher selection result
├── claudecode_fzf_<PID>               # fzf display data
├── claudecode_fzf_<PID>_panes         # Pane ID mappings for fzf
├── claudecode_fzf_<PID>_pane_data     # Combined display+pane info
├── claudecode_shared_process_cache    # Global shared cache (5-sec TTL, no PID)
└── claudecode_batch_<PID>/            # Batch processing working directory
    ├── ps                             # Process tree
    ├── panes                          # Pane info from tmux list-panes
    ├── term                           # Terminal detection cache
    ├── pidmap                         # PID->pane_id mapping
    ├── opts                           # tmux options
    ├── clients                        # tmux client info
    └── ttystat                        # TTY mtime stats
```

### Cache Lifecycle

| File | TTL | Writer | Reader | Strategy |
|------|-----|--------|--------|----------|
| claudecode_status_cache_$$ | 2s | claudecode_status.sh | tmux status-right | Prevents rapid re-querying |
| claudecode_shared_process_cache | 5s | claudecode_status.sh | select_claude_launcher.sh | Cross-script data sharing |
| claudecode_batch_$$/* | Session | init_batch_cache() | Batch functions | Bulk data collection |
| claudecode_fzf_$$ | Session | select_claude_launcher.sh | fzf popup | UI display data |

**Cleanup**: 
- Batch cache deleted on script exit (trap cleanup_batch_cache EXIT)
- Temp files cleaned by popup cleanup trap
- Shared cache not auto-deleted (relies on age check)

---

## PLATFORM-SPECIFIC DEPENDENCIES

### macOS (Primary Development Platform)

**Terminal Detection** (focus_session.sh, get_terminal_emoji):
- Uses **parent process traversal** via `ps -p <pid> -o comm=`
- Detects: iTerm2, Terminal.app, WezTerm, Ghostty
- Fallback: Direct `ps` inspection of parent chain up to 20 levels deep
- **osascript** for app activation: `osascript -e 'tell app "name" to activate'`

**File Stats**:
- `stat -f "%m"` for mtime (macOS format)
- `stat -f "%N %m"` for name+mtime (batch TTY stat)

**Process Commands**:
- `ps -eo pid,ppid,comm` for process tree
- `ps -o ppid= -p <pid>` for single parent lookup

### Linux (Standard Environment)

**File Stats**:
- `stat -c %Y` for mtime
- `stat -c "%N %Y"` for name+mtime

**WSL-Specific Logic** (focus_session.sh, shared.sh):
- Detects via: `grep -qi microsoft /proc/version`
- Terminal detection from `/proc/<pid>/environ`:
  - `WT_SESSION` → Windows Terminal
  - `TERM_PROGRAM=WezTerm` → WezTerm
  - `VSCODE_IPC_HOOK_CLI` → VS Code
  - `ALACRITTY_*` → Alacritty
- Requires **powershell.exe** availability on Windows side

### Cross-Platform Functions

| Function | macOS | Linux | WSL |
|----------|-------|-------|-----|
| `get_file_mtime()` | stat -f %m | stat -c %Y | stat -c %Y |
| `get_current_timestamp()` | EPOCHSECONDS or date +%s | EPOCHSECONDS or date +%s | (same) |
| `get_terminal_emoji()` | ps parent traversal (3 methods) | TERM_PROGRAM env var | /proc/environ + parents |
| Session focus | osascript -e | N/A | powershell.exe -Command |

---

## DATA FLOW & CRITICAL PATHS

### Flow 1: Statusline Update (claudecode_status.sh)

```
1. Check local cache (2s TTL) → cached output
2. Load shared batch cache from claudecode_status.sh before
3. Call get_session_details() → queries all Claude processes
   ├─ get_all_claude_info_batch() → gets "pid|pane_id|session|window|tty|terminal|cwd"
   ├─ Caches in shared cache file (5s TTL)
   └─ Used by select_claude_launcher.sh
4. Parse & sort entries (by status, terminal, pane)
5. Format output "emoji #window project_name ●"
6. Cache locally (2s) & output
```

### Flow 2: Launcher (select_claude_launcher.sh)

```
1. Load/init batch cache (if not fresh)
2. Get process data (reuse from shared cache if available)
3. Format fzf display lines (emoji + project + status)
4. Launch fzf popup with preview
5. On selection:
   ├─ ctrl-s → send_prompt.sh (send command)
   └─ enter → focus_session.sh (activate tmux session)
```

### Flow 3: Process Detection (init_batch_cache)

```
Parallel phase:
├─ ps -eo pid,ppid,comm > BATCH_PROCESS_TREE_FILE &
├─ tmux list-panes -a > BATCH_PANE_INFO_FILE &
├─ tmux show-options -g @claudecode* > BATCH_TMUX_OPTIONS_FILE &
└─ tmux list-clients > BATCH_CLIENTS_CACHE_FILE &

Post-processing phase (parallel):
├─ _build_pid_pane_map() → awk: find claude procs, match to pane_ids
├─ _prebuild_terminal_cache() → awk: detect terminal from parent procs
└─ stat all TTYs from panes
```

---

## CODE ORGANIZATION ISSUES (Refactoring Targets)

### 1. **shared.sh is Monolithic** (1224 lines)
- Batch cache logic (300+ lines)
- Terminal detection (250+ lines)
- Process tree functions (100+ lines)
- tmux option wrappers (150+ lines)
- **Opportunity**: Split into modules:
  - `batch-cache.sh` - init, cleanup, cache file ops
  - `terminal-detection.sh` - all emoji/terminal logic
  - `tmux-wrapper.sh` - option/command wrappers
  - `process-tree.sh` - ps, pgrep, ppid functions

### 2. **awk Scripts Embedded in Shell Functions**
- 20+ awk programs scattered throughout
- Some 40+ lines with complex state machines
- **Opportunity**: Extract to separate `.awk` files or consolidate

### 3. **Repeated Process Tree Traversal**
- `get_terminal_emoji()` traverses parent chain (3 methods per platform)
- `get_pane_info_for_pid()` does similar traversal
- `_build_pid_pane_map()` predates all
- **Opportunity**: Single unified tree function with memoization

### 4. **Platform Detection Scattered**
- `grep -qi microsoft /proc/version` appears 3+ times
- `[[ "$(get_os)" == "Darwin" ]]` throughout
- **Opportunity**: Centralized platform module (`platform.sh`)

### 5. **Batch Cache vs Direct Function Duality**
- Every function has `func()` and `func_cached()` variants
- 50+ lines of "if BATCH_INITIALIZED check then use cache else call original"
- **Opportunity**: Transparent caching wrapper

---

## DEPENDENCY MATRIX

### Scripts by External Dependency Count

```
shared.sh             ████████████████████ (25+ external cmds, 20+ awk scripts)
session_tracker.sh    ████████ (ps, pgrep, tmux, awk, stat)
claudecode_status.sh  ████████ (tmux, awk, sort, cut, printf)
select_claude_launcher.sh ████ (tmux, fzf, stat, awk, basename, cat)
focus_session.sh      ████ (tmux, osascript, powershell.exe, grep)
preview_pane.sh       ███ (tmux, head, tail, cat, printf)
send_prompt.sh        ██ (tmux, printf, read)
select_claude.sh      ███ (shared.sh, tmux, awk, grep)
test_*.sh             ██ (bash, source, test assertions)
```

### Import Dependencies

```
claudecode_status.sh
├── shared.sh ✓
└── session_tracker.sh ✓
    └── shared.sh ✓

select_claude_launcher.sh
├── shared.sh ✓
└── select_claude.sh (indirectly via launcher logic)

focus_session.sh
└── shared.sh ✓

preview_pane.sh
└── shared.sh ✓

send_prompt.sh
└── (standalone)

select_claude.sh
└── shared.sh ✓

Tests
└── scripts/*.sh
```

---

## BASH VERSION & COMPATIBILITY

**Target**: Bash 3.2+ (macOS compatibility)

**Features Used**:
- Local variables ✓ (Bash 2.0+)
- Arrays ✓ (Bash 3.0+)
- Parameter expansion `${var%%pattern}` ✓ (Bash 2.0+)
- Process substitution `< <()` ✓ (Bash 3.0+)
- `trap` cleanup ✓ (Bash 2.0+)
- `EPOCHSECONDS` (Bash 4.0+) **with fallback to `date +%s`** ✓

**NOT Used** (good):
- `[[` conditional (Bash 3.1+) - uses `[` for portability
- `declare -n` (Bash 4.3+ nameref)
- `mapfile` / `readarray` (Bash 4.0+)

---

## RISK ASSESSMENT

### HIGH RISK
1. **tmux unavailable** → Entire plugin fails (no fallback)
2. **stat platform differences** → Needs explicit testing on Linux
3. **ps format inconsistency** → Different header names across systems
4. **awk version mismatch** → Complex awk scripts may break on BSD awk
5. **/tmp space exhaustion** → No size checks on batch files

### MEDIUM RISK
1. **Parent process chain depth** (hardcoded max 10-20) → May miss deeply nested terminals
2. **Shared cache contention** → Non-PID file may have race conditions in concurrent tmux
3. **WSL path detection** → Depends on `/proc/version` which varies

### LOW RISK
1. **Emoji rendering** → User configurable, falls back to unknown emoji
2. **Temp file cleanup** → Uses trap, generally safe
3. **fzf availability** → Only used in launcher, shows error message

---

## RECOMMENDATIONS FOR REFACTORING

### Phase 1: Modularize (Immediate)
1. Extract `batch-cache.sh` (300 lines from shared.sh)
2. Extract `terminal-detection.sh` (250 lines)
3. Create `platform.sh` for OS detection
4. Create `.awk/` directory for awk scripts

### Phase 2: Consolidate (Medium-term)
1. Unified process tree traversal function
2. Transparent caching layer (remove _cached duplication)
3. Single stat/mtime function with platform handling
4. Deduplicate terminal detection logic (3 methods → 1 fallback chain)

### Phase 3: Robustness (Long-term)
1. Add timeout handling for tmux commands
2. Add temp file size limits
3. Better error messages for missing dependencies
4. Automated platform detection in build/install

---

## FILES MODIFIED / CREATED

- **Primary data flow**: shared.sh (1224 lines) → needs split
- **Batch logic**: `init_batch_cache()` (300 lines)
- **Terminal detection**: `get_terminal_emoji()` (200 lines) + variants
- **Test coverage**: `tests/test_*.sh` (detect, output, status, preview)

---

**End of Report**
