package main

import (
	"fmt"
	"os"
	"os/signal"
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

func main() {
	// Options
	reverse := getopt.BoolLong("reverse", 'r', "Sort files in reverse alphabetical order.")
	maxFiles := getopt.IntLong("max-files", 'n', -1, "Limit the number of files listed.")
	showDirs := getopt.BoolLong("show-directories", 'd', "Print directories too.")
	showAll := getopt.BoolLong("show-all", 'a', "Show hidden directories (like .git) that are hidden by default.")
	para := getopt.IntLong("para", 'j', 0, "Limit the number of parallel worker goroutines (defaults to min(8, CPU cores)).")
	maxDepth := getopt.IntLong("max-depth", 'm', -1, "Limit the max depth for subdirectories.")
	help := getopt.BoolLong("help", 'h', "Show help message.")

	getopt.SetParameters("[DIR ...]")
	getopt.Parse()

	if *help {
		getopt.Usage()
		os.Exit(0)
	}

	// Metavar checks/limit checks
	var limit int64
	hasLimit := false
	if getopt.Lookup('n').Seen() {
		if *maxFiles < 0 {
			fmt.Fprintln(os.Stderr, "list-files2: option -n/--max-files: must be a non-negative integer")
			os.Exit(2)
		}
		limit = int64(*maxFiles)
		hasLimit = true
	}

	var maxDepthLimit int
	hasMaxDepth := false
	if getopt.Lookup('m').Seen() {
		if *maxDepth < 0 {
			fmt.Fprintln(os.Stderr, "list-files2: option -m/--max-depth: must be a non-negative integer")
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
			fmt.Fprintln(os.Stderr, "list-files2: option -j/--para: must be a positive integer")
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
		for p := range out {
			if state.Increment() {
				_, err := fmt.Println(p)
				if err != nil {
					if isBrokenPipe(err) {
						os.Exit(0)
					}
					fmt.Fprintf(os.Stderr, "Write error: %v\n", err)
					os.Exit(2)
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
