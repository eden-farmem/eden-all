Figures & data for the paper.

The paper itself is at https://github.com/anilkyelam/eden-paper


## Figures



## Table 1 Data
Thread benchmarks are measured using the tools from previous papers.

Linux Pthreads' tbench tool at https://github.com/shenango/bench/tree/master/threading
```
$ ./tbench_linux 
test 'SpawnJoin' took 39.1156 us.
test 'UncontendedMutex' took 0.0246329 us.
test 'Yield' took 0.137207 us.
test 'CondvarPingPong' took 3.54439 us.
```

Shenango's tbench tool [here](../scheduler/apps/bench/tbench.cc)
You need to `make` the bindings before `make`ing the bench folder. 
```
./tbench tbench.config
test 'SpawnJoin' took 0.150136 us.
test 'UncontendedMutex' took 0.0279107 us.
test 'Yield' took 0.045793 us.
test 'CondvarPingPong' took 0.0951025 us.
```

## LOC
Shenango Before: 8680 (runtime) + 3128 (iokernel)
Our changes: 1281 (mostly in runtime for page fault support)
Kona Before: 14584
Our changes: 2604
