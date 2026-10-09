---- MODULE ParallelChunks ----
EXTENDS Naturals, Sequences, FiniteSets

Chunks == { 1, 2 }

VARIABLES unsentChunks,
          chunkPackets,
          followerReceived,
          ackPackets,
          leaderAcked,
          chunkReceiveOrder,
          ackReceiveOrder

vars ==
  << unsentChunks,
     chunkPackets,
     followerReceived,
     ackPackets,
     leaderAcked,
     chunkReceiveOrder,
     ackReceiveOrder
  >>

Init ==
  /\ unsentChunks = Chunks
  /\ chunkPackets = {}
  /\ followerReceived = {}
  /\ ackPackets = {}
  /\ leaderAcked = {}
  /\ chunkReceiveOrder = <<>>
  /\ ackReceiveOrder = <<>>

SendChunk(chunk) ==
  /\ chunk \in unsentChunks
  /\ unsentChunks' = unsentChunks \ { chunk }
  /\ chunkPackets' = chunkPackets \cup { chunk }
  /\ UNCHANGED << followerReceived,
        ackPackets,
        leaderAcked,
        chunkReceiveOrder,
        ackReceiveOrder
     >>

ReceiveChunk(chunk) ==
  /\ chunk \in chunkPackets
  /\ chunkPackets' = chunkPackets \ { chunk }
  /\ followerReceived' = followerReceived \cup { chunk }
  /\ ackPackets' = ackPackets \cup { chunk }
  /\ chunkReceiveOrder' = Append(chunkReceiveOrder, chunk)
  /\ UNCHANGED << unsentChunks, leaderAcked, ackReceiveOrder >>

ReceiveAck(chunk) ==
  /\ chunk \in ackPackets
  /\ ackPackets' = ackPackets \ { chunk }
  /\ leaderAcked' = leaderAcked \cup { chunk }
  /\ ackReceiveOrder' = Append(ackReceiveOrder, chunk)
  /\ UNCHANGED << unsentChunks,
        chunkPackets,
        followerReceived,
        chunkReceiveOrder
     >>

Done ==
  /\ leaderAcked = Chunks
  /\ UNCHANGED vars

Next ==
  \E chunk \in Chunks:
    SendChunk(chunk) \/ ReceiveChunk(chunk) \/ ReceiveAck(chunk) \/ Done

FairProgress == \A chunk \in Chunks: /\ WF_vars(SendChunk(chunk))
                                     /\ WF_vars(ReceiveChunk(chunk))
                                     /\ WF_vars(ReceiveAck(chunk))

Spec == Init /\ [][Next]_vars /\ FairProgress

SequenceElements(sequence) == {sequence[index]: index \in 1 .. Len(sequence)}

TypeOK ==
  /\ unsentChunks \subseteq Chunks
  /\ chunkPackets \subseteq Chunks
  /\ followerReceived \subseteq Chunks
  /\ ackPackets \subseteq Chunks
  /\ leaderAcked \subseteq Chunks
  /\ chunkReceiveOrder \in Seq(Chunks)
  /\ ackReceiveOrder \in Seq(Chunks)

ChunkConservation ==
  /\ unsentChunks \cup chunkPackets \cup followerReceived = Chunks
  /\ unsentChunks \cap chunkPackets = {}
  /\ unsentChunks \cap followerReceived = {}
  /\ chunkPackets \cap followerReceived = {}

AckOnlyAfterDelivery ==
  ( ackPackets \cup leaderAcked ) \subseteq followerReceived

ChunkReceiveOrderConsistent ==
  /\ SequenceElements(chunkReceiveOrder) = followerReceived
  /\ Len(chunkReceiveOrder) = Cardinality(followerReceived)

AckReceiveOrderConsistent ==
  /\ SequenceElements(ackReceiveOrder) = leaderAcked
  /\ Len(ackReceiveOrder) = Cardinality(leaderAcked)

AllChunksAcked == leaderAcked = Chunks

EventuallyAllChunksAcked == <>AllChunksAcked
====
