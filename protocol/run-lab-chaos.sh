#!/bin/bash

# Build on the host, then run the safe timeout-based chaos test inside the
# existing percorr_ns network namespace.

set -e

cd "$(dirname "$0")"
go build -o leader.bin ./leader
go build -o follower.bin ./follower

exec sudo ip netns exec percorr_ns bash ./chaos-timeout.sh
