# Refactor Execution Plan: tmux-claudecode-status

## Mission: Decompose monolithic shared.sh into cohesive modules

**Complexity**: 90 (high)
**Estimated Effort**: high
**Risk Level**: high (shared.sh is sourced by 5+ scripts)

---

## 1. Current State Analysis

### File Inventory (8 scripts, 4 tests)

| File | Lines | Functions | Role | Depends On |
|------|-------|-----------|------|------------|
| `scripts/shared.sh` | 1224 | 32 | Monolithic utility hub | (none) |
| `scripts/session_tracker.sh` | 687 | 21 | Status detection | shared.sh |
| `scripts/claudecode_status.sh` | 190 | 1 (main) | Statusline output | shared.sh, session_tracker.sh |
| `scripts/select_claude.sh` | 364 | 4 | fzf selection UI | shared.sh |
| `scripts/select_claude_launcher.sh` | 151 | 0 (script) | Popup data prep | shared.sh |
| `scripts/focus_session.sh` | 398 | 8 | Terminal focus/switch | shared.sh |
| `scripts/send_prompt.sh` | 21 | 0 (script) | Prompt input | (standalone) |
| `scripts/preview_pane.sh` | 49 | 0 (script) | fzf preview | (standalone) |
| `claudecode_status.tmux` | 114 | 3 | TPM entry point | shared.sh |

### Identified Concerns in shared.sh (6 cohesion clusters)

| Cluster | Lines | Functions | Description |
|---------|-------|-----------|-------------|
| Platform Utils | ~30 | 3 | `get_os`, `get_file_mtime`, `get_current_timestamp` |
| tmux Options | ~90 | 4 | `get_tmux_option`, `set_tmux_option`, `*_cached`, `*_bulk` |
| Terminal Detection | ~300 | 8 | `_detect_terminal_from_pname`, `get_terminal_emoji*`, WSL functions |
| Shared Cache | ~110 | 7 | `write_shared_cache`, `read_shared_cache*`, inter-process comm |
| Batch Cache | ~350 | 18 | `init_batch_cache`, all `get_*_cached` helpers, `_build_*` |
| Sorting/Pane Helpers | ~40 | 4 | `get_terminal_priority`, `get_status_priority`, `get_pane_index*` |

### Consumer Dependency Map (source graph)

```
claudecode_status.tmux ──→ shared.sh
claudecode_status.sh   ──→ shared.sh ──→ session_tracker.sh
session_tracker.sh     ──→ shared.sh
select_claude.sh       ──→ shared.sh
select_claude_launcher ──→ shared.sh
focus_session.sh       ──→ shared.sh
send_prompt.sh         ──→ (none)
preview_pane.sh        ──→ (none)
```

### Data Contracts (MUST PRESERVE)

| Contract | Format | Producers | Consumers |
|----------|--------|-----------|-----------|
| Process info | `pid\|pane_id\|session\|window\|tty\|terminal\|cwd` | `get_all_claude_info_batch` | select_claude.sh, launcher, shared cache |
| Session details | `terminal_emoji:pane_index:project_name:status\|...` | `get_session_details` | claudecode_status.sh |
| Shared cache file | Line1=timestamp, Line2=tmux_opts(TAB), Line3=tty_stat(;), Line4+=process_info | `write_shared_cache` | `read_shared_cache*`, select_claude.sh |
| Session states | `working:N,idle:M` | `get_session_states` | tests, legacy |
| Batch pane info | TAB-delimited: `pane_id\tpane_pid\tsession\twindow\tpane_idx\ttty\tcwd` | `init_batch_cache` | batch getters |

### Cache Layers (4-layer architecture)

