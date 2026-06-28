package list_files2

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

	runTraverse := func(limit int64, hasLimit, showDirs, showAll, reverse bool) []string {
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

		TraverseDir(tempDir, state, sem, showDirs, showAll, reverse, out)
		close(out)
		<-done
		return results
	}

	t.Run("Default Alphabetical Depth First", func(t *testing.T) {
		got := runTraverse(0, false, false, false, false)
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
		got := runTraverse(0, false, false, false, true)
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
		got := runTraverse(0, false, true, false, false)
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
		got := runTraverse(4, true, true, false, false)
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
		got := runTraverse(0, false, false, true, false)
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
		got := runTraverse(0, false, true, true, false)
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
}
