# LCRDT

First, launch the shell. This will bind three CvRDTs under `:foo_crdt`, `:bar_crdt` and `:baz_crdt`.

## Testing

It is important to run the test without running the application.
```
mix test --no-start
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
iex(1)> LCRDT.OrSet.contains(:foo_crdt, :test_1)
false
iex(2)> LCRDT.OrSet.add(:foo_crdt, :test_1)
:ok
iex(3)> LCRDT.OrSet.contains(:foo_crdt, :test_1)
true
iex(4)> LCRDT.OrSet.remove(:foo_crdt, :test_1)  
:ok
iex(5)> LCRDT.OrSet.contains(:foo_crdt, :test_1)
false
iex(6)> LCRDT.OrSet.add(:foo_crdt, :test_1)
:ok
iex(7)> LCRDT.OrSet.add(:bar_crdt, :test_2)
:ok
iex(8)> LCRDT.OrSet.sync(:foo_crdt)
:ok
iex(9)> LCRDT.OrSet.contains(:bar_crdt, :test_1)
true
```

The sets will broadcast their state to synchronize every 10 seconds.
