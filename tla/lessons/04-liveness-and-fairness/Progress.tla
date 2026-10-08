---- MODULE Progress ----
VARIABLES pending, served

vars == << pending, served >>

Init ==
  /\ pending = TRUE
  /\ served = FALSE

Serve ==
  /\ pending
  /\ pending' = FALSE
  /\ served' = TRUE

Done ==
  /\ served
  /\ UNCHANGED vars

Next == Serve \/ Done

Spec == Init /\ [][Next]_vars /\ WF_vars(Serve)

TypeOK ==
  /\ pending \in BOOLEAN
  /\ served \in BOOLEAN

EventuallyServed == <>served
====
