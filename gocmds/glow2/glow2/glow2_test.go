package glow2

import (
	"strings"
	"testing"
)

func TestRenderMarkdown(t *testing.T) {
	input := []byte("# Hello World\nThis is a test.")

	// Test dark style
	out, err := RenderMarkdown(input, "dark", 80, true)
	if err != nil {
		t.Fatalf("Failed to render markdown: %v", err)
	}
	if !strings.Contains(out, "Hello") || !strings.Contains(out, "World") {
		t.Errorf("Expected output to contain 'Hello' and 'World', got: %q", out)
	}

	// Test force color off (notty style)
	outNotty, err := RenderMarkdown(input, "dark", 80, false)
	if err != nil {
		t.Fatalf("Failed to render markdown with no color: %v", err)
	}
	if outNotty == "" {
		t.Errorf("Expected non-empty output, got empty")
	}
	if !strings.Contains(outNotty, "Hello World") {
		t.Errorf("Expected non-colored output to contain 'Hello World', got: %q", outNotty)
	}
}
