---- MODULE Interleaving ----
EXTENDS Naturals

VARIABLES shared, pcA, pcB, readA, readB

vars == << shared, pcA, pcB, readA, readB >>

Init ==
  /\ shared = 0
  /\ pcA = "Read"
  /\ pcB = "Read"
  /\ readA = 0
  /\ readB = 0


IncrementA ==
  /\ pcA = "Read"
  /\ shared' = shared + 1
  /\ pcA' = "Done"
  /\ UNCHANGED << pcB, readA, readB >>

IncrementB ==
  /\ pcB = "Read"
  /\ shared' = shared + 1
  /\ pcB' = "Done"
  /\ UNCHANGED << pcA, readA, readB >>


Finish ==
  /\ pcA = "Done"
  /\ pcB = "Done"
  /\ UNCHANGED vars

Next == IncrementA \/ IncrementB \/ Finish

Spec == Init /\ [][Next]_vars

BothWorkersIncremented == ( pcA = "Done" /\ pcB = "Done" ) => shared = 2
====
