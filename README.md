# LCRDT

First, launch the shell. This will bind three counters under `:foo`, `:bar` and `:baz`.
```
iex -S mix
```

Now, you can use the counter functionalities:
```
iex(1)> LCRDT.Counter.sum(:foo)
0
iex(2)> LCRDT.Counter.inc(:foo)
:ok
iex(3)> LCRDT.Counter.sum(:foo)
1
iex(4)> LCRDT.Counter.inc(:bar)
:ok
iex(5)> LCRDT.Counter.sum(:foo)
1
iex(6)> LCRDT.Counter.sync(:bar)
:ok
iex(7)> LCRDT.Counter.sum(:foo)
2
```


