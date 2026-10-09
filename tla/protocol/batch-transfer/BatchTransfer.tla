---- MODULE BatchTransfer ----
EXTENDS Naturals, FiniteSets

CONSTANTS MaxChunks, WindowSize

Chunks == 0 .. ( MaxChunks - 1 )

VARIABLES leaderPC,
          batchBase,
          sentChunks,
          batchAcked,
          batchTimerExpired,
          chunkPackets,
          ackPackets,
          followerWriteOffset,
          followerBuffer

vars ==
  << leaderPC,
     batchBase,
     sentChunks,
     batchAcked,
     batchTimerExpired,
     chunkPackets,
     ackPackets,
     followerWriteOffset,
     followerBuffer
  >>

CurrentBatch ==
  {chunk \in Chunks: batchBase <= chunk /\ chunk < batchBase + WindowSize}

Init ==
  /\ leaderPC = "SENDING_BATCH"
  /\ batchBase = 0
  /\ sentChunks = {}
  /\ batchAcked = {}
  /\ batchTimerExpired = FALSE
  /\ chunkPackets = {}
  /\ ackPackets = {}
  /\ followerWriteOffset = 0
  /\ followerBuffer = {}

LeaderSendChunk(chunk) ==
  /\ leaderPC = "SENDING_BATCH"
  /\ chunk \in CurrentBatch
  /\ chunk \notin sentChunks
  /\ sentChunks' = sentChunks \cup { chunk }
  /\ chunkPackets' = chunkPackets \cup { chunk }
  /\ UNCHANGED << leaderPC,
        batchBase,
        batchAcked,
        batchTimerExpired,
        ackPackets,
        followerWriteOffset,
        followerBuffer
     >>

LeaderWaitForBatchAcks ==
  /\ leaderPC = "SENDING_BATCH"
  /\ sentChunks = CurrentBatch
  /\ leaderPC' = "WAITING_FOR_ACKS"
  /\ batchTimerExpired' = FALSE
  /\ UNCHANGED << batchBase,
        sentChunks,
        batchAcked,
        chunkPackets,
        ackPackets,
        followerWriteOffset,
        followerBuffer
     >>

ExpireBatchTimer ==
  /\ leaderPC = "WAITING_FOR_ACKS"
  /\ batchAcked # CurrentBatch
  /\ ~batchTimerExpired
  /\ batchTimerExpired' = TRUE
  /\ UNCHANGED << leaderPC,
        batchBase,
        sentChunks,
        batchAcked,
        chunkPackets,
        ackPackets,
        followerWriteOffset,
        followerBuffer
     >>

TimeoutResendBatch ==
  /\ leaderPC = "WAITING_FOR_ACKS"
  /\ batchAcked # CurrentBatch
  /\ batchTimerExpired
  /\ chunkPackets' = chunkPackets \cup CurrentBatch
  /\ batchTimerExpired' = FALSE
  /\ UNCHANGED << leaderPC,
        batchBase,
        sentChunks,
        batchAcked,
        ackPackets,
        followerWriteOffset,
        followerBuffer
     >>

DropChunk(chunk) ==
  /\ chunk \in chunkPackets
  /\ chunkPackets' = chunkPackets \ { chunk }
  /\ UNCHANGED << leaderPC,
        batchBase,
        sentChunks,
        batchAcked,
        batchTimerExpired,
        ackPackets,
        followerWriteOffset,
        followerBuffer
     >>

FollowerReceiveChunk(chunk) ==
  /\ chunk \in chunkPackets
  /\ chunk < followerWriteOffset \/ chunk \in followerBuffer \/
       Cardinality(followerBuffer) < WindowSize
  /\ chunkPackets' = chunkPackets \ { chunk }
  /\ followerBuffer' =
       IF chunk < followerWriteOffset
       THEN followerBuffer
       ELSE followerBuffer \cup { chunk }
  /\ ackPackets' =
       IF chunk < followerWriteOffset
       THEN ackPackets \cup { chunk }
       ELSE ackPackets
  /\ UNCHANGED << leaderPC,
        batchBase,
        sentChunks,
        batchAcked,
        batchTimerExpired,
        followerWriteOffset
     >>

