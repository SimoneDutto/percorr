// gentest writes an 8 GiB file of random data ending with "performance".
package main

import (
	"crypto/rand"
	"io"
	"os"
)

const (
	size = 100 << 30 // 100 GiB
	sig  = "performance"
)

func main() {
	f, err := os.Create("fio-testfile")
	check(err)
	defer f.Close()

	// Random body: 8 GiB minus the trailer length.
	if _, err := io.CopyN(f, rand.Reader, size-int64(len(sig))); err != nil {
		check(err)
	}
	// Trailer.
	_, err = io.WriteString(f, sig)
	check(err)
	check(f.Sync())
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}
