// Package cacher implements stdout caching and background command execution.
package cacher

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

type Options struct {
	Command           string
	CacheFile         string
	LockFile          string
	MaxAge            int // in seconds, -1 if not set
	DefaultText       string
	Timeout           int // in seconds, -1 if not set
	Verbose           bool
	ShowStderr        bool
	Force             bool
	Foreground        bool
	DaemonRun         bool
	UpdatingIndicator string
}

func isTerminal(fd uintptr) bool {
	var termios syscall.Termios
	_, _, err := syscall.Syscall(syscall.SYS_IOCTL, fd, uintptr(syscall.TCGETS), uintptr(unsafe.Pointer(&termios)))
	return err == 0
}

func writePidAndUtime(f *os.File, path string) error {
	if err := f.Truncate(0); err != nil {
		return err
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return err
	}
	if _, err := fmt.Fprintf(f, "%d\n", os.Getpid()); err != nil {
		return err
	}
	if err := f.Sync(); err != nil {
		return err
	}
	now := time.Now()
	return os.Chtimes(path, now, now)
}

func RunDaemon(lockFile, cacheFile, command string, showStderr bool) {
	// The lock file descriptor is passed as FD 3.
	lockF := os.NewFile(3, lockFile)
	if lockF == nil {
		fmt.Fprintln(os.Stderr, "cacher daemon: invalid lock file descriptor")
		os.Exit(1)
	}

	if err := writePidAndUtime(lockF, lockFile); err != nil {
		fmt.Fprintf(os.Stderr, "cacher daemon: failed to write PID: %v\n", err)
	}

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
}

func startDaemon(lockF *os.File, opts *Options) error {
	daemonArgs := []string{"-daemon-run"}
	daemonArgs = append(daemonArgs, "-c", opts.Command, "-f", opts.CacheFile, "-l", opts.LockFile)
	if opts.ShowStderr {
		daemonArgs = append(daemonArgs, "-show-stderr")
	}
	if opts.Verbose {
		daemonArgs = append(daemonArgs, "-v")
	}

	exe, err := os.Executable()
	if err != nil {
		exe = os.Args[0]
	}

	cmd := exec.Command(exe, daemonArgs...)
	cmd.Stdin = nil
	cmd.Stdout = nil
	if opts.ShowStderr {
		cmd.Stderr = os.Stderr
	} else {
		cmd.Stderr = nil
	}

	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid: true,
	}
	cmd.ExtraFiles = []*os.File{lockF}

	err = cmd.Start()
	if err != nil {
		return fmt.Errorf("failed to start daemon: %w", err)
	}
	return nil
}