```
Layer 1: SHARED_CACHE (5s TTL, /tmp/claudecode_shared_process_cache)
         Producer: claudecode_status.sh → write_shared_cache()
         Consumer: select_claude.sh → read_shared_cache_all()

Layer 2: BATCH_CACHE (process-lifetime, /tmp/claudecode_batch_$$/)
         Producer/Consumer: init_batch_cache() within single script execution

Layer 3: TTY_STAT (embedded in shared cache or batch-collected)
         stat -f "%N %m" on pane TTY devices

Layer 4: TERMINAL_CACHE (per-session, within batch dir)
         Detected terminal name per tmux session
```

---

## 2. Target Architecture

### New Module Structure

```
scripts/
  lib/
    platform.sh        # 3 functions:  get_os, get_file_mtime, get_current_timestamp
    tmux_options.sh    # 4 functions:  get/set_tmux_option, *_cached, *_bulk
    terminal.sh        # 10 functions: detection, emoji mapping, WSL support
    cache_shared.sh    # 7 functions:  inter-process shared cache
    cache_batch.sh     # 18 functions: process-lifetime batch cache
    pane_utils.sh      # 4 functions:  pane index, sorting helpers
  shared.sh            # FACADE: sources all lib/* modules (backward compat)
  session_tracker.sh   # (unchanged source path, gains precision sourcing)
  claudecode_status.sh # (unchanged)
  select_claude.sh     # (unchanged)
  select_claude_launcher.sh # (unchanged)
  focus_session.sh     # (refactored: use lib/terminal.sh, remove duplication)
  send_prompt.sh       # (unchanged)
  preview_pane.sh      # (unchanged)
```

### Module Dependency Graph

```
platform.sh ←── tmux_options.sh (independent, no deps)
    ↑                ↑
    |                |
    ├── terminal.sh ─┘ (depends: platform + tmux_options)
    |        ↑
    ├── cache_shared.sh (depends: platform)
    |
    └── cache_batch.sh (depends: platform + terminal + tmux_options)
             ↑
        pane_utils.sh (depends: tmux_options + cache_batch)
```

---

## 3. Function Signature Preservation Rules

### ABSOLUTE: No Signature Changes

Every public function extracted from shared.sh MUST retain:
1. **Identical function name** - no renaming
2. **Identical parameter order and count** - `$1`, `$2`, etc.
3. **Identical return value format** - stdout output, exit codes
4. **Identical side effects** - global variable writes (e.g., `_SHARED_CACHE_OPTIONS`)
5. **Identical global variable names** - `BATCH_INITIALIZED`, `SHARED_CACHE_FILE`, etc.

### Global Variables That MUST Remain Accessible

```bash
# From platform.sh
_CACHED_OS
FAST_MODE

# From cache_shared.sh
SHARED_CACHE_FILE
SHARED_CACHE_TTL

# From cache_batch.sh
BATCH_PROCESS_TREE_FILE
BATCH_PANE_INFO_FILE
BATCH_TERMINAL_CACHE_FILE
BATCH_TMUX_OPTIONS_FILE
BATCH_CLIENTS_CACHE_FILE
BATCH_TTY_STAT_FILE
BATCH_PID_PANE_MAP_FILE
BATCH_INITIALIZED
```

### Source Guard Pattern (for each lib module)

```bash
# Prevent double-sourcing
if [ -n "${__LIB_PLATFORM_LOADED:-}" ]; then return 0; fi
__LIB_PLATFORM_LOADED=1
```

---

## 4. Phase-by-Phase Execution Plan

### Phase 0: Foundation Setup
**Effort**: trivial | **Risk**: none | **Duration**: 15min

**Tasks**:
- P0-T1: Create `scripts/lib/` directory
- P0-T2: Create shared test helpers file `tests/test_helpers.sh` extracting common assert functions

**Files Modified**: (new files only)
- `scripts/lib/` (new directory)
- `tests/test_helpers.sh` (new, extract from 4 test files)

**Verification**: `ls scripts/lib/` exists

---

### Phase 1: Extract platform.sh
**Effort**: simple | **Risk**: low | **Duration**: 30min
**Dependencies**: Phase 0

