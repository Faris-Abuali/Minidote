defmodule PersistentLog do
  use GenServer

  require Logger

  @typep log_updates() :: [{Minidote.key(), atom(), any()}]
  @typep log_initial_state() :: %{optional(Minidote.key()) => :antidote_crdt.crdt()}
  @typep state() :: %{initial_state: log_initial_state(), updates: log_updates()}
  # TODO: More precise type for this
  @type entries() :: any()

  def get_log_path(server_name) do
    :filename.join(~c"logs", ~c"#{server_name}.LOG")
  end

  def start_link(respond_to, server_name) do
    GenServer.start_link(PersistentLog, [respond_to, server_name])
  end

  @impl true
  def init([respond_to, server_name]) do
    Logger.info("#{inspect(respond_to)}; #{inspect(server_name)}")

    log_path = get_log_path(server_name)

    open_result =
      :disk_log.open(
        name: String.to_charlist(server_name),
        file: log_path,
        type: :halt,
        size: 1_048_576 # 1 MB
      )

    case open_result do
      {:ok, log} ->
        {:ok, %{log: log, respond_to: respond_to}}

      {:repaired, log, _recovered, _bad_chunks} ->
        Logger.warning("Log file was corrupted and has been repaired")
        {:ok, %{log: log, respond_to: respond_to}}

      err = {:error, reason} ->
        Logger.error("Failed to open log file: #{inspect(reason)}")
        {:stop, err}
    end
  end

  @impl true
  @spec handle_call(
          {:persist, [{Vectorclock.t(), Minidote.key(), atom(), term()}]},
          GenServer.from(),
          state()
        ) ::
          {:reply, :ok | {:error, any()}, state()}
  def handle_call({:persist, operation}, _from, state) do
    # Open a new disk_log file for reading or writing.
    # log name: my_halt_log.
    # log file name: "my_log_file.log".
    # log type: halt.
    # log size: 1 MB.

    trylogres = :disk_log.log(state.log, operation)

    IO.inspect(trylogres)

    case trylogres do
      :ok ->
        {:reply, :ok, state}

      err = {:error, reason} ->
        Logger.error("Failed to open disk_log: #{inspect(reason)}")
        {:reply, err, state}
    end
  end

  @impl true
  @spec handle_call(:get_entries, GenServer.from(), state()) ::
          {:reply, {:ok, entries()} | {:error, any()}, state}
  def handle_call(:get_entries, _from, state) do
    result = read_chunks(state.log, :start, [])
    {:reply, result, state}
  end

  @spec read_chunks(any(), any(), entries()) :: {:ok, entries()} | {:error, any()}
  defp read_chunks(log, cont, acc) do
    case :disk_log.chunk(log, cont) do
      :eof ->
        {:ok, acc}

      err = {:error, _} ->
        err

      # TODO: rewrite this as a prepend + reverse if performance becomes an issue.
      {next_cont, terms} ->
        read_chunks(log, next_cont, acc ++ terms)

      {next_cont, terms, bad_bytes} ->
        # TODO: add server_name to this logging message
        Logger.warning("Encountered #{bad_bytes} bad bytes while reading chunk from log.")
        read_chunks(log, next_cont, acc ++ terms)
    end
  end
end
