defmodule CausalBroadcastNonWaiting do
  use GenServer

  ##############
  # PUBLIC API
  ##############
  def start_link(link_layer, respond_to) do
    GenServer.start_link(__MODULE__, {link_layer, respond_to})
  end


  def broadcast(pid, message) do
    # this exact tuple will be process by a `handle_call` function header
    GenServer.call(pid, {:rco_broadcast, message})
  end

  ##############
  # TO IMPLEMENT
  ##############

  # given a link layer and a respond to process
  # add the process to the link layer to make it discoverable
  def init({link_layer, respond_to}) do
    {:ok, rb} = ReliableBroadcast.start_link(link_layer, self())
    {:ok, this_node} = LinkLayer.this_node(link_layer)
    {:ok, %{
      :rb => rb,
      :respond_to => respond_to,
      :self => this_node,
      :delivered => MapSet.new(),
      :msg_counter => 0,
      :past => []
    }}
  end

  def handle_call({:rco_broadcast, msg}, _from, state) do
    mid = {state[:self], state[:msg_counter]}
    past = state[:past] ++ [{state[:self], mid, msg}]
    state = %{state | :past => past, :msg_counter => state[:msg_counter] + 1}

    #broadcast
    ReliableBroadcast.broadcast(state[:rb], {mid, past, msg})

    {:reply, :ok, state}
  end

  def handle_info({:deliver, {mid, past_m, _m}}, state) do
    delivered = state[:delivered]
    case MapSet.member?(delivered, mid) do
      true -> {:noreply, state}
      false ->
        {delivered, past} = deliver_past(past_m, delivered, state[:past], state[:respond_to])


        {:noreply, %{state | :delivered => delivered, :past => past}}
    end


    {:noreply, state}
  end

  def deliver_past([], delivered, past, _respond_to) do
    {delivered, past}
  end

  def deliver_past([{pj, nid, n} | msgs], delivered, past, respond_to) do
    case MapSet.member?(delivered, nid) do
      true ->
        deliver_past(msgs, delivered, past, respond_to)
      false ->
        # new message!

        # trigger rco-deliver(pj, n)
        send(respond_to, {:deliver, n})

        # add history
        delivered = MapSet.put(delivered, nid)
        past = past ++ [{pj, nid, n}]

        # continue
        deliver_past(msgs, delivered, past, respond_to)
    end

  end

end