FollowerWriteNext ==
  /\ followerWriteOffset \in followerBuffer
  /\ followerBuffer' = followerBuffer \ { followerWriteOffset }
  /\ followerWriteOffset' = followerWriteOffset + 1
  /\ ackPackets' = ackPackets \cup { followerWriteOffset }
  /\ UNCHANGED << leaderPC,
        batchBase,
        sentChunks,
        batchAcked,
        batchTimerExpired,
        chunkPackets
     >>

DropAck(chunk) ==
  /\ chunk \in ackPackets
  /\ ackPackets' = ackPackets \ { chunk }
  /\ UNCHANGED << leaderPC,
        batchBase,
        sentChunks,
        batchAcked,
        batchTimerExpired,
        chunkPackets,
        followerWriteOffset,
        followerBuffer
     >>

LeaderReceiveAck(chunk) ==
  /\ chunk \in ackPackets
  /\ ackPackets' = ackPackets \ { chunk }
  /\ batchAcked' =
       IF chunk \in CurrentBatch THEN batchAcked \cup { chunk } ELSE batchAcked
  /\ UNCHANGED << leaderPC,
        batchBase,
        sentChunks,
        batchTimerExpired,
        chunkPackets,
        followerWriteOffset,
        followerBuffer
     >>

LeaderAdvanceBatch ==
  /\ leaderPC = "WAITING_FOR_ACKS"
  /\ batchAcked = CurrentBatch
  /\ IF batchBase + WindowSize < MaxChunks
     THEN /\ leaderPC' = "SENDING_BATCH"
          /\ batchBase' = batchBase + WindowSize
          /\ sentChunks' = {}
          /\ batchAcked' = {}
          /\ batchTimerExpired' = FALSE
     ELSE /\ leaderPC' = "DONE"
          /\ UNCHANGED << batchBase,
                sentChunks,
                batchAcked,
                batchTimerExpired
             >>
  /\ UNCHANGED << chunkPackets,
        ackPackets,
        followerWriteOffset,
        followerBuffer
     >>

Done ==
  /\ leaderPC = "DONE"
  /\ UNCHANGED vars

Next ==
  \/ LeaderWaitForBatchAcks
  \/ ExpireBatchTimer
  \/ TimeoutResendBatch
  \/ FollowerWriteNext
  \/ LeaderAdvanceBatch
  \/ Done
  \/ \E chunk \in Chunks:
       LeaderSendChunk(chunk) \/ DropChunk(chunk) \/ FollowerReceiveChunk(chunk) \/
           DropAck(chunk) \/
         LeaderReceiveAck(chunk)

FairProgress ==
  /\ WF_vars(LeaderWaitForBatchAcks)
  /\ WF_vars(ExpireBatchTimer)
  /\ WF_vars(TimeoutResendBatch)
  /\ WF_vars(FollowerWriteNext)
  /\ WF_vars(LeaderAdvanceBatch)
  /\ \A chunk \in Chunks:
       /\ WF_vars(LeaderSendChunk(chunk))
       /\ SF_vars(FollowerReceiveChunk(chunk)) /\
            SF_vars(LeaderReceiveAck(chunk))

Spec == Init /\ [][Next]_vars /\ FairProgress

TypeOK ==
  /\ MaxChunks \in Nat \ { 0 }
  /\ WindowSize \in Nat \ { 0 }
  /\ leaderPC \in { "SENDING_BATCH", "WAITING_FOR_ACKS", "DONE" }
  /\ batchBase \in 0 .. MaxChunks
  /\ sentChunks \subseteq Chunks
  /\ batchAcked \subseteq Chunks
  /\ batchTimerExpired \in BOOLEAN
  /\ chunkPackets \subseteq Chunks
  /\ ackPackets \subseteq Chunks
  /\ followerWriteOffset \in 0 .. MaxChunks
  /\ followerBuffer \subseteq Chunks

BufferBound == Cardinality(followerBuffer) <= WindowSize

BufferContainsOnlyUnwrittenChunks ==
  \A chunk \in followerBuffer: chunk >= followerWriteOffset

AckMeansWritten ==
  ( ackPackets \cup batchAcked ) \subseteq
    {chunk \in Chunks: chunk < followerWriteOffset}

SentAndAckedBelongToCurrentBatch ==
  /\ sentChunks \subseteq CurrentBatch
  /\ batchAcked \subseteq CurrentBatch

FileComplete ==
  /\ leaderPC = "DONE"
  /\ followerWriteOffset = MaxChunks
  /\ followerBuffer = {}

EventuallyFileComplete == <>FileComplete
====
