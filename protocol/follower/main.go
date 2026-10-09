package main

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strconv"
	"time"
)

const (
	address         = ":9777"
	destinationFile = "destination.data"
	followerLogFile = "follower.log"
	readTimeout     = 50 * time.Millisecond
	windowSize      = 4
	maxRetries      = 3
	finishRetries   = 100
	restartMessage  = "restart"
	restartRev      = "restart_rev"
	ackMessage      = "ack"
	chunkMessage    = "chunk"
)

func main() {
	logFile, err := os.OpenFile(followerLogFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.Fatal(err)
	}
	defer logFile.Close()
	log.SetOutput(logFile)
	log.SetFlags(log.Ldate | log.Lmicroseconds)
	log.Printf("state=%s", followerWaitRestart)

	file, err := os.OpenFile(destinationFile, os.O_CREATE|os.O_RDWR, 0644)
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	conn, err := net.ListenPacket("udp", address)
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()
	log.Printf("listening on %s", address)
	machine := &followerMachine{
		file:          file,
		conn:          conn,
		state:         followerWaitRestart,
		pendingChunks: make(map[int64][]byte),
	}

	packet := make([]byte, 65535)
	for machine.state != followerDone {
		if err := machine.conn.SetReadDeadline(time.Now().Add(readTimeout)); err != nil {
			log.Fatal(err)
		}
		n, address, err := machine.conn.ReadFrom(packet)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				machine.handleTimeout()
				continue
			}
			log.Fatal(err)
		}
		machine.address = address
		machine.packet = packet[:n]
		machine.retries = 0
		log.Printf("state=RECEIVE bytes=%d", n)
		if err := machine.step(); err != nil {
			// Per the protocol: an unexpected message at any point sends
			// the follower back to the start.
			log.Printf("state=RESET from=%s err=%v", machine.state, err)
			machine.state = followerWaitRestart
		}
	}
	log.Printf("state=%s", machine.state)
}

func (m *followerMachine) handleTimeout() {
	log.Printf("state=TIMEOUT from=%s", m.state)
	if m.state == followerWaitFinish {
		m.finishTimeouts++
		if m.finishTimeouts >= finishRetries {
			m.state = followerDone
		}
		return
	}

	m.retries++
	if m.retries >= maxRetries {
		log.Printf("state=RESYNC from=%s", m.state)
		m.retries = 0
		m.state = followerWaitRestart
		return
	}

	if m.state == followerBlockLoop {
		if m.retryState == followerSendAck {
			m.state = followerSendAck
			m.retryLastAck()
		}
		return
	}

	// Other states retry the last response they sent.
	m.state = m.retryState
	if m.state != followerWaitRestart {
		m.retryLastAck()
	}
}

func (m *followerMachine) retryLastAck() {
	if err := m.step(); err != nil {
		log.Printf("state=RESET from=%s err=%v", m.state, err)
		m.state = followerWaitRestart
	}
}

type followerState string

const (
	followerWaitRestart followerState = "WAIT_RESTART"
	followerSendRestart followerState = "SEND_RESTART_REV"
	followerBlockLoop   followerState = "BLOCK_LOOP"
	followerSendAck     followerState = "SEND_ACK"
	followerWaitFinish  followerState = "WAIT_FINISH"
	followerDone        followerState = "DONE"
)

type followerMachine struct {
	file           *os.File
	conn           net.PacketConn
	address        net.Addr
	packet         []byte
	offset         int64
	size           int64
	state          followerState
	retryState     followerState
	retries        int
	finishTimeouts int
	pendingChunks  map[int64][]byte
	lastAckOffsets []int64
}

func (m *followerMachine) step() error {
	log.Printf("state=%s", m.state)
	switch m.state {
	case followerWaitRestart:
		return m.waitRestart()
	case followerSendRestart:
		return m.sendRestartRevision()
	case followerBlockLoop:
		return m.blockLoop()
	case followerSendAck:
		return m.sendAck()
	case followerWaitFinish:
		return m.waitFinish()
	default:
		return fmt.Errorf("unknown state %q", m.state)
	}
}

// WAIT_RESTART: wait for a restart request.
func (m *followerMachine) waitRestart() error {
	var size int64
	if _, err := fmt.Sscanf(string(m.packet), restartMessage+" %d", &size); err == nil && size >= 0 {
		m.size = size
		m.state = followerSendRestart
		return m.step()
	}
	return fmt.Errorf("unexpected message %q", m.packet)
}

