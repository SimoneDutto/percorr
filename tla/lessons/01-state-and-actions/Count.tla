---- MODULE Count ----
EXTENDS Naturals

CONSTANT Limit

VARIABLE count

vars == << count >>

Init == count = 0

Step ==
  /\ count < Limit
  /\ count' = count + 1

Finish ==
  /\ count = Limit
  /\ UNCHANGED vars

Next == Step \/ Finish

Spec == Init /\ [][Next]_vars

InRange == count \in 0 .. Limit
====
