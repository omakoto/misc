# cacher

`cacher` is a Go-based command-line utility that caches command standard output (`stdout`) and executes the command in the background when the cache expires. It is designed to return cached content instantly and refresh the cache asynchronously.

It is a drop-in replacement for the Python-based `cacher` utility.

## Features

- **Asynchronous Execution**: Instantly outputs cached content while refreshing the cache in the background.
- **Double-Run Prevention**: Employs an exclusive file lock (`flock`) to prevent multiple instances from running the command concurrently.
- **Stale Process Mitigation**: Automatically detects and terminates hung background process groups based on timeout settings or force option.
- **Foreground Mode**: Optionally runs commands synchronously in the foreground.

## Usage

```
cacher [-h] -c COMMAND -f FILE [-a MAX_AGE] [-d DEFAULT] [-l LOCK_FILE] [-v] [-t TIMEOUT] [--show-stderr] [-F] [-g]
```

### Options

- `-c`, `--command COMMAND`  
  **Required.** Command to run (executed via `/bin/sh -c`).
- `-f`, `--file CACHE-FILE`  
  **Required.** Cache file path to store the command's stdout.
- `-a`, `--max-age SECONDS`  
  *Optional.* If the cache file is older than this threshold, the command is triggered in the background. If omitted, the cache never expires.
- `-d`, `--default TEXT`  
  *Optional.* Default string to write to the cache file and print on the very first run (defaults to `?`).
- `-l`, `--lock-file LOCK-FILE`  
  *Optional.* Lock file to detect running instances (defaults to `CACHE-FILE.lock`).
- `-v`, `--verbose`  
  *Optional.* Enable verbose logging to `stderr`.
- `-t`, `--timeout SECONDS`  
  *Optional.* If a previous run has been running for longer than this limit, it is killed and restarted.
- `--show-stderr`  
  *Optional.* Redirects command `stderr` to the parent terminal's `stderr` for debugging.
- `-F`, `--force`  
  *Optional.* Forces execution: kills any running background process groups and refreshes the cache regardless of age.
- `-g`, `--foreground`  
  *Optional.* Runs the command synchronously in the foreground and outputs the result directly (automatically enables `--force`).

### Examples

1. Cache an external IP query for 5 minutes (300 seconds):
   ```bash
   cacher -c "curl -s https://api.ipify.org" -f /tmp/myip.txt -a 300
   ```
2. Sleep for 5 seconds and write result, showing default text on first run:
   ```bash
   cacher -c "sleep 5 && echo done" -f /tmp/test.cache -a 10 -d "loading..."
   ```

## Development

### Setup Workspace
Initialize local `go.work` file:
```bash
./0-setup.sh
```

### Build and Run Locally
Build the binary into `bin/cacher` and run it:
```bash
./00-run.sh [args...]
```

### Install
Build and install `cacher` into `$GOBIN` (falls back to `$(go env GOPATH)/bin`):
```bash
./01-install.sh
```

### Run Presubmits & Tests
Run formatting (`gofmt`), static analysis (`go vet` and `staticcheck`), and unit tests:
```bash
./10-presubmit.sh
```

### Integration Tests
Run the integration test suite:
```bash
./scripts/cacher_test.bash
```
