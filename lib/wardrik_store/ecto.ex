if Code.ensure_loaded?(Ecto.Adapters.SQL) do
  defmodule WardrikStore.Ecto do
    @moduledoc """
    An Ecto store keeps its keys in a Postgres table, through your app's repo.

        store = WardrikStore.Ecto.new(repo: MyApp.Repo)
        children = [MyApp.Repo, {WardrikStore, store}]
    """

    @behaviour WardrikStore.Adapter

    require Logger

    alias Ecto.Adapters.SQL

    @table "wardrik_store"

    @doc "Builds a store over `:repo`. Starts nothing."
    @spec new(keyword()) :: WardrikStore.t()
    def new(opts), do: WardrikStore.new(__MODULE__, Keyword.fetch!(opts, :repo))

    @doc "Checks the store's table is there, logging an error when it isn't. Returns `:ignore`."
    @spec start_link(module()) :: :ignore
    def start_link(repo) do
      case SQL.query(repo, "SELECT to_regclass($1)::text", [@table]) do
        {:ok, %{rows: [[@table]]}} -> :ok
        {:ok, _missing} -> Logger.error("#{@table} is missing; run WardrikStore.Ecto.Migration")
        {:error, reason} -> Logger.error("Couldn't check #{@table} is there: #{inspect(reason)}")
      end

      :ignore
    end

    @impl WardrikStore.Adapter
    def child_spec(repo), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [repo]}}

    @impl WardrikStore.Adapter
    def put(repo, path, value, opts) do
      vsn = :rand.uniform(0x7FFFFFFFFFFFFFFF)
      condition = Keyword.fetch(opts, :if_vsn)

      case written(repo, condition, [path, :erlang.term_to_binary(value), vsn]) do
        {:ok, %{num_rows: 1}} -> {:ok, vsn}
        {:ok, %{num_rows: 0}} -> {:error, :conflict}
        {:error, reason} -> {:error, reason}
      end
    end

    @impl WardrikStore.Adapter
    def lookup(repo, path) do
      case SQL.query!(repo, "SELECT value, vsn FROM #{@table} WHERE key = $1", [path]) do
        %{rows: [[value, vsn]]} -> {:erlang.binary_to_term(value, [:safe]), vsn}
        %{rows: []} -> nil
      end
    end

    @impl WardrikStore.Adapter
    def delete(repo, path, opts) do
      case removed(repo, Keyword.fetch(opts, :if_vsn), path) do
        {:ok, %{num_rows: 1}} -> :ok
        {:ok, %{num_rows: 0}} -> gone_or_conflict(repo, path)
        {:error, reason} -> {:error, reason}
      end
    end

    @impl WardrikStore.Adapter
    def keys(repo, prefix) do
      %{rows: rows} =
        SQL.query!(
          repo,
          "SELECT key FROM #{@table} WHERE key LIKE $1 ESCAPE '\\' ORDER BY key",
          [like(prefix) <> "%"]
        )

      Enum.map(rows, fn [key] -> key end)
    end

    defp written(repo, :error, args) do
      SQL.query(
        repo,
        """
        INSERT INTO #{@table} (key, value, vsn) VALUES ($1, $2, $3)
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, vsn = EXCLUDED.vsn
        """,
        args
      )
    end

    defp written(repo, {:ok, nil}, args) do
      SQL.query(
        repo,
        "INSERT INTO #{@table} (key, value, vsn) VALUES ($1, $2, $3) ON CONFLICT (key) DO NOTHING",
        args
      )
    end

    defp written(repo, {:ok, vsn}, args) when is_integer(vsn) do
      SQL.query(
        repo,
        "UPDATE #{@table} SET value = $2, vsn = $3 WHERE key = $1 AND vsn = $4",
        args ++ [vsn]
      )
    end

    defp written(_repo, {:ok, _not_a_vsn}, _args), do: {:ok, %{num_rows: 0}}

    defp removed(repo, :error, path),
      do: SQL.query(repo, "DELETE FROM #{@table} WHERE key = $1", [path])

    defp removed(repo, {:ok, vsn}, path) when is_integer(vsn),
      do: SQL.query(repo, "DELETE FROM #{@table} WHERE key = $1 AND vsn = $2", [path, vsn])

    defp removed(_repo, {:ok, _not_a_vsn}, _path), do: {:ok, %{num_rows: 0}}

    defp gone_or_conflict(repo, path) do
      if lookup(repo, path) == nil, do: :ok, else: {:error, :conflict}
    end

    defp like(prefix), do: String.replace(prefix, ~r/[\\%_]/, "\\\\\\0")
  end
end
