defmodule BestEffortBroadcast do
  use GenServer
  # to start an instance of a broadcast,
  # a link layer process and a respond to process have to be supplied to the broadcast process
  #
  # message    repond_to          ===   application layer, expects a {:deliver, msg} tuple as messages from the broadcasts
  #    |       ^
  #    |       |
  #     --> broadcast module      ===   broadcasting/routing layer
  #            ^
  #            |
  #            v
  #          link layer           ===   network layer
  #
  # while the link layer can be transparent
  # (distributed elixir/erlang provides this for you)
  # we use a separate link layer to implement discoverability of nodes
  # and for testing purposes
  #
  # To use the broadcasting layer
  # * start the link layer process with a group name, save that pid
  # * implement some process that processes messages that are broadcast; can be a simple echo process

  ##############
  # PUBLIC API
  ##############
  def start_link(link_layer, respond_to) do
    GenServer.start_link(__MODULE__, {link_layer, respond_to})
  end


  def broadcast(pid, message) do
    # this exact tuple will be process by a `handle_call` function header
    GenServer.call(pid, {:broadcast, message})
  end

  ##############
  # INTERNAL API
  ##############

  # given a link layer and a respond to process
  # add the process to the link layer to make it discoverable
  def init({link_layer, respond_to}) do
    LinkLayer.register(link_layer, self())
    # the state of the GenServer is: tuple of link_layer and respond_to
    {:ok, {link_layer, respond_to}}
  end

  def handle_call({:broadcast, msg}, _from, state = {link_layer, _}) do
    {:ok, all_nodes} = LinkLayer.all_nodes(link_layer)
    for nn <- all_nodes do
      # NODE 1!
      LinkLayer.send(link_layer, {:best_effort_broadcast_msg, msg}, nn)
    end
    {:reply, :ok, state}
  end

  # NODE 2!
  def handle_info({:best_effort_broadcast_msg, msg}, state = {_, respond_to}) do
    send(respond_to, {:deliver, msg})
    {:noreply, state}
  end
end
