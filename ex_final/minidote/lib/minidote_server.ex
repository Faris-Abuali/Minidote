defmodule Minidote.Server do
  use GenServer
  require Logger

  @moduledoc """
  The API documentation for `Minidote.Server`.
  """

  # @typep state :: %{
  #          required(:vc) => Minidote.clock(),
  #          required(:key_value_store) => %{optional(Minidote.key()) => :antidote_crdt.value()},
  #          required(:pending_requests) =>
  #            MapSet.t({Process.dest(), Minidote.clock(), [{Minidote.key(), atom(), any()}]}),
  #          required(:broadcast_layer) => any()
  #          # should be CausalBroadcastWaiting/CausalBroadcastNonWaiting
  #        }

  @typep state() :: %{
           broadcast_layer: pid(),
           key_value_store: %{optional(Minidote.key()) => :antidote_crdt.crdt()},
           pending_requests:
             MapSet.t({Process.dest(), Minidote.clock(), [{Minidote.key(), atom(), any()}]}),
           vc: Vectorclock.t()
         }


  def start_link(server_name) do
    # if you need arguments for initialization, change here
    GenServer.start_link(Minidote.Server, [], name: server_name)
  end


  @spec init(any()) :: {:ok, state()}
  @impl true
  def init(_) do
    # FIXME the link layer should be initialized in the broadcast layer
    {:ok, link_layer} = LinkLayerDistr.start_link(:minidote)
    {:ok, causal_broadcast} = CausalBroadcastWaiting.start_link(link_layer, self())
    # the state of the GenServer is: tuple of link_layer and respond_to
    {:ok,
     %{
       :vc => Vectorclock.new(),
       :key_value_store => %{},
       :pending_requests => MapSet.new(),
       :broadcast_layer => causal_broadcast
     }}
  end

  @impl true
  def handle_call(:ping, _, state) do
    {:reply, {:pong, self()}, state}
  end

  @impl true
  def handle_call(request = {:read_objects, objects, caller_clock}, from, state) do
    current_clock = state.vc

    if Vectorclock.leq(caller_clock, current_clock) do
      results =
        for key = {_, crdt_type, _} <- objects do
          case state.key_value_store[key] do
            nil ->
              crdt = :antidote_crdt.new(crdt_type)
              {key, :antidote_crdt.value(crdt_type, crdt)}

            crdt ->
              {key, :antidote_crdt.value(crdt_type, crdt)}
          end
        end

      # NOTE: clock does not have to be advanced for read ops
      {:reply, {:ok, results, current_clock}, state}
    else
      updated_state = %{
        state
        | :pending_requests => MapSet.put(state.pending_requests, {from, request})
      }

      {:noreply, updated_state}
    end
  end

  @impl true
  def handle_call(request = {:update_objects, updates, caller_clock}, from, state) do
    current_clock = state.vc

    if caller_clock == :ignore || Vectorclock.leq(caller_clock, current_clock) do
      updated_clock = Vectorclock.increment(current_clock, self())

      key_effect_pairs =
        for {key = {_, crdt_typ, _}, op, arg} <- updates do
          {:ok, eff} =
            :antidote_crdt.downstream(crdt_typ, {op, arg}, state.key_value_store[key] || :ignore)

          {key, eff}
        end

      updated_state = apply_effects(key_effect_pairs, state)
      updated_state = %{updated_state | :vc => updated_clock}

      CausalBroadcastWaiting.broadcast(
        state.broadcast_layer,
        {:apply_effects, key_effect_pairs, updated_clock}
      )

      {:reply, {:ok, updated_clock}, updated_state}
    else
      # NOTE: caller has seen a later database version than we have available
      # we need to observe the previous updates before we can respond to the client.
      updated_state = %{
        state
        | :pending_requests => MapSet.put(state.pending_requests, {from, request})
      }

      {:noreply, updated_state}
    end
  end

  # def handle_call({:deliver, {:apply_effects, key_effect_pairs, sender_clock}}, _from, state) do
  @impl true
  def handle_cast({:deliver, {:apply_effects, key_effect_pairs, sender_clock}}, state) do
    if Vectorclock.lt(state.vc, sender_clock) do
      updated_clock = Vectorclock.merge(sender_clock, state.vc)
      updated_state = apply_effects(key_effect_pairs, state)
      updated_state = %{updated_state | :vc => updated_clock}
      {:noreply, updated_state}
    else
      {:noreply, state}
    end
  end

  # def handle_call(_msg, _from, state) do
  #   {:reply, :not_implemented, state}
  # end

  # def handle_info(msg, state) do
  #   Logger.warning("Unhandled info message: #{inspect(msg)}")
  #   {:noreply, state}
  # end

  @spec apply_effects([{Minidote.key(), :antidote_crdt.effect()}], state()) :: state()
  defp apply_effects(key_effect_pairs, state) do
key_updated_crdt_pairs =
      for {key = {_, crdt_type, _}, effect} <- key_effect_pairs do
        {:ok, updated_crdt} =
          :antidote_crdt.update(
            crdt_type,
            effect,
            state.key_value_store[key] || :antidote_crdt.new(crdt_type)
          )

        {key, updated_crdt}
      end

    updated_kv_store =
      List.foldl(key_updated_crdt_pairs, state.key_value_store, fn {key, updated_crdt},
                                                                   kv_store ->
        Map.put(kv_store, key, updated_crdt)
      end)

    %{state | :key_value_store => updated_kv_store}
  end
end
