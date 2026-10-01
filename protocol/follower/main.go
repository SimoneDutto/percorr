package main

import (
	"bytes"
	"fmt"
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
		file:  file,
		conn:  conn,
		state: followerWaitRestart,
	}

	packet := make([]byte, 65535)
	for machine.state != followerDone {
		if err := machine.conn.SetReadDeadline(time.Now().Add(readTimeout)); err != nil {
			log.Fatal(err)
		}
		n, address, err := machine.conn.ReadFrom(packet)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				log.Printf("state=TIMEOUT from=%s", machine.state)
				if machine.state == followerWaitFinish {
					machine.finishTimeouts++
					if machine.finishTimeouts >= finishRetries {
						machine.state = followerDone
					}
					continue
				}
				machine.retries++
				if machine.retries >= maxRetries {
					log.Printf("state=RESYNC from=%s", machine.state)
					machine.retries = 0
					machine.state = followerWaitRestart
					continue
				}
				// Resend whichever response was sent immediately before this
				// read: restart_rev or ack.
				machine.state = machine.retryState
				if machine.state != followerWaitRestart {
					if err := machine.step(); err != nil {
						log.Printf("state=RESET from=%s err=%v", machine.state, err)
						machine.state = followerWaitRestart
					}
				}
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
	ackOffset      int64
	size           int64
	state          followerState
	retryState     followerState
	retries        int
	finishTimeouts int
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
	prefix := []byte(chunkMessage + " ")
	if !bytes.HasPrefix(m.packet, prefix) {
		return fmt.Errorf("unexpected message %q", m.packet)
	}
	remainder := m.packet[len(prefix):]
	space := bytes.IndexByte(remainder, ' ')
	if space < 0 {
		return fmt.Errorf("unexpected message %q", m.packet)
	}
	offset, err := strconv.ParseInt(string(remainder[:space]), 10, 64)
	if err != nil || offset < 0 {
		return fmt.Errorf("invalid chunk offset %q", remainder[:space])
	}
	data := remainder[space+1:]
	if offset == m.offset {
		if _, err := m.file.WriteAt(data, m.offset); err != nil {
			return err
		}
		m.offset += int64(len(data))
	} else if offset > m.offset {
		return fmt.Errorf("unexpected chunk offset %d, expected %d", offset, m.offset)
	}
	m.ackOffset = offset
	m.state = followerSendAck
	return m.step()
}

// SEND_ACK: acknowledge the chunk and wait for the next packet.
func (m *followerMachine) sendAck() error {
	message := fmt.Sprintf("%s %d", ackMessage, m.ackOffset)
	if _, err := m.conn.WriteTo([]byte(message), m.address); err != nil {
		return err
	}
	log.Printf("state=SEND bytes=%d msg=ack offset=%d", len(message), m.ackOffset)
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
	return m.waitRestart()
}
