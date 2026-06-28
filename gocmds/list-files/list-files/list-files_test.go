package list_files

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestTraverseDir(t *testing.T) {
	tempDir := t.TempDir()

	// Create structure:
	// tempDir/
	// ├── .git/
	// │   └── config
	// ├── a/
	// │   └── x.txt
	// ├── b/
	// │   └── y.txt
	// ├── c.txt
	// └── d/
	//     └── e/
	//         └── z.txt
	os.MkdirAll(filepath.Join(tempDir, ".git"), 0755)
	os.MkdirAll(filepath.Join(tempDir, "a"), 0755)
	os.MkdirAll(filepath.Join(tempDir, "b"), 0755)
	os.MkdirAll(filepath.Join(tempDir, "d", "e"), 0755)

	os.WriteFile(filepath.Join(tempDir, ".git", "config"), []byte("config"), 0644)
	os.WriteFile(filepath.Join(tempDir, "a", "x.txt"), []byte("a/x"), 0644)
	os.WriteFile(filepath.Join(tempDir, "b", "y.txt"), []byte("b/y"), 0644)
	os.WriteFile(filepath.Join(tempDir, "c.txt"), []byte("c"), 0644)
	os.WriteFile(filepath.Join(tempDir, "d", "e", "z.txt"), []byte("d/e/z"), 0644)

	runTraverse := func(limit int64, hasLimit, showDirs, showAll, reverse bool, hasMaxDepth bool, maxDepth int) []string {
		sem := make(chan struct{}, 4)
		state, cancel := NewTraversalState(limit, hasLimit)
		defer cancel()

		out := make(chan string, 100)
		done := make(chan struct{})
		var results []string

		go func() {
			for p := range out {
				if state.Increment() {
					rel, err := filepath.Rel(tempDir, p)
					if err == nil {
						// Re-append trailing slash if original had it
						if strings.HasSuffix(p, "/") && !strings.HasSuffix(rel, "/") {
							rel += "/"
						}
						results = append(results, rel)
					}
				}
			}
			close(done)
		}()

		TraverseDir(tempDir, state, sem, showDirs, showAll, reverse, hasMaxDepth, maxDepth, out)
		close(out)
		<-done
		return results
	}

	t.Run("Default Alphabetical Depth First", func(t *testing.T) {
		got := runTraverse(0, false, false, false, false, false, 0)
		want := []string{
			"a/x.txt",
			"b/y.txt",
			"c.txt",
			"d/e/z.txt",
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("got %v, want %v", got, want)
		}
	})

	t.Run("Reverse Alphabetical Depth First", func(t *testing.T) {
		got := runTraverse(0, false, false, false, true, false, 0)
		want := []string{
			"d/e/z.txt",
			"c.txt",
			"b/y.txt",
			"a/x.txt",
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("got %v, want %v", got, want)
		}
	})

	t.Run("Show Directories Alphabetical", func(t *testing.T) {
		got := runTraverse(0, false, true, false, false, false, 0)
		want := []string{
			"./",
			"a/",
			"a/x.txt",
			"b/",
			"b/y.txt",
			"c.txt",
			"d/",
			"d/e/",
			"d/e/z.txt",
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("got %v, want %v", got, want)
		}
	})

	t.Run("Show Directories Limit", func(t *testing.T) {
		got := runTraverse(4, true, true, false, false, false, 0)
		want := []string{
			"./",
			"a/",
			"a/x.txt",
			"b/",
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("got %v, want %v", got, want)
		}
	})

	t.Run("Show All Files (include hidden)", func(t *testing.T) {
		got := runTraverse(0, false, false, true, false, false, 0)
		want := []string{
			".git/config",
			"a/x.txt",
			"b/y.txt",
			"c.txt",
			"d/e/z.txt",
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("got %v, want %v", got, want)
		}
	})

	t.Run("Show All With Directories", func(t *testing.T) {
		got := runTraverse(0, false, true, true, false, false, 0)
		want := []string{
			"./",
			".git/",
			".git/config",
			"a/",
			"a/x.txt",
			"b/",
			"b/y.txt",
			"c.txt",
			"d/",
			"d/e/",
			"d/e/z.txt",
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("got %v, want %v", got, want)
		}
	})

	t.Run("Max Depth 0", func(t *testing.T) {
		// depth 0: only the start directory itself is listed (if showDirs is true)
		got := runTraverse(0, false, true, false, false, true, 0)
		want := []string{
			"./",
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("got %v, want %v", got, want)
		}
	})

	t.Run("Max Depth 1 With Directories", func(t *testing.T) {
		// depth 1: start directory (depth 0) and direct entries (depth 1)
		got := runTraverse(0, false, true, false, false, true, 1)
		want := []string{
			"./",
			"a/",
			"b/",
			"c.txt",
			"d/",
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("got %v, want %v", got, want)
		}
	})

	t.Run("Max Depth 1 Default (no directories)", func(t *testing.T) {
		got := runTraverse(0, false, false, false, false, true, 1)
		want := []string{
			"c.txt",
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("got %v, want %v", got, want)
		}
	})

	t.Run("Max Depth 2 With Directories", func(t *testing.T) {
		got := runTraverse(0, false, true, false, false, true, 2)
		want := []string{
			"./",
			"a/",
			"a/x.txt",
			"b/",
			"b/y.txt",
			"c.txt",
			"d/",
			"d/e/",
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("got %v, want %v", got, want)
		}
	})
}
