defmodule LinkLayerDistr do
  require ExUnit.Assertions
  use GenServer
  require Logger
  # Callbacks

  @cookie :Cookie

  @leader_name "MINIDOTE_LEADER"
               |> System.get_env("minidote1@127.0.0.1")
               |> String.to_atom()

  def start_link(group_name) do
    GenServer.start_link(__MODULE__, group_name)
  end

  def try_connect_to_leader(t \\ 2500, was_disconnected \\ true) do
    case :net_adm.ping(@leader_name) do
      :pong ->
        :ok
        if was_disconnected do
          Logger.notice("#{inspect(node())} reestablished connection to leader.")
        end
        Process.sleep(t)
        try_connect_to_leader(2500, false)

      :pang ->
        duration = min(2 * t, 60000)

        Logger.notice(
          "#{inspect(node())} Failed to connect to leader, waiting #{duration}ms before reconnecting."
        )

        Process.sleep(t)
        try_connect_to_leader(min(2 * t, 60000))
    end
  end

  @impl true
  def init(group_name) do
    server_name = node()
    :erlang.set_cookie(@cookie)
    :global.register_name(server_name, self())

    {:ok, _} = :pg.start_link()
    :ok = :pg.join(group_name, self())
    {_ref, _} = :pg.monitor(group_name)

    _pid = spawn_link(fn -> try_connect_to_leader(500, false) end)
    :global.sync()

    members = :pg.get_members(group_name)
    registered_names = :global.registered_names()

    # Assertions.assert(Enum.count(members) === Enum.count(registered_names))

    for member <- registered_names, member !== server_name, do: Node.ping(member)

    Logger.notice(
      "Started #{inspect(server_name)}. Connected to: #{inspect(registered_names)}, #{inspect(members)}"
    )

    {:ok, %{:group_name => group_name, :respond_to => nil}}
  end

  @impl true
  def handle_info({_ref, :join, _group, new_pids}, state) do
    Logger.notice("#{inspect(node())}: Got notification that #{inspect(new_pids)} just joined.")
    members = :pg.get_members(state[:group_name])

    new_pids
    |> Enum.all?(&Enum.member?(members, &1))

    {:noreply, state}
  end

  @impl true
  def handle_info({_ref, :leave, _group, stale_pids}, state) do
    Logger.notice("#{inspect(node())}: #{inspect(stale_pids)} left the process group.")

    members = :pg.get_members(state[:group_name])

    stale_pids
    |> Enum.all?(fn i -> not Enum.member?(members, i) end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:send, data, node}, _from, state) do
    GenServer.cast(node, {:remote, data})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:register, r}, _from, state) do
    {:reply, :ok, %{state | :respond_to => r}}
  end

  @impl true
  def handle_call(:all_nodes, _from, state) do
    members = :pg.get_members(state[:group_name])
    {:reply, {:ok, members}, state}
  end

  @impl true
  def handle_call(:other_nodes, _from, state) do
    members = :pg.get_members(state[:group_name])
    other_members = for n <- members, n !== self(), do: n
    {:reply, {:ok, other_members}, state}
  end

  @impl true
  def handle_call(:this_node, _from, state) do
    {:reply, {:ok, self()}, state}
  end

  @impl true
  def handle_cast({:remote, msg}, state) do
    send(state[:respond_to], msg)
    {:noreply, state}
  end
end
