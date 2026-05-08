# tmux-ai-agents-status

A tmux plugin that displays Claude Code's execution status in real-time on the status bar. It tracks multiple Claude Code sessions individually and shows each session's working/idle state with color coding.

## Features

- **Multiple Session Support**: Track multiple Claude Code processes simultaneously
- **State Differentiation**: Distinguish between working and idle states with colors
- **Lightweight & Fast**: Optimized performance with cache functionality and TTY-based change detection (< 50ms)
- **Customizable**: Customize icons, colors, and dot symbols
- **Cross-Platform**: Supports Linux/macOS

## Installation

### Using TPM (Recommended)

Add the following to `~/.tmux.conf`:

```bash
set -g @plugin 'takets/tmux-ai-agents-status'
```

Then run `prefix + I` in tmux to reload TPM plugins.

### Manual Installation

1. Clone this repository:
```bash
git clone https://github.com/nekowasabi/tmux-ai-agents-status ~/.tmux/plugins/tmux-ai-agents-status
```

2. Add the following to `~/.tmux.conf`:
```bash
run-shell "~/.tmux/plugins/tmux-ai-agents-status/ai_agent_status.tmux"
```

3. Restart tmux.

## Configuration

### Default Display

By default, you need to set the `#{ai_agent_status}` format string in your status bar.

#### Status Bar Position Settings

Add one of the following to `~/.tmux.conf`:

```bash
# Display in status-right
set -g status-right "#{ai_agent_status} #[default]%H:%M"

# Display in status-left
set -g status-left "#{ai_agent_status} #[default]"

# Display in status-format[1] (top status bar)
set -g status 2
set -g status-format[1] "#{ai_agent_status}"
```

### Customization Options

| Option | Default | Description |
|--------|---------|-------------|
| `@ai_agent_working_dot` | `🤖` | Dot for working state (robot emoji) |
| `@ai_agent_idle_dot` | `🔔` | Dot for idle state (bell emoji) |
| `@ai_agent_working_color` | `""` (empty) | Color for working state (empty=tmux default) |
| `@ai_agent_idle_color` | `""` (empty) | Color for idle state (empty=tmux default) |
| `@ai_agent_separator` | `" "` | Separator between sessions |
| `@ai_agent_left_sep` | `""` (empty) | Left enclosure character |
| `@ai_agent_right_sep` | `""` (empty) | Right enclosure character |
| `@ai_agent_show_terminal` | `on` | Show terminal emoji |
| `@ai_agent_show_pane` | `on` | Show pane number |
| `@ai_agent_terminal_iterm` | `🍎` | Emoji for iTerm/Terminal |
| `@ai_agent_terminal_wezterm` | `⚡` | Emoji for WezTerm |
| `@ai_agent_terminal_ghostty` | `👻` | Emoji for Ghostty |
| `@ai_agent_terminal_windows` | `🪟` | Emoji for Windows Terminal |
| `@ai_agent_terminal_unknown` | `❓` | Emoji for unknown terminal |
| `@ai_agent_working_threshold` | `30` | Threshold for working/idle detection (seconds) |
| `@ai_agent_selector` | `fzf` / `menu` | Selector type: `fzf` (fzf popup with prerender, ~300ms) or `menu` (tmux native menu, ~30-50ms) |
| `@ai_agent_select_key` | `""` (empty) | Keybinding to open process selector (e.g., `C-g`) |
| `@ai_agent_fzf_opts` | `"--height=40% --reverse --border --prompt='Select Claude: '"` | fzf options for process selector |
| `@ai_agent_fzf_preview` | `on` | Enable/disable fzf preview pane (`on`/`off`) |
| `@ai_agent_fzf_preview_lines` | `30` | Number of lines to show in preview |
| `@ai_agent_fzf_preview_position` | `down` | fzf preview window position: `up`, `down`, `left`, `right` |
| `@ai_agent_fzf_preview_size` | `50%` | fzf preview window size (e.g., `50%`, `40%`, `60%`) |
| `@ai_agent_pane_title_sync` | `off` | When `on`, prefer the tmux `pane_title` (updated via Claude Code `/rename` OSC 2) as the display name. The plugin auto-applies `set-titles on` / `allow-rename on` / `automatic-rename off` at startup. |

