# Different network setup different results

10 process restarts at the beginning to test the correctness, and then it's left uninterrupted.


- clean: 11 seconds for 100MB (9.1 MB/s)
- drop 20% pkts: 342 seconds for 100MB (0.3 MB/s)
- duplicate 20% pkts: 219 seconds for 100MB (0.5 MB/s)
- reorder 20% pkts: not done yet