**Tasks**:
- P1-T1: Create `scripts/lib/platform.sh` with source guard
- P1-T2: Move `_CACHED_OS`, `FAST_MODE`, `get_os()`, `get_file_mtime()`, `get_current_timestamp()` from shared.sh
- P1-T3: Remove moved code from shared.sh, add `source "$SHARED_LIB_DIR/platform.sh"` at top

**Files Modified**:
- `scripts/lib/platform.sh` (new, ~40 lines)
- `scripts/shared.sh` (remove 3 functions, add source line)

**Verification Checkpoint**:
```bash
# Unit: platform functions work standalone
source scripts/lib/platform.sh && get_os && get_current_timestamp
# Integration: all existing tests pass
bash tests/test_detection.sh
```

---

### Phase 2: Extract tmux_options.sh
**Effort**: simple | **Risk**: low | **Duration**: 30min
**Dependencies**: Phase 0

**Tasks**:
- P2-T1: Create `scripts/lib/tmux_options.sh` with source guard
- P2-T2: Move `get_tmux_option()`, `set_tmux_option()`, `get_tmux_option_cached()`, `get_tmux_options_bulk()` from shared.sh
- P2-T3: Remove moved code from shared.sh, add source line

**Files Modified**:
- `scripts/lib/tmux_options.sh` (new, ~100 lines)
- `scripts/shared.sh` (remove 4 functions, add source line)

**Verification Checkpoint**:
```bash
source scripts/lib/tmux_options.sh
# Must work without tmux (returns defaults)
result=$(get_tmux_option "@nonexistent" "default_val")
[ "$result" = "default_val" ] && echo "PASS"
bash tests/test_detection.sh
```

---

### Phase 3: Extract terminal.sh
**Effort**: moderate | **Risk**: medium | **Duration**: 1.5h
**Dependencies**: Phase 1 (platform.sh), Phase 2 (tmux_options.sh)

**Tasks**:
- P3-T1: Create `scripts/lib/terminal.sh` with source guard
- P3-T2: Move the following from shared.sh:
  - `_detect_terminal_from_pname()`
  - `detect_terminal_from_client_env()`
  - `get_terminal_for_session_wsl()`
  - `get_terminal_emoji()` (non-cached version)
  - `get_terminal_emoji_cached()`
  - `get_terminal_priority()`
  - `get_status_priority()`
- P3-T3: Add dependency sourcing at top of terminal.sh:
  ```bash
  source "${BASH_SOURCE[0]%/*}/platform.sh"
  source "${BASH_SOURCE[0]%/*}/tmux_options.sh"
  ```
- P3-T4: Identify duplicate terminal detection in `focus_session.sh`:
  - `detect_terminal_app()` overlaps with `get_terminal_emoji()`
  - `get_terminal_for_session()` overlaps with walking parent process tree
  - Refactor focus_session.sh to call `lib/terminal.sh` functions instead
- P3-T5: Remove moved code from shared.sh, add source line

**Files Modified**:
- `scripts/lib/terminal.sh` (new, ~320 lines)
- `scripts/shared.sh` (remove ~300 lines, add source line)
- `scripts/focus_session.sh` (refactor duplicate functions to use terminal.sh)

**Verification Checkpoint**:
```bash
source scripts/lib/terminal.sh
_detect_terminal_from_pname "iTerm2" # should return "iTerm2"
_detect_terminal_from_pname "wezterm" # should return "WezTerm"
bash tests/test_detection.sh
bash tests/test_preview.sh
```

---

### Phase 4: Extract cache_shared.sh
**Effort**: moderate | **Risk**: medium | **Duration**: 1h
**Dependencies**: Phase 1 (platform.sh)

**Tasks**:
- P4-T1: Create `scripts/lib/cache_shared.sh` with source guard
- P4-T2: Move the following from shared.sh:
  - `SHARED_CACHE_FILE`, `SHARED_CACHE_TTL` constants
  - `write_shared_cache()`
  - `read_shared_cache()`
  - `read_shared_cache_options()`
  - `read_shared_cache_processes()`
  - `read_shared_cache_tty_stat()`
  - `read_shared_cache_all()` (plus its global vars `_SHARED_CACHE_*`)
  - `get_shared_cache_age()`
