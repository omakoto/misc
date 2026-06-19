# glow2

`glow2` is a lightweight Go command-line utility built directly on top of the Charmbracelet `glamour` markdown rendering library. It is designed to format and render markdown files with ANSI color output directly to `stdout` without requiring a pseudo-terminal (PTY) or interactive terminal check.

It serves as a performant, TTY-independent alternative to Charmbracelet's `glow` command for scripts, automation, and tools like `fzf`'s preview window.

---

## Why `glow2` Was Created (The PTY/10-Second Delay Problem)

We needed `glow2` **only** because the original `glow` command does not support a `--color=always` (or similar) option yet to force ANSI color output when redirected. **When `glow` eventually gets this option, `glow2` will no longer be needed and can be retired.**

When running the original `glow` command inside redirected or non-interactive environments (such as `fzf`'s preview window):
1. `glow` checks if stdout is a TTY. If it is not, it disables coloring.
2. Sourcing hacks like `script -c "glow ..."` or using Python's `pty.spawn` to force color output works in interactive shells but causes a severe **10-second delay** in redirected subshells (e.g. within `fzf` previews).
3. This 10-second delay occurs because when stdin/stdout are redirected to `/dev/null` inside the container or PAM environment, calling PTY spawn triggers a D-Bus/systemd/PAM logind registration request that eventually times out.

`glow2` solves this by using the `glamour` library directly. It allows you to specify `--color=always` to force ANSI escape sequence formatting to any output stream instantly (<10ms) without any TTY allocation or terminal registration timeouts.

---

## Features

- **No TTY/PTY Requirement**: Can output ANSI colors directly into files, pipes, or non-interactive previews.
- **Dynamic Width Wrapping**: Defaults to automatic width detection (reads `$FZF_PREVIEW_COLUMNS` first, then `$COLUMNS`, falling back to `80`).
- **Terminal Theme Detection**: Automatically checks the `$COLORFGBG` environment variable to determine if the terminal is light or dark.
- **Color Modes**: Supports `--color=always`, `--color=never`, and `--color=auto`.

---

## Usage

```bash
glow2 [options] [file...]
```

If no files are specified, or if `-` is passed, `glow2` reads from standard input.

### Options

- `-s`, `--style STYLE`  
  Style name or JSON stylesheet path (defaults to `"auto"`). Valid standard styles include: `dark`, `light`, `notty`, `ascii`, `pink`, `dracula`, etc.
- `-w`, `--width WIDTH`  
  Word-wrap width (defaults to `0` for auto-detection).
- `--color MODE`  
  Color output mode: `always`, `never`, or `auto` (defaults to `"auto"`).
- `-h`, `--help`  
  Show the help message.

### Examples

1. Force color rendering inside an `fzf` preview window (runs instantly):
   ```bash
   glow2 --color=always my_document.md
   ```
2. Render markdown using stdin:
   ```bash
   cat README.md | glow2 -s dracula
   ```

---

## Development & Maintenance

### Directory Structure
- [glow2.go](glow2/glow2.go): Glamour term renderer integration and color theme auto-detection.
- [glow2_test.go](glow2/glow2_test.go): Unit tests verifying styled/colored rendering and non-colored output.
- [cmd/main.go](glow2/cmd/main.go): Command CLI parser (parsing flags, fallback terminal width, reading inputs).

### Scripts
- `./0-setup.sh`: Initialized local Go workspace (`go.work`).
- `./00-run.sh`: Compile and execute locally (`bin/glow2`).
- `./01-install.sh`: Compile and install to `$GOBIN` (or `$GOPATH/bin`).
- `./10-presubmit.sh`: Run formatter (`gofmt`), type vetting (`go vet`), static analysis (`staticcheck`), and unit tests.

---

## Maintenance Guidelines for Future AI Agents

When the original Charmbracelet `glow` or its rendering engine `glamour` is updated:

1. **New Formatting Features / Styles**:
   - If `glow` introduces new terminal rendering styles or options, check if they are supported by the `glamour` library.
   - You can configure `glamour` renderer options in `glow2.go` using `glamour.WithStylePath` or `glamour.WithStandardStyle`.
2. **Exposing New CLI Flags**:
   - Add new flags inside `glow2/cmd/main.go` and map them to their corresponding `glamour.TermRendererOption` parameters in `glow2/glow2.go`.
3. **Upgrading Glamour Dependency**:
   - To upgrade dependencies, modify `go.mod` or run `go get github.com/charmbracelet/glamour@latest` within the directory.
   - Always run `./10-presubmit.sh` to confirm compilation and verify that tests still pass after an upgrade.
4. **Preserve TTY Independence**:
   - **CRITICAL**: Do not add any interactive TTY checks or prompt logic that blocks stdin/stdout redirection. `glow2`'s primary purpose is non-interactive rendering for tools like `fzf` previews. Always keep coloring independent of TTY state when `--color=always` is set.
