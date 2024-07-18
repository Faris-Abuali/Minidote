# Minidote

## Installation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/minidote>.

## TODOs 
- [ ] Serve pending requests after incrementing vector clocks
- [ ]

## Notes

ElixirLS, Dialyzer and Gradient might complain that [:antidote_crdt.typ](./lib/minidote.ex#8) is an Unknown type. This is because it's not exported by [antidote_crdt.erl](minidote/deps/antidote_crdt/src/antidote_crdt.erl).
Apply the following patch to fix it.

```sh
$ patch deps/antidote_crdt/src/antidote_crdt.erl < patches/export_typ.patch
patching file 'deps/antidote_crdt/src/antidote_crdt.erl'
$ mix deps.compile; mix dialyzer.clean; mix dialyzer 
```

```
key = {"location", :antidote_crdt_set_go, "mensa"}

Minidote.update_objects([{key, :add, 83}], :ignore)
Minidote.update_objects([{key, :add, "From 2"}], :ignore)

Minidote.read_objects([key], :ignore)
```

## Questions for Albert
- When should we prune the log?
    - Note: A quick and efficient way to compare states, is to compare the vector clocks of replicas instead of sending the entire state.

- Can the logs diverge or should they always be strongly consistent.
    - i.e. Which is sufficient, can we just ask for the logs of all replicas, and concatenate/combine? the updates of each together, or do we need Raft

- We wanted to implement replicated state machine in the logs themselves. We get a strong consistency but sacrifysing availability.
    - Which is


# TODO: ask this once we've formulated it better.
- Is using acknowledgements after broadcasting effects a good idea?
    - Keep list of updates_to_be_acknowledged :: Map[Update, Set[replica]]
    - for each update, while updates_to_be_acknowledged[update] is not empty:
        - attempt to broadcast to replica, remove replica from set if received an ack back.
    - but what if the node in charge of tracking acknowledgements crashes?
    - do other nodes need to handle acknowledgements for this update as well?
