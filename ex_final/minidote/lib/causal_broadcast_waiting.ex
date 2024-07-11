defmodule CausalBroadcastWaiting do
  use GenServer

  # uses vectorclocks to wait for unreceived messages

  ##############
  # PUBLIC API
  ##############
  def start_link(link_layer, respond_to) do
    GenServer.start_link(__MODULE__, {link_layer, respond_to})
  end

  def broadcast(pid, message) do
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

    {:ok,
     %{
       :rb => rb,
       :respond_to => respond_to,
       :self => this_node,
       :vc => Vectorclock.new(),
       :pending => :sets.new()
     }}
  end

  def handle_call({:rco_broadcast, msg}, _from, state) do
    # deliver self
    GenServer.cast(state[:respond_to], {:deliver, msg})

    # broadcast
    ReliableBroadcast.broadcast(state[:rb], {state[:self], state[:vc], msg})

    {:reply, :ok, %{state | :vc => Vectorclock.increment(state[:vc], state[:self])}}
  end

  def handle_info({:deliver, {p, vc, m}}, state) do
    case p == state[:self] do
      true ->
        {:noreply, state}

      false ->
        pending = :sets.add_element({p, vc, m}, state[:pending])
        {new_pending, new_vc} = deliver_pending(state, pending, state[:vc])
        {:noreply, %{state | :pending => new_pending, :vc => new_vc}}
    end

    {:noreply, state}
  end

  def deliver_pending(state, pending, vc) do
    can_deliver =
      :sets.filter(
        fn {_, vcq, _} -> Vectorclock.leq(vcq, vc) end,
        pending
      )

    case :sets.size(can_deliver) do
      0 ->
        {pending, vc}

      _ ->
        new_pending = :sets.subtract(pending, can_deliver)

        new_vc =
          :sets.fold(
            fn {q, _, m}, vca ->
              GenServer.cast(state[:respond_to], {:deliver, m})
              Vectorclock.increment(vca, q)
            end,
            vc,
            can_deliver
          )

        deliver_pending(state, new_pending, new_vc)
    end
  end
end
