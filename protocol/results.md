# Different network setup different results

10 process restarts at the beginning to test the correctness, and then it's left uninterrupted.

- clean: 11 seconds for 100MB (9.1 MB/s)
- drop 20% pkts: 342 seconds for 100MB (0.3 MB/s)
- duplicate 20% pkts: 219 seconds for 100MB (0.5 MB/s)

Reorder required another algorithm so it's not super fair to compare them:
- reorder 20% and delay 10ms:  427 seconds (0.2MB/s)