func Run(opts *Options, stdout, stderr io.Writer) int {
	if opts.DaemonRun {
		RunDaemon(opts.LockFile, opts.CacheFile, opts.Command, opts.ShowStderr)
		return 0
	}

	if opts.Foreground {
		opts.Force = true
	}

	logMsg := func(msg string) {
		if !opts.Verbose {
			return
		}
		isTerm := false
		if f, ok := stderr.(*os.File); ok {
			isTerm = isTerminal(f.Fd())
		}
		if isTerm {
			fmt.Fprintf(stderr, "\033[90mcacher: %s\033[0m\n", msg)
		} else {
			fmt.Fprintf(stderr, "cacher: %s\n", msg)
		}
	}

	logMsg(fmt.Sprintf("Checking lock file: %s", opts.LockFile))
	var prevMtime time.Time
	var hasPrevMtime bool
	if info, err := os.Stat(opts.LockFile); err == nil {
		prevMtime = info.ModTime()
		hasPrevMtime = true
	}

	lockF, err := os.OpenFile(opts.LockFile, os.O_RDWR|os.O_CREATE, 0666)
	if err != nil {
		fmt.Fprintf(stderr, "Failed to open lock file %s: %v\n", opts.LockFile, err)
		return 1
	}

	err = syscall.Flock(int(lockF.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
	locked := (err == nil)

	if !locked {
		shouldKill := false
		killReason := ""
		if opts.Force {
			shouldKill = true
			killReason = "Force option specified"
		} else if opts.Timeout >= 0 && hasPrevMtime {
			lockAge := time.Since(prevMtime).Seconds()
			if lockAge > float64(opts.Timeout) {
				shouldKill = true
				killReason = fmt.Sprintf("Stale process detected: ran for %.2fs (timeout %ds)", lockAge, opts.Timeout)
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
		if data, err := os.ReadFile(opts.CacheFile); err == nil {
			stdout.Write(data)
		} else {
			fmt.Fprint(stdout, opts.DefaultText)
		}
		_ = lockF.Close()
		return 0
	}

	logMsg("Lock acquired successfully.")

	if opts.Foreground {
		if err := writePidAndUtime(lockF, opts.LockFile); err != nil {
			fmt.Fprintf(stderr, "Error writing lock file: %v\n", err)
		}

		if opts.UpdatingIndicator != "" {
			logMsg(fmt.Sprintf("Writing updating indicator to cache file: %s", opts.UpdatingIndicator))
			if err := os.WriteFile(opts.CacheFile, []byte(opts.UpdatingIndicator), 0666); err != nil {
				fmt.Fprintf(stderr, "Failed to write updating indicator: %v\n", err)
			}
		}

		tmpFile := opts.CacheFile + ".tmp"
		tmpF, err := os.OpenFile(tmpFile, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0666)
		if err != nil {
			fmt.Fprintf(stderr, "Error opening tmp file: %v\n", err)
			_ = lockF.Close()
			return 1
		}

		cmd := exec.Command("/bin/sh", "-c", opts.Command)
		cmd.Stdout = tmpF
		cmd.Stderr = stderr

		_ = cmd.Run()
		_ = tmpF.Close()

		if _, err := os.Stat(tmpFile); err == nil {
			_ = os.Rename(tmpFile, opts.CacheFile)
		} else {
			_ = os.Remove(tmpFile)
		}

		if data, err := os.ReadFile(opts.CacheFile); err == nil {
			stdout.Write(data)
		}
		_ = lockF.Close()
		return 0
	}

	_, statErr := os.Stat(opts.CacheFile)
	cacheExists := (statErr == nil)

	if !cacheExists {
		logMsg(fmt.Sprintf("First run detected (cache file %s does not exist), writing default string: %s", opts.CacheFile, opts.DefaultText))
		err = os.WriteFile(opts.CacheFile, []byte(opts.DefaultText), 0666)
		if err != nil {
			fmt.Fprintf(stderr, "Failed to write default text to cache file: %v\n", err)
			_ = lockF.Close()
			return 1
		}

		fmt.Fprint(stdout, opts.DefaultText)

		if opts.UpdatingIndicator != "" {
			logMsg(fmt.Sprintf("Writing updating indicator to cache file: %s", opts.UpdatingIndicator))
			if err := os.WriteFile(opts.CacheFile, []byte(opts.UpdatingIndicator), 0666); err != nil {
				fmt.Fprintf(stderr, "Failed to write updating indicator: %v\n", err)
			}
		}

		logMsg(fmt.Sprintf("Starting background command: %s", opts.Command))
		if err := startDaemon(lockF, opts); err != nil {
			fmt.Fprintf(stderr, "Error starting daemon: %v\n", err)
			_ = lockF.Close()
			return 1
		}
		return 0
	}

	logMsg(fmt.Sprintf("Reading cached content from: %s", opts.CacheFile))
	cachedContent, err := os.ReadFile(opts.CacheFile)
	if err != nil {
		fmt.Fprintf(stderr, "Failed to read cache file: %v\n", err)
		_ = lockF.Close()
		return 1
	}

	info, err := os.Stat(opts.CacheFile)
	if err != nil {
		fmt.Fprintf(stderr, "Failed to stat cache file: %v\n", err)
		_ = lockF.Close()
		return 1
	}
	age := time.Since(info.ModTime()).Seconds()
	logMsg(fmt.Sprintf("Cache age: %.2fs, max-age: %ds", age, opts.MaxAge))

	isNewEnough := (opts.MaxAge < 0) || (age <= float64(opts.MaxAge))
	if opts.Force {
		isNewEnough = false
	}

	if isNewEnough {
		logMsg("Cache file is fresh. Releasing lock and exiting.")
		_ = lockF.Close()
		stdout.Write(cachedContent)
		return 0
	}

	logMsg(fmt.Sprintf("Cache file is stale. Starting background command to refresh: %s", opts.Command))
	stdout.Write(cachedContent)

	if opts.UpdatingIndicator != "" {
		logMsg(fmt.Sprintf("Writing updating indicator to cache file: %s", opts.UpdatingIndicator))
		if err := os.WriteFile(opts.CacheFile, []byte(opts.UpdatingIndicator), 0666); err != nil {
			fmt.Fprintf(stderr, "Failed to write updating indicator: %v\n", err)
		}
	}

	if err := startDaemon(lockF, opts); err != nil {
		fmt.Fprintf(stderr, "Error starting daemon: %v\n", err)
		_ = lockF.Close()
		return 1
	}
	return 0
}
