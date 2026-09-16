#!/bin/sh

set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE="$DIR/source.data"
DESTINATION="$DIR/destination.data"
LEADER_LOG="$DIR/leader.log"
FOLLOWER_LOG="$DIR/follower.log"

rm -f "$DESTINATION"
rm -f "$LEADER_LOG" "$FOLLOWER_LOG"

cleanup() {
	for pid in "${FOLLOWER_PID:-}" "${LEADER_PID:-}"; do
		if [ -n "$pid" ]; then
			kill "$pid" 2>/dev/null || true
		fi
	done
}
trap cleanup EXIT INT TERM

(cd "$DIR" && go build -o follower.bin ./follower)
(cd "$DIR" && go build -o leader.bin ./leader)

(cd "$DIR" && ./follower.bin) &
FOLLOWER_PID=$!

# Wait until the follower has bound the UDP socket before starting the leader.
until grep -q "listening on" "$FOLLOWER_LOG" 2>/dev/null; do
	if ! kill -0 "$FOLLOWER_PID" 2>/dev/null; then
		echo "follower stopped before becoming ready" >&2
		exit 1
	fi
	sleep 0.01
done

(cd "$DIR" && ./leader.bin) &
LEADER_PID=$!

wait "$LEADER_PID"
wait "$FOLLOWER_PID"

if cmp -s "$SOURCE" "$DESTINATION"; then
	echo "source and destination are equal"
else
	echo "source and destination differ" >&2
	exit 1
fi
