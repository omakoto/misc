// Package grepgo provides a simple grep-like package using standard RE2 regex.
package grepgo

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"regexp"
)

// GrepOptions contains the options for the grep execution.
type GrepOptions struct {
	IgnoreCase bool
}

// Grep scans the sources and prints lines matching the pattern to stdout.
// If any file reading or opening errors occur, it logs them to stderr and returns the first error encountered.
// If multiple sources are provided, it prefixes each match with the filename.
func Grep(pattern string, sources []string, opts GrepOptions, stdout io.Writer, stderr io.Writer) (bool, error) {
	if opts.IgnoreCase {
		pattern = "(?i)" + pattern
	}
	re, err := regexp.Compile(pattern)
	if err != nil {
		return false, fmt.Errorf("invalid pattern: %w", err)
	}

	matchedAny := false
	var firstErr error

	if len(sources) == 0 {
		matched, err := grepReader(re, os.Stdin, "", false, stdout)
		if err != nil {
			return false, err
		}
		return matched, nil
	}

	printFilename := len(sources) > 1

	for _, source := range sources {
		var r io.Reader
		var filename string
		var closer io.Closer

		if source == "-" {
			r = os.Stdin
			filename = "(standard input)"
		} else {
			f, err := os.Open(source)
			if err != nil {
				fmt.Fprintf(stderr, "grepgo: %s: %v\n", source, err)
				if firstErr == nil {
					firstErr = err
				}
				continue
			}
			r = f
			closer = f
			filename = source
		}

		matched, err := grepReader(re, r, filename, printFilename, stdout)
		if closer != nil {
			closer.Close()
		}

		if err != nil {
			fmt.Fprintf(stderr, "grepgo: %s: %v\n", filename, err)
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		if matched {
			matchedAny = true
		}
	}

	return matchedAny, firstErr
}

func grepReader(re *regexp.Regexp, r io.Reader, filename string, printFilename bool, stdout io.Writer) (bool, error) {
	scanner := bufio.NewScanner(r)
	matched := false
	for scanner.Scan() {
		line := scanner.Text()
		if re.MatchString(line) {
			matched = true
			if printFilename {
				fmt.Fprintf(stdout, "%s:%s\n", filename, line)
			} else {
				fmt.Fprintln(stdout, line)
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return matched, err
	}
	return matched, nil
}
