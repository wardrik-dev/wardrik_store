if Code.ensure_loaded?(EKV) do
  defmodule WardrikStore.EKV do
    @moduledoc """
    An EKV store keeps its keys on this node's disk, replicated between connected nodes.

        store = WardrikStore.EKV.new(name: :my_app, data_dir: "/var/lib/my_app", cluster_size: 3)
        children = [{WardrikStore, store}]

    It takes EKV's own options, and `cluster_size` is 1 unless you set it. Its keys sit under
    `wardrik_store/`, so it can share an EKV instance with WardrikCore's agents. When your app
    already runs that instance, build the store with its name and leave it out of your children.

    Reach for this when you want durable storage with no database to run.
    """

    @behaviour WardrikStore.Adapter

    @root "wardrik_store/"

    @doc "Builds a store over the EKV instance named `:name`. Starts nothing."
    @spec new(keyword()) :: WardrikStore.t()
    def new(opts) do
      options = Keyword.put_new(opts, :cluster_size, 1)
      WardrikStore.new(__MODULE__, %{name: Keyword.fetch!(opts, :name), options: options})
    end

    @impl WardrikStore.Adapter
    def child_spec(%{options: options}), do: EKV.child_spec(options)

    @impl WardrikStore.Adapter
    def put(%{name: name}, path, value, opts) do
      case EKV.put(name, @root <> path, value, conditional(opts)) do
        :ok -> {:ok, nil}
        {:ok, vsn} -> {:ok, vsn}
        {:error, reason} -> {:error, reason}
      end
    end

    @impl WardrikStore.Adapter
    def lookup(%{name: name}, path), do: EKV.lookup(name, @root <> path)

    @impl WardrikStore.Adapter
    def delete(%{name: name}, path, opts) do
      case EKV.delete(name, @root <> path, conditional(opts)) do
        :ok -> :ok
        {:ok, _vsn} -> :ok
        {:error, :not_found} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end

    @impl WardrikStore.Adapter
    def keys(%{name: name}, prefix) do
      name
      |> EKV.keys(@root <> prefix)
      |> Enum.map(fn {key, _vsn} -> String.replace_prefix(key, @root, "") end)
    end

    defp conditional(opts) do
      case Keyword.fetch(opts, :if_vsn) do
        {:ok, vsn} -> [if_vsn: vsn, resolve_unconfirmed: true]
        :error -> []
      end
    end
  end
end