### Customization Examples

```bash
# Add enclosure characters
set -g @ai_agent_left_sep "["
set -g @ai_agent_right_sep "]"
# Result: [🍎#0 project-name 🤖]

# Customize terminal emojis
set -g @ai_agent_terminal_iterm "🖥️"
set -g @ai_agent_terminal_wezterm "W"

# Change working/idle detection threshold (default: 30 seconds)
set -g @ai_agent_working_threshold "10"

# Enable process selector with keybinding (requires fzf)
set -g @ai_agent_select_key "C-j"  # prefix + Ctrl-j to open selector

# Use tmux native menu instead of fzf (~30-50ms, no fzf required)
set -g @ai_agent_selector "menu"

# Customize fzf options for process selector
set -g @ai_agent_fzf_opts "--height=50% --reverse --border --prompt='Claude> '"

# Customize fzf preview window (optional)
set -g @ai_agent_fzf_preview_position "right"  # or up, down, left
set -g @ai_agent_fzf_preview_size "60%"

# Customize colors (optional)
set -g @ai_agent_working_color "#f97316"
set -g @ai_agent_idle_color "#22c55e"
```

### About Color Settings

Color settings are empty by default (inheriting tmux theme colors). Configure as needed.

### Process Selector Feature

The process selector allows you to quickly switch between multiple Claude Code sessions using fzf. This feature is particularly useful when running multiple Claude Code instances simultaneously across different projects.

**Requirements:**
- fzf (install with `brew install fzf` on macOS or `apt install fzf` on Ubuntu)
- tmux 3.2+ for popup support (older versions use split-window fallback)

**Features:**
- **Interactive Selection**: Use fzf to search and select from running Claude Code processes
- **Status Display**: Shows working/idle status of each process
- **Terminal Awareness**: Displays which terminal application each process is running in (Terminal.app, iTerm2, Ghostty, etc.)
- **Automatic Focus**: Automatically switches focus to the selected process and its tmux pane
- **Status Priority**: Sorts processes with working status first, followed by idle processes
- **Send Prompt (Ctrl+S)**: Send a prompt to the selected Claude Code session via popup
- **Prerender Fast Path**: Display data is prerendered by `ai_agent_status.sh` (TTL: 10s), eliminating ~300ms collection delay on launch
- **Native Menu Mode**: Set `@ai_agent_selector "menu"` to use tmux `display-menu` (~30-50ms) instead of fzf popup

**Setup:**
```bash
# Enable the process selector with a keybinding
set -g @ai_agent_select_key "C-j"
```

**Usage - Keybinding Mode:**
1. Press `prefix + Ctrl-j` (or your configured key) to open the selector
2. Start typing to filter processes by project name or terminal type
3. Navigate with arrow keys and use one of the following keys:
   - **Enter**: Switch to the selected Claude Code session
   - **Ctrl+S**: Open a popup to send a prompt to the selected session
4. The selected process's terminal will be activated and the corresponding tmux pane will be focused

**Tip — Rename via Claude Code `/rename`:**
When using Claude Code, run `/rename <project-name>` at session start in each pane. With `@ai_agent_pane_title_sync` enabled, the `claude` label shown in the statusline and window-status will be replaced with the chosen name.

**Usage - Command Line:**
```bash
# Interactive selection with fzf
~/.tmux/plugins/tmux-ai-agents-status/scripts/select_claude.sh

# List mode - print all processes without fzf
~/.tmux/plugins/tmux-ai-agents-status/scripts/select_claude.sh --list
```

