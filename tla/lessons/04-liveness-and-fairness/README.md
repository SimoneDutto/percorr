# Lesson 4: Liveness and fairness

Run `Progress.tla` with `Progress.cfg` using TLC. This tiny model has a pending request and one action, `Serve`, that completes it.

`EventuallyServed == <>served` is a liveness property: `<>` means "eventually." It says the request is eventually served. Unlike an invariant, this property is about an entire behavior, not a single state.

The model is intentionally missing an assumption about scheduling. TLC should find a behavior that stays forever in the initial state: `Serve` is allowed, but the specification does not require it to happen. The liveness counterexample will show a loop, meaning the same state can repeat forever.

The TLA+ fairness operator `WF_vars(Serve)` means weak fairness for `Serve`: if `Serve` remains continuously enabled, it must eventually occur. Add that fairness condition to `Spec`, then rerun TLC. The liveness property should pass. In your own words, explain why this does not require `Serve` to happen immediately, and why it cannot be postponed forever here.

After you get this toy model passing, continue in [the protocol model](../../protocol/duplicate-delivery/README.md). The same lesson is applied there: make a transfer-completion property and add fairness to the actions needed for progress. From this point on, lessons extend that shared protocol model rather than ending with an isolated toy example.
