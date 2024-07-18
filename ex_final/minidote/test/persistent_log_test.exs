defmodule PersistentLogTest do
  use ExUnit.Case

  test "log test" do
    # Spawn a process
    # TODO: clear log before test
    name = "persistent_unit_test"
    File.rm(PersistentLog.get_log_path(name))
    {:ok, log_proc} = PersistentLog.start_link(self(), name)

    # log an update
    vc = Vectorclock.new()
    key = {"location", :antidote_crdt_counter_fat, "mensa"}

    :ok =
      GenServer.call(
        log_proc,
        {:persist,
         [
           {vc, key, :increment, 42},
           {vc, key, :decrement, 42}
         ]}
      )

    # read the log
    read_result = GenServer.call(log_proc, :get_entries)
    # pattern match
    {:ok, [[{^vc, key, :increment, 42}, {^vc, key, :decrement, 42}]]} = read_result
  end
end
