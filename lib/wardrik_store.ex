defmodule WardrikStore do
  @moduledoc """
  A durable key-value store that Wardrik packages keep their data in.

      store = WardrikStore.ETS.new(name: MyApp.Store)
      children = [{WardrikStore, store}]

  Hand the same store to each package. A package scopes it by its OTP app name before it writes, so
  two packages never share a key:

      vault = WardrikStore.scope(store, "wardrik_vault")
      {:ok, vsn} = WardrikStore.put(vault, "github/jon", grant, if_vsn: nil)

  Scope it yourself to keep your app's own data apart, or to run two of one package. Scopes nest,
  and a key in one scope never matches a key in another, whatever characters it holds.

  A write with `if_vsn:` lands only over that version, or only where nothing is written yet when
  it's `nil`. Notice a key written that way should always be written that way, because some
  adapters refuse an unconditional write over it.

  Reach for this when a package needs to keep something past a restart.
  """

  alias WardrikStore.Adapter

  @enforce_keys [:adapter, :config]
  defstruct [:adapter, :config, scope: ""]

  @typedoc "A store, scoped or not."
  @type t() :: %__MODULE__{adapter: module(), config: Adapter.config(), scope: String.t()}

  @typedoc "A key within a scope."
  @type key() :: String.t()

  @typedoc "The version an adapter stamps a write with."
  @type vsn() :: term()

  @scope_name ~r/^[a-z][a-z0-9_]*$/

  @doc "Builds a store over `adapter`. Adapters call this from their own `new/1`."
  @spec new(module(), Adapter.config()) :: t()
  def new(adapter, config) when is_atom(adapter),
    do: %__MODULE__{adapter: adapter, config: config}

  @doc "Returns the child that runs the store."
  @spec child_spec(t()) :: Supervisor.child_spec()
  def child_spec(%__MODULE__{adapter: adapter, config: config}),
    do: Supervisor.child_spec(adapter.child_spec(config), id: __MODULE__)

  @doc "Nests the store under `name`, which is lowercase letters, digits and underscores."
  @spec scope(t(), String.t()) :: t()
  def scope(%__MODULE__{} = store, name) when is_binary(name) do
    if Regex.match?(@scope_name, name),
      do: %{store | scope: nested(store.scope, name)},
      else: raise(ArgumentError, not_a_scope_name(name))
  end

  @doc "Writes `value` under `key`. With `if_vsn:` it writes only over that version."
  @spec put(t(), key(), term(), if_vsn: vsn() | nil) ::
          {:ok, vsn() | nil} | {:error, :conflict | term()}
  def put(%__MODULE__{} = store, key, value, opts \\ []) when is_binary(key),
    do: store.adapter.put(store.config, path(store, key), value, opts)

  @doc "Finds the value under `key`, or returns `nil`."
  @spec get(t(), key()) :: term() | nil
  def get(%__MODULE__{} = store, key) do
    case lookup(store, key) do
      {value, _vsn} -> value
      nil -> nil
    end
  end

  @doc "Finds the value under `key` with its version, or returns `nil`."
  @spec lookup(t(), key()) :: {term(), vsn()} | nil
  def lookup(%__MODULE__{} = store, key) when is_binary(key),
    do: store.adapter.lookup(store.config, path(store, key))

  @doc "Removes `key`. With `if_vsn:` it removes only that version."
  @spec delete(t(), key(), if_vsn: vsn()) :: :ok | {:error, :conflict | term()}
  def delete(%__MODULE__{} = store, key, opts \\ []) when is_binary(key),
    do: store.adapter.delete(store.config, path(store, key), opts)

  @doc "Lists every key in the scope that starts with `prefix`, in order."
  @spec keys(t(), String.t()) :: [key()]
  def keys(%__MODULE__{} = store, prefix \\ "") when is_binary(prefix) do
    root = path(store, "")
    paths = store.adapter.keys(store.config, root <> prefix)

    paths
    |> Enum.map(&String.replace_prefix(&1, root, ""))
    |> Enum.sort()
  end

  defp nested("", name), do: name
  defp nested(scope, name), do: scope <> "/" <> name

  defp path(%__MODULE__{scope: scope}, key), do: scope <> ":" <> key

  defp not_a_scope_name(name),
    do: "A scope's name is lowercase letters, digits and underscores, got: #{inspect(name)}"
end
