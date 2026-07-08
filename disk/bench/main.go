package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

const BLOCK_SIZE = 4 * 1024 * 1024
const DEPTH = 32
const SEARCH_STRING = "performance"

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	// flush OS page cache + flood SSD read cache before benchmarking
	if err := exec.Command("sh", "-c", "sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null && sudo dd if=/dev/nvme0n1 of=/dev/null bs=1M count=2048 status=none").Run(); err != nil {
		return fmt.Errorf("flush caches: %w", err)
	}

	println("starting disk benchmark with ", DEPTH, " goroutines and block size of ", BLOCK_SIZE, " bytes")
	t0 := time.Now()
	fi, err := os.OpenFile("fio-testfile", os.O_RDONLY|syscall.O_DIRECT, 0)
	if err != nil {
		return fmt.Errorf("open file: %w", err)
	}
	defer func(f *os.File) {
		if err := f.Close(); err != nil {
			fmt.Fprintf(os.Stderr, "close file: %v\n", err)
		}
	}(fi)

	bufs := make([][]byte, DEPTH)
	for i := range DEPTH {
		raw := make([]byte, BLOCK_SIZE+4095)
		align := -int(uintptr(unsafe.Pointer(&raw[0])) & 4095)
		bufs[i] = raw[align : align+BLOCK_SIZE]
	}
	found := make(chan bool, 1)
	errCh := make(chan error, 1)
	offset := 0
	for {
		wg := sync.WaitGroup{}
		for i := range DEPTH {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				n, err := fi.ReadAt(bufs[i], int64(offset+i*BLOCK_SIZE))
				if err != nil && err != io.EOF {
					errCh <- fmt.Errorf("read at offset %d: %w", offset+i*BLOCK_SIZE, err)
					return
				}
				if n == 0 {
					return
				}
				seachStringBytes := []byte(SEARCH_STRING)
				lenSearchStringBytes := len(seachStringBytes)
				if n >= lenSearchStringBytes {
					lastBytes := bufs[i][n-lenSearchStringBytes : n]
					if string(lastBytes) == SEARCH_STRING {
						println("Found the search string at the end of the file.")
						t1 := time.Now()
						elapsed := t1.Sub(t0)
						println("Time taken to read the file:", elapsed.String())
						found <- true
						return
					}
				}
				if err != nil {
					errCh <- fmt.Errorf("post-read: %w", err)
					return
				}
			}(i)
		}
		wg.Wait()
		offset += BLOCK_SIZE * DEPTH

		select {
		case <-found:
			return nil
		case err := <-errCh:
			return err
		default:
		}
	}
}
