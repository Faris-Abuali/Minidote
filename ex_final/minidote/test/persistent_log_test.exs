defmodule PersistentLogTest do
  use ExUnit.Case

  test "log test" do
    dc1 = TestSetup.start_node(:minidote_log_test)
    key = {"upvotes", :antidote_crdt_counter_pn, "minireddit"}

    # test/persistent_log_test.exs:4
    # ** (MatchError) no match of right hand side value: {:ok, [{{"upvotes", :antidote_crdt_counter_pn, "minireddit"}, -5}], %{}}
    {:ok, vc} =
      :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [
        [{key, :increment, 20}],
        :ignore
      ])

    # Force kill the minidote server process
    :rpc.call(dc1, :"Elixir.Minidote", :unsafe_force_crash, [])
    # NOTE: Does the log crash with the server? if not then maybe we should stop it.
    # Either seperate the log from the server or close the log with the server (when it crashes).
    {:ok, [{^key, 20}], _} =
      :rpc.call(dc1, :"Elixir.Minidote", :read_objects, [
        [key],
        :ignore
      ])

    TestSetup.stop_node(dc1)
    # # Spawn a process
    # # TODO: clear log before test
    # name = "persistent_unit_test"
    # File.rm(PersistentLog.get_log_path(name))
    # {:ok, log_proc} = PersistentLog.start_link(self(), name)

    # # log an update
    # vc = Vectorclock.new()
    # key = {"location", :antidote_crdt_counter_fat, "mensa"}

    # # TODO: fix this test, we broke how :persist works.
    # :ok =
    #   GenServer.call(
    #     log_proc,
    #     {:persist,
    #       vc,
    #      [
    #        {vc, key, :increment, 42},
    #        {vc, key, :decrement, 42}
    #      ]}
    #   )

    # # read the log
    # read_result = GenServer.call(log_proc, :get_entries)
    # # pattern match
    # {:ok, [[{^vc, key, :increment, 42}, {^vc, key, :decrement, 42}]]} = read_result
  end

  test "server should recover state after crashing" do
    key = {"recovered", :antidote_crdt_flag_ew, "minidote_test"}
    dc1 = TestSetup.start_node(:minidote_recover)

    {:ok, _} =
      :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [
        [{key, :enable, {}}],
        :ignore
      ])

    :rpc.call(dc1, :"Elixir.Minidote", :unsafe_force_crash, [])

    # Server should be down and restarted now.

    {:ok, [{^key, true}], _} =
      :rpc.call(dc1, :"Elixir.Minidote", :read_objects, [
        [key],
        :ignore
      ])

    TestSetup.stop_node(dc1)
  end

  test "freshly spawned replica should be able to be consistent with others" do
    # key = {"shopping_cart", :antidote_crdt_set_aw, "minizon"}
    key = {"shopping_cart", :antidote_crdt_set_aw, "minizon"}

    dc1 = TestSetup.start_node(:minidote1_minizon)
    # dc2 = TestSetup.start_node(:minidote2_minizon)

    # # Force crash dc2
    # force_crash =
    #   Task.async(fn ->
    #     :rpc.call(dc2, :"Elixir.Minidote", :unsafe_force_crash, [])
    #   end)

    {:ok, vc1} =
      :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [
        [{key, :add, "foo"}],
        :ignore
      ])

    dc2 = TestSetup.start_node(:minidote2_minizon)

    {:ok, vc1} =
      :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [
        [{key, :add, "faris"}],
        :ignore
      ])

    # Task.await(force_crash)

    {:ok, vc2} =
      :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [
        [{key, :add, "bar"}],
        :ignore
      ])

    # {:ok, [{^key, ["bar", "foo"]}], _} =
    #   :rpc.call(dc1, :"Elixir.Minidote", :read_objects, [
    #     [key],
    #     :ignore
    #   ])

    {:ok, [{^key, ["bar", "faris", "foo"]}], _} =
      :rpc.call(dc2, :"Elixir.Minidote", :read_objects, [
        [key],
        :ignore
      ])

    # {:ok, vc3} =
    #   :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [
    #     [{key, :add, "baz"}],
    #     :ignore
    #   ])

    # {:ok, [{^key, ["bar", "baz", "foo"]}], _} =
    #   :rpc.call(dc2, :"Elixir.Minidote", :read_objects, [
    #     [key],
    #     :ignore
    #   ])

    Enum.map([dc1, dc2], &TestSetup.stop_node(&1))
  end
end