- P4-T3: Note: `write_shared_cache()` calls `get_current_timestamp()` and `tmux show-options`, ensure platform.sh is sourced
- P4-T4: Remove moved code from shared.sh, add source line

**Files Modified**:
- `scripts/lib/cache_shared.sh` (new, ~120 lines)
- `scripts/shared.sh` (remove ~110 lines, add source line)

**Verification Checkpoint**:
```bash
source scripts/lib/cache_shared.sh
# Verify global variable availability
echo "$SHARED_CACHE_FILE" # should be /tmp/claudecode_shared_process_cache
bash tests/test_detection.sh
bash tests/test_status.sh
```

---

### Phase 5: Extract cache_batch.sh
**Effort**: complex | **Risk**: high | **Duration**: 2h
**Dependencies**: Phase 1, Phase 2, Phase 3

**Tasks**:
- P5-T1: Create `scripts/lib/cache_batch.sh` with source guard
- P5-T2: Move the following from shared.sh:
  - All `BATCH_*` global variables
  - `init_batch_cache()` (the largest single function)
  - `_prebuild_terminal_cache()` (internal, depends on terminal detection)
  - `_build_pid_pane_map()` (internal)
  - `get_pane_id_for_pid_direct()`
  - `get_all_claude_info_batch()`
  - `cleanup_batch_cache()`
  - `get_ppid_cached()`, `get_comm_cached()`
  - `get_pane_info_cached()`, `get_session_name_cached()`, `get_window_index_cached()`, `get_window_name_cached()`, `get_all_panes_cached()`
  - `get_terminal_for_session_cached()` (batch terminal cache)
  - `get_client_pid_for_session_cached()`
  - `init_lsof_cache()`, `get_cwd_from_lsof_cache()`
- P5-T3: Add dependency sourcing (platform.sh, terminal.sh for WSL `_prebuild_terminal_cache`)
- P5-T4: Verify `init_batch_cache()` parallel subprocess spawning still works when sourced from lib/
- P5-T5: Remove moved code from shared.sh, add source line

**Files Modified**:
- `scripts/lib/cache_batch.sh` (new, ~380 lines)
- `scripts/shared.sh` (remove ~350 lines, add source line)

**Verification Checkpoint**:
```bash
source scripts/lib/cache_batch.sh
echo "$BATCH_INITIALIZED" # should be "0"
bash tests/test_detection.sh
bash tests/test_status.sh
bash tests/test_output.sh
```

---

### Phase 6: Extract pane_utils.sh + Create Facade
**Effort**: simple | **Risk**: low | **Duration**: 45min
**Dependencies**: Phase 1-5 all complete

**Tasks**:
- P6-T1: Create `scripts/lib/pane_utils.sh` with remaining functions:
  - `get_pane_index()`
  - `get_pane_index_cached()`
- P6-T2: Transform `scripts/shared.sh` into a thin facade:
  ```bash
  #!/usr/bin/env bash
  # shared.sh - Backward-compatible facade
  # Sources all lib modules for consumers that `source shared.sh`
  _SHARED_LIB_DIR="${BASH_SOURCE[0]%/*}/lib"
  source "$_SHARED_LIB_DIR/platform.sh"
  source "$_SHARED_LIB_DIR/tmux_options.sh"
  source "$_SHARED_LIB_DIR/terminal.sh"
  source "$_SHARED_LIB_DIR/cache_shared.sh"
  source "$_SHARED_LIB_DIR/cache_batch.sh"
  source "$_SHARED_LIB_DIR/pane_utils.sh"
  ```
- P6-T3: Verify the facade works as a drop-in replacement

**Files Modified**:
- `scripts/lib/pane_utils.sh` (new, ~45 lines)
- `scripts/shared.sh` (now ~15 lines, facade only)

