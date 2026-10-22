defmodule WardrikStore.ETS do
  @moduledoc """
  An ETS store keeps its keys in memory, for as long as its process runs.

      store = WardrikStore.ETS.new(name: MyApp.Store)
      children = [{WardrikStore, store}]

  You name it, and the name is its table's, so pick one your app owns. Reads go straight to the
  table. Writes go through the process one at a time, so a conditional write sees the version it
  names.

  Reach for this in tests, in development, and for data your app can rebuild after a restart.
  """

  @behaviour WardrikStore.Adapter

  use GenServer

  @doc "Builds a store named `:name`. Starts nothing."
  @spec new(keyword()) :: WardrikStore.t()
  def new(opts), do: WardrikStore.new(__MODULE__, Keyword.fetch!(opts, :name))

  @doc "Starts the store, empty, under `name`."
  @spec start_link(atom()) :: GenServer.on_start()
  def start_link(name) when is_atom(name), do: GenServer.start_link(__MODULE__, name, name: name)

  @impl WardrikStore.Adapter
  def child_spec(name), do: %{id: name, start: {__MODULE__, :start_link, [name]}}

  @impl WardrikStore.Adapter
  def put(name, path, value, opts),
    do: GenServer.call(name, {:put, path, value, Keyword.fetch(opts, :if_vsn)})

  @impl WardrikStore.Adapter
  def lookup(name, path) do
    case :ets.lookup(name, path) do
      [{^path, value, vsn}] -> {value, vsn}
      [] -> nil
    end
  end

  @impl WardrikStore.Adapter
  def delete(name, path, opts),
    do: GenServer.call(name, {:delete, path, Keyword.fetch(opts, :if_vsn)})

  @impl WardrikStore.Adapter
  def keys(name, prefix) do
    name
    |> first_at_or_after(prefix)
    |> Stream.unfold(fn
      :"$end_of_table" -> nil
      path -> {path, :ets.next(name, path)}
    end)
    |> Enum.take_while(&String.starts_with?(&1, prefix))
  end

  defp first_at_or_after(name, prefix) do
    if :ets.member(name, prefix), do: prefix, else: :ets.next(name, prefix)
  end

  @impl GenServer
  def init(name),
    do: {:ok, :ets.new(name, [:ordered_set, :protected, :named_table, read_concurrency: true])}

  @impl GenServer
  def handle_call({:put, path, value, if_vsn}, _from, table) do
    if current?(if_vsn, :ets.lookup(table, path)) do
      vsn = System.unique_integer([:positive, :monotonic])
      true = :ets.insert(table, {path, value, vsn})
      {:reply, {:ok, vsn}, table}
    else
      {:reply, {:error, :conflict}, table}
    end
  end

  def handle_call({:delete, path, if_vsn}, _from, table) do
    if deletable?(if_vsn, :ets.lookup(table, path)) do
      true = :ets.delete(table, path)
      {:reply, :ok, table}
    else
      {:reply, {:error, :conflict}, table}
    end
  end

  defp current?(:error, _written), do: true
  defp current?({:ok, nil}, []), do: true
  defp current?({:ok, vsn}, [{_path, _value, vsn}]), do: true
  defp current?({:ok, _vsn}, _written), do: false

  defp deletable?({:ok, _vsn}, []), do: true
  defp deletable?(if_vsn, written), do: current?(if_vsn, written)
end
