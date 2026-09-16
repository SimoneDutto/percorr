package main

import (
	"bytes"
	"fmt"
	"log"
	"net"
	"os"
	"time"
)

const (
	address        = "127.0.0.1:9777"
	sourceFile     = "source.data"
	leaderLogFile  = "leader.log"
	chunkSize      = 1200
	stepTimeout    = 5 * time.Second
	restartMessage = "restart"
	restartRev     = "restart_rev"
	ackMessage     = "ack"
	chunkMessage   = "chunk"
)

func main() {
	logFile, err := os.OpenFile(leaderLogFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.Fatal(err)
	}
	defer logFile.Close()
	log.SetOutput(logFile)
	log.SetFlags(log.Ldate | log.Lmicroseconds)
	log.Printf("state=%s", leaderRestartLoop)

	file, err := os.Open(sourceFile)
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		log.Fatal(err)
	}

	conn, err := net.Dial("udp", address)
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	machine := &leaderMachine{
		file:      file,
		size:      info.Size(),
		chunkSize: chunkSize,
		timeout:   stepTimeout,
		conn:      conn,
		offset:    0,
		state:     leaderRestartLoop,
	}

	for machine.state != leaderDone {
		log.Printf("state=%s", machine.state)
		if err := machine.step(); err != nil {
			// Per the protocol: a timeout (or any failure) at any point
			// sends the leader back to the start for a fresh handshake.
			log.Printf("state=TIMEOUT from=%s err=%v", machine.state, err)
			machine.state = leaderRestartLoop
		}
	}
	log.Printf("state=%s", machine.state)
	log.Printf("sent %d bytes", info.Size())
}

type leaderState string

const (
	leaderRestartLoop leaderState = "RESTART_LOOP"
	leaderWaitRestart leaderState = "WAIT_RESTART_RESPONSE"
	leaderBlockLoop   leaderState = "BLOCK_LOOP"
	leaderWaitAck     leaderState = "WAIT_FOR_ACK"
	leaderDone        leaderState = "DONE"
)

type leaderMachine struct {
	file      *os.File
	size      int64
	offset    int64
	chunkSize int
	timeout   time.Duration
	conn      net.Conn
	state     leaderState
	count     int64
}

func (m *leaderMachine) step() error {
	switch m.state {
	case leaderRestartLoop:
		return m.restartLoop()
	case leaderWaitRestart:
		return m.waitRestart()
	case leaderBlockLoop:
		return m.blockLoop()
	case leaderWaitAck:
		return m.waitAck()
	default:
		return fmt.Errorf("unknown state %q", m.state)
	}
}

// RESTART_LOOP: send restart and move to WAIT_RESTART_RESPONSE.
func (m *leaderMachine) restartLoop() error {
	if m.chunkSize <= 0 || m.chunkSize > 65000 {
		return fmt.Errorf("chunk size must be between 1 and 65000")
	}
	message := fmt.Sprintf("%s %d", restartMessage, m.size)
	if err := m.send([]byte(message)); err != nil {
		return err
	}
	log.Printf("state=SEND bytes=%d msg=restart size=%d", len(message), m.size)
	m.state = leaderWaitRestart
	return nil
}

// WAIT_RESTART_RESPONSE: read restart_rev and set the current offset.
func (m *leaderMachine) waitRestart() error {
	packet, err := m.receive()
	if err != nil {
		return err
	}
	if !bytes.HasPrefix(packet, []byte(restartRev+" ")) {
		return fmt.Errorf("unexpected response %q", packet)
	}
	if _, err := fmt.Sscanf(string(packet), restartRev+" %d", &m.offset); err != nil {
		return err
	}
	log.Printf("state=RECEIVED_REV offset=%d", m.offset)
	if m.offset < 0 || m.offset > m.size {
		return fmt.Errorf("invalid offset %d", m.offset)
	}
	m.state = leaderBlockLoop
	return nil
}

// BLOCK_LOOP: read one file block and move to WAIT_FOR_ACK.
func (m *leaderMachine) blockLoop() error {
	if m.offset >= m.size {
		m.state = leaderDone
		return nil
	}
	m.count = int64(m.chunkSize)
	if remaining := m.size - m.offset; remaining < m.count {
		m.count = remaining
	}
	data := make([]byte, m.count)
	if _, err := m.file.ReadAt(data, m.offset); err != nil {
		return err
	}
	message := make([]byte, 0, len(chunkMessage)+1+int(m.count))
	message = append(message, chunkMessage...)
	message = append(message, ' ')
	message = append(message, data...)
	if err := m.send(message); err != nil {
		return err
	}
	log.Printf("state=SEND bytes=%d msg=chunk offset=%d", len(message), m.offset)
	m.state = leaderWaitAck
	return nil
}

// WAIT_FOR_ACK: accept ack and advance to the next block.
func (m *leaderMachine) waitAck() error {
	packet, err := m.receive()
	if err != nil {
		return err
	}
	if !bytes.Equal(packet, []byte(ackMessage)) {
		return fmt.Errorf("unexpected acknowledgement %q", packet)
	}
	log.Printf("state=RECEIVED_ACK offset=%d", m.offset)
	m.offset += m.count
	m.state = leaderBlockLoop
	return nil
}

func (m *leaderMachine) send(message []byte) error {
	if err := m.conn.SetDeadline(time.Now().Add(m.timeout)); err != nil {
		return err
	}
	_, err := m.conn.Write(message)
	return err
}

func (m *leaderMachine) receive() ([]byte, error) {
	if err := m.conn.SetDeadline(time.Now().Add(m.timeout)); err != nil {
		return nil, err
	}
	packet := make([]byte, 65535)
	n, err := m.conn.Read(packet)
	return packet[:n], err
}
