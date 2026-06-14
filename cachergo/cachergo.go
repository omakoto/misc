// cachergo - Cache command stdout, run command in background when expired.
// This is a Go-based drop-in replacement of the python cacher utility.
// Run 'cacher_test.bash' to verify changes.

package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"github.com/omakoto/go-common/src/runner"
)

var (
	command     string
	cacheFile   string
	maxAge      int = -1
	defaultText string = "?"
	lockFile    string
	verbose     bool
	timeout     int = -1
	showStderr  bool
	force       bool
	foreground  bool
	daemonRun   bool
)

func isTerminal(fd uintptr) bool {
	var termios syscall.Termios
	_, _, err := syscall.Syscall(syscall.SYS_IOCTL, fd, uintptr(syscall.TCGETS), uintptr(unsafe.Pointer(&termios)))
	return err == 0
}

func logMsg(msg string) {
	if !verbose {
		return
	}
	if isTerminal(2) {
		fmt.Fprintf(os.Stderr, "\033[90mcacher: %s\033[0m\n", msg)
	} else {
		fmt.Fprintf(os.Stderr, "cacher: %s\n", msg)
	}
}

func writePidAndUtime(lockF *os.File, lockFile string) {
	_ = lockF.Truncate(0)
	_, _ = lockF.Seek(0, io.SeekStart)
	_, _ = lockF.WriteString(fmt.Sprintf("%d\n", os.Getpid()))
	_ = lockF.Sync()
	now := time.Now()
	_ = os.Chtimes(lockFile, now, now)
}

func runDaemon(lockFile, cacheFile, command string, showStderr bool) {
	// The lock file descriptor is passed as FD 3.
	lockF := os.NewFile(3, lockFile)
	if lockF == nil {
		fmt.Fprintln(os.Stderr, "Daemon: failed to get lock file descriptor")
		os.Exit(1)
	}

	writePidAndUtime(lockF, lockFile)

	tmpFile := cacheFile + ".tmp"
	tmpF, err := os.OpenFile(tmpFile, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0666)
	if err != nil {
		_ = lockF.Close()
		os.Exit(1)
	}

	cmd := exec.Command("/bin/sh", "-c", command)
	cmd.Stdout = tmpF
	if showStderr {
		cmd.Stderr = os.Stderr
	} else {
		cmd.Stderr = nil
	}

	_ = cmd.Run()
	_ = tmpF.Close()

	if _, err := os.Stat(tmpFile); err == nil {
		_ = os.Rename(tmpFile, cacheFile)
	} else {
		_ = os.Remove(tmpFile)
	}

	_ = lockF.Close()
	os.Exit(0)
}

func startDaemon(lockF *os.File, lockFile string) {
	daemonArgs := []string{"--daemon-run"}
	for _, arg := range os.Args[1:] {
		if arg != "-g" && arg != "--foreground" && arg != "--daemon-run" {
			daemonArgs = append(daemonArgs, arg)
		}
	}

	cmd := exec.Command(os.Args[0], daemonArgs...)
	cmd.Stdin = nil
	cmd.Stdout = nil
	if showStderr {
		cmd.Stderr = os.Stderr
	} else {
		cmd.Stderr = nil
	}

	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.ExtraFiles = []*os.File{lockF}

	err := cmd.Start()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to start daemon: %v\n", err)
		_ = lockF.Close()
		os.Exit(1)
	}
}

