#!/bin/bash

set -u

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE="$DIR/source.data"
DESTINATION="$DIR/destination.data"
LEADER_LOG="$DIR/leader.log"
FOLLOWER_LOG="$DIR/follower.log"
CHAOS_LOG="$DIR/chaos.log"
LEADER_BIN="$DIR/leader.bin"
FOLLOWER_BIN="$DIR/follower.bin"

LEADER_PID=""
FOLLOWER_PID=""

cleanup() {
	for pid in "$LEADER_PID" "$FOLLOWER_PID"; do
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			echo "[$(date '+%Y/%m/%d %H:%M:%S.%6N')] [chaos] cleanup killing $pid" >> "$CHAOS_LOG"
			kill "$pid" 2>/dev/null || true
			wait "$pid" 2>/dev/null || true
		fi
	done
}
trap cleanup EXIT INT TERM

rm -f "$DESTINATION" "$LEADER_LOG" "$FOLLOWER_LOG" "$CHAOS_LOG"

(cd "$DIR" && go build -o follower.bin ./follower)
(cd "$DIR" && go build -o leader.bin ./leader)

start_follower() {
	(cd "$DIR" && ./follower.bin) &
	FOLLOWER_PID=$!
	until grep -q "listening on" "$FOLLOWER_LOG" 2>/dev/null; do
		if ! kill -0 "$FOLLOWER_PID" 2>/dev/null; then
			echo "follower stopped before becoming ready" >&2
			exit 1
		fi
		sleep 0.01
	done
}

start_leader() {
	(cd "$DIR" && ./leader.bin) &
	LEADER_PID=$!
}

kill_process() {
	local target=$1 pid=$2
	echo "[$(date '+%Y/%m/%d %H:%M:%S.%6N')] [chaos] killing $target" >> "$CHAOS_LOG"
	echo "[chaos] killing $target"
	kill -9 "$pid" 2>/dev/null || true
	wait "$pid" 2>/dev/null || true
}

kill_random() {
	case $((RANDOM % 2)) in
	0)
		if kill -0 "$LEADER_PID" 2>/dev/null; then
			kill_process leader "$LEADER_PID"
			LEADER_PID=""
			sleep 0.05
			start_leader
		fi
		;;
	1)
		if kill -0 "$FOLLOWER_PID" 2>/dev/null; then
			kill_process follower "$FOLLOWER_PID"
			FOLLOWER_PID=""
			sleep 0.05
			start_follower
		fi
		;;
	esac
}

start_follower
start_leader

# Run until the transfer completes or the chaos budget is exhausted.
# Long gaps between kills (5-20s) leave the protocol mostly undisturbed so
# the general case can be observed between crash/restart cycles.
ROUNDS=5
for _ in $(seq 1 "$ROUNDS"); do
	if ! kill -0 "$LEADER_PID" 2>/dev/null; then
		start_leader
	fi
	sleep "$((RANDOM % 15))"
	kill_random
done

wait "$LEADER_PID" 2>/dev/null
LEADER_PID=""

if kill -0 "$FOLLOWER_PID" 2>/dev/null; then
	sleep 1
	kill "$FOLLOWER_PID" 2>/dev/null || true
fi
wait "$FOLLOWER_PID" 2>/dev/null
FOLLOWER_PID=""

if cmp -s "$SOURCE" "$DESTINATION"; then
	echo "source and destination are equal"
else
	echo "source and destination differ" >&2
	exit 1
fi
