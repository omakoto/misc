package grepgo

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestGrep(t *testing.T) {
	// Create a temp directory for test files
	tmpDir := t.TempDir()

	file1Path := filepath.Join(tmpDir, "file1.txt")
	file2Path := filepath.Join(tmpDir, "file2.txt")

	err := os.WriteFile(file1Path, []byte("Hello World\nGo Programming\nhello world\n"), 0644)
	if err != nil {
		t.Fatalf("failed to write file1: %v", err)
	}

	err = os.WriteFile(file2Path, []byte("Grep in Go\nIgnore case option\n"), 0644)
	if err != nil {
		t.Fatalf("failed to write file2: %v", err)
	}

	tests := []struct {
		name       string
		pattern    string
		sources    []string
		opts       GrepOptions
		wantMatch  bool
		wantErr    bool
		wantStdout string
	}{
		{
			name:       "case-sensitive match single file",
			pattern:    "Hello",
			sources:    []string{file1Path},
			opts:       GrepOptions{IgnoreCase: false},
			wantMatch:  true,
			wantErr:    false,
			wantStdout: "Hello World\n",
		},
		{
			name:       "case-insensitive match single file",
			pattern:    "Hello",
			sources:    []string{file1Path},
			opts:       GrepOptions{IgnoreCase: true},
			wantMatch:  true,
			wantErr:    false,
			wantStdout: "Hello World\nhello world\n",
		},
		{
			name:       "no match single file",
			pattern:    "Python",
			sources:    []string{file1Path},
			opts:       GrepOptions{IgnoreCase: false},
			wantMatch:  false,
			wantErr:    false,
			wantStdout: "",
		},
		{
			name:       "multiple files matching",
			pattern:    "Go",
			sources:    []string{file1Path, file2Path},
			opts:       GrepOptions{IgnoreCase: false},
			wantMatch:  true,
			wantErr:    false,
			wantStdout: file1Path + ":Go Programming\n" + file2Path + ":Grep in Go\n",
		},
		{
			name:      "invalid pattern",
			pattern:   "[a-z",
			sources:   []string{file1Path},
			opts:      GrepOptions{IgnoreCase: false},
			wantMatch: false,
			wantErr:   true,
		},
		{
			name:      "non-existent file",
			pattern:   "Go",
			sources:   []string{filepath.Join(tmpDir, "does-not-exist.txt")},
			opts:      GrepOptions{IgnoreCase: false},
			wantMatch: false,
			wantErr:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var stdout bytes.Buffer
			var stderr bytes.Buffer

			matched, err := Grep(tt.pattern, tt.sources, tt.opts, &stdout, &stderr)
			if (err != nil) != tt.wantErr {
				t.Fatalf("Grep() error = %v, wantErr %v", err, tt.wantErr)
			}

			if matched != tt.wantMatch {
				t.Errorf("Grep() matched = %v, want %v", matched, tt.wantMatch)
			}

			if !tt.wantErr && stdout.String() != tt.wantStdout {
				t.Errorf("Grep() stdout = %q, want %q", stdout.String(), tt.wantStdout)
			}
		})
	}
}