func main() {
	runner.GenWrapper(runner.Options{WrapperPath: "../cacher2"})

	flag.StringVar(&command, "c", "", "")
	flag.StringVar(&command, "command", "", "")
	flag.StringVar(&cacheFile, "f", "", "")
	flag.StringVar(&cacheFile, "file", "", "")
	flag.IntVar(&maxAge, "a", -1, "")
	flag.IntVar(&maxAge, "max-age", -1, "")
	flag.StringVar(&defaultText, "d", "?", "")
	flag.StringVar(&defaultText, "default", "?", "")
	flag.StringVar(&lockFile, "l", "", "")
	flag.StringVar(&lockFile, "lock-file", "", "")
	flag.BoolVar(&verbose, "v", false, "")
	flag.BoolVar(&verbose, "verbose", false, "")
	flag.IntVar(&timeout, "t", -1, "")
	flag.IntVar(&timeout, "timeout", -1, "")
	flag.BoolVar(&showStderr, "show-stderr", false, "")
	flag.BoolVar(&force, "F", false, "")
	flag.BoolVar(&force, "force", false, "")
	flag.BoolVar(&foreground, "g", false, "")
	flag.BoolVar(&foreground, "foreground", false, "")
	flag.BoolVar(&daemonRun, "daemon-run", false, "")

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage of cacher:\n")
		fmt.Fprintf(os.Stderr, "  -c, --command COMMAND      command to run. Use /bin/sh -c to run it. required\n")
		fmt.Fprintf(os.Stderr, "  -f, --file CACHE-FILE      required. cache file to store command stdout\n")
		fmt.Fprintf(os.Stderr, "  -a, --max-age SECONDS      optional. if the cache file is older than this, run the command, unless it's already running.\n")
		fmt.Fprintf(os.Stderr, "  -d, --default TEXT         optional. default string to put in the file if it's the first run. Default is \"?\"\n")
		fmt.Fprintf(os.Stderr, "  -l, --lock-file LOCK-FILE  optional. lock file to detect double-run. default is CACHE-FILE.lock\n")
		fmt.Fprintf(os.Stderr, "  -v, --verbose              optional. enable verbose logging to stderr.\n")
		fmt.Fprintf(os.Stderr, "  -t, --timeout SECONDS      optional. if the previous run was taking more than this, kill it and start over.\n")
		fmt.Fprintf(os.Stderr, "      --show-stderr          optional. redirect command stderr to original stderr.\n")
		fmt.Fprintf(os.Stderr, "  -F, --force                optional. force refresh cache and kill running instance if any.\n")
		fmt.Fprintf(os.Stderr, "  -g, --foreground           optional. run the command in the foreground, without daemonizing. Always enables --force.\n")
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  cacher -c \"curl -s https://api.ipify.org\" -f /tmp/myip.txt -a 300\n")
		fmt.Fprintf(os.Stderr, "  cacher -c \"sleep 5 && echo done\" -f /tmp/test.cache -a 10 -d \"default-val\"\n")
	}

	flag.Parse()

	if command == "" {
		fmt.Fprintln(os.Stderr, "Error: command is required")
		flag.Usage()
		os.Exit(2)
	}
	if cacheFile == "" {
		fmt.Fprintln(os.Stderr, "Error: file is required")
		flag.Usage()
		os.Exit(2)
	}

	isMaxAgeSet := false
	isTimeoutSet := false
	flag.Visit(func(f *flag.Flag) {
		if f.Name == "a" || f.Name == "max-age" {
			isMaxAgeSet = true
		}
		if f.Name == "t" || f.Name == "timeout" {
			isTimeoutSet = true
		}
	})

	if isMaxAgeSet && maxAge < 0 {
		fmt.Fprintln(os.Stderr, "max-age must be a non-negative integer")
		os.Exit(2)
	}
	if isTimeoutSet && timeout < 0 {
		fmt.Fprintln(os.Stderr, "timeout must be a non-negative integer")
		os.Exit(2)
	}

	var err error
	cacheFile, err = filepath.Abs(cacheFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to resolve absolute path for cache file: %v\n", err)
		os.Exit(1)
	}

	if lockFile != "" {
		lockFile, err = filepath.Abs(lockFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to resolve absolute path for lock file: %v\n", err)
			os.Exit(1)
		}
	} else {
		lockFile = cacheFile + ".lock"
	}

	for _, path := range []string{cacheFile, lockFile} {
		parent := filepath.Dir(path)
		if parent != "" {
			if err := os.MkdirAll(parent, 0755); err != nil {
				fmt.Fprintf(os.Stderr, "Failed to create directory %s: %v\n", parent, err)
				os.Exit(1)
			}
		}
	}

	if daemonRun {
		runDaemon(lockFile, cacheFile, command, showStderr)
		return
	}

	if foreground {
		force = true
	}

	logMsg(fmt.Sprintf("Checking lock file: %s", lockFile))
	var prevMtime time.Time
	var hasPrevMtime bool
	if info, err := os.Stat(lockFile); err == nil {
		prevMtime = info.ModTime()
		hasPrevMtime = true
	}

	lockF, err := os.OpenFile(lockFile, os.O_RDWR|os.O_CREATE, 0666)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to open lock file %s: %v\n", lockFile, err)
		os.Exit(1)
	}

	err = syscall.Flock(int(lockF.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
	locked := (err == nil)

	if !locked {
		shouldKill := false
		killReason := ""
		if force {
			shouldKill = true
			killReason = "Force option specified"
		} else if isTimeoutSet && timeout >= 0 && hasPrevMtime {
			lockAge := time.Since(prevMtime).Seconds()
			if lockAge > float64(timeout) {
				shouldKill = true
				killReason = fmt.Sprintf("Stale process detected: ran for %.2fs (timeout %ds)", lockAge, timeout)
			}
		}

		if shouldKill {
			_, _ = lockF.Seek(0, io.SeekStart)
			data, readErr := io.ReadAll(lockF)
			if readErr == nil {
				pidStr := strings.TrimSpace(string(data))
				if prevPid, err := strconv.Atoi(pidStr); err == nil && prevPid > 0 {
					if !strings.HasPrefix(killReason, "Stale") {
						killReason = fmt.Sprintf("Force option specified. Killing running instance PID %d", prevPid)
					} else {
						killReason = fmt.Sprintf("%s. Killing PID %d", killReason, prevPid)
					}
					logMsg(killReason + "...")

					_ = syscall.Kill(-prevPid, syscall.SIGTERM)
					for i := 0; i < 10; i++ {
						time.Sleep(100 * time.Millisecond)
						flockErr := syscall.Flock(int(lockF.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
						if flockErr == nil {
							locked = true
							break
						}
					}

					if !locked {
						logMsg(fmt.Sprintf("Process group %d did not exit on SIGTERM. Sending SIGKILL...", prevPid))
						_ = syscall.Kill(-prevPid, syscall.SIGKILL)
						for i := 0; i < 5; i++ {
							time.Sleep(100 * time.Millisecond)
							flockErr := syscall.Flock(int(lockF.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
							if flockErr == nil {
								locked = true
								break
							}
						}
					}
				}
			}
		}
	}

	if !locked {
		logMsg("Lock already held by another instance. Printing cached content (or default) and exiting.")
		if data, err := os.ReadFile(cacheFile); err == nil {
			os.Stdout.Write(data)
		} else {
			fmt.Print(defaultText)
		}
		_ = lockF.Close()
		os.Exit(0)
	}

	logMsg("Lock acquired successfully.")

	if foreground {
		writePidAndUtime(lockF, lockFile)

		tmpFile := cacheFile + ".tmp"
		tmpF, err := os.OpenFile(tmpFile, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0666)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error opening tmp file: %v\n", err)
			_ = lockF.Close()
			os.Exit(1)
		}

		cmd := exec.Command("/bin/sh", "-c", command)
		cmd.Stdout = tmpF
		cmd.Stderr = os.Stderr

		_ = cmd.Run()
		_ = tmpF.Close()

		if _, err := os.Stat(tmpFile); err == nil {
			_ = os.Rename(tmpFile, cacheFile)
		} else {
			_ = os.Remove(tmpFile)
		}

		if data, err := os.ReadFile(cacheFile); err == nil {
			os.Stdout.Write(data)
		}
		_ = lockF.Close()
		os.Exit(0)
	}

	_, statErr := os.Stat(cacheFile)
	cacheExists := (statErr == nil)

	if !cacheExists {
		logMsg(fmt.Sprintf("First run detected (cache file %s does not exist), writing default string: %s", cacheFile, defaultText))
		err = os.WriteFile(cacheFile, []byte(defaultText), 0666)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Failed to write default text to cache file: %v\n", err)
			_ = lockF.Close()
			os.Exit(1)
		}

		fmt.Print(defaultText)
		logMsg(fmt.Sprintf("Starting background command: %s", command))
		startDaemon(lockF, lockFile)
		os.Exit(0)
	}

	logMsg(fmt.Sprintf("Reading cached content from: %s", cacheFile))
	cachedContent, err := os.ReadFile(cacheFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to read cache file: %v\n", err)
		_ = lockF.Close()
		os.Exit(1)
	}

	info, err := os.Stat(cacheFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to stat cache file: %v\n", err)
		_ = lockF.Close()
		os.Exit(1)
	}
	age := time.Since(info.ModTime()).Seconds()
	logMsg(fmt.Sprintf("Cache age: %.2fs, max-age: %ds", age, maxAge))

	isNewEnough := (!isMaxAgeSet) || (age <= float64(maxAge))
	if force {
		isNewEnough = false
	}

	if isNewEnough {
		logMsg("Cache file is fresh. Releasing lock and exiting.")
		_ = lockF.Close()
		os.Stdout.Write(cachedContent)
		os.Exit(0)
	}

	logMsg(fmt.Sprintf("Cache file is stale. Starting background command to refresh: %s", command))
	os.Stdout.Write(cachedContent)
	startDaemon(lockF, lockFile)
	os.Exit(0)
}
