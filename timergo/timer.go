package main

import (
	"fmt"
	"github.com/omakoto/go-common/src/runner"
)

func main() {
	runner.GenWrapper(runner.Options{WrapperPath: "../timer"})

	fmt.Printf("OK\n")
}