**Verification Checkpoint** (CRITICAL - full regression):
```bash
# ALL test suites must pass
bash tests/test_detection.sh
bash tests/test_status.sh
bash tests/test_output.sh
bash tests/test_preview.sh
```

---

### Phase 7: Refactor Consumers
**Effort**: moderate | **Risk**: medium | **Duration**: 1.5h
**Dependencies**: Phase 6

**Tasks**:
- P7-T1: Refactor `focus_session.sh`:
  - Remove `detect_terminal_app()` (duplicate of logic in terminal.sh)
  - Remove `get_terminal_for_session()` (duplicate)
  - Import `lib/terminal.sh` and use `_detect_terminal_from_pname()` and process-walking pattern
  - Keep `activate_terminal_app()`, `switch_to_pane()`, WSL functions (unique to this file)
- P7-T2: Refactor `session_tracker.sh` (optional, low priority):
  - Could source only needed lib modules instead of full shared.sh
  - Keep `source shared.sh` for now (lower risk)
- P7-T3: Verify `select_claude_launcher.sh` still works (it calls `try_use_shared_cache` which does not exist in current code - this is a potential bug)
- P7-T4: Add module-level comments to each lib file documenting public API

**Files Modified**:
- `scripts/focus_session.sh` (refactor, ~-80 lines from dedup)
- `scripts/session_tracker.sh` (comment updates only)
- `scripts/select_claude_launcher.sh` (fix `try_use_shared_cache` reference if needed)

**Verification Checkpoint**:
```bash
bash tests/test_detection.sh
bash tests/test_status.sh
bash tests/test_output.sh
bash tests/test_preview.sh
# Manual: verify focus_session.sh works in tmux
```

---

### Phase 8: Test Enhancement & Integration Validation
**Effort**: moderate | **Risk**: low | **Duration**: 1.5h
**Dependencies**: Phase 7

**Tasks**:
- P8-T1: Add unit tests for each lib module:
  - `tests/test_lib_platform.sh` - timestamp, mtime, OS detection
  - `tests/test_lib_terminal.sh` - terminal name detection, emoji mapping
  - `tests/test_lib_tmux_options.sh` - option get/set with defaults
- P8-T2: Add source-guard tests (verify double-sourcing is idempotent)
- P8-T3: Add integration test: source shared.sh facade, verify all functions available
- P8-T4: Performance validation:
  - Time `claudecode_status.sh` execution (baseline vs refactored)
  - Ensure no regression from additional source operations
- P8-T5: Remove dead code (any unused functions discovered during refactoring)

**Files Modified**:
- `tests/test_lib_platform.sh` (new)
- `tests/test_lib_terminal.sh` (new)
- `tests/test_lib_tmux_options.sh` (new)
- `tests/test_helpers.sh` (from Phase 0)

**Verification**: All tests green, performance within 10% of baseline

---

## 5. DAG Task Decomposition

### Task Dependency Graph

