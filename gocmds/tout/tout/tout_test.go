package tout

import (
	"testing"
	"time"
)

func TestParseDuration(t *testing.T) {
	tests := []struct {
		input    string
		expected time.Duration
		err      bool
	}{
		{"0.1", 100 * time.Millisecond, false},
		{"2s", 2 * time.Second, false},
		{"1.5m", 90 * time.Second, false},
		{"1h", time.Hour, false},
		{"1d", 24 * time.Hour, false},
		{"", 0, true},
		{"abc", 0, true},
	}

	for _, tc := range tests {
		got, err := parseDuration(tc.input)
		if tc.err {
			if err == nil {
				t.Errorf("expected error for %q, got nil", tc.input)
			}
		} else {
			if err != nil {
				t.Errorf("unexpected error for %q: %v", tc.input, err)
			}
			if got != tc.expected {
				t.Errorf("for %q, expected %v, got %v", tc.input, tc.expected, got)
			}
		}
	}
}

func TestRun(t *testing.T) {
	// Test normal successful execution (exit code 0)
	code, err := Run("1s", "true", nil)
	if err != nil {
		t.Errorf("Run failed: %v", err)
	}
	if code != 0 {
		t.Errorf("expected exit code 0, got %d", code)
	}

	// Test normal non-zero exit code
	code, err = Run("1s", "false", nil)
	if err != nil {
		t.Errorf("Run failed: %v", err)
	}
	if code != 1 {
		t.Errorf("expected exit code 1, got %d", code)
	}

	// Test timeout (exit code 124)
	code, err = Run("0.05s", "sleep", []string{"1"})
	if err != nil {
		t.Errorf("Run failed: %v", err)
	}
	if code != 124 {
		t.Errorf("expected exit code 124 on timeout, got %d", code)
	}

	// Test invalid command error (should fail to start, exit code 125)
	code, err = Run("1s", "nonexistent-command-xyz", nil)
	if err == nil {
		t.Errorf("expected error for nonexistent command, got nil")
	}
	if code != 125 {
		t.Errorf("expected exit code 125 for start error, got %d", code)
	}
}
