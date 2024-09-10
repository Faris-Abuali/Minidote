# Minidote

## Core

Most of the core implementation is in the [Minidote.Server](lib/minidote_server.ex) module.
Each server instance maintains a state consisting of its vector clock, key-value store, a set of pending requests, and the PID of its persistent log (See section on robustness).

After initialization, the server can respond to the following types of messages.

- `:unsafe_force_crash`: Forcefully stops the server. A process with the same node name will be spawned by the supervisor. This is meant to be used for debugging / in tests.

- `:unsafe_clear_log`: Delete the log file on disk. This is meant to be used for debugging / in tests.

- `:ping`: Responds with `pong` and the server's PID. This is meant to be used for debugging / in tests.

- `{:read_objects, objects, caller_clock}`: Performs a read on the replica's key-value store, with the guarantee that values returned are not older than `caller_clock`, otherwise we add the request to the pending set.

- `{:update_objects, updates, caller_clock}`: Performs an update on the replica's key-value store, followed by a broadcast of the `apply_effects` message to other replicas and we increment its entry in the vector clock. Similar to `read_objects`, if the clock provided in the request is greater than the replica's current clock, we add the request to the pending set.

Each time the vector clock is incremented (or merged with another vector clock), we traverse through the pending set and check for requests it can serve (following its removal from the pending set).

- `{:apply_effects, sender, key_effect_pairs, sender_clock}`: When received by a replica, it updates its local key-value store, if it has not already (determined by comparing vector clocks). If the receiving replica is `> 1` updates behind, it sends a `send_missing` request to the sender.

- `{:send_missing, recipient, from_vc, upto_vc}`: The replica reads the operations with vector clock timestamps between `from_vc` and `upto_vc` and transmits them to the issuing replica in an `:apply_effects` message.

## Extensions

### Robustness

We implement robustness by introducing a persistent log consisting of a list of {key, operation effects} pairs on disk (using Erlang's `disk_log` library). Each instance of the minidote server spawns a process responsible for handling logging operations. Logs are saved on disk as `<node name>.LOG` in the logs directory.

When a client sends an update request to the replica, it persists the effect of the operation on the disk and then updates the in-memory key-value store.

When a node first starts up or recovers from a crash and is restarted by the supervisor, it reads from the persistent log and applies the operations to its in-memory key-value store during its initialization phase (in other words, before it can begin answering requests).

Therefore, our implementation implements the `Durability` property described in the project description.

If a node is down, other replicas make updates in the meantime, it can become consistent (eventually) with other replicas when it receives another update. An `:apply_effects` message is issued when a replica has performed an update to the other replica, the message contains the list of key effect pairs, as well as the sender's vector clock. The node behind compares its vector clock to the sender's and casts a request to the sender for it to retransmit effects within an interval `[from_vc, upto_vc]`.

### Dynamic Membership

We modified the [link_layer_distr.ex](lib/link_layer/link_layer_distr.ex). When the link layer is initialized, it attempts to ping a "leader" node specified in an environmental variable `MINIDOTE_LEADER` (which is `minidote1@127.0.0.1` by default) to establish a connection to other replicas in the process group. A monitor is attached to the process group so that each link layer instance gets notified whenever a process joins or leaves.

There is also a background process that frequently pings the leader to keep the connection live. We assume that the leader is restarted, or another replica joins under the same name as the leader. The nodes in the same process group remain connected while the leader is down.

Since each replica is responsible for keeping track of its state, a new replica can join with the same node name (including the leader) as one that has already left without an issue and will eventually be consistent with the other replicas using the same mechanism described in the section on Robustness.

## Additional Notes

Execute tests using `rm logs/*.LOG; mix test`.

ElixirLS, Dialyzer, and Gradient might complain that [:antidote_crdt.typ](./lib/minidote.ex#8) is an Unknown type. This is because it's not exported by [antidote_crdt.erl](minidote/deps/antidote_crdt/src/antidote_crdt.erl).
Apply the following patch to fix it.

```sh
$ patch deps/antidote_crdt/src/antidote_crdt.erl < patches/export_typ.patch
patching file 'deps/antidote_crdt/src/antidote_crdt.erl'
$ mix deps.compile; mix dialyzer.clean; mix dialyzer 
```

## Team Members

- Mahmoud Hamido (Mtr. No. 428723)
- Faris Abuali (Mtr. No. 429085)
