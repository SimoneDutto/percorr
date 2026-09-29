#!/bin/bash

# One-shot lab setup: a single network namespace with a lossy loopback.
# Run once as root. Everything the protocol sends (chunks AND acks) crosses
# the lossy path, in both directions.
#
#   sudo ./netlab.sh                 create the lab
#   sudo ./netlab.sh teardown        remove the lab
#
# Then run the chaos test inside it (no sudo needed inside, but entering
# requires root):
#
#   sudo ip netns exec percorr_ns ./protocol/chaos.sh

set -eu

NS=percorr_ns
LOSS=20

case ${1:-setup} in
setup)
	ip netns add "$NS"
	# Loopback must be up inside the namespace for 127.0.0.1 to work.
	ip -n "$NS" link set lo up
	# Lossy loopback: drops packets in both directions.
	ip netns exec "$NS" tc qdisc add dev lo root netem loss "$LOSS%"
	echo "lab ready: sudo ip netns exec $NS ./protocol/chaos.sh"
	;;
teardown)
	ip netns del "$NS"
	echo "lab removed"
	;;
*)
	echo "usage: sudo $0 [setup|teardown]" >&2
	exit 1
	;;
esac
