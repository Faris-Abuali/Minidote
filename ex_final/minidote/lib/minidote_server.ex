defmodule Minidote.Server do
  use GenServer
  require Logger
  @moduledoc """
  The API documentation for `Minidote.Server`.
  """

  def start_link(server_name) do
    # if you need arguments for initialization, change here
    GenServer.start_link(Minidote.Server, [], name: server_name)
  end

  def init(_) do
    # FIXME the link layer should be initialized in the broadcast layer
    {:ok, _link_layer} = LinkLayerDistr.start_link(:minidote)
    # the state of the GenServer is: tuple of link_layer and respond_to
    {:ok, %{}}
  end

  def handle_call(_msg, _from, state) do
    {:reply, :not_implemented, state}
  end

  def handle_info(msg, state) do
    Logger.warning("Unhandled info message: #{inspect msg}")
    {:noreply, state}
  end
end