```
P0-T1 ─────────────────────────────────────────────────────┐
P0-T2 ─────────────────────────────────────────────────────┐│
                                                            ││
P1-T1 ← P0-T1                                              ││
P1-T2 ← P1-T1                                              ││
P1-T3 ← P1-T2                                              ││
                                                            ││
P2-T1 ← P0-T1         (PARALLEL with P1)                   ││
P2-T2 ← P2-T1                                              ││
P2-T3 ← P2-T2                                              ││
                                                            ││
P3-T1 ← P1-T3, P2-T3  (needs platform + tmux_options)      ││
P3-T2 ← P3-T1                                              ││
P3-T3 ← P3-T1                                              ││
P3-T4 ← P3-T2                                              ││
P3-T5 ← P3-T4                                              ││
                                                            ││
P4-T1 ← P1-T3          (PARALLEL with P3, needs platform)  ││
P4-T2 ← P4-T1                                              ││
P4-T3 ← P4-T2                                              ││
P4-T4 ← P4-T3                                              ││
                                                            ││
P5-T1 ← P3-T5, P4-T4   (needs terminal + platform)         ││
P5-T2 ← P5-T1                                              ││
P5-T3 ← P5-T1                                              ││
P5-T4 ← P5-T2                                              ││
P5-T5 ← P5-T4                                              ││
                                                            ││
P6-T1 ← P5-T5           (all extractions done)             ││
P6-T2 ← P6-T1                                              ││
P6-T3 ← P6-T2           (FULL REGRESSION)                  ││
                                                            ││
P7-T1 ← P6-T3                                              ││
P7-T2 ← P6-T3           (PARALLEL with P7-T1)              ││
P7-T3 ← P6-T3           (PARALLEL with P7-T1)              ││
P7-T4 ← P7-T1, P7-T2                                      ││
                                                            ││
P8-T1 ← P7-T4, P0-T2                                      ←┘│
P8-T2 ← P8-T1                                              ←─┘
P8-T3 ← P8-T2
P8-T4 ← P8-T3
P8-T5 ← P8-T4
```

### Parallelization Opportunities

| Group | Tasks | Can Run In Parallel | Blocking Dependency |
|-------|-------|---------------------|---------------------|
| G0 | P0-T1, P0-T2 | Yes (with each other) | None |
| G1 | P1-*, P2-* | Yes (Phase 1 || Phase 2) | G0 |
| G2 | P3-*, P4-* | Yes (Phase 3 || Phase 4) | G1 |
| G3 | P5-* | No (sequential) | G2 |
| G4 | P6-* | No (sequential) | G3 |
| G5 | P7-T1, P7-T2, P7-T3 | Yes (parallel) | G4 |
| G6 | P8-* | No (sequential) | G5 |

### Critical Path

```
P0-T1 → P1-* → P3-* → P5-* → P6-* → P7-T1 → P8-*
                                              (longest path ~8.5h total)
```

### Parallelized Estimate

```
Sequential:  ~9.75h
With parallel groups: ~7h
```

---

## 6. Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| shared.sh facade breaks consumers | Medium | Critical | Full regression test after Phase 6 |
| Source guard breaks re-sourcing | Low | High | Test double-source scenarios explicitly |
| Batch cache parallel subprocesses break | Medium | High | Test init_batch_cache in isolation after extraction |
| Terminal detection WSL path breaks | Low | Medium | WSL-specific test (skip on macOS if no WSL) |
| Performance regression from extra source ops | Low | Medium | Benchmark before/after, target <10% overhead |
| `select_claude_launcher.sh` has dead reference (`try_use_shared_cache`) | High | Low | Fix in Phase 7 |
| Merge conflicts if concurrent dev | Low | Medium | Single-branch refactor, atomic commits per phase |

---

## 7. Commit Strategy

One commit per phase with descriptive message:
```
Phase 0: chore: add lib directory and test helpers
Phase 1: refactor: extract platform utilities to lib/platform.sh
Phase 2: refactor: extract tmux option management to lib/tmux_options.sh
Phase 3: refactor: extract terminal detection to lib/terminal.sh
Phase 4: refactor: extract shared cache to lib/cache_shared.sh
Phase 5: refactor: extract batch cache to lib/cache_batch.sh
Phase 6: refactor: convert shared.sh to facade, extract pane_utils.sh
Phase 7: refactor: deduplicate terminal detection in focus_session.sh
Phase 8: test: add per-module unit tests and integration validation
```

---

## 8. Success Criteria

1. **All existing tests pass** (4 test files, ~45 test cases)
2. **shared.sh is <20 lines** (facade only)
3. **No function signature changes** (backward compatible)
4. **6 focused modules** in `scripts/lib/` (each <400 lines)
5. **No performance regression** (<10% overhead from source operations)
6. **Terminal detection deduplicated** (focus_session.sh uses lib/terminal.sh)
7. **Each module independently sourceable** with explicit dependencies
