---- MODULE FullTransfer ----
EXTENDS Naturals

CONSTANT MaxChunks

NoPacket == MaxChunks

VARIABLES leaderPC,
          followerPC,
          leaderOffset,
          durableOffset,
          followerOffset,
          restartRequestPacket,
          restartRevisionPacket,
          restartRevisionOffset,
          chunkInFlight,
          chunkPacket,
          ackPacket

vars ==
  << leaderPC,
     followerPC,
     leaderOffset,
     durableOffset,
     followerOffset,
     restartRequestPacket,
     restartRevisionPacket,
     restartRevisionOffset,
     chunkInFlight,
     chunkPacket,
     ackPacket
  >>

Init ==
  /\ leaderPC = "RESTART_LOOP"
  /\ followerPC = "WAIT_RESTART"
  /\ leaderOffset = 0
  /\ durableOffset = 0
  /\ followerOffset = 0
  /\ restartRequestPacket = FALSE
  /\ restartRevisionPacket = FALSE
  /\ restartRevisionOffset = 0
  /\ chunkInFlight = FALSE
  /\ chunkPacket = NoPacket
  /\ ackPacket = NoPacket

LeaderSendRestart ==
  /\ leaderPC = "RESTART_LOOP"
  /\ ~restartRequestPacket
  /\ ~restartRevisionPacket
  /\ leaderPC' = "WAIT_RESTART_RESPONSE"
  /\ restartRequestPacket' = TRUE
  /\ UNCHANGED << followerPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight,
        chunkPacket,
        ackPacket
     >>

DropRestartRequest ==
  /\ restartRequestPacket
  /\ restartRequestPacket' = FALSE
  /\ UNCHANGED << leaderPC,
        followerPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight,
        chunkPacket,
        ackPacket
     >>

LeaderRestartTimeout ==
  /\ leaderPC = "WAIT_RESTART_RESPONSE"
  /\ ~restartRevisionPacket
  /\ leaderPC' = "WAIT_RESTART_RESPONSE"
  /\ restartRequestPacket' = TRUE
  /\ UNCHANGED << followerPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight,
        chunkPacket,
        ackPacket
     >>

FollowerReceiveRestart ==
  /\ followerPC \in
       { "WAIT_RESTART", "SEND_RESTART_REV", "BLOCK_LOOP", "WAIT_FINISH" }
  /\ restartRequestPacket
  /\ ~restartRevisionPacket
  /\ followerPC' = "SEND_RESTART_REV"
  /\ restartRequestPacket' = FALSE
  /\ UNCHANGED << leaderPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight,
        chunkPacket,
        ackPacket
     >>

FollowerSendRestartRevision ==
  /\ followerPC = "SEND_RESTART_REV"
  /\ restartRevisionOffset' = durableOffset
  /\ restartRevisionPacket' = TRUE
  /\ followerOffset' = durableOffset
  /\ followerPC' =
       IF durableOffset = MaxChunks THEN "WAIT_FINISH" ELSE "BLOCK_LOOP"
  /\ UNCHANGED << leaderPC,
        leaderOffset,
        durableOffset,
        restartRequestPacket,
        chunkInFlight,
        chunkPacket,
        ackPacket
     >>

DropRestartRevision ==
  /\ restartRevisionPacket
  /\ restartRevisionPacket' = FALSE
  /\ UNCHANGED << leaderPC,
        followerPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRequestPacket,
        restartRevisionOffset,
        chunkInFlight,
        chunkPacket,
        ackPacket
     >>

FollowerRestartTimeout ==
  /\ followerPC \in { "BLOCK_LOOP", "WAIT_FINISH" }
  /\ leaderPC = "WAIT_RESTART_RESPONSE"
  /\ ~restartRevisionPacket
  /\ followerPC' = "SEND_RESTART_REV"
  /\ UNCHANGED << leaderPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRequestPacket,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight,
        chunkPacket,
        ackPacket
     >>

