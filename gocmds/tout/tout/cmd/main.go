package main

import (
	"fmt"
	"os"
	"tout/tout"
)

func usage() {
	fmt.Fprintf(os.Stderr, `Usage: tout DURATION COMMAND [ARGS...]
       tout -h | --help

Run COMMAND with a timeout. If the command times out, exits with status 124.
If it completes before the timeout, exits with the command's status.

DURATION: A number (in seconds by default), or with unit suffixes (e.g. 100ms, 2s, 1.5m, 1h).

Examples:
  tout 0.1 test -d /
  tout 2s sleep 5
`)
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(125)
	}

	arg1 := os.Args[1]
	if arg1 == "-h" || arg1 == "--help" {
		usage()
		os.Exit(0)
	}

	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "Error: missing command to execute")
		usage()
		os.Exit(125)
	}

	duration := os.Args[1]
	cmdName := os.Args[2]
	cmdArgs := os.Args[3:]

	exitCode, err := tout.Run(duration, cmdName, cmdArgs)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
	}

	os.Exit(exitCode)
}
