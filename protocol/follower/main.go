package main

import (
	"bytes"
	"fmt"
	"log"
	"net"
	"os"
)

const (
	address         = ":9777"
	destinationFile = "destination.data"
	followerLogFile = "follower.log"
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
		n, address, err := machine.conn.ReadFrom(packet)
		if err != nil {
			log.Fatal(err)
		}
		machine.address = address
		machine.packet = packet[:n]
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
	followerDone        followerState = "DONE"
)

type followerMachine struct {
	file    *os.File
	conn    net.PacketConn
	address net.Addr
	packet  []byte
	offset  int64
	size    int64
	state   followerState
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
	m.state = followerBlockLoop
	return nil
}

// BLOCK_LOOP: accept one chunk and move to SEND_ACK.
func (m *followerMachine) blockLoop() error {
	prefix := []byte(chunkMessage + " ")
	if len(m.packet) < len(prefix) || !bytes.HasPrefix(m.packet, prefix) {
		return fmt.Errorf("unexpected message %q", m.packet)
	}
	data := m.packet[len(prefix):]
	if _, err := m.file.WriteAt(data, m.offset); err != nil {
		return err
	}
	m.offset += int64(len(data))
	m.state = followerSendAck
	return m.step()
}

// SEND_ACK: acknowledge the chunk and wait for the next packet.
func (m *followerMachine) sendAck() error {
	if _, err := m.conn.WriteTo([]byte(ackMessage), m.address); err != nil {
		return err
	}
	log.Printf("state=SEND bytes=3 msg=ack offset=%d", m.offset)
	if m.offset >= m.size {
		m.state = followerDone
	} else {
		m.state = followerBlockLoop
	}
	return nil
}
