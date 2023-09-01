package main

import (
	"fmt"
	"github.com/omakoto/go-common/src/cmdchain"
	"github.com/omakoto/go-common/src/runner"
)

func main() {
	runner.GenWrapper()

	//fmt.Printf("on!\n")
	cmd := cmdchain.New().Command("bash", "-c", "for n in {0..9}; do echo $n; done")

	//cmd.MustRunAndWait()
	// fmt.Printf("%s", cmd.MustRunAndGetString())
	cmd.MustRunAndStreamStrings(func(s string) {
		fmt.Printf("%s", s)
	})
}
