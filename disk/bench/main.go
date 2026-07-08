package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"runtime/pprof"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

const SEARCH_STRING = "performance"

type Result struct {
	BlockSize int           `json:"block_size"`
	Depth     int           `json:"iodepth"`
	Time      time.Duration `json:"time_ns"`
	TimeSecs  float64       `json:"time_s"`
}

func main() {
	blockSize := flag.Int("bs", 4*1024*1024, "block size in bytes")
	depth := flag.Int("depth", 32, "I/O depth (number of goroutines)")
	output := flag.String("output", "", "output JSON file path (empty = stdout)")
	cpuprofile := flag.String("cpuprofile", "", "write CPU profile to file")
	flag.Parse()

	res, err := run(*blockSize, *depth, *cpuprofile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	data, err := json.MarshalIndent(res, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "json marshal: %v\n", err)
		os.Exit(1)
	}

	if *output != "" {
		if err := os.WriteFile(*output, data, 0644); err != nil {
			fmt.Fprintf(os.Stderr, "write output: %v\n", err)
			os.Exit(1)
		}
	} else {
		fmt.Println(string(data))
	}
}

func run(blockSize, depth int, cpuprofile string) (*Result, error) {
	// flush OS page cache + flood SSD read cache before benchmarking
	if err := exec.Command("sh", "-c", "sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null && sudo dd if=/dev/nvme0n1 of=/dev/null bs=1M count=2048 status=none").Run(); err != nil {
		return nil, fmt.Errorf("flush caches: %w", err)
	}

	// start CPU profiling after cache flush, so it only covers the benchmark
	if cpuprofile != "" {
		f, err := os.Create(cpuprofile)
		if err != nil {
			return nil, fmt.Errorf("create cpu profile: %w", err)
		}
		defer f.Close()
		if err := pprof.StartCPUProfile(f); err != nil {
			return nil, fmt.Errorf("start cpu profile: %w", err)
		}
		defer pprof.StopCPUProfile()
	}

	fmt.Printf("starting disk benchmark with %d goroutines and block size of %d bytes\n", depth, blockSize)
	seachStringBytes := []byte(SEARCH_STRING)
	lenSearchStringBytes := len(seachStringBytes)
	t0 := time.Now()
	fi, err := os.OpenFile("fio-testfile", os.O_RDONLY|syscall.O_DIRECT, 0)
	if err != nil {
		return nil, fmt.Errorf("open file: %w", err)
	}
	defer func(f *os.File) {
		if err := f.Close(); err != nil {
			fmt.Fprintf(os.Stderr, "close file: %v\n", err)
		}
	}(fi)

	// get file size to know when we're at the last chunk
	stat, err := fi.Stat()
	if err != nil {
		return nil, fmt.Errorf("stat file: %w", err)
	}
	fileSize := stat.Size()

	bufs := make([][]byte, depth)
	for i := range depth {
		raw := make([]byte, blockSize+4095)
		align := -int(uintptr(unsafe.Pointer(&raw[0])) & 4095)
		bufs[i] = raw[align : align+blockSize]
	}
	found := make(chan bool, 1)
	errCh := make(chan error, 1)
	offset := 0
	for {
		wg := sync.WaitGroup{}
		for i := range depth {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				n, err := fi.ReadAt(bufs[i], int64(offset+i*blockSize))
				if err != nil && err != io.EOF {
					errCh <- fmt.Errorf("read at offset %d: %w", offset+i*blockSize, err)
					return
				}
				if n == 0 {
					return
				}
				// only check for the search string on the last chunk of the file
				isLastChunk := int64(offset+i*blockSize+n) >= fileSize
				if isLastChunk && bytes.Equal(bufs[i][n-lenSearchStringBytes:n], seachStringBytes) {
					println("Found the search string at the end of the file.")
					found <- true
					return
				}
				if err != nil {
					errCh <- fmt.Errorf("post-read: %w", err)
					return
				}
			}(i)
		}
		wg.Wait()
		offset += blockSize * depth

		select {
		case <-found:
			elapsed := time.Since(t0)
			println("Time taken to read the file:", elapsed.String())
			return &Result{
				BlockSize: blockSize,
				Depth:     depth,
				Time:      elapsed,
				TimeSecs:  elapsed.Seconds(),
			}, nil
		case err := <-errCh:
			return nil, err
		default:
		}
	}
}
