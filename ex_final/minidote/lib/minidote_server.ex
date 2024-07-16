defmodule Minidote.Server do
  use GenServer
  require Logger

  @moduledoc """
  The API documentation for `Minidote.Server`.
  """

  @type read_request() :: {:read_objects, [Minidote.key()], Vectorclock.t()}

  @type update_request() ::
          {:update_objects, [{Minidote.key(), atom(), term()}], Vectorclock.t()}

  @type read_response() ::
          {:ok, [{Minidote.key(), term()}], Vectorclock.t()}
          | {:error, :invalid_key, Minidote.key()}

  @type update_response() ::
          {:ok, Vectorclock.t()} | {:error, any()}

  @type effect_request() ::
          {:apply_effects, [{Minidote.key(), :antidote_crdt.effect()}], Vectorclock.t()}

  @opaque state() :: %{
            required(:broadcast_layer) => any(),
            required(:key_value_store) => %{optional(Minidote.key()) => :antidote_crdt.crdt()},
            required(:pending_requests) =>
              MapSet.t({Process.dest(), Minidote.clock(), [{Minidote.key(), atom(), any()}]}),
            required(:vc) => Vectorclock.t()
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

  @spec can_serve_request(:ignore | Minidote.clock(), Minidote.clock()) :: boolean()
  defp can_serve_request(:ignore, _), do: true
  defp can_serve_request(vc1, vc2), do: Vectorclock.leq(vc1, vc2)

  @impl true
  @spec handle_call(:ping, GenServer.from(), state()) :: {:reply, {:pong, pid()}, state()}
  def handle_call(:ping, _, state) do
    {:reply, {:pong, self()}, state}
  end

  @impl true
  @spec handle_call(read_request(), GenServer.from(), Minidote.clock()) ::
          {:reply, read_response(), state()} | {:noreply, state()}
  def handle_call(request = {:read_objects, objects, caller_clock}, from, state) do
    current_clock = state.vc

    if can_serve_request(caller_clock, current_clock) do
      results =
        Enum.reduce_while(objects, {:ok, []}, fn
          key = {_, crdt_type, _}, {:ok, acc} ->
            value =
              case state.key_value_store[key] do
                nil ->
                  crdt = :antidote_crdt.new(crdt_type)
                  :antidote_crdt.value(crdt_type, crdt)

                crdt ->
                  :antidote_crdt.value(crdt_type, crdt)
              end

            {:cont, {:ok, [{key, value} | acc]}}

          invalid_key, _ ->
            {:halt, {:error, :invalid_key, invalid_key}}
        end)

      # NOTE: clock does not have to be advanced for read ops
      case results do
        {:ok, response} -> {:reply, {:ok, Enum.reverse(response), current_clock}, state}
        err -> {:reply, err, state}
      end
    else
      Logger.info(
        "Cannot currently serve read request at #{Vectorclock.to_string(current_clock)}"
      )

      updated_state = %{
        state
        | :pending_requests => MapSet.put(state.pending_requests, {from, request})
      }

      {:noreply, updated_state}
    end
  end

  @impl true
  @spec handle_call(update_request(), GenServer.from(), state()) ::
          {:reply, update_response(), state()} | {:noreply, state()}
  def handle_call(request = {:update_objects, updates, caller_clock}, from, state) do
    current_clock = state.vc

    if can_serve_request(caller_clock, current_clock) do
      key_effect_pairs =
        Enum.reduce_while(updates, {:ok, []}, fn
          {key = {_, crdt_type, _}, op, arg}, {:ok, acc} ->
            case :antidote_crdt.downstream(
                   crdt_type,
                   {op, arg},
                   Map.get(state.key_value_store, key, :antidote_crdt.new(crdt_type))
                 ) do
              {:ok, eff} -> {:cont, {:ok, [{key, eff} | acc]}}
              err = {:error, _} -> {:halt, err}
            end

          invalid_op, _ ->
            {:halt, {:error, :invalid_update, invalid_op}}
        end)

      case key_effect_pairs do
        {:ok, effs} ->
          updated_clock = Vectorclock.increment(current_clock, self())

          CausalBroadcastWaiting.broadcast(
            state.broadcast_layer,
            {:apply_effects, Enum.reverse(effs), updated_clock}
          )

          {:reply, {:ok, updated_clock}, state}

        err ->
          {:reply, err, state}
      end
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

  @impl true
  @spec handle_cast({:deliver, effect_request()}, state()) :: {:noreply, state()}
  def handle_cast({:deliver, {:apply_effects, key_effect_pairs, sender_clock}}, state) do
    Logger.info("Received effects on #{Vectorclock.to_string(sender_clock)}")

    if Vectorclock.lt(state.vc, sender_clock) do
      updated_clock = Vectorclock.merge(sender_clock, state.vc)
      updated_state = apply_effects(key_effect_pairs, state)
      updated_state = %{updated_state | :vc => updated_clock}
      updated_state = serve_pending_requests(updated_state)
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
    # print out the key_effect_pairs
    Logger.info("Applying effects: #{inspect(key_effect_pairs)}")

    key_updated_crdt_pairs =
      Enum.reduce_while(key_effect_pairs, state, fn
        {key = {_, crdt_type, _}, effect}, state ->
          {:ok, updated_crdt} =
            :antidote_crdt.update(
              crdt_type,
              effect,
              Map.get(state.key_value_store, key, :antidote_crdt.new(crdt_type))
            )

          {:cont, Map.put(state, key, updated_crdt)}

        invalid_key_eff, _ ->
          {:halt, {:error, :invalid_key_eff, invalid_key_eff}}
      end)

    case key_updated_crdt_pairs do
      {:error, :invalid_key_eff, invalid_key_eff} ->
        Logger.warning("Invalid Key/Effect pair: #{invalid_key_eff}")
        state

      updated_kv_store when is_map(updated_kv_store) ->
        %{state | :key_value_store => updated_kv_store}

      unknown_err ->
        Logger.warning("Failed to apply effects: #{unknown_err}")
    end
  end

  @spec serve_pending_requests(state()) :: state()
  defp serve_pending_requests(state) do
    requests = state.pending_requests

    Enum.reduce(requests, %{state | :pending_requests => MapSet.new()}, fn
      {client, request}, current_state ->
        case handle_call(request, client, current_state) do
          # The replica served the request, all we need to do now is forward the response
          # back to the client that first issued it.
          {:reply, result, updated_state} ->
            Logger.info(
              "Served Request #{inspect(request)} from #{inspect(client)} at #{Vectorclock.to_string(updated_state.vc)}"
            )

            GenServer.reply(client, result)
            updated_state

          # The server is still unable to server this request
          # (i.e. the vc of the request might be larger that the server's vc)
          {:noreply, updated_state} ->
            updated_state
        end
    end)
  end
end
