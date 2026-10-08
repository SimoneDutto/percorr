# Lesson 2: Interleaving

Run `Interleaving.tla` with `Interleaving.cfg` using TLC. Two workers each perform what looks like an increment, but the model splits each increment into a read action and a write action.

`Next` is a disjunction of the four worker actions. At each step, any enabled action may happen. TLC explores the possible action orders instead of choosing one schedule. Each action is atomic in the model: its primed variables change together, and the other variables are unchanged.

The invariant says that once both workers are done, the shared value should be `2`. The model is intentionally wrong; TLC should find an execution where both workers finish but the invariant fails.

Read the trace one action at a time. What value did each worker read? Which write happened last? Why does that execution follow the model even if it is not the order you expected? Try a repair and rerun TLC; bring me your explanation and result before moving to the protocol exercise.