LeaderReceiveRestartRevision ==
  /\ leaderPC = "WAIT_RESTART_RESPONSE"
  /\ restartRevisionPacket
  /\ leaderOffset' = restartRevisionOffset
  /\ leaderPC' =
       IF restartRevisionOffset = MaxChunks THEN "DONE" ELSE "BLOCK_LOOP"
  /\ restartRevisionPacket' = FALSE
  /\ UNCHANGED << followerPC,
        durableOffset,
        followerOffset,
        restartRequestPacket,
        restartRevisionOffset,
        chunkInFlight,
        chunkPacket,
        ackPacket
     >>

LeaderSendChunk ==
  /\ leaderPC = "BLOCK_LOOP"
  /\ leaderOffset < MaxChunks
  /\ ~chunkInFlight
  /\ chunkPacket = NoPacket
  /\ leaderPC' = "WAIT_FOR_ACK"
  /\ chunkInFlight' = TRUE
  /\ chunkPacket' = leaderOffset
  /\ UNCHANGED << followerPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRequestPacket,
        restartRevisionPacket,
        restartRevisionOffset,
        ackPacket
     >>

LeaderChunkTimeout ==
  /\ leaderPC = "WAIT_FOR_ACK"
  /\ ackPacket = NoPacket
  /\ chunkPacket = NoPacket
  /\ leaderPC' = "BLOCK_LOOP"
  /\ UNCHANGED << followerPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRequestPacket,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight,
        chunkPacket,
        ackPacket
     >>

LeaderRetryChunk ==
  /\ leaderPC = "BLOCK_LOOP"
  /\ chunkInFlight
  /\ chunkPacket = NoPacket
  /\ leaderPC' = "WAIT_FOR_ACK"
  /\ chunkPacket' = leaderOffset
  /\ UNCHANGED << followerPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRequestPacket,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight,
        ackPacket
     >>

DropChunk ==
  /\ chunkPacket # NoPacket
  /\ chunkPacket' = NoPacket
  /\ UNCHANGED << leaderPC,
        followerPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRequestPacket,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight,
        ackPacket
     >>

FollowerReceiveAndAckChunk ==
  /\ followerPC \in { "BLOCK_LOOP", "WAIT_FINISH" }
  /\ chunkPacket # NoPacket
  /\ chunkPacket <= followerOffset
  /\ ackPacket = NoPacket
  /\ followerOffset' =
       IF chunkPacket = followerOffset
       THEN followerOffset + 1
       ELSE followerOffset
  /\ durableOffset' =
       IF chunkPacket = followerOffset THEN durableOffset + 1 ELSE durableOffset
  /\ chunkPacket' = NoPacket
  /\ ackPacket' = chunkPacket
  /\ followerPC' =
       IF durableOffset = MaxChunks \/
           ( chunkPacket = followerOffset /\ durableOffset + 1 = MaxChunks )
       THEN "WAIT_FINISH"
       ELSE "BLOCK_LOOP"
  /\ UNCHANGED << leaderPC,
        leaderOffset,
        restartRequestPacket,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight
     >>

DropAck ==
  /\ ackPacket # NoPacket
  /\ ackPacket' = NoPacket
  /\ UNCHANGED << leaderPC,
        followerPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRequestPacket,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight,
        chunkPacket
     >>

FollowerAckTimeout ==
  /\ followerPC \in { "BLOCK_LOOP", "WAIT_FINISH" }
  /\ chunkInFlight
  /\ ackPacket = NoPacket
  /\ followerOffset = leaderOffset + 1
  /\ ackPacket' = leaderOffset
  /\ UNCHANGED << leaderPC,
        followerPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRequestPacket,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight,
        chunkPacket
     >>

