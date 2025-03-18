package main

import (
	"fmt"
	"github.com/omakoto/go-common/src/must"
	"github.com/omakoto/go-common/src/runner"
	"os"
	"strconv"
	"strings"
	"time"
)

var (
	tick = getTick()
)

func getTick() time.Duration {
	e := os.Getenv("TIMER_TICK")
	if e == "" {
		return time.Second
	}
	return time.Duration(must.Must2(strconv.ParseFloat(e, 64)) * float64(time.Second))
}

func usage() {
	fmt.Printf("Usage: work-timer.py DURATION [REP] [REST]\n")
}

func parseSec(v string) int {
	unit := 1
	if strings.HasSuffix(v, "m") {
		v = v[0 : len(v)-1]
		unit = 60
	} else if strings.HasSuffix(v, "s") {
		v = v[0 : len(v)-1]
	}
	return must.Must2(strconv.Atoi(v)) * unit
}

func parseArgs(args []string) (rep, duration, rest int) {
	if len(args) < 1 {
		usage()
		os.Exit(1)
	}

	duration = parseSec(args[0])
	rep = 1
	rest = 3

	if len(args) >= 3 {
		rest = must.Must2(strconv.Atoi(args[2]))
	}
	if len(args) >= 2 {
		rep = parseSec(args[1])
	}
	return
}

func p(format string, args ...interface{}) {
	fmt.Printf(format, args...)
}

func beep() {
	p("\x07")
}

func doTimer1(prefix string, duration int, needHeadsupBeeps bool) {
	beep()
	for i := duration; ; i-- {
		p("\r\x1b[K%s%d", prefix, i)
		if i == 0 {
			beep()
			break
		}
		if needHeadsupBeeps && i <= 3 {
			beep()
		}
		time.Sleep(tick)
	}
	p("\n")
}

func doTimer(n int, duration int, rest int) {
	doTimer1(fmt.Sprintf("[\x1b[38;5;13;1mWORK\x1b[0m %d] ", n), duration, true)

	if rest > 0 {
		doTimer1("[\x1b[38;5;10;1mREST\x1b[0m] ", rest, rest >= 10)
	}
}

func main() {
	runner.GenWrapper(runner.Options{WrapperPath: "../timer"})

	rep, duration, rest := parseArgs(os.Args[1:])
	if rep > 1 {
		p("Rep=%d  Duration=%d  Rest=%d\n", rep, duration, rest)
	}

	if rep == 1 {
		doTimer1("[\x1b[38;5;13;1mTIMER\x1b[0m] ", duration, true)
	} else {
		for i := rep; i > 0; i-- {
			r := rest
			if i == 1 {
				r = 0 // Last one doens't need a rest
			}
			doTimer(i, duration, r)
		}
	}

	for i := 0; i < 3; i++ {
		beep()
		time.Sleep(160 * time.Millisecond)
	}
}
