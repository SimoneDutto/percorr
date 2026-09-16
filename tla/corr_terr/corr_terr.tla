---- MODULE corr_terr ----
EXTENDS Integers, TLC

(* --algorithm pluscal
variables
 x = 2;
 y = TRUE;

begin
  A:
    x := x + 1;
  B:
    x := x + 2;
    y := FALSE;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "2ccbc9e1" /\ chksum(tla) = "f7c1fdcd")
VARIABLES pc, x, y

vars == << pc, x, y >>

Init ==
  (* Global variables *)
  /\ x = 2
  /\ y = TRUE
  /\ pc = "A"

A ==
  /\ pc = "A"
  /\ x' = x + 1
  /\ pc' = "B"
  /\ y' = y

B ==
  /\ pc = "B"
  /\ x' = x + 2
  /\ y' = FALSE
  /\ pc' = "Done"

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == pc = "Done" /\ UNCHANGED vars

Next == A \/ B \/ Terminating

Spec == Init /\ [][Next]_vars

Termination == <>( pc = "Done" )

\* END TRANSLATION 
====
