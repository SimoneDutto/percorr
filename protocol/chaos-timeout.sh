#!/bin/bash

# Safe chaos test for the network namespace.
#
# Leader and follower crash independently. Each is supervised by its own
# timeout loop, and timeout only kills the direct child it started. This script
# never sends a signal to a saved PID.

set -u

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROUNDS=5
START_TIME=$(date +%s)

rm -f "$DIR/destination.data" "$DIR/leader.log" "$DIR/follower.log" "$DIR/chaos.log"

if [ ! -x "$DIR/leader.bin" ] || [ ! -x "$DIR/follower.bin" ]; then
	echo "build first: cd $DIR && go build -o leader.bin ./leader && go build -o follower.bin ./follower" >&2
	exit 1
fi

run_leader_crashes() {
	for round in $(seq 1 "$ROUNDS"); do
		duration="$((RANDOM % 3 + 1))s"
		echo "leader crash $round/$ROUNDS after $duration" >> "$DIR/chaos.log"
		timeout -s KILL "$duration" bash -c 'cd "$1" && exec ./leader.bin 127.0.0.1:9777' bash "$DIR" >> "$DIR/leader.log" 2>&1 || true
	done
}

run_follower_crashes() {
	for round in $(seq 1 "$ROUNDS"); do
		duration="$((RANDOM % 3 + 1))s"
		echo "follower crash $round/$ROUNDS after $duration" >> "$DIR/chaos.log"
		timeout -s KILL "$duration" bash -c 'cd "$1" && exec ./follower.bin' bash "$DIR" >> "$DIR/follower.log" 2>&1 || true
	done
}

# These loops run concurrently, so crashes of one side do not imply crashes
# or restarts of the other side.
run_follower_crashes &
FOLLOWER_SUPERVISOR=$!
run_leader_crashes &
LEADER_SUPERVISOR=$!

wait "$LEADER_SUPERVISOR"
wait "$FOLLOWER_SUPERVISOR"

echo "final uninterrupted run"

bash -c 'cd "$1" && exec ./follower.bin' bash "$DIR" >> "$DIR/follower.log" 2>&1 &
FINAL_FOLLOWER=$!

until grep -q "listening on" "$DIR/follower.log" 2>/dev/null; do
	if ! kill -0 "$FINAL_FOLLOWER" 2>/dev/null; then
		echo "follower stopped before becoming ready" >&2
		exit 1
	fi
	sleep 0.01
done

bash -c 'cd "$1" && exec ./leader.bin 127.0.0.1:9777' bash "$DIR" >> "$DIR/leader.log" 2>&1 &
FINAL_LEADER=$!

wait "$FINAL_LEADER"
wait "$FINAL_FOLLOWER"

cmp "$DIR/source.data" "$DIR/destination.data"
echo "source and destination are equal in $(( $(date +%s) - START_TIME )) seconds"