**Example Output:**
```
🍎 #0 my-project [session-1] 🤖
🖥️ #1 web-app [session-2] 🤖
⚡ #2 cli-tool [session-3] 🔔
```

**Advanced Configuration:**
```bash
# Customize keybinding
set -g @ai_agent_select_key "C-g"

# Customize fzf appearance
set -g @ai_agent_fzf_opts "--height=50% --reverse --border --prompt='🤖 Select: '"

# Use with custom colors
set -g @ai_agent_working_color "#f97316"
set -g @ai_agent_idle_color "#22c55e"
```

**How it Works:**
1. Scans for running Claude Code processes using `pgrep`
2. Retrieves process metadata including TTY path, working directory, and terminal application
3. Determines status (working/idle) by checking TTY modification time
4. Sorts by status and terminal priority
5. Displays formatted list with terminal emoji, pane number, project name, and status
6. On selection, activates the terminal application and focuses the corresponding tmux pane

## How It Works

### Session Detection

1. Detects Claude Code processes (process name: `claude`) using `pgrep`
2. On Linux, identifies debug files from `/proc/{pid}/fd`
3. Determines state by debug file modification time (`~/.claude/debug/*.txt`)

### State Determination

- **working**: Processes whose debug file was updated within the last 5 seconds
- **idle**: Processes whose debug file hasn't been updated for more than 5 seconds

The default threshold (5 seconds) can be changed via environment variable:

```bash
export AI_AGENT_WORKING_THRESHOLD=10  # Change to 10 seconds
```

### Cache Function

Status output is cached for 2 seconds for improved performance.

### Process Selector Performance

The process selector uses a **prerender fast path** for near-instant display:

1. `ai_agent_status.sh` pre-generates `/tmp/ai_agent_fzf_prerender` (TAB-delimited: `display_string\tpane_id`) every 2 seconds
2. `select_claude_launcher.sh` reads the prerender file directly if fresh (≤10s TTL) — no shell sourcing needed
3. Falls back to legacy path (full `shared.sh` + `session_tracker.sh` sourcing) when prerender is stale or missing

This reduces selector startup latency from ~2s to ~100ms on typical systems.

## Display Example

```
  ●●○      # icon + working×2 + idle×1
```

## Troubleshooting

### Status Not Displaying

1. Verify Claude Code is running:
```bash
pgrep claude
```

2. Check if status bar is enabled in tmux:
```bash
tmux show-option -g status
```

3. Verify status format is correctly configured:
```bash
tmux show-option -g status-right
```

### Status Not Updating

1. Delete cache files:
```bash
rm -f /tmp/ai_agent_status_cache_*
```

2. Check if debug files exist:
```bash
ls -la ~/.claude/debug/
```

## Running Tests

Run project tests:

```bash
# Detection test
./tests/test_detection.sh

# Output test
./tests/test_output.sh

# Status test
./tests/test_status.sh
```

Ensure all tests PASS.

## File Structure

```
tmux-ai-agents-status/
├── ai_agent_status.tmux       # TPM entry point
├── scripts/
│   ├── shared.sh               # Common utilities
│   ├── session_tracker.sh       # Session tracking logic
│   ├── ai_agent_status.sh      # Main output script
│   ├── select_claude.sh         # Process selector UI (fzf)
│   └── focus_session.sh         # Terminal focus & pane switch
├── tests/
│   ├── test_detection.sh        # Detection function tests
│   ├── test_status.sh           # Status determination tests
│   └── test_output.sh           # Output format tests
├── README.md                    # This file
└── README_ja.md                 # Japanese documentation
```

## License

MIT License

## Contributing

Please submit bug reports and feature requests to GitHub Issues.

## References

- [tmux Plugin Manager (TPM)](https://github.com/tmux-plugins/tpm)
- [tmux Manual](https://manpages.debian.org/tmux.1)
- [Claude Code CLI](https://github.com/anthropics/claude-code)
