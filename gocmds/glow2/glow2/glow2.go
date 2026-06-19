package glow2

import (
	"fmt"
	"os"

	"github.com/charmbracelet/glamour"
)

// RenderMarkdown renders markdown text with specific styling options.
func RenderMarkdown(markdown []byte, style string, width int, forceColor bool) (string, error) {
	glamourStyle := style
	if glamourStyle == "auto" || glamourStyle == "" {
		glamourStyle = "dark"
		colorFgbg := os.Getenv("COLORFGBG")
		if len(colorFgbg) > 0 {
			lastPart := ""
			for i := len(colorFgbg) - 1; i >= 0; i-- {
				if colorFgbg[i] == ';' {
					lastPart = colorFgbg[i+1:]
					break
				}
			}
			if lastPart == "7" || lastPart == "9" || lastPart == "11" || lastPart == "15" {
				glamourStyle = "light"
			}
		}
	}

	if !forceColor {
		glamourStyle = "notty"
	}

	var styleOpt glamour.TermRendererOption
	if _, err := os.Stat(glamourStyle); err == nil {
		styleOpt = glamour.WithStylePath(glamourStyle)
	} else {
		styleOpt = glamour.WithStandardStyle(glamourStyle)
	}

	r, err := glamour.NewTermRenderer(
		styleOpt,
		glamour.WithWordWrap(width),
	)
	if err != nil {
		return "", fmt.Errorf("failed to create glamour renderer: %w", err)
	}

	rendered, err := r.RenderBytes(markdown)
	if err != nil {
		return "", fmt.Errorf("failed to render markdown: %w", err)
	}

	return string(rendered), nil
}
