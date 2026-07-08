# How `is-interactive-bash` Works

`is-interactive-bash` is a utility designed to distinguish whether a running program or command is being executed under an existing **interactive bash shell** versus being executed directly in a new terminal window or subshell (e.g., `gnome-terminal -- COMMAND`).

## The Core Concept: Session Leaders

When a terminal emulator (such as `gnome-terminal`, `alacritty`, `xterm`, or an SSH session) opens a new window, tab, or session, the operating system creates a new OS Session (`setsid()`). The first process spawned inside that new session becomes the **Session Leader**, whose Process ID is equal to the Session ID (`PID == SID`).

Because the Session Leader represents the root process of the entire terminal window or session, inspecting the Session Leader of any running command allows us to determine how that window and command were launched.

## The Detection Algorithm

When `is-interactive-bash` inspects a process (defaulting to the current shell `$$`), it performs the following steps:

### 1. Locate the Session Leader
The script queries the Session ID of the target process using `ps`:
```bash
sid=$(ps -o sid= -p "$target_pid" 2>/dev/null | tr -d ' ')
```
The process with PID `$sid` is literally the "first process created on the current terminal/session".

### 2. Verify the Session Leader is `bash`
We check the executable command name of the Session Leader:
```bash
comm=$(ps -o comm= -p "$sid" 2>/dev/null | tr -d ' ')
comm="${comm#-}" # Strip leading hyphen for login shells (e.g., -bash)
```
* **If `$comm` is NOT `bash`** (for example, `gnome-terminal -- top` or `gnome-terminal -- python3`):
  The Session Leader is the target command itself, meaning the program was spawned directly by the terminal emulator without an underlying interactive shell.
  ➡️ **Result: FALSE (Exit 1)**

### 3. Verify Interactive Shell State
If the Session Leader is indeed `bash`, we must distinguish between an interactive prompt (like `gnome-terminal -- bash`) and non-interactive executions (such as `gnome-terminal -- bash -c "..."` or script files). We check three Linux/POSIX indicators:

#### Indicator A: Controlling TTY Check
An interactive shell must be attached to a controlling terminal. We verify that `$sid` has a valid TTY assigned:
```bash
tty=$(ps -o tty= -p "$sid" 2>/dev/null | tr -d ' ')
```
If `$tty` is empty or `?`, the shell is running in the background or as a daemon.

#### Indicator B: Command-Line Arguments (`-c` and Script Filenames)
Per the official GNU Bash manual, an interactive shell is started without `-c` and without non-option script arguments (unless `-i` is explicitly specified). We inspect `args=$(ps -o args= -p "$sid")`:
* If invoked with `-c` (e.g., `bash -c "echo hi"`) ➡️ **Non-interactive (FALSE)**
* If invoked with a script filename (e.g., `bash /path/to/script.sh`) ➡️ **Non-interactive (FALSE)**
* If invoked without `-c` or script arguments (e.g., `bash` or `bash --login`) ➡️ **Interactive (TRUE)**

#### Indicator C: File Descriptor 255 (`/proc/$sid/fd/255`)
When Bash runs as an interactive shell with job control and readline editing enabled, it duplicates the terminal file descriptor to `fd 255`. In non-interactive script or `-c` executions, `fd 255` is never opened. If `/proc/$sid/fd/255` exists, it provides immediate kernel-level confirmation that the shell is interactive.

---

## Summary Verification Table

| User Action / Invocation | Session Leader (`$sid`) | Interactive Checks (`-c` absent, fd 255 open) | Script Result |
| :--- | :--- | :--- | :--- |
| Normal terminal window (running `my-app` from prompt) | `bash` | **Yes** | **TRUE (Exit 0)** |
| `gnome-terminal -- bash` *(Exception 1)* | `bash` | **Yes** | **TRUE (Exit 0)** |
| `gnome-terminal -- top` | `top` *(not bash)* | N/A | **FALSE (Exit 1)** |
| `gnome-terminal -- bash -c "my-app"` *(Exception 2)* | `bash` | **No** (`-c` present, no fd 255) | **FALSE (Exit 1)** |
| `gnome-terminal -- bash script.sh` | `bash` | **No** (script arg present, no fd 255) | **FALSE (Exit 1)** |

---

## Usage Examples

Check if the current session is running under an interactive bash shell:
```bash
if is-interactive-bash; then
  echo "Running under an interactive bash terminal"
else
  echo "Running directly in a terminal window or non-interactive script"
fi
```

Inspect a specific PID with verbose output explaining the decision:
```bash
is-interactive-bash -p 12345 -v
```
