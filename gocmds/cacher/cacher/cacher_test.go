package cacher

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestCacherBasic(t *testing.T) {
	tempDir := t.TempDir()
	cacheFile := filepath.Join(tempDir, "cache.txt")
	lockFile := filepath.Join(tempDir, "cache.lock")

	// Test 1: First run writes default string
	opts := &Options{
		Command:     "echo -n 'hello'",
		CacheFile:   cacheFile,
		LockFile:    lockFile,
		MaxAge:      10,
		DefaultText: "default",
		Timeout:     -1,
		Verbose:     true,
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	// Run first time (no cache exists)
	// In the real code, it starts the daemon in background.
	// But in tests, startDaemon might fail or try to run the test binary with -daemon-run.
	// To prevent startDaemon executing the test binary as a daemon, we can override or test
	// the fresh cache path, where startDaemon is NOT called.

	// Create cache file directly to simulate an existing fresh cache
	err := os.WriteFile(cacheFile, []byte("cached_value"), 0666)
	if err != nil {
		t.Fatalf("failed to write cache file: %v", err)
	}

	// Make lock file and lock age recent (fresh cache)
	opts.MaxAge = 100
	exitCode := Run(opts, &stdout, &stderr)
	if exitCode != 0 {
		t.Errorf("expected exit code 0, got %d", exitCode)
	}

	if stdout.String() != "cached_value" {
		t.Errorf("expected stdout 'cached_value', got %q", stdout.String())
	}
}

func TestCacherFreshVsStale(t *testing.T) {
	tempDir := t.TempDir()
	cacheFile := filepath.Join(tempDir, "cache.txt")
	lockFile := filepath.Join(tempDir, "cache.lock")

	err := os.WriteFile(cacheFile, []byte("cached_value"), 0666)
	if err != nil {
		t.Fatalf("failed to write cache file: %v", err)
	}

	// Let's set MaxAge to 0 (stale)
	// We want to test that it recognizes stale and prints the cache.
	// Wait, stale run starts the daemon. Since startDaemon executes os.Executable() (which is the test binary),
	// we want to avoid executing the test binary.
	// We can test Foreground run which doesn't spawn a daemon!
	opts := &Options{
		Command:     "echo -n 'new_value'",
		CacheFile:   cacheFile,
		LockFile:    lockFile,
		MaxAge:      0,
		DefaultText: "default",
		Timeout:     -1,
		Foreground:  true, // Foreground doesn't daemonize, runs in foreground
		Verbose:     true,
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := Run(opts, &stdout, &stderr)
	if exitCode != 0 {
		t.Errorf("expected exit code 0, got %d", exitCode)
	}

	// Wait, foreground run updates the cache and prints the new value
	data, err := os.ReadFile(cacheFile)
	if err != nil {
		t.Fatalf("failed to read cache: %v", err)
	}
	if string(data) != "new_value" {
		t.Errorf("expected cache to be 'new_value', got %q", string(data))
	}
	if stdout.String() != "new_value" {
		t.Errorf("expected stdout 'new_value', got %q", stdout.String())
	}
}
