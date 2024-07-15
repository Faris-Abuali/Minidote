defmodule MinidoteTest do
  use ExUnit.Case
  doctest Minidote

  test "setup nodes" do
    # start minidote1, minidote2
    [dc1, dc2] = [TestSetup.start_node(:minidote1), TestSetup.start_node(:minidote2)]
    # start minidote3
    dc3 = TestSetup.start_node(:minidote3)
    # crash a node
    TestSetup.stop_node(dc2)
    # restart a node
    dc2 = TestSetup.start_node(:minidote2)

    # tear down all nodes
    [TestSetup.stop_node(dc1), TestSetup.stop_node(dc2), TestSetup.stop_node(dc3)]
  end

  test "setup nodes in other test" do
    # note: using the same name affects other tests if some state is persisted
    [dc1, dc2] = [TestSetup.start_node(:minidote1), TestSetup.start_node(:minidote2)]
    dc3 = TestSetup.start_node(:minidote3)

    # tear down all nodes
    [TestSetup.stop_node(dc1), TestSetup.stop_node(dc2), TestSetup.stop_node(dc3)]
  end

  test "simple counter replication" do
    (nodes = [dc1, dc2]) = [
      TestSetup.start_node(:t1_minidote1),
      TestSetup.start_node(:t1_minidote2)
    ]

    # debug messages:
    TestSetup.mock_link_layer(nodes, %{:debug => true})

    # increment counter by 42
    # When using Erlang rpc calls, the module name needs to be specified. Elixir modules are converted into Erlang modules via a $ModuleName -> :"Elixir.ModuleName" transformation
    # TODO FOR TEMPLATE: check if Elixir has native rpc calls
    {:ok, vc} =
      :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [
        [{{"key", :antidote_crdt_counter_pn, "simple counter replication"}, :increment, 42}],
        :ignore
      ])

    # reading on the same replica returns 42
    {:ok, [{{"key", :antidote_crdt_counter_pn, "simple counter replication"}, 42}], _vc2} =
      :rpc.call(dc1, :"Elixir.Minidote", :read_objects, [
        [{"key", :antidote_crdt_counter_pn, "simple counter replication"}],
        vc
      ])

    # reading on the other replica returns 42
    {:ok, [{{"key", :antidote_crdt_counter_pn, "simple counter replication"}, 42}], _vc2} =
      :rpc.call(dc2, :"Elixir.Minidote", :read_objects, [
        [{"key", :antidote_crdt_counter_pn, "simple counter replication"}],
        vc
      ])

    # tear down all nodes
    [TestSetup.stop_node(dc1), TestSetup.stop_node(dc2)]
  end

  test "sample replication test" do
    key = {"location", :antidote_crdt_set_go, "mensa"}

    (nodes = [dc1, dc2, dc3]) = [
      TestSetup.start_node(:minidote1),
      TestSetup.start_node(:minidote2),
      TestSetup.start_node(:minidote3)
    ]

    TestSetup.mock_link_layer(nodes, %{:debug => true})

    # Each replica makes some update
    {:ok, vc1} = :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [[{key, :add, "from :minidote1"}], :ignore])
    {:ok, vc2} = :rpc.call(dc2, :"Elixir.Minidote", :update_objects, [[{key, :add, "from :minidote2"}], :ignore])
    {:ok, vc3} = :rpc.call(dc3, :"Elixir.Minidote", :update_objects, [[{key, :add, "from :minidote3"}], :ignore])

    # We want to observe all updates made
    vc4 = Vectorclock.merge(Vectorclock.merge(vc1, vc2), vc3)

    expected_result = ["from :minidote1", "from :minidote2", "from :minidote3"]

    {:ok, [{^key, ^expected_result}], _} = :rpc.call(dc1, :"Elixir.Minidote", :read_objects, [[key], vc4])
    {:ok, [{^key, ^expected_result}], _} = :rpc.call(dc2, :"Elixir.Minidote", :read_objects, [[key], vc4])
    {:ok, [{^key, ^expected_result}], _} = :rpc.call(dc3, :"Elixir.Minidote", :read_objects, [[key], vc4])


    Enum.map(nodes, &TestSetup.stop_node(&1))
  end
end
