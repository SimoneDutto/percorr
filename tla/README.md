# Learning TLA+

This folder holds a hands-on path toward a TLA+ model that matches the protocol in `../protocol`. The first two lessons use small models to teach notation and interleaving; from the protocol exercise onward, each lesson applies its concept to the shared leader/follower spec and moves it closer to the Go implementation. The existing `corr_terr` experiment is left as-is.

## VS Code setup

The workspace already has the community **TLA+ (Temporal Logic of Actions)** extension installed (`tlaplus.vscode-ide`), and Java 21 is available. The extension provides TLA+ syntax support, TLC model checking, and trace visualization. If setting up another machine, install the TLA+ extension by the TLA+ Community publisher and a supported Java runtime.

To run a lesson, open its `.tla` file and run **TLA+: Check model with TLC** from the Command Palette. Keep the matching `.cfg` file beside it; use **Check model with TLC using non-default config...** if the extension does not select that config automatically. TLC output is available in the extension's output/model-checker view. The **TLA+: Visualize TLC output** command can help inspect a saved trace.

## How we'll work

Run each model before changing it. Read a counterexample as a sequence of complete states: compare the variables between adjacent states to see what changed, then identify which action allowed that transition. Try your own change and rerun TLC. Bring me the trace or your hypothesis when you want guidance; I'll help you reason it through without jumping straight to the answer.

## Learning path

1. [State and actions](lessons/01-state-and-actions/README.md): state variables, initial predicates, primed next-state values, `UNCHANGED`, and what TLC does with a bounded model.
2. [Interleaving](lessons/02-interleaving/README.md): nondeterministic action choice, atomic steps, and why a concurrent execution can differ from the sequential one you expect.
3. [Duplicate delivery](protocol/duplicate-delivery/README.md): apply those ideas to leader/follower offsets and retry behavior.
4. [Liveness and fairness](lessons/04-liveness-and-fairness/README.md): express eventual progress and rule out an action being postponed forever.

Next we'll model packet loss, timeout, and retry behavior, then refine the abstractions and compare each transition and state variable with the Go implementation. The goal is an explicit correspondence, including any implementation details we intentionally abstract away.
