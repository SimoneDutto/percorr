#!/usr/bin/env python3
"""Open an interactive native window with the state timeline.

Same data as states_html.py but rendered with matplotlib so it opens in its
own window with zoom/pan - no browser needed. Scroll wheel zooms, and the
toolbar at the bottom supports pan, box zoom and home/reset.
"""

import os
import re
import sys
from datetime import datetime

import matplotlib

matplotlib.use("TkAgg")
import matplotlib.pyplot as plt

DIR = os.path.dirname(os.path.abspath(__file__))
PATTERN = re.compile(r"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}\.\d{6}) state=(\S+)$")

PROCESSES = [
    (
        "leader",
        "leader.log",
        "#1f77b4",
        [
            "RESTART_LOOP",
            "WAIT_RESTART_RESPONSE",
            "SEND",
            "RECEIVED_REV",
            "BLOCK_LOOP",
            "WAIT_FOR_ACK",
            "RECEIVED_ACK",
            "TIMEOUT",
            "DONE",
        ],
    ),
    (
        "follower",
        "follower.log",
        "#d62728",
        [
            "WAIT_RESTART",
            "RECEIVE",
            "SEND_RESTART_REV",
            "BLOCK_LOOP",
            "SEND",
            "SEND_ACK",
            "TIMEOUT",
            "DONE",
        ],
    ),
]
CHAOS_LOG = os.path.join(DIR, "chaos.log")
CHAOS_PATTERN = re.compile(
    r"^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}\.\d{6}) \[chaos\] (killing|cleanup killing) (\S+)$"
)


def parse(path, pattern):
    events = []
    if not os.path.exists(path):
        return events
    with open(path) as handle:
        for line in handle:
            match = pattern.match(line.strip())
            if not match:
                continue
            timestamp = datetime.strptime(match.group(1), "%Y/%m/%d %H:%M:%S.%f")
            events.append((timestamp, match.group(2)))
    return events


def main():
    parsed = {}
    start = None
    for name, filename, _, _ in PROCESSES:
        events = parse(os.path.join(DIR, filename), PATTERN)
        if not events:
            sys.exit(f"no state events found in {filename}")
        if start is None or events[0][0] < start:
            start = events[0][0]
        parsed[name] = events
    chaos = parse(CHAOS_LOG, CHAOS_PATTERN)

    def seconds(timestamp):
        return (timestamp - start).total_seconds()

    fig, axes = plt.subplots(
        len(PROCESSES), 1, figsize=(16, 5), sharex=True, squeeze=False
    )
    fig.canvas.manager.set_window_title("protocol state timeline")

    state_colors = {}
    palette = ["#1f77b4", "#ff7f0e", "#2ca02c", "#9467bd", "#8c564b", "#17becf"]

    for index, (name, _, color, states) in enumerate(PROCESSES):
        axis = axes[index][0]
        events = parsed[name]
        for stateIndex, state in enumerate(states):
            times = [
                seconds(timestamp)
                for timestamp, eventState in events
                if eventState == state
            ]
            if not times:
                continue
            if state not in state_colors:
                state_colors[state] = palette[stateIndex % len(palette)]
            axis.plot(
                times,
                [state] * len(times),
                ".",
                markersize=4,
                color=state_colors[state],
            )
        # Mark the very first event of this process on its lane.
        first = seconds(events[0][0])
        axis.axvline(
            first,
            color=color,
            linestyle=":",
            linewidth=1.5,
            alpha=0.9,
        )
        axis.annotate(
            "start",
            (first, states[0]),
            textcoords="offset points",
            xytext=(4, 0),
            fontsize=8,
            color=color,
            va="bottom",
        )
        for timestamp, kind, target in chaos:
            if target != name:
                continue
            when = seconds(timestamp)
            cleanup = kind == "cleanup killing"
            axis.axvline(
                when,
                color="black",
                linestyle="--" if not cleanup else ":",
                linewidth=1,
                alpha=0.4 if cleanup else 0.7,
            )
            # A skull marker on the lane plus a label, so the crash point is
            # obvious even when zoomed out. Cleanup kills are fainter.
            axis.plot(
                when,
                states[0],
                marker="X",
                markersize=9 if not cleanup else 6,
                color="black" if not cleanup else "gray",
                zorder=5,
            )
            axis.annotate(
                "cleanup" if cleanup else "killed",
                (when, states[0]),
                textcoords="offset points",
                xytext=(4, -12),
                fontsize=8,
                color="black" if not cleanup else "gray",
                rotation=45,
            )
        axis.set_ylabel(name)
        axis.set_ylim(-0.8, len(states) - 0.2)
        axis.grid(True, axis="x", alpha=0.2)
        axis.margins(x=0.01)

    if chaos:
        label = "chaos kills: " + ", ".join(
            f"{seconds(timestamp):.2f}s ({target})" for timestamp, target in chaos
        )
        axes[-1][0].set_xlabel(label, fontsize=8)
    else:
        axes[-1][0].set_xlabel("seconds since first event")

    fig.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
