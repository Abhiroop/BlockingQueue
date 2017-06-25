# Blocking Queue
Message passing concurrency unlike shared memory concurrency offers a unique way of handling problems in concurrent and distributed systems. Cloud Haskell gives us access to message passing concurrency like Erlang. Here is a Blocking Queue implemented in Cloud Haskell.

We use the `gen-server` implementation of OTP that handles

1. requests to enqueue a task are handled immediately
2. callers which are blocked until the task completes (or fails)
3. an upper bound is placed on the number of concurrent running tasks

Once the upper bound is reached, tasks will be queued up for execution. Only when we drop below this limit will tasks be taken from the backlog and executed.
