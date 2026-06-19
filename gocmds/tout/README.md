# tout (Timeout Utility)

`tout` is a basic, lightweight command-line utility in Go that runs a specified command with a timeout. It serves as a high-performance replacement for the standard `timeout` command in environments where process spawning overhead and latency are critical.

## Why We Needed It

In this environment, the standard `timeout` command is provided by `uutils coreutils` (a Rust implementation). However, `uutils timeout` has a design behavior/bug where it sleeps using a fixed polling interval (typically 100ms) to check on the child process:
* Even if the child process (e.g. `test -d /path`) completes instantly (in $<1\text{ms}$), `uutils timeout` continues sleeping for the rest of its polling tick.
* Consequently, every execution of `timeout` has a baseline latency overhead of **~110ms**.
* For utilities like `recent-dirs` that validate a list of directories in a loop (e.g. checking 100 paths), this overhead compounds into **10–15 seconds** of total delay.

`tout` addresses this by leveraging Go's runtime process management:
* Go's `exec.CommandContext` waits for child process termination via the OS `wait4` system call, which returns immediately when the child exits.
* There is no arbitrary sleep or polling interval.
* As a result, `tout` completes standard quick commands in **~18ms** (a **6x speedup** over `uutils timeout`).

---

## Usage

```bash
tout DURATION COMMAND [ARGS...]
```

* **`DURATION`**: A number representing seconds (e.g., `0.1`), or with a suffix unit (e.g., `100ms`, `2s`, `1.5m`).
* **`COMMAND`**: The command executable to launch.
* **`ARGS`**: Optional arguments passed to the command.

### Examples

Check if a directory exists within `0.1` seconds:
```bash
tout 0.1 test -d /home/omakoto/cbin/misc
```

Run a command with a 5-second limit:
```bash
tout 5s sleep 10
```

---

## Exit Status

* `0`: The command completed successfully before the timeout.
* `124`: The command timed out.
* `125`: `tout` itself failed (e.g. invalid duration or failed to spawn the command).
* Other: The exit status of the command itself if it finished before timing out.