// SEND_RESTART_REV: report the current file size as the resume offset.
func (m *followerMachine) sendRestartRevision() error {
	info, err := m.file.Stat()
	if err != nil {
		return err
	}
	m.offset = info.Size()
	m.pendingChunks = make(map[int64][]byte)
	m.lastAckOffsets = nil
	if _, err := m.conn.WriteTo([]byte(fmt.Sprintf("%s %d", restartRev, m.offset)), m.address); err != nil {
		return err
	}
	log.Printf("state=SEND bytes=%d msg=restart_rev offset=%d", len(restartRev)+1+20, m.offset)
	m.retryState = followerSendRestart
	if m.offset >= m.size {
		m.state = followerWaitFinish
	} else {
		m.state = followerBlockLoop
	}
	return nil
}

// BLOCK_LOOP: accept one chunk and move to SEND_ACK.
func (m *followerMachine) blockLoop() error {
	offset, data, err := parseChunk(m.packet, m.size)
	if err != nil {
		return err
	}
	ackOffsets, err := m.acceptChunk(offset, data)
	if err != nil {
		return err
	}
	if len(ackOffsets) == 0 {
		log.Printf("state=BUFFER offset=%d expected=%d", offset, m.offset)
		m.state = followerBlockLoop
		return nil
	}
	m.lastAckOffsets = ackOffsets
	m.state = followerSendAck
	return m.step()
}

func parseChunk(packet []byte, fileSize int64) (int64, []byte, error) {
	prefix := []byte(chunkMessage + " ")
	if !bytes.HasPrefix(packet, prefix) {
		return 0, nil, fmt.Errorf("unexpected message %q", packet)
	}
	remainder := packet[len(prefix):]
	space := bytes.IndexByte(remainder, ' ')
	if space < 0 {
		return 0, nil, fmt.Errorf("unexpected message %q", packet)
	}
	offset, err := strconv.ParseInt(string(remainder[:space]), 10, 64)
	if err != nil || offset < 0 {
		return 0, nil, fmt.Errorf("invalid chunk offset %q", remainder[:space])
	}
	data := append([]byte(nil), remainder[space+1:]...)
	if len(data) == 0 || offset > fileSize || int64(len(data)) > fileSize-offset {
		return 0, nil, fmt.Errorf("invalid chunk range offset=%d bytes=%d", offset, len(data))
	}
	return offset, data, nil
}

func (m *followerMachine) acceptChunk(offset int64, data []byte) ([]int64, error) {
	if offset < m.offset {
		return []int64{offset}, nil
	}
	if m.pendingChunks == nil {
		m.pendingChunks = make(map[int64][]byte)
	}
	if _, exists := m.pendingChunks[offset]; !exists {
		if len(m.pendingChunks) >= windowSize {
			return nil, fmt.Errorf("chunk buffer full at offset %d", offset)
		}
		m.pendingChunks[offset] = data
	}
	ackOffsets := make([]int64, 0, windowSize)
	for {
		writtenOffset, written, err := m.writeNextBufferedChunk()
		if err != nil {
			return nil, err
		}
		if !written {
			break
		}
		ackOffsets = append(ackOffsets, writtenOffset)
	}
	return ackOffsets, nil
}

func (m *followerMachine) writeNextBufferedChunk() (int64, bool, error) {
	data, exists := m.pendingChunks[m.offset]
	if !exists {
		return 0, false, nil
	}
	writeOffset := m.offset
	bytesWritten, err := m.file.WriteAt(data, writeOffset)
	if err != nil {
		return 0, false, err
	}
	if bytesWritten != len(data) {
		return 0, false, io.ErrShortWrite
	}
	delete(m.pendingChunks, writeOffset)
	m.offset += int64(bytesWritten)
	log.Printf("state=WRITE offset=%d bytes=%d", writeOffset, bytesWritten)
	return writeOffset, true, nil
}

// SEND_ACK: acknowledge the chunk and wait for the next packet.
func (m *followerMachine) sendAck() error {
	for _, ackOffset := range m.lastAckOffsets {
		message := fmt.Sprintf("%s %d", ackMessage, ackOffset)
		if _, err := m.conn.WriteTo([]byte(message), m.address); err != nil {
			return err
		}
		log.Printf("state=SEND bytes=%d msg=ack offset=%d", len(message), ackOffset)
	}
	m.retryState = followerSendAck
	if m.offset >= m.size {
		m.state = followerWaitFinish
	} else {
		m.state = followerBlockLoop
	}
	return nil
}

// WAIT_FINISH: keep accepting a restart for a short grace period so a leader
// that missed the final ack can resynchronize before the follower exits.
func (m *followerMachine) waitFinish() error {
	if bytes.HasPrefix(m.packet, []byte(chunkMessage+" ")) {
		return m.blockLoop()
	}
	return m.waitRestart()
}
