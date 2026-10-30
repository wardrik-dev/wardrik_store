# WardrikStore

A durable key-value store. Wardrik packages keep their data in it, and
[WardrikCore](https://hexdocs.pm/wardrik_core) can keep its agents in it too.

## Install

```elixir
def deps do
  [
    {:wardrik_store, "~> 0.1.0-rc.1"}
  ]
end
```

## Start a store

Build a store from an adapter. Start it in your supervision tree, ahead of what uses it:

```elixir
store = WardrikStore.ETS.new(name: MyApp.Store)
children = [{WardrikStore, store}]
```

A store that's already running starts nothing. So each thing that uses the store can list it among
its own children.

Pick an adapter for where your data is kept:

```elixir
# In memory, gone when the store stops
store = WardrikStore.ETS.new(name: MyApp.Store)

# On disk, copied to each connected node
store = WardrikStore.EKV.new(name: MyApp.Store, data_dir: "/var/lib/my_app")

# In Postgres, through your app's repo
store = WardrikStore.Ecto.new(repo: MyApp.Repo)

# In Postgres, through a repo of its own
store = WardrikStore.Ecto.new(url: "postgres://user:pass@db.example.com/wardrik?ssl=true")
```

| Adapter | Keeps data | Needs |
| --- | --- | --- |
| `WardrikStore.ETS` | In memory. Use it for tests, development and data you can rebuild. | Nothing. |
| `WardrikStore.EKV` | On disk, and on each connected node. | `{:ekv, "~> 0.4"}` |
| `WardrikStore.Ecto` | In a Postgres table. | `{:ecto_sql, "~> 3.13"}`, and `:postgrex` for `:url` |

### Ecto through your repo

Create the table from a migration of your own:

```elixir
defmodule MyApp.Repo.Migrations.AddWardrikStore do
  use Ecto.Migration

  def up, do: WardrikStore.Ecto.Migration.up(version: 1)
  def down, do: WardrikStore.Ecto.Migration.down(version: 1)
end
```

If the table is missing, the store logs an error as it starts. Your app still boots, so a release
can run its migrations.

Point your repo at the primary, not a replica, so each read sees the last write.

### Ecto through a URL

The store starts a repo of its own. It creates its table before it keeps anything, one node at a
time.

`?ssl=true` connects over TLS, verified against the system's certificates.

## Hand it to packages

Give the same store to each package. Each package scopes it by its OTP app name, so two packages
never share a key. Scope it yourself to keep your app's data apart:

```elixir
mine = WardrikStore.scope(store, "my_app")

{:ok, _vsn} = WardrikStore.put(mine, "settings/theme", "dark", if_vsn: nil)

WardrikStore.get(mine, "settings/theme")
#=> "dark"

WardrikStore.keys(mine, "settings/")
#=> ["settings/theme"]
```

A scope's name is lowercase letters, digits and underscores, like an OTP app's. A key can hold any
characters.

## Write conditionally

Use `:if_vsn` when two processes, or two nodes, might change the same key at once. The write lands
only over the version you read. With `nil`, it lands only where nothing is written yet.

```elixir
{"dark", vsn} = WardrikStore.lookup(mine, "settings/theme")

{:ok, _new_vsn} = WardrikStore.put(mine, "settings/theme", "light", if_vsn: vsn)

WardrikStore.put(mine, "settings/theme", "blue", if_vsn: vsn)
#=> {:error, :conflict}
```

A version is whatever the adapter stamps a write with. Pass back the one you read.

Once you write a key conditionally, keep writing it that way. EKV refuses an unconditional write
over it.

## Keep agents in it

`WardrikStore.Durable` keeps WardrikCore's agents in the store, under its `durable` scope:

```elixir
store = WardrikStore.Ecto.new(repo: MyApp.Repo)

children = [
  MyApp.Repo,
  {WardrikStore, store},
  {WardrikCore, backend: {WardrikStore.Durable, store: store}}
]
```

Use it with the Ecto or ETS store. It needs `durable_server`, which WardrikCore already brings.

With EKV, use DurableServer's own `EKVStore` instead. It's faster. The two can share one EKV
instance, since the store's keys sit under `wardrik_store/`:

```elixir
store = WardrikStore.EKV.new(name: :my_app)

children = [
  {EKV, name: :my_app, data_dir: "/var/lib/my_app", cluster_size: 1},
  {WardrikCore, backend: {DurableServer.Backends.EKVStore, name: :my_app}}
]
```

EKV is already in the children here, so leave the store out.

## Write an adapter

Implement `WardrikStore.Adapter`, plus a `new/1` that builds the store:

```elixir
defmodule MyApp.Store do
  @behaviour WardrikStore.Adapter

  def new(opts), do: WardrikStore.new(__MODULE__, Keyword.fetch!(opts, :name))
end
```

Each callback gets that config, and a full path that already holds the store's scopes:

| Callback | Does |
| --- | --- |
| `child_spec/1` | Returns the child spec that runs the adapter. |
| `put/4` | Writes a value. Honours `:if_vsn`. |
| `lookup/2` | Returns `{value, vsn}`, or `nil`. |
| `delete/3` | Removes a path. Honours `:if_vsn`. |
| `keys/2` | Returns every path that starts with a prefix. |
| `lookup_many/2` | Optional. Reads many paths at once. |
| `entries/2` | Optional. Reads every path under a prefix, with values. |
