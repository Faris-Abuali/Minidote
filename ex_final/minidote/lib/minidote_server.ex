defmodule Minidote.Server do
  use GenServer
  require Logger

  @moduledoc """
  The API documentation for `Minidote.Server`.
  """

  @type read_request() :: {:read_objects, [Minidote.key()], Vectorclock.t()}

  @type update_request() ::
          {:update_objects, [{Minidote.key(), atom(), term()}], Vectorclock.t()}

  @type apply_effects_request() ::
          {:apply_effects, Vectorclock.t(), Process.dest(),
           [{Minidote.key(), :antidote_crdt.effect()}]}

  @type request() :: read_request() | update_request() | apply_effects_request()

  @type read_response() ::
          {:ok, [{Minidote.key(), term()}], Vectorclock.t()}
          | {:error, :invalid_key, Minidote.key()}

  @type update_response() ::
          {:ok, Vectorclock.t()} | {:error, any()}

  @type effect_request() ::
          {:apply_effects, Process.dest(), [{Minidote.key(), :antidote_crdt.effect()}],
           Vectorclock.t()}

  @opaque state() :: %{
            required(:broadcast_layer) => any(),
            required(:key_value_store) => %{optional(Minidote.key()) => :antidote_crdt.crdt()},
            required(:pending_requests) => MapSet.t(request()),
            required(:vc) => Vectorclock.t(),
            required(:log) => pid()
          }

  def start_link(server_name) do
    # if you need arguments for initialization, change here
    GenServer.start_link(Minidote.Server, [], name: server_name)
  end

  # Once the GenServer is started, the init/1 callback is invoked to initialize the process state.
  @spec init(any()) :: {:ok, state()} | {:stop, term()}
  @impl true
  def init(_) do
    {:ok, causal_broadcast} = CausalBroadcastWaiting.start_link(self())

    {:ok, log} =
      PersistentLog.start_link(
        self(),
        node()
        |> Atom.to_string()
        |> String.replace("@", "_")
      )

    init_state = %{
      :vc => Vectorclock.new(),
      :key_value_store => %{},
      :pending_requests => MapSet.new(),
      :broadcast_layer => causal_broadcast,
      :log => log
    }

    # Initialize the state of the server from the disk log file if it exists
    state = init_state_from_log(init_state)
    Logger.notice("#{node()} finished initializing.")
    # {:ok, init_state}
    state
  end

  # Initializes the state of the server from the disk log file if it exists
  @spec init_state_from_log(state()) :: {:ok, state()} | {:stop, term()}
  defp init_state_from_log(state) do
    case PersistentLog.get_entries(state.log) do
      {:ok, vc_transaction_entries} ->
        transaction_entries = Enum.map(vc_transaction_entries, fn {_, t} -> t end)
        Logger.info("Loaded #{Enum.count(transaction_entries)} transactions from log.")

        updated_state =
          Enum.reduce(transaction_entries, state, &apply_effects/2)

        {:ok, updated_state}

      {:error, err} ->
        {:stop, err}
    end
  end

  @spec can_serve_request(:ignore | Minidote.clock(), Minidote.clock()) :: boolean()
  defp can_serve_request(:ignore, _), do: true
  defp can_serve_request(vc1, vc2), do: Vectorclock.leq(vc1, vc2)

  # When a Minidote server is about to terminate, make sure the log process is also stopped.
  @impl true
  def terminate(_reason, state) do
    GenServer.stop(state.log)
  end

  # def serve_update_request(updates, state) do
  #   key_effect_pairs =
  #     Enum.reduce_while(updates, {:ok, []}, fn
  #       {key = {_, crdt_type, _}, op, arg}, {:ok, acc} ->
  #         # case :antidote_crdt.downstream(
  #         #        crdt_type,
  #         #        {op, arg},
  #         #        Map.get(state.key_value_store, key, :antidote_crdt.new(crdt_type))
  #         #      ) do
  #         #   {:ok, eff} ->
  #         #     {:cont, {:ok, [{key, eff} | acc]}}

  #         #   err = {:error, _} ->
  #         #     {:halt, err}
  #         # end

  #       invalid_op, _ ->
  #         {:halt, {:error, :invalid_update, invalid_op}}
  #     end)

  #   with {:ok, effs, _} <- key_effect_pairs do
  #     updated_state = apply_effects(Enum.reverse(effs), state)
  #     {:ok, updated_state}
  #   end
  # end

  @impl true
  @spec handle_call(:unsafe_force_crash, GenServer.from(), state()) :: :ok
  def handle_call(:unsafe_force_crash, from, _) do
    GenServer.stop(self(), "Got :unsafe_force_crash signal from #{inspect(from)}")
  end

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
      updated_clock = Vectorclock.increment(current_clock, self())

      key_effect_pairs =
        Enum.reduce_while(updates, {:ok, [], []}, fn
          {key = {_, crdt_type, _}, op, arg}, {:ok, acc, ops} ->
            case :antidote_crdt.downstream(
                   crdt_type,
                   {op, arg},
                   Map.get(state.key_value_store, key, :antidote_crdt.new(crdt_type))
                 ) do
              {:ok, eff} ->
                {:cont, {:ok, [{key, eff} | acc], [{updated_clock, key, op, arg} | ops]}}

              err = {:error, _} ->
                {:halt, err}
            end

          invalid_op, _ ->
            {:halt, {:error, :invalid_update, invalid_op}}
        end)

      result =
        with {:ok, effs, _ops} <- key_effect_pairs,
             :ok <- PersistentLog.persist(state.log, updated_clock, Enum.reverse(effs)) do
          CausalBroadcastWaiting.broadcast(
            state.broadcast_layer,
            {:apply_effects, self(), Enum.reverse(effs), updated_clock}
          )

          {:ok, updated_clock}
        end

      {:reply, result, state}
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
  def handle_cast({:deliver, {:apply_effects, sender, key_effect_pairs, sender_clock}}, state) do
    Logger.info("Received effects on #{Vectorclock.to_string(sender_clock)}")

    if Vectorclock.lt(state.vc, sender_clock) do
      delta = Vectorclock.delta(state.vc, sender_clock)
      Logger.info("Message delta: #{delta}")

      updated_state =
        if delta <= 1 do
          updated_clock = Vectorclock.merge(sender_clock, state.vc)
          updated_state = apply_effects(key_effect_pairs, state)
          updated_state = %{updated_state | :vc => updated_clock}
          serve_pending_requests(updated_state)
        else
          Logger.info(
            "Missing #{delta} updates. Asking #{inspect(sender)} to retransmit messages."
          )

          # Ask the sender to transmit missing operations (without waiting for a response).
          GenServer.cast(sender, {:send_missing, self(), state.vc, sender_clock})

          # Construct a synthetic pending request.
          # Essentially, we'll apply this update once we've applied the ones before.

          %{
            state
            | :pending_requests =>
                MapSet.put(
                  state.pending_requests,
                  {:apply_effects, sender_clock, key_effect_pairs, sender_clock}
                )
          }

          # TODO: Is this necessary? or can we apply the effect now
        end

      {:noreply, updated_state}
    else
      {:noreply, state}
    end
  end

  def handle_cast(:unsafe_clear_log, state) do
    GenServer.cast(state.log, :unsafe_clear_log)
  end

  def handle_cast({:send_missing, recepient, from_vc, upto_vc}, state) do
    # TODO: read from log and respond with effs.
    # what should happen if there's an error. Do we try again?
    with {:ok, result} <- PersistentLog.get_entries_between(state.log, from_vc, upto_vc) do
      # result :: [{Vectorclock.t(), [{key, eff}]}]
      # should we cast individual :apply_effect messages? or do them in bulk.
      # YES
      # GenServer.cast(
      #   recepient,
      #   {:bulk_apply_effects, self(), effects, vc}
      # )
      Enum.each(result, fn {vc, key_effect_pairs} ->
        req = {:apply_effects, self(), key_effect_pairs, vc}
        GenServer.cast(recepient, {:deliver, req})
      end)
    end

    {:noreply, state}
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
    # Logger.info("Applying effects: #{inspect(key_effect_pairs)}")

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
        Logger.warning("Invalid Key/Effect pair: #{inspect(invalid_key_eff)}")
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
      request = {:apply_effects, _, key_eff_pairs, vc}, current_state ->
        if Vectorclock.lt(vc, current_state.vc) do
          apply_effects(key_eff_pairs, current_state)
        else
          %{
            current_state
            | :pending_requests => MapSet.put(current_state.pending_requests, request)
          }
        end

      {client, request}, current_state ->
        case handle_call(request, client, current_state) do
          # The replica served the request, all we need to do now is forward the response
          # back to the client that first issued it.
          {:reply, result, updated_state} ->
            Logger.info(
              "Served Request #{inspect(request)} from #{inspect(client)} at #{Vectorclock.to_string(updated_state.vc)}"
            )

            if client != nil do
              GenServer.reply(client, result)
            end

            updated_state

          # The server is still unable to server this request
          # (i.e. the vc of the request might be larger that the server's vc)
          {:noreply, updated_state} ->
            updated_state
        end
    end)
  end
end
