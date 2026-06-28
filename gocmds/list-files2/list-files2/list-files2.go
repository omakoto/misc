package list_files2

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync/atomic"
)

// hiddenDirectories maps directory names that should be hidden by default.
// It is easy to add more hidden directories here.
var hiddenDirectories = map[string]bool{
	".git": true,
}

func isHiddenDirectory(name string) bool {
	return hiddenDirectories[name]
}

// TraversalState tracks the state of traversal, including limits on max files printed.
type TraversalState struct {
	maxFiles     int64
	hasLimit     bool
	printedCount int64
	ctx          context.Context
	cancel       context.CancelFunc
}

func NewTraversalState(maxFiles int64, hasLimit bool) (*TraversalState, context.CancelFunc) {
	ctx, cancel := context.WithCancel(context.Background())
	return &TraversalState{
		maxFiles: maxFiles,
		hasLimit: hasLimit,
		ctx:      ctx,
		cancel:   cancel,
	}, cancel
}

func (s *TraversalState) LimitReached() bool {
	if !s.hasLimit {
		return false
	}
	return atomic.LoadInt64(&s.printedCount) >= s.maxFiles
}

func (s *TraversalState) Increment() bool {
	if s.LimitReached() {
		return false
	}
	if s.hasLimit {
		val := atomic.AddInt64(&s.printedCount, 1)
		if val >= s.maxFiles {
			s.cancel()
		}
		return val <= s.maxFiles
	}
	atomic.AddInt64(&s.printedCount, 1)
	return true
}

type task struct {
	path         string
	inlineSubdir string
	subStream    <-chan string
}

// TraverseDir starts the traversal of startDir.
func TraverseDir(startDir string, state *TraversalState, sem chan struct{}, showDirs, showAll, reverse bool, hasMaxDepth bool, maxDepth int, out chan<- string) bool {
	fi, err := os.Stat(startDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: '%s' is not a directory.\n", startDir)
		return false
	}
	if !fi.IsDir() {
		fmt.Fprintf(os.Stderr, "Error: '%s' is not a directory.\n", startDir)
		return false
	}

	if showDirs {
		if state.LimitReached() {
			return true
		}
		p := startDir
		if !strings.HasSuffix(p, "/") {
			p += "/"
		}
		out <- p
	}

	_traverseDirRecursive(startDir, 0, state, sem, showDirs, showAll, reverse, hasMaxDepth, maxDepth, out)
	return true
}

func _traverseDirRecursive(currentDir string, depth int, state *TraversalState, sem chan struct{}, showDirs, showAll, reverse bool, hasMaxDepth bool, maxDepth int, out chan<- string) {
	if state.LimitReached() {
		return
	}
	if hasMaxDepth && depth >= maxDepth {
		return
	}

	tasks, ok := scanDir(currentDir, depth, state, sem, showDirs, showAll, reverse, hasMaxDepth, maxDepth, out)
	if !ok {
		return
	}

	// Output tasks in order to preserve depth-first sorting.
	// This part is I/O free and runs without holding a slot in the semaphore.
	for _, t := range tasks {
		if state.LimitReached() {
			break
		}
		if t.path != "" {
			out <- t.path
		} else if t.inlineSubdir != "" {
			_traverseDirRecursive(t.inlineSubdir, depth+1, state, sem, showDirs, showAll, reverse, hasMaxDepth, maxDepth, out)
		} else if t.subStream != nil {
			for p := range t.subStream {
				if state.LimitReached() {
					break
				}
				out <- p
			}
		}
	}
}

// scanDir acquires the semaphore, reads the directory entries, schedules child goroutines,
// and releases the semaphore before returning the tasks.
func scanDir(currentDir string, depth int, state *TraversalState, sem chan struct{}, showDirs, showAll, reverse bool, hasMaxDepth bool, maxDepth int, out chan<- string) ([]task, bool) {
	sem <- struct{}{}
	defer func() { <-sem }()

	if state.LimitReached() {
		return nil, false
	}
	if hasMaxDepth && depth >= maxDepth {
		return nil, false
	}

	entries, err := os.ReadDir(currentDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading directory '%s': %v\n", currentDir, err)
		return nil, false
	}

	sort.Slice(entries, func(i, j int) bool {
		if reverse {
			return entries[i].Name() > entries[j].Name()
		}
		return entries[i].Name() < entries[j].Name()
	})

	var tasks []task
	firstDir := true

	for _, entry := range entries {
		if state.LimitReached() {
			break
		}

		name := entry.Name()
		entryPath := filepath.Join(currentDir, name)

		var isDir, isFile bool
		if entry.Type()&fs.ModeSymlink != 0 {
			fi, statErr := os.Stat(entryPath)
			if statErr == nil {
				isDir = fi.IsDir()
				isFile = !fi.IsDir()
			}
		} else {
			isDir = entry.Type().IsDir()
			isFile = !entry.Type().IsDir()
		}

		if !showAll && isDir && isHiddenDirectory(name) {
			continue
		}

		isDirToPrint := isDir && showDirs
		if isFile || isDirToPrint {
			p := entryPath
			if isDirToPrint && !strings.HasSuffix(p, "/") {
				p += "/"
			}
			tasks = append(tasks, task{path: p})
		}

		// Avoid traversing symlinks to directories to prevent infinite recursion/loops.
		if entry.Type().IsDir() {
			if !hasMaxDepth || depth+1 < maxDepth {
				if firstDir {
					tasks = append(tasks, task{inlineSubdir: entryPath})
					firstDir = false
				} else {
					subStream := make(chan string, 100)
					tasks = append(tasks, task{subStream: subStream})
					go func(path string, ch chan string, d int) {
						_traverseDirRecursive(path, d, state, sem, showDirs, showAll, reverse, hasMaxDepth, maxDepth, ch)
						close(ch)
					}(entryPath, subStream, depth+1)
				}
			}
		}
	}

	return tasks, true
}
