// Entry point for cacher command.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"cacher/cacher"
)

func main() {
	var opts cacher.Options

	// Define short and long flags
	flag.StringVar(&opts.Command, "c", "", "")
	flag.StringVar(&opts.Command, "command", "", "")

	flag.StringVar(&opts.CacheFile, "f", "", "")
	flag.StringVar(&opts.CacheFile, "file", "", "")

	flag.IntVar(&opts.MaxAge, "a", -1, "")
	flag.IntVar(&opts.MaxAge, "max-age", -1, "")

	flag.StringVar(&opts.DefaultText, "d", "?", "")
	flag.StringVar(&opts.DefaultText, "default", "?", "")

	flag.StringVar(&opts.LockFile, "l", "", "")
	flag.StringVar(&opts.LockFile, "lock-file", "", "")

	flag.BoolVar(&opts.Verbose, "v", false, "")
	flag.BoolVar(&opts.Verbose, "verbose", false, "")

	flag.IntVar(&opts.Timeout, "t", -1, "")
	flag.IntVar(&opts.Timeout, "timeout", -1, "")

	flag.BoolVar(&opts.ShowStderr, "show-stderr", false, "")

	flag.BoolVar(&opts.Force, "F", false, "")
	flag.BoolVar(&opts.Force, "force", false, "")

	flag.BoolVar(&opts.Foreground, "g", false, "")
	flag.BoolVar(&opts.Foreground, "foreground", false, "")

	flag.BoolVar(&opts.DaemonRun, "daemon-run", false, "")

	flag.StringVar(&opts.UpdatingIndicator, "u", "", "")
	flag.StringVar(&opts.UpdatingIndicator, "updating-indicator", "", "")

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: cacher [-h] -c COMMAND -f FILE [-a MAX_AGE] [-d DEFAULT] [-l LOCK_FILE] [-v] [-t TIMEOUT] [--show-stderr] [-F] [-g] [-u UPDATING_INDICATOR]\n\n")
		fmt.Fprintf(os.Stderr, "Cache command stdout and run command in background when expired.\n\n")
		fmt.Fprintf(os.Stderr, "options:\n")
		fmt.Fprintf(os.Stderr, "  -h, --help            show this help message and exit\n")
		fmt.Fprintf(os.Stderr, "  -c, --command COMMAND\n")
		fmt.Fprintf(os.Stderr, "                        Command to run. Use /bin/sh -c to run it.\n")
		fmt.Fprintf(os.Stderr, "  -f, --file FILE       Cache file to store command stdout.\n")
		fmt.Fprintf(os.Stderr, "  -a, --max-age MAX_AGE\n")
		fmt.Fprintf(os.Stderr, "                        If the cache file is older than this (in seconds), run the command, unless it's already running.\n")
		fmt.Fprintf(os.Stderr, "  -d, --default DEFAULT\n")
		fmt.Fprintf(os.Stderr, "                        Default string to put in the file if it's the first run. Default is \"?\"\n")
		fmt.Fprintf(os.Stderr, "  -l, --lock-file LOCK_FILE\n")
		fmt.Fprintf(os.Stderr, "                        Lock file to detect double-run. Default is CACHE-FILE.lock.\n")
		fmt.Fprintf(os.Stderr, "  -v, --verbose         Enable verbose logging to stderr.\n")
		fmt.Fprintf(os.Stderr, "  -t, --timeout TIMEOUT\n")
		fmt.Fprintf(os.Stderr, "                        If the previous run was taking more than this (in seconds), kill it and start over.\n")
		fmt.Fprintf(os.Stderr, "  --show-stderr         Redirect command stderr to original stderr for debugging.\n")
		fmt.Fprintf(os.Stderr, "  -F, --force           Force run the command: kill the previous running instance if any, and refresh the cache even if it is recent.\n")
		fmt.Fprintf(os.Stderr, "  -g, --foreground      Run the command in the foreground, without daemonizing. Always enables --force.\n")
		fmt.Fprintf(os.Stderr, "  -u, --updating-indicator UPDATING_INDICATOR\n")
		fmt.Fprintf(os.Stderr, "                        If set, write this string to the cache file when the command starts.\n")
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  cacher -c \"curl -s https://api.ipify.org\" -f /tmp/myip.txt -a 300\n")
		fmt.Fprintf(os.Stderr, "  cacher -c \"sleep 5 && echo done\" -f /tmp/test.cache -a 10 -d \"default-val\"\n")
	}

	flag.Parse()

	// Validation
	if opts.Command == "" {
		fmt.Fprintln(os.Stderr, "Error: -c/--command is required")
		flag.Usage()
		os.Exit(2)
	}

	if opts.CacheFile == "" {
		fmt.Fprintln(os.Stderr, "Error: -f/--file is required")
		flag.Usage()
		os.Exit(2)
	}

	// Determine if max-age or timeout flags were explicitly set and check if they are negative
	isMaxAgeSet := false
	isTimeoutSet := false
	flag.Visit(func(f *flag.Flag) {
		if f.Name == "a" || f.Name == "max-age" {
			isMaxAgeSet = true
		}
		if f.Name == "t" || f.Name == "timeout" {
			isTimeoutSet = true
		}
	})

	if isMaxAgeSet && opts.MaxAge < 0 {
		fmt.Fprintln(os.Stderr, "max-age must be a non-negative integer")
		os.Exit(2)
	}
	if isTimeoutSet && opts.Timeout < 0 {
		fmt.Fprintln(os.Stderr, "timeout must be a non-negative integer")
		os.Exit(2)
	}

	// Resolve absolute paths
	var err error
	opts.CacheFile, err = filepath.Abs(opts.CacheFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to resolve absolute path for cache file: %v\n", err)
		os.Exit(1)
	}

	if opts.LockFile != "" {
		opts.LockFile, err = filepath.Abs(opts.LockFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to resolve absolute path for lock file: %v\n", err)
			os.Exit(1)
		}
	} else {
		opts.LockFile = opts.CacheFile + ".lock"
	}

	// Create parent directories if they don't exist
	for _, path := range []string{opts.CacheFile, opts.LockFile} {
		parent := filepath.Dir(path)
		if parent != "" {
			if err := os.MkdirAll(parent, 0755); err != nil {
				fmt.Fprintf(os.Stderr, "Failed to create directory %s: %v\n", parent, err)
				os.Exit(1)
			}
		}
	}

	// Adjust MaxAge/Timeout to -1 if they were not explicitly set
	if !isMaxAgeSet {
		opts.MaxAge = -1
	}
	if !isTimeoutSet {
		opts.Timeout = -1
	}

	exitCode := cacher.Run(&opts, os.Stdout, os.Stderr)
	os.Exit(exitCode)
}
