package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"strconv"

	"github.com/mattn/go-isatty"
	"glow2/glow2"
)

var style string
var width int
var color string
var help bool

func init() {
	flag.StringVar(&style, "style", "auto", "style name or JSON path (default \"auto\")")
	flag.StringVar(&style, "s", "auto", "style name or JSON path (shorthand)")
	flag.IntVar(&width, "width", 0, "word-wrap at width (set to 0 to disable or auto-detect)")
	flag.IntVar(&width, "w", 0, "word-wrap at width (shorthand)")
	flag.StringVar(&color, "color", "auto", "color output: always, never, auto (default \"auto\")")
	flag.BoolVar(&help, "help", false, "show help message")
	flag.BoolVar(&help, "h", false, "show help message (shorthand)")
}

func main() {
	flag.Parse()

	if help {
		fmt.Fprintf(os.Stdout, "Usage of %s:\n", os.Args[0])
		flag.PrintDefaults()
		os.Exit(0)
	}

	if width == 0 {
		if colsStr := os.Getenv("FZF_PREVIEW_COLUMNS"); colsStr != "" {
			if cols, err := strconv.Atoi(colsStr); err == nil && cols > 0 {
				width = cols
			}
		}
		if width == 0 {
			if colsStr := os.Getenv("COLUMNS"); colsStr != "" {
				if cols, err := strconv.Atoi(colsStr); err == nil && cols > 0 {
					width = cols
				}
			}
		}
		if width == 0 {
			width = 80 // fallback
		}
	}

	var forceColor bool
	switch color {
	case "always":
		forceColor = true
	case "never":
		forceColor = false
	case "auto":
		forceColor = isatty.IsTerminal(os.Stdout.Fd()) || isatty.IsCygwinTerminal(os.Stdout.Fd())
	default:
		fmt.Fprintf(os.Stderr, "invalid value for --color: %s (must be always, never, or auto)\n", color)
		os.Exit(2)
	}

	var markdown []byte
	var err error

	if flag.NArg() == 0 {
		markdown, err = io.ReadAll(os.Stdin)
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to read from stdin: %v\n", err)
			os.Exit(2)
		}
	} else {
		for _, arg := range flag.Args() {
			if arg == "-" {
				content, err := io.ReadAll(os.Stdin)
				if err != nil {
					fmt.Fprintf(os.Stderr, "failed to read from stdin: %v\n", err)
					os.Exit(2)
				}
				markdown = append(markdown, content...)
			} else {
				content, err := os.ReadFile(arg)
				if err != nil {
					fmt.Fprintf(os.Stderr, "failed to read file %s: %v\n", arg, err)
					os.Exit(2)
				}
				markdown = append(markdown, content...)
			}
		}
	}

	rendered, err := glow2.RenderMarkdown(markdown, style, width, forceColor)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to render markdown: %v\n", err)
		os.Exit(2)
	}

	fmt.Print(rendered)
}