LeaderReceiveAck ==
  /\ leaderPC = "WAIT_FOR_ACK"
  /\ ackPacket = leaderOffset
  /\ leaderOffset' = leaderOffset + 1
  /\ chunkInFlight' = FALSE
  /\ ackPacket' = NoPacket
  /\ leaderPC' = IF leaderOffset + 1 = MaxChunks THEN "DONE" ELSE "BLOCK_LOOP"
  /\ UNCHANGED << followerPC,
        durableOffset,
        followerOffset,
        restartRequestPacket,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkPacket
     >>

LeaderRejectStaleAck ==
  /\ ackPacket # NoPacket
  /\ ackPacket < leaderOffset
  /\ ackPacket' = NoPacket
  /\ UNCHANGED << leaderPC,
        followerPC,
        leaderOffset,
        durableOffset,
        followerOffset,
        restartRequestPacket,
        restartRevisionPacket,
        restartRevisionOffset,
        chunkInFlight,
        chunkPacket
     >>

Done ==
  /\ leaderPC = "DONE"
  /\ followerPC = "WAIT_FINISH"
  /\ durableOffset = MaxChunks
  /\ ~chunkInFlight
  /\ UNCHANGED vars

Next ==
  LeaderSendRestart \/ DropRestartRequest \/ LeaderRestartTimeout \/
                                FollowerReceiveRestart \/
                              FollowerSendRestartRevision \/
                            DropRestartRevision \/
                          FollowerRestartTimeout \/
                        LeaderReceiveRestartRevision \/
                      LeaderSendChunk \/
                    LeaderChunkTimeout \/
                  LeaderRetryChunk \/
                DropChunk \/
              FollowerReceiveAndAckChunk \/
            DropAck \/
          FollowerAckTimeout \/
        LeaderReceiveAck \/
      LeaderRejectStaleAck \/
    Done

Spec ==
  Init /\ [][Next]_vars /\ WF_vars(LeaderSendRestart) /\
                          WF_vars(LeaderRestartTimeout) /\
                        SF_vars(FollowerReceiveRestart) /\
                      WF_vars(FollowerSendRestartRevision) /\
                    WF_vars(FollowerRestartTimeout) /\
                  SF_vars(LeaderReceiveRestartRevision) /\
                WF_vars(LeaderSendChunk) /\
              WF_vars(LeaderChunkTimeout) /\
            SF_vars(LeaderRetryChunk) /\
          SF_vars(FollowerReceiveAndAckChunk) /\
        WF_vars(FollowerAckTimeout) /\
      SF_vars(LeaderReceiveAck) /\
    WF_vars(LeaderRejectStaleAck)

TypeOK ==
  /\ leaderPC \in
       { "RESTART_LOOP",
         "WAIT_RESTART_RESPONSE",
         "BLOCK_LOOP",
         "WAIT_FOR_ACK",
         "DONE"
       }
  /\ followerPC \in
       { "WAIT_RESTART", "SEND_RESTART_REV", "BLOCK_LOOP", "WAIT_FINISH" }
  /\ leaderOffset \in 0 .. MaxChunks
  /\ durableOffset \in 0 .. MaxChunks
  /\ followerOffset \in 0 .. MaxChunks
  /\ restartRequestPacket \in BOOLEAN
  /\ restartRevisionPacket \in BOOLEAN
  /\ restartRevisionOffset \in 0 .. MaxChunks
  /\ chunkInFlight \in BOOLEAN
  /\ chunkPacket \in 0 .. MaxChunks
  /\ ackPacket \in 0 .. MaxChunks

LeaderNeverAheadOfFollower == leaderOffset <= durableOffset

FollowerAtMostOneAhead == durableOffset <= leaderOffset + 1

FollowerMemoryMatchesFile ==
  followerPC \in { "BLOCK_LOOP", "WAIT_FINISH" } =>
    followerOffset = durableOffset

FileComplete ==
  /\ leaderPC = "DONE"
  /\ followerPC = "WAIT_FINISH"
  /\ leaderOffset = MaxChunks
  /\ durableOffset = MaxChunks
  /\ followerOffset = MaxChunks

EventuallyFileComplete == <>FileComplete
====
