# LCRDT

First, launch the shell. This will bind three CvRDTs under `:foo_crdt`, `:bar_crdt` and `:baz_crdt`.

## Pre-requisites
In order to run the counter functionalities below, the corresponding CvRDT must have enough leases to be able to increment or add to its configuration. The default configuration is that each node has 0 leases. To add leases to the `:foo_crdt` node, you can use the following command,
allocating 5 leases:
```
iex(0)> LCRDT.Participant.allocate(:foo_crdt, 5)
:ok
```

## Increment-Decrement Counter
```
CRDT="counter" iex -S mix
```

Now, you can use the counter functionalities:
```
iex(1)> LCRDT.Counter.sum(:foo_crdt)
0
iex(2)> LCRDT.Counter.inc(:foo_crdt)
:ok
iex(3)> LCRDT.Counter.inc(:foo_crdt)
:ok
iex(4)> LCRDT.Counter.dec(:foo_crdt)
:ok
iex(5)> LCRDT.Counter.sum(:foo_crdt)
1
iex(6)> LCRDT.Counter.inc(:bar_crdt)
:ok
iex(7)> LCRDT.Counter.sum(:foo_crdt)
1
iex(8)> LCRDT.Counter.sync(:bar_crdt)
:ok
iex(9)> LCRDT.Counter.sum(:foo_crdt)
2
```

The counters will broadcast their state to synchronize every 10 seconds.

## Or-Set
```
CRDT="orset" iex -S mix
```

Now, you can use the or-set functionalities:
```
iex(1)> LCRDT.OrSet.contains(:foo_crdt, :test_1, :apple)
false
iex(2)> LCRDT.OrSet.add(:foo_crdt, :test_1, :apple)
:ok
iex(3)> LCRDT.OrSet.contains(:foo_crdt, :test_1, :apple)
true
iex(4)> LCRDT.OrSet.remove(:foo_crdt, :test_1, :apple)  
:ok
iex(5)> LCRDT.OrSet.contains(:foo_crdt, :test_1, :apple)
false
iex(6)> LCRDT.OrSet.add(:foo_crdt, :test_1, :apple)
:ok
iex(7)> LCRDT.OrSet.add(:bar_crdt, :test_2, :banana)
:ok
iex(8)> LCRDT.OrSet.sync(:foo_crdt)
:ok
iex(9)> LCRDT.OrSet.contains(:bar_crdt, :test_1, :apple)
true
```

The sets will broadcast their state to synchronize every 10 seconds.
