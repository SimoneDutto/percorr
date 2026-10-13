---- MODULE ModelDestruction ----
EXTENDS Naturals


VARIABLE model_dying,
         model_destroyed_jimm,
         model_destroyed_juju,
         jujuResultDestroy,
         jimmUpdateResult,
         jujuResultGet

vars ==
  << model_dying,
     model_destroyed_jimm,
     model_destroyed_juju,
     jujuResultDestroy,
     jimmUpdateResult,
     jujuResultGet
  >>

Init ==
  model_dying = FALSE /\ model_destroyed_jimm = FALSE /\
          model_destroyed_juju = FALSE /\
        jujuResultDestroy = "not-called" /\
      jimmUpdateResult = "not-attempted" /\
    jujuResultGet = "not-called"

SetModelDying ==
  /\ model_dying = FALSE
  /\ model_dying' = TRUE
  /\ model_destroyed_jimm = FALSE
  /\ model_destroyed_juju = FALSE
  /\ jujuResultDestroy = "not-called"
  /\ UNCHANGED << model_destroyed_jimm,
        model_destroyed_juju,
        jujuResultDestroy,
        jimmUpdateResult,
        jujuResultGet
     >>

JujuDestroy ==
  /\ model_dying
  /\ model_destroyed_juju = FALSE
  /\ jujuResultDestroy = "not-called"
  /\ jujuResultDestroy' \in { "success", "not-found", "other-error" }
  /\ UNCHANGED << model_destroyed_jimm,
        model_destroyed_juju,
        model_dying,
        jimmUpdateResult,
        jujuResultGet
     >>

SetModelDestroyedJuju ==
  /\ model_dying = TRUE
  /\ model_destroyed_juju = FALSE
  /\ jujuResultDestroy \in { "success", "not-found" }
  /\ model_destroyed_juju' = TRUE
  /\ UNCHANGED << model_dying,
        jujuResultDestroy,
        model_destroyed_jimm,
        jimmUpdateResult,
        jujuResultGet
     >>

SetModelDestroyedJimm ==
  /\ model_destroyed_jimm = FALSE
  /\ model_destroyed_juju = TRUE
  /\ jimmUpdateResult = "not-attempted"
  /\ jimmUpdateResult' = "succeeded"
  /\ model_destroyed_jimm' = TRUE
  /\ UNCHANGED << model_dying,
        model_destroyed_juju,
        jujuResultDestroy,
        jujuResultGet
     >>

FailSetModelDestroyedJimm ==
  /\ model_destroyed_jimm = FALSE
  /\ model_destroyed_juju = TRUE
  /\ jimmUpdateResult = "not-attempted"
  /\ jimmUpdateResult' = "failed"
  /\ UNCHANGED << model_dying,
        model_destroyed_jimm,
        model_destroyed_juju,
        jujuResultDestroy,
        jujuResultGet
     >>

JujuGet ==
  /\ model_dying = TRUE
  /\ model_destroyed_jimm = FALSE
  /\ model_destroyed_juju = TRUE
  /\ jimmUpdateResult = "failed"
  /\ jujuResultGet = "not-called"
  /\ jujuResultGet' \in { "not-found", "found" }
  /\ UNCHANGED << model_dying,
        model_destroyed_jimm,
        model_destroyed_juju,
        jujuResultDestroy,
        jimmUpdateResult
     >>

SetModelAlive ==
  /\ model_dying = TRUE
  /\ jujuResultDestroy = "other-error"
  /\ model_destroyed_jimm = FALSE
  /\ model_destroyed_juju = FALSE
  /\ model_dying' = FALSE
  /\ UNCHANGED << model_destroyed_jimm,
        model_destroyed_juju,
        jujuResultDestroy,
        jimmUpdateResult,
        jujuResultGet
     >>

ModelPollerDestroying ==
  /\ model_dying = TRUE
  /\ model_destroyed_jimm = FALSE
  /\ model_destroyed_juju = TRUE
  /\ jimmUpdateResult = "failed"
  /\ jujuResultGet = "not-found"
  /\ model_dying' = TRUE
  /\ model_destroyed_jimm' = TRUE
  /\ UNCHANGED << model_dying,
        model_destroyed_juju,
        jujuResultDestroy,
        jimmUpdateResult,
        jujuResultGet
     >>

ManualReconciliation ==
  /\ model_dying = TRUE
  /\ jujuResultGet = "found"
  /\ model_destroyed_jimm = FALSE
  /\ jimmUpdateResult = "failed"
  /\ model_dying' = FALSE
  /\ model_destroyed_juju' = FALSE
  /\ UNCHANGED << model_destroyed_jimm,
        jujuResultDestroy,
        jimmUpdateResult,
        jujuResultGet
     >>

ModelRemoved ==
  /\ model_destroyed_jimm = TRUE
  /\ model_destroyed_juju = TRUE

DestroyCallFailedRestore ==
  /\ jujuResultDestroy = "other-error"
  /\ jimmUpdateResult = "not-attempted"

ManualReconciliationRestore ==
  /\ jujuResultGet = "found"
  /\ jimmUpdateResult = "failed"

ModelRestoredAlive ==
  /\ model_dying = FALSE
  /\ model_destroyed_jimm = FALSE
  /\ model_destroyed_juju = FALSE
  /\ ( DestroyCallFailedRestore \/ ManualReconciliationRestore )

EventuallyModelRemoved == <>ModelRemoved

Resolved == ModelRemoved \/ ModelRestoredAlive
EventuallyResolved == <>Resolved

TypeOK ==
  /\ model_dying \in BOOLEAN
  /\ model_destroyed_jimm \in BOOLEAN
  /\ model_destroyed_juju \in BOOLEAN
  /\ jujuResultDestroy \in
       { "not-called", "success", "not-found", "other-error" }
  /\ jimmUpdateResult \in { "not-attempted", "succeeded", "failed" }
  /\ jujuResultGet \in { "not-called", "not-found", "found" }

JimmRemovedOnlyAfterJuju == model_destroyed_jimm => model_destroyed_juju

Finish ==
  /\ Resolved
  /\ UNCHANGED vars

Next ==
  SetModelDying \/ SetModelDestroyedJuju \/ ModelPollerDestroying \/ JujuDestroy \/
              JujuGet \/
            SetModelAlive \/
          SetModelDestroyedJimm \/
        FailSetModelDestroyedJimm \/
      ManualReconciliation \/
    Finish

Spec ==
  Init /\ [][Next]_vars /\ WF_vars(SetModelDying) /\ WF_vars(SetModelAlive) /\
                WF_vars(SetModelDestroyedJuju) /\
              WF_vars(SetModelDestroyedJimm) /\
            WF_vars(FailSetModelDestroyedJimm) /\
          WF_vars(ModelPollerDestroying) /\
        WF_vars(JujuDestroy) /\
      WF_vars(JujuGet) /\
    WF_vars(ManualReconciliation)

====
