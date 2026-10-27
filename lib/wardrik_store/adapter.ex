defmodule WardrikStore.Adapter do
  @moduledoc """
  An adapter is where a store keeps its keys. Callers go through `WardrikStore`. An adapter that
  reads many keys at once more cheaply than one by one, as a database does, implements
  `c:lookup_many/2` and `c:entries/2`; `WardrikStore` reads them one by one for one that doesn't.
  """

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

  @doc "Finds the values under `paths` with their versions, leaving out those that aren't there."
  @callback lookup_many(config(), paths :: [String.t()]) :: [
              {String.t(), term(), WardrikStore.vsn()}
            ]

  @doc "Lists every full path that starts with `prefix`, with its value and version."
  @callback entries(config(), prefix :: String.t()) :: [{String.t(), term(), WardrikStore.vsn()}]

  @optional_callbacks lookup_many: 2, entries: 2
end
