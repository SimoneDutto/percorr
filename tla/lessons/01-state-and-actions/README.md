# Lesson 1: State and actions

Start here. Run `Count.tla` with `Count.cfg` using TLC. It is a deliberately small model with one variable and one transition, but it has the same basic shape as larger specifications.

TLA+ describes possible behaviors rather than giving a sequence of commands to execute:

- `count` is a state variable. A state is an assignment of values to all the variables.
- `Init` describes which states may be first.
- `Step` describes a transition from a current state to a next state. Unprimed `count` is its current value; `count'` is its value after the transition.
- `UNCHANGED vars` says the listed state variables keep their current values in that transition.
- `Next` names the allowed transition relation. `Spec` says to start in `Init` and keep taking allowed transitions. The brackets allow a step to leave the state unchanged; this is called stuttering and we'll return to it later.

The `.cfg` gives TLC a small value for `Limit` and asks it to check `InRange` in every reachable state. The model is intentionally wrong, so TLC should show a trace where `count` moves outside the range.

Before editing, read the trace and locate the first bad state. Which action led there? Make the smallest change you think fixes the model, run TLC again, and tell me what you changed and what TLC reported. Don't worry if the notation is unfamiliar yet; we'll build it up from the trace.
