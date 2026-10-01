#!/bin/bash

# One-shot network lab. Everything crosses the netem qdisc on loopback.
#
#   sudo ./netlab.sh duplicates      duplicate packets only
#   sudo ./netlab.sh clean           no network changes
#   sudo ./netlab.sh drop            drop packets only
#   sudo ./netlab.sh reorder         reorder packets only
#   sudo ./netlab.sh all             combine drop, duplicates and reordering
#   sudo ./netlab.sh teardown        remove the lab

set -eu

NS=percorr_ns
MODE=${1:-all}

case "$MODE" in
clean|duplicates|drop|reorder|all)
	ip netns add "$NS"
	ip -n "$NS" link set lo up
	case "$MODE" in
	clean)
		;;
	duplicates)
		ip netns exec "$NS" tc qdisc add dev lo root netem duplicate 20%
		;;
	drop)
		ip netns exec "$NS" tc qdisc add dev lo root netem loss 20%
		;;
	reorder)
		# netem needs delay before it can reorder queued packets.
		ip netns exec "$NS" tc qdisc add dev lo root netem delay 10ms reorder 20%
		;;
	all)
		ip netns exec "$NS" tc qdisc add dev lo root netem loss 20% duplicate 20% delay 10ms reorder 20%
		;;
	esac
	echo "lab ready: $MODE"
	;;
teardown)
	ip netns del "$NS"
	echo "lab removed"
	;;
*)
	echo "usage: sudo $0 {clean|duplicates|drop|reorder|all|teardown}" >&2
	exit 1
	;;
esac
