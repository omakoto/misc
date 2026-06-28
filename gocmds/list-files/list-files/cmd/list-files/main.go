package main

import (
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"

	"github.com/pborman/getopt/v2"
	"list-files/list-files"
)

func init() {
	signal.Ignore(syscall.SIGPIPE)
}

func isBrokenPipe(err error) bool {
	if err == nil {
		return false
	}
	if pe, ok := err.(*os.PathError); ok {
		err = pe.Err
	}
	return err == syscall.EPIPE || strings.Contains(err.Error(), "broken pipe")
}

func formatRelativePath(p string, stripStartDir bool) string {
	if stripStartDir {
		if strings.HasPrefix(p, "./") {
			return p[2:]
		}
		if p == "." {
			return ""
		}
		return p
	} else {
		if p == "." {
			return "./"
		}
		if !filepath.IsAbs(p) && !strings.HasPrefix(p, ".") && !strings.HasPrefix(p, "~") {
			return "./" + p
		}
		return p
	}
}

func main() {
	// Options
	reverse := getopt.BoolLong("reverse", 'r', "Sort files in reverse alphabetical order.")
	maxFiles := getopt.IntLong("max-files", 'n', -1, "Limit the number of files listed.")
	showDirs := getopt.BoolLong("show-directories", 'd', "Print directories too.")
	showAll := getopt.BoolLong("show-all", 'a', "Show hidden directories (like .git) that are hidden by default.")
	para := getopt.IntLong("para", 'j', 0, "Limit the number of parallel worker goroutines (defaults to min(8, CPU cores)).")
	maxDepth := getopt.IntLong("max-depth", 'm', -1, "Limit the max depth for subdirectories.")
	help := getopt.BoolLong("help", 'h', "Show help message.")

	// Output control options
	stripStartDirOpt := getopt.BoolLong("strip-start-dir", 0, "Strip leading ./ from relative output path (default).")
	noStripStartDirOpt := getopt.BoolLong("no-strip-start-dir", 0, "Do not strip leading ./ from relative output path.")
	showFullpathOpt := getopt.BoolLong("show-fullpath", 'F', "Show full path of the file.")
	noShowFullpathOpt := getopt.BoolLong("no-show-fullpath", 0, "Do not show full path of the file.")
	homeTildOpt := getopt.BoolLong("home-tild", 0, "Replace user home directory with ~ in full path output (default).")
	noHomeTildOpt := getopt.BoolLong("no-home-tild", 0, "Do not replace user home directory with ~ in full path output.")
	showRelativeOpt := getopt.BoolLong("show-relative-path", 'R', "Show relative path output (default).")
	noShowRelativeOpt := getopt.BoolLong("no-show-relative-path", 0, "Do not show relative path output.")

	getopt.SetParameters("[DIR ...]")
	getopt.Parse()

	if *help {
		getopt.Usage()
		os.Exit(0)
	}

	// Parse output control options
	stripStartDir := true
	if *noStripStartDirOpt {
		stripStartDir = false
	}
	if *stripStartDirOpt {
		stripStartDir = true
	}

	showFullpath := false
	if *showFullpathOpt {
		showFullpath = true
	}
	if *noShowFullpathOpt {
		showFullpath = false
	}

	homeTild := true
	if *noHomeTildOpt {
		homeTild = false
	}
	if *homeTildOpt {
		homeTild = true
	}

	showRelative := true
	if *noShowRelativeOpt {
		showRelative = false
	}
	if *showRelativeOpt {
		showRelative = true
	}

	// Metavar checks/limit checks
	var limit int64
	hasLimit := false
	if getopt.Lookup('n').Seen() {
		if *maxFiles < 0 {
			fmt.Fprintln(os.Stderr, "list-files: option -n/--max-files: must be a non-negative integer")
			os.Exit(2)
		}
		limit = int64(*maxFiles)
		hasLimit = true
	}

	var maxDepthLimit int
	hasMaxDepth := false
	if getopt.Lookup('m').Seen() {
		if *maxDepth < 0 {
			fmt.Fprintln(os.Stderr, "list-files: option -m/--max-depth: must be a non-negative integer")
			os.Exit(2)
		}
		maxDepthLimit = *maxDepth
		hasMaxDepth = true
	}

	dirs := getopt.Args()
	if len(dirs) == 0 {
		dirs = []string{"."}
	}

	// Determine max workers
	var maxWorkers int
	if getopt.Lookup('j').Seen() {
		if *para <= 0 {
			fmt.Fprintln(os.Stderr, "list-files: option -j/--para: must be a positive integer")
			os.Exit(2)
		}
		maxWorkers = *para
	} else {
		maxWorkers = runtime.NumCPU()
		if maxWorkers > 8 {
			maxWorkers = 8
		}
	}
	sem := make(chan struct{}, maxWorkers)

	state, cancel := list_files.NewTraversalState(limit, hasLimit)
	defer cancel()

	overallSuccess := true
	out := make(chan string, 100)

	// Consume out channel and print to stdout
	done := make(chan struct{})
	go func() {
		defer close(done)
		homeDir, _ := os.UserHomeDir()
		for p := range out {
			if state.Increment() {
				// 1. Relative path
				relPath := formatRelativePath(p, stripStartDir)

				// 2. Full path
				var fullPath string
				if showFullpath {
					abs, err := filepath.Abs(p)
					if err == nil {
						fullPath = abs
						if homeTild && homeDir != "" {
							if fullPath == homeDir {
								fullPath = "~"
							} else if strings.HasPrefix(fullPath, homeDir+string(filepath.Separator)) {
								fullPath = "~" + fullPath[len(homeDir):]
							}
						}
					} else {
						fullPath = p
					}
				}

				// 3. Print
				if showRelative {
					if _, err := fmt.Println(relPath); err != nil {
						if isBrokenPipe(err) {
							os.Exit(0)
						}
						fmt.Fprintf(os.Stderr, "Write error: %v\n", err)
						os.Exit(2)
					}
				}
				if showFullpath {
					if _, err := fmt.Println(fullPath); err != nil {
						if isBrokenPipe(err) {
							os.Exit(0)
						}
						fmt.Fprintf(os.Stderr, "Write error: %v\n", err)
						os.Exit(2)
					}
				}
			}
		}
	}()

	for _, directory := range dirs {
		if state.LimitReached() {
			break
		}
		if !list_files.TraverseDir(directory, state, sem, *showDirs, *showAll, *reverse, hasMaxDepth, maxDepthLimit, out) {
			overallSuccess = false
		}
	}

	close(out)
	<-done

	if !overallSuccess {
		os.Exit(1)
	}
}
