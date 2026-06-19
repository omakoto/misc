package tout

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"syscall"
	"time"
)

// Run runs the command with the specified timeout duration.
// It returns the exit code to use.
func Run(timeoutStr string, cmdName string, cmdArgs []string) (int, error) {
	duration, err := parseDuration(timeoutStr)
	if err != nil {
		return 125, fmt.Errorf("invalid duration %q: %w", timeoutStr, err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), duration)
	defer cancel()

	cmd := exec.CommandContext(ctx, cmdName, cmdArgs...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err = cmd.Start()
	if err != nil {
		return 125, fmt.Errorf("failed to start command: %w", err)
	}

	err = cmd.Wait()
	if err != nil {
		// Check if it timed out
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return 124, nil
		}

		// Otherwise extract exit code from the process exit error
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			if status, ok := exitErr.Sys().(syscall.WaitStatus); ok {
				if status.Signaled() {
					// Return 128 + signal number
					return 128 + int(status.Signal()), nil
				}
				return status.ExitStatus(), nil
			}
			return exitErr.ExitCode(), nil
		}
		return 125, err
	}

	return 0, nil
}

func parseDuration(s string) (time.Duration, error) {
	if s == "" {
		return 0, errors.New("empty duration")
	}

	// Check for a suffix
	lastChar := s[len(s)-1]
	hasSuffix := lastChar == 's' || lastChar == 'm' || lastChar == 'h' || lastChar == 'd'

	var valStr string
	var unit string
	if hasSuffix {
		valStr = s[:len(s)-1]
		unit = string(lastChar)
	} else {
		valStr = s
		unit = "s"
	}

	// Parse the numeric part as a float
	val, err := strconv.ParseFloat(valStr, 64)
	if err != nil {
		return 0, err
	}

	var factor time.Duration
	switch unit {
	case "s":
		factor = time.Second
	case "m":
		factor = time.Minute
	case "h":
		factor = time.Hour
	case "d":
		factor = 24 * time.Hour
	default:
		return 0, fmt.Errorf("unknown unit %q", unit)
	}

	return time.Duration(val * float64(factor)), nil
}
