# list-files2

`list-files2` is a high-performance Go-based drop-in replacement for `list-files`. It traverses directories and lists files depth-first, using bounded concurrent workers to speed up the process while maintaining the correct sorted order of results.

## Features

- Depth-first traversal
- Alphabetical or reverse alphabetical (`-r` / `--reverse`) sorting
- Print directory paths (`-d` / `--show-directories`) with a trailing slash `/`
- Limit output to a maximum number of files (`-n` / `--max-files`)
- Ignore hidden directories (e.g. `.git`) by default, unless requested (`-a` / `--show-all`)
- High performance utilizing up to 8 concurrent goroutines for I/O and directory scanning
- Graceful handling of broken pipe (`SIGPIPE`) on stdout (exits with status 0)

## Usage

```bash
list-files2 [options] [DIR ...]
```

### Options

```
  -r, --reverse             Sort files in reverse alphabetical order.
  -n, --max-files=MAX-FILES Limit the number of files listed.
  -d, --show-directories    Print directories too.
  -a, --show-all            Show hidden directories (like .git) that are hidden by default.
  -j, --para=PARA           Limit the number of parallel worker goroutines (defaults to min(8, CPU cores)).
  -h, --help                Show help message.
```
