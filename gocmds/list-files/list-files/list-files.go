package list_files

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
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

type item struct {
	path             string
	inlineSubdirPath string
	inlineSubdir     *dirResultTree
	futureChan       <-chan *dirResultTree
}

type dirResultTree struct {
	items []item
}

// TraverseDir starts the traversal of startDir.
func TraverseDir(startDir string, state *TraversalState, sem chan struct{}, showDirs, showAll, reverse bool, hasMaxDepth bool, maxDepth int, pattern string, out chan<- string) bool {
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
		// If there is a pattern, we should check if the startDir matches it?
		// Usually startDir is passed explicitly, so maybe we don't filter it,
		// or maybe we do?
		// If I run `list-files -p "matching" dir`, `dir/` itself might not match.
		// Standard find: `find dir -name "matching"` does not print `dir` unless it matches.
		// But `list-files` prints startDir if showDirs is true.
		// Let's match startDir too if showDirs is true and pattern is set.
		matched := true
		if pattern != "" {
			matched, _ = filepath.Match(pattern, filepath.Base(startDir))
		}
		if matched {
			p := startDir
			if !strings.HasSuffix(p, "/") {
				p += "/"
			}
			out <- p
		}
	}

	tree, ok := buildDirTree(startDir, 0, state, sem, showDirs, showAll, reverse, hasMaxDepth, maxDepth, pattern)
	if ok {
		printDirTree(tree, state, out)
	}
	return ok
}

func buildDirTree(currentDir string, depth int, state *TraversalState, sem chan struct{}, showDirs, showAll, reverse bool, hasMaxDepth bool, maxDepth int, pattern string) (*dirResultTree, bool) {
	tree, ok := scanDirTree(currentDir, depth, state, sem, showDirs, showAll, reverse, hasMaxDepth, maxDepth, pattern)
	if !ok {
		return nil, false
	}

	for i := range tree.items {
		if tree.items[i].inlineSubdirPath != "" {
			subTree, _ := buildDirTree(tree.items[i].inlineSubdirPath, depth+1, state, sem, showDirs, showAll, reverse, hasMaxDepth, maxDepth, pattern)
			tree.items[i].inlineSubdir = subTree
		}
	}
	return tree, true
}

func scanDirTree(currentDir string, depth int, state *TraversalState, sem chan struct{}, showDirs, showAll, reverse bool, hasMaxDepth bool, maxDepth int, pattern string) (*dirResultTree, bool) {
	sem <- struct{}{}
	defer func() { <-sem }()

	if state.LimitReached() {
		return &dirResultTree{}, true
	}
	if hasMaxDepth && depth >= maxDepth {
		return &dirResultTree{}, true
	}

	entries, err := os.ReadDir(currentDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading directory '%s': %v\n", currentDir, err)
		return nil, false
	}

	slices.SortFunc(entries, func(a, b fs.DirEntry) int {
		aName, bName := a.Name(), b.Name()
		if reverse {
			if aName > bName {
				return -1
			}
			if aName < bName {
				return 1
			}
			return 0
		}
		if aName < bName {
			return -1
		}
		if aName > bName {
			return 1
		}
		return 0
	})

	var items []item
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

		isDirToPrint := isDir && showDirs
		if isFile || isDirToPrint {
			matched := true
			if pattern != "" {
				var err error
				matched, err = filepath.Match(pattern, name)
				if err != nil {
					matched = false
				}
			}
			if matched {
				p := entryPath
				if isDirToPrint && !strings.HasSuffix(p, "/") {
					p += "/"
				}
				items = append(items, item{path: p})
			}
		}

		// Avoid traversing symlinks to directories to prevent infinite recursion/loops.
		if entry.Type().IsDir() {
			shouldTraverse := showAll || !isHiddenDirectory(name)
			if shouldTraverse && (!hasMaxDepth || depth+1 < maxDepth) {
				if firstDir {
					items = append(items, item{inlineSubdirPath: entryPath})
					firstDir = false
				} else {
					futureChan := make(chan *dirResultTree, 1)
					items = append(items, item{futureChan: futureChan})
					go func(path string, ch chan *dirResultTree, d int) {
						defer close(ch)
						res, ok := buildDirTree(path, d, state, sem, showDirs, showAll, reverse, hasMaxDepth, maxDepth, pattern)
						if ok {
							ch <- res
						} else {
							ch <- nil
						}
					}(entryPath, futureChan, depth+1)
				}
			}
		}
	}

	return &dirResultTree{items: items}, true
}

func printDirTree(tree *dirResultTree, state *TraversalState, out chan<- string) {
	if tree == nil || state.LimitReached() {
		return
	}

	for _, item := range tree.items {
		if state.LimitReached() {
			break
		}
		if item.path != "" {
			out <- item.path
		} else if item.inlineSubdir != nil {
			printDirTree(item.inlineSubdir, state, out)
		} else if item.futureChan != nil {
			subTree := <-item.futureChan
			if subTree != nil {
				printDirTree(subTree, state, out)
			}
		}
	}
	out <- ""
}
