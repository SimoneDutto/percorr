---- MODULE Restart ----
EXTENDS Naturals

CONSTANT MaxChunks

VARIABLES durableOffset, volatileOffset, running

vars == << durableOffset, volatileOffset, running >>

Init ==
  /\ durableOffset = 0
  /\ volatileOffset = 0
  /\ running = TRUE

WriteChunk ==
  /\ running
  /\ durableOffset < MaxChunks
  /\ volatileOffset = durableOffset
  /\ durableOffset' = durableOffset + 1
  /\ volatileOffset' = volatileOffset + 1
  /\ UNCHANGED running

Crash ==
  /\ running
  /\ durableOffset > 0
  /\ running' = FALSE
  /\ UNCHANGED << durableOffset, volatileOffset >>

ProcessRestart ==
  /\ ~running
  /\ running' = TRUE
  /\ volatileOffset' = durableOffset
  /\ UNCHANGED durableOffset

Done ==
  /\ running
  /\ durableOffset = MaxChunks
  /\ UNCHANGED vars

Next == WriteChunk \/ Crash \/ ProcessRestart \/ Done

Spec == Init /\ [][Next]_vars /\ WF_vars(ProcessRestart) /\ SF_vars(WriteChunk)

Served ==
  /\ durableOffset = MaxChunks

TypeOK ==
  /\ durableOffset \in 0 .. MaxChunks
  /\ volatileOffset \in 0 .. MaxChunks
  /\ running \in BOOLEAN
  /\ Served \in BOOLEAN

RunningStateConsistent == running => volatileOffset = durableOffset

EventuallyServed == <>Served
====
