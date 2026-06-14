// Entry point for grepgo command.
package main

import (
	"flag"
	"fmt"
	"os"

	"grepgo/grepgo"
)

func main() {
	ignoreCase := flag.Bool("i", false, "Ignore case distinctions in patterns and input data.")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: grepgo [-i] PATTERN [FILE...]\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	args := flag.Args()
	if len(args) < 1 {
		flag.Usage()
		os.Exit(2)
	}

	pattern := args[0]
	files := args[1:]

	opts := grepgo.GrepOptions{
		IgnoreCase: *ignoreCase,
	}

	matched, err := grepgo.Grep(pattern, files, opts, os.Stdout, os.Stderr)
	if err != nil {
		// If there was an error but we found matches, what should the exit status be?
		// Standard grep exits with 2 if there's any file read error.
		// Since Grep returns the first error, we always exit with 2 if err != nil.
		os.Exit(2)
	}

	if matched {
		os.Exit(0)
	} else {
		os.Exit(1)
	}
}
