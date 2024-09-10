defmodule ReliableBroadcast do
  use GenServer

  ##############
  # PUBLIC API
  ##############
  def start_link(link_layer, respond_to) do
    GenServer.start_link(__MODULE__, {link_layer, respond_to})
  end


  def broadcast(pid, message) do
    # this exact tuple will be process by a `handle_call` function header
    GenServer.call(pid, {:rb_broadcast, message})
  end

  ##############
  # TO IMPLEMENT
  ##############

  # given a link layer and a respond to process
  # add the process to the link layer to make it discoverable
  def init({link_layer, respond_to}) do
    # reliable broadcast builds upon the best effort broadcast implementation
    {:ok, beb} = BestEffortBroadcast.start_link(link_layer, self())
    {:ok, this_node} = LinkLayer.this_node(link_layer)
    # the state of the reliable broadcast is now a key-value map
    # here, the keys are atoms
    {:ok, %{ :beb => beb, :respond_to => respond_to, :self => this_node, :delivered => MapSet.new(), :msg_counter => 0}}
  end

  def handle_call({:rb_broadcast, msg}, _from, state) do
    # deliver self
    # state key can be looked up via the MAP[KEY] construct
    send(state[:respond_to], {:deliver, msg})
    # generate unique message id
    uid = {state[:self], state[:msg_counter]}
    new_state = %{state | :delivered => MapSet.put(state[:delivered], uid), :msg_counter => state[:msg_counter] + 1}
    BestEffortBroadcast.broadcast(state[:beb], {uid, msg})
    {:reply, :ok, new_state}
  end

  # deliver from beb!
  def handle_info({:deliver, {uid, msg}}, state) do
    case MapSet.member?(state[:delivered], uid) do
      false ->
        new_state = %{state | :delivered => MapSet.put(state[:delivered], uid)}
        # deliver self <- not allowed to deliver instantly for uniform reliable broadcast
        send(state[:respond_to], {:deliver, msg})
        # reliable broadcast part
        BestEffortBroadcast.broadcast(state[:beb], {uid, msg})
        {:noreply, new_state}
      true -> {:noreply, state}
    end
  end

end
