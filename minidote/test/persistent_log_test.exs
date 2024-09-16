defmodule PersistentLogTest do
  use ExUnit.Case

  test "log test" do
    dc1 = TestSetup.start_node(:minidote_log_test)
    key = {"upvotes", :antidote_crdt_counter_pn, "minireddit"}

    {:ok, vc} =
      :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [
        [{key, :increment, 20}],
        :ignore
      ])

    :rpc.call(dc1, :"Elixir.Minidote", :unsafe_force_crash, [])
    {:ok, [{^key, 20}], _} =
      :rpc.call(dc1, :"Elixir.Minidote", :read_objects, [
        [key],
        :ignore
      ])

    TestSetup.stop_node(dc1)
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
    key = {"shopping_cart", :antidote_crdt_set_aw, "minizon"}

    dc1 = TestSetup.start_node(:minidote1)
    dc2 = TestSetup.start_node(:minidote2)

    {:ok, vc1} =
      :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [
        [{key, :add, "foo"}],
        :ignore
      ])

    {:ok, vc1} =
      :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [
        [{key, :add, "faris"}],
        :ignore
      ])

    {:ok, vc2} =
      :rpc.call(dc1, :"Elixir.Minidote", :update_objects, [
        [{key, :add, "bar"}],
        :ignore
      ])

    {:ok, [{^key, ["bar", "faris", "foo"]}], _} =
      :rpc.call(dc2, :"Elixir.Minidote", :read_objects, [
        [key],
        :ignore
      ])

    Enum.map([dc1, dc2], &TestSetup.stop_node(&1))
  end
end
