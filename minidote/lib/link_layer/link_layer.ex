defmodule LinkLayer do
  # API
  def send(ll, data, node) do GenServer.call(ll, {:send, data, node}) end
  def register(ll, receiver) do GenServer.call(ll, {:register, receiver}) end
  def all_nodes(ll) do GenServer.call(ll, :all_nodes) end
  def other_nodes(ll) do GenServer.call(ll, :other_nodes) end
  def this_node(ll) do GenServer.call(ll, :this_node) end
end
