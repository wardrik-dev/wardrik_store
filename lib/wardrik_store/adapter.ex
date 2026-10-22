defmodule WardrikStore.Adapter do
  @moduledoc "An adapter is where a store keeps its keys. Callers go through `WardrikStore`."

  @typedoc "What an adapter's `new/1` built, handed back to each of its callbacks."
  @type config() :: term()

  @doc "Returns the child that runs the adapter."
  @callback child_spec(config()) :: Supervisor.child_spec()

  @doc "Writes `value` under the full `path`."
  @callback put(config(), path :: String.t(), value :: term(), keyword()) ::
              {:ok, WardrikStore.vsn() | nil} | {:error, :conflict | term()}

  @doc "Finds the value under `path` with its version, or returns `nil`."
  @callback lookup(config(), path :: String.t()) :: {term(), WardrikStore.vsn()} | nil

  @doc "Removes `path`. Removing one that isn't there is `:ok`."
  @callback delete(config(), path :: String.t(), keyword()) :: :ok | {:error, :conflict | term()}

  @doc "Lists every full path that starts with `prefix`."
  @callback keys(config(), prefix :: String.t()) :: [String.t()]
end
