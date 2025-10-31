defmodule Rclip.Store do
  use GenServer

  @cleanup_interval :timer.minutes(1)

  ## Public API

  # Put a new clipboard
  def put(id, data, ip, content_type \\ "text/plain", ttl \\ 300, private \\ false, once \\ false) do
    expires_at = System.system_time(:second) + ttl

    record = %{
      id: id,
      data: data,
      content_type: content_type,
      ip: ip,
      inserted_at: System.system_time(:second),
      expires_at: expires_at,
      private: private,
      once: once
    }

    :ets.insert(:clipboards, {id, record})
    notify_subscribers(id, record)
    :ok
  end

  # Get a clipboard
  def get(id) do
    case :ets.lookup(:clipboards, id) do
      [{^id, record}] ->
        if record.once, do: :ets.delete(:clipboards, id)
        {:ok, record}

      [] ->
        :not_found
    end
  end

  # List active, non-private clipboards
  def list_active do
    now = System.system_time(:second)

    :ets.tab2list(:clipboards)
    |> Enum.filter(fn {_id, record} -> record.expires_at > now end)
    |> Enum.reject(fn {_id, record} -> record.private end)
    |> Enum.map(fn {_id, record} ->
      Map.take(record, [:id, :content_type, :ip, :inserted_at, :expires_at, :private, :once])
    end)
  end

  # Subscribe current process to updates for an ID
  def subscribe(id), do: GenServer.call(__MODULE__, {:subscribe, id, self()})

  ## Internal: notify all subscribers about an update
  defp notify_subscribers(id, record) do
    GenServer.cast(__MODULE__, {:notify, id, record})
  end

  ## Server callbacks

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    # ETS table for active clipboards
    :ets.new(:clipboards, [:named_table, :set, :public, read_concurrency: true])

    # DETS for clipboard history
    {:ok, dets} =
      :dets.open_file(:clipboard_history,
        type: :set,
        file: 'clipboards.dets'
      )

    state = %{dets: dets, subscribers: %{}}

    # Periodic cleanup
    :timer.send_interval(@cleanup_interval, :cleanup)

    {:ok, state}
  end

  # Cleanup expired clipboards
  def handle_info(:cleanup, state) do
    now = System.system_time(:second)

    :ets.tab2list(:clipboards)
    |> Enum.each(fn {id, record} ->
      if record.expires_at <= now do
        :dets.insert(state.dets, {id, record})
        :ets.delete(:clipboards, id)
      end
    end)

    {:noreply, state}
  end

  # Subscribe a process to clipboard updates
  def handle_call({:subscribe, id, pid}, _from, state) do
    subscribers = Map.update(state.subscribers, id, [pid], &[pid | &1])
    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  # Notify subscribers of a new clipboard
  def handle_cast({:notify, id, record}, state) do
    subscribers = Map.get(state.subscribers, id, [])
    Enum.each(subscribers, fn pid -> send(pid, {:clipboard_update, record}) end)
    {:noreply, %{state | subscribers: Map.put(state.subscribers, id, [])}}
  end

  def terminate(_reason, %{dets: dets}) do
    :dets.close(dets)
    :ok
  end
end
