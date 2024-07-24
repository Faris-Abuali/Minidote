defmodule LinkLayerDistr do
  use GenServer
  require Logger
  # Callbacks

  def start_link(group_name) do
    GenServer.start_link(__MODULE__, group_name)
  end

  @impl true
  def init(group_name) do
    # initially, try to connect with other erlang nodes
    # spawn_link(&find_other_nodes/0)
    :pg.start_link()
    :ok = :pg.join(group_name, self())

    # subscribe to the group
    {_ref, current_members} = :pg.monitor(group_name)

    named_members =
      Enum.map(current_members, fn member ->
        if member !== self() do
          {:ok, name} = GenServer.call(member, :this_node_name)
          {member, name}
        else
          {member, node()}
        end
      end)

    Logger.notice("#{inspect(node())}: #{inspect(current_members)}")
    # for member <- :pg.get_members(group_name), member !== self() do
    # for member <- current_members, member !== self() do
    #   GenServer.cast(member, :update_nodes)
    # end

    Logger.notice("Connected to node #{inspect(node())}")

    {:ok, %{:group_name => group_name, :respond_to => :none, :nodes => named_members}}
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
  def handle_call(:this_node_name, _from, state) do
    {:reply, {:ok, node()}, state}
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

  # @impl true
  # def handle_cast(:update_nodes, state) do
  #   members = :pg.get_members(state[:group_name])

  #   nodes =
  #     for member <- members, member !== self() do
  #       Logger.notice("Asking #{inspect(member)} for its name.")
  #       {:ok, name} = GenServer.call(member, :this_node_name)
  #       {member, name}
  #     end

  #   updated_state = %{state | :nodes => nodes}
  #   Logger.notice("Connected #{node()} to other nodes: #{inspect(nodes)}")
  #   {:noreply, updated_state}
  # end

  @impl true
  def handle_info({_ref, :join, _group, new_pids}, state) do
    Logger.notice("#{inspect(node())}: Got notification that #{inspect(new_pids)} just joined.")

    updated_nodes =
      Enum.map(new_pids, fn member ->
        Logger.notice("Asking #{inspect(member)} for its name.")
        {:ok, name} = GenServer.call(member, :this_node_name)
        {member, name}
      end)

    updated_state = %{state | :nodes => updated_nodes ++ state.nodes}
    {:noreply, updated_state}
  end

  @impl true
  def handle_info({_ref, :leave, _group, stale_pids}, state) do
    Logger.notice("#{inspect(node())}: Got notification that #{inspect(stale_pids)} is/are down.")

    updated_state = %{
      state
      | :nodes =>
          Enum.filter(
            state.nodes,
            fn {pid, _} -> not Enum.member?(stale_pids, pid) end
          )
    }

    {:noreply, updated_state}
  end

  def find_other_nodes() do
    nodes = os_or_app_env()
    Logger.notice("Connecting #{node()} to other nodes: #{inspect(nodes)}")
    try_connect(nodes, 500)
  end

  defp try_connect(nodes, t) do
    {ping, pong} = :lists.partition(fn n -> :pong == :net_adm.ping(n) end, nodes)

    for n <- ping do
      Logger.notice("Connected to node #{n}")
    end

    case t > 1000 do
      true ->
        for n <- pong do
          Logger.notice("Failed to connect #{node()} to node #{n}")
        end

      _ ->
        :ok
    end

    case pong do
      [] ->
        Logger.notice("Connected to all nodes")

      _ ->
        :timer.sleep(t)
        try_connect(pong, min(2 * t, 60000))
    end
  end

  def os_or_app_env() do
    nodes = :string.tokens(:os.getenv(~c"MINIDOTE_NODES", ~c""), ~c",")

    case nodes do
      ~c"" ->
        :application.get_env(:microdote, :microdote_nodes, [])

      _ ->
        for n <- nodes do
          :erlang.list_to_atom(n)
        end
    end
  end
end
