# list-files

`list-files` is a high-performance Go-based drop-in replacement for `list-files`. It traverses directories and lists files depth-first, using bounded concurrent workers to speed up the process while maintaining the correct sorted order of results.

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
list-files [options] [DIR ...]
```

### Options

```
  -r, --reverse             Sort files in reverse alphabetical order.
  -n, --max-files=MAX-FILES Limit the number of files listed.
  -d, --show-directories    Print directories too.
  -a, --show-all            Show hidden directories (like .git) that are hidden by default.
  -j, --para=PARA           Limit the number of parallel worker goroutines (defaults to min(8, CPU cores)).
  -m, --max-depth=MAX-DEPTH Limit the max depth for subdirectories.
  -F, --show-fullpath       Print the full path of the file (and --no-show-fullpath).
      --home-tild           Replace user home directory with ~ in full path output (default, and --no-home-tild).
  -R, --show-relative-path  Print relative path output (default, and --no-show-relative-path).
      --strip-start-dir     Strip leading ./ from relative output path (default, and --no-strip-start-dir).
  -h, --help                Show help message.
```
