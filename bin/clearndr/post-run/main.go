package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintf(os.Stderr, "Hello, post-run.")
}
