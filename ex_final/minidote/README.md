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
