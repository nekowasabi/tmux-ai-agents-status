# tmux-claudecode-status

A tmux plugin that displays Claude Code's execution status in real-time on the status bar. It tracks multiple Claude Code sessions individually and shows each session's working/idle state with color coding.

## Features

- **Multiple Session Support**: Track multiple Claude Code processes simultaneously
- **State Differentiation**: Distinguish between working and idle states with colors
- **Lightweight & Fast**: Cache functionality enables high speed even with per-second execution (< 50ms)
- **Customizable**: Customize icons, colors, and dot symbols
- **Cross-Platform**: Supports Linux/macOS

## Installation

### Using TPM (Recommended)

Add the following to `~/.tmux.conf`:

```bash
set -g @plugin 'takets/tmux-claudecode-status'
```

Then run `prefix + I` in tmux to reload TPM plugins.

### Manual Installation

1. Clone this repository:
```bash
git clone https://github.com/takets/tmux-claudecode-status ~/.tmux/plugins/tmux-claudecode-status
```

2. Add the following to `~/.tmux.conf`:
```bash
run-shell "~/.tmux/plugins/tmux-claudecode-status/claudecode_status.tmux"
```

3. Restart tmux.

## Configuration

### Default Display

By default, you need to set the `#{claudecode_status}` format string in your status bar.

#### Status Bar Position Settings

Add one of the following to `~/.tmux.conf`:

```bash
# Display in status-right
set -g status-right "#{claudecode_status} #[default]%H:%M"

# Display in status-left
set -g status-left "#{claudecode_status} #[default]"

# Display in status-format[1] (top status bar)
set -g status 2
set -g status-format[1] "#{claudecode_status}"
```

### Customization Options

| Option | Default | Description |
|--------|---------|-------------|
| `@claudecode_working_dot` | `🤖` | Dot for working state (robot emoji) |
| `@claudecode_idle_dot` | `🔔` | Dot for idle state (bell emoji) |
| `@claudecode_working_color` | `""` (empty) | Color for working state (empty=tmux default) |
| `@claudecode_idle_color` | `""` (empty) | Color for idle state (empty=tmux default) |
| `@claudecode_separator` | `" "` | Separator between sessions |
| `@claudecode_left_sep` | `""` (empty) | Left enclosure character |
| `@claudecode_right_sep` | `""` (empty) | Right enclosure character |
| `@claudecode_show_terminal` | `on` | Show terminal emoji |
| `@claudecode_show_pane` | `on` | Show pane number |
| `@claudecode_terminal_iterm` | `🍎` | Emoji for iTerm/Terminal |
| `@claudecode_terminal_wezterm` | `⚡` | Emoji for WezTerm |
| `@claudecode_terminal_ghostty` | `👻` | Emoji for Ghostty |
| `@claudecode_terminal_windows` | `🪟` | Emoji for Windows Terminal |
| `@claudecode_terminal_unknown` | `❓` | Emoji for unknown terminal |
| `@claudecode_working_threshold` | `30` | Threshold for working/idle detection (seconds) |
| `@claudecode_select_key` | `""` (empty) | Keybinding to open process selector (e.g., `C-g`) |
| `@claudecode_fzf_opts` | `"--height=40% --reverse --border --prompt='Select Claude: '"` | fzf options for process selector |

### Customization Examples

```bash
# Add enclosure characters
set -g @claudecode_left_sep "["
set -g @claudecode_right_sep "]"
# Result: [🍎#0 project-name 🤖]

# Customize terminal emojis
set -g @claudecode_terminal_iterm "🖥️"
set -g @claudecode_terminal_wezterm "W"

# Change working/idle detection threshold (default: 30 seconds)
set -g @claudecode_working_threshold "10"

# Enable process selector with keybinding (requires fzf)
set -g @claudecode_select_key "C-j"  # prefix + Ctrl-j to open selector

# Customize fzf options for process selector
set -g @claudecode_fzf_opts "--height=50% --reverse --border --prompt='Claude> '"

# Customize colors (optional)
set -g @claudecode_working_color "#f97316"
set -g @claudecode_idle_color "#22c55e"
```

### About Color Settings

Color settings are empty by default (inheriting tmux theme colors). Configure as needed.

### Process Selector Feature

The process selector allows you to quickly switch between multiple Claude Code sessions using fzf.

**Requirements:**
- fzf (install with `brew install fzf` on macOS or `apt install fzf` on Ubuntu)
- tmux 3.2+ for popup support (older versions use split-window fallback)

**Setup:**
```bash
# Enable the process selector with a keybinding
set -g @claudecode_select_key "C-j"
```

**Usage:**
1. Press `prefix + Ctrl-j` (or your configured key) to open the selector
2. Use fzf to filter and select a Claude Code process
3. The selected process's terminal will be activated and focused

**Command Line Usage:**
```bash
# Interactive selection
~/.tmux/plugins/tmux-claudecode-status/scripts/select_claude.sh

# List all Claude Code processes
~/.tmux/plugins/tmux-claudecode-status/scripts/select_claude.sh --list
```

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
export CLAUDECODE_WORKING_THRESHOLD=10  # Change to 10 seconds
```

### Cache Function

Status output is cached for 2 seconds for improved performance.

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
rm -f /tmp/claudecode_status_cache_*
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
tmux-claudecode-status/
├── claudecode_status.tmux      # TPM entry point
├── scripts/
│   ├── shared.sh               # Common utilities
│   ├── session_tracker.sh       # Session tracking logic
│   ├── claudecode_status.sh     # Main output script
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
