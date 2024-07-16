defmodule UniformReliableBroadcast do
  use GenServer

  ##############
  # PUBLIC API
  ##############
  def start_link(link_layer, respond_to) do
    GenServer.start_link(__MODULE__, {link_layer, respond_to})
  end


  def broadcast(pid, message) do
    # this exact tuple will be process by a `handle_call` function header
    GenServer.call(pid, {:urb_broadcast, message})
  end

  ##############
  # TO IMPLEMENT
  ##############

  # given a link layer and a respond to process
  # add the process to the link layer to make it discoverable
  def init({link_layer, respond_to}) do
    {:ok, beb} = BestEffortBroadcast.start_link(link_layer, self())
    {:ok, this_node} = LinkLayer.this_node(link_layer)
    {:ok, %{
      :beb => beb,
      :respond_to => respond_to,
      :self => this_node,
      :ack => %{},
      :pending => MapSet.new(),
      :delivered => MapSet.new(),
      :msg_counter => 0}
    }
  end

  def handle_call({:urb_broadcast, msg}, _from, state) do
    # generate unique message id, add to pending set
    uid = {state[:self], state[:msg_counter]}
    new_state = %{state |
      :pending => MapSet.put(state[:pending], {state[:self], uid, msg}), # TYPO in video slides!
      :msg_counter => state[:msg_counter] + 1
    }
    BestEffortBroadcast.broadcast(state[:beb], {state[:self], uid, msg})
    {:reply, :ok, new_state}
  end

  def handle_info({:deliver, {pj, uid, msg}}, state) do
    # pk
    pk = state[:self]

    # ack[uid] <- ack[uid] U k
    ack = state[:ack]
    ackuid = Map.get(ack, uid, MapSet.new())
    newackuid = MapSet.put(ackuid, pk)
    newack = Map.put(state[:ack], uid, newackuid)

    state = %{state | :ack => newack}

    state = case MapSet.member?(state[:pending], {pj, uid, msg}) do
      false ->
        state = %{state | :pending => MapSet.put(state[:pending], {pj, uid, msg})}
        # trigger broadcast
        BestEffortBroadcast.broadcast(state[:beb], {pj, uid, msg})
        state
      true -> state
    end

    state = deliver_pending(state)
    {:noreply, state}
  end

  defp deliver_pending(state) do
    # TODO global n
    n = 3
    pending = state[:pending]
    can_deliver =
      MapSet.filter(
        pending,
        fn({_pj, mid, _m}) ->
          map_size(Map.get(state[:ack], mid, MapSet.new())) > n/2
          and
          not MapSet.member?(state[:delivered], mid)
        end
    )

    case MapSet.size(can_deliver) do
      0 -> state
      _ ->
        delivered = List.foldl(MapSet.to_list(can_deliver), state[:delivered],
         fn({_pj, mid, m}, ddelivered) ->
          send(state[:respond_to], {:deliver, m})
          MapSet.union(ddelivered, MapSet.new([mid]))
        end)

        deliver_pending(%{state | :delivered => delivered})
    end
  end

end
