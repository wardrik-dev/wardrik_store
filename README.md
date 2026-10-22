# WardrikStore

A durable key-value store that Wardrik packages keep their data in, and that can keep
[WardrikCore](https://hexdocs.pm/wardrik_core)'s agents too.

## Install

```elixir
def deps do
  [
    {:wardrik_store, "~> 0.1"}
  ]
end
```

## Start a store

Build a store from an adapter, and run it in your supervision tree:

```elixir
store = WardrikStore.EKV.new(name: :my_app, data_dir: "/var/lib/my_app")
children = [{WardrikStore, store}]
```

| Adapter | Keeps your data | Needs |
| --- | --- | --- |
| `WardrikStore.ETS` | In memory. It's gone when its process stops. | Nothing. For tests, development, and data your app can rebuild. |
| `WardrikStore.EKV` | On disk, and on each node when clustered. | The `ekv` dependency. |
| `WardrikStore.Ecto` | In a Postgres table, through your app's repo. | The `ecto_sql` dependency, and a migration. |

EKV and Ecto are optional. Add the one you keep your data with:

```elixir
{:ekv, "~> 0.4"}
{:ecto_sql, "~> 3.13"}
```

The Ecto store keeps its keys in one Postgres table. Create it from a migration of your own:

```elixir
defmodule MyApp.Repo.Migrations.AddWardrikStore do
  use Ecto.Migration

  def up, do: WardrikStore.Ecto.Migration.up(version: 1)
  def down, do: WardrikStore.Ecto.Migration.down(version: 1)
end
```

The store logs an error as it starts when the table is missing, and your app boots anyway, so
a release can still run its migrations. Point your repo at the primary, not a replica, so each
read sees the last write.

## Hand it to packages

Give the same store to each package. A package scopes it by its OTP app name before it writes, so
two packages never share a key. Scope it yourself to keep your app's own data apart:

```elixir
mine = WardrikStore.scope(store, "my_app")

{:ok, vsn} = WardrikStore.put(mine, "settings/theme", "dark", if_vsn: nil)
WardrikStore.get(mine, "settings/theme")
#=> "dark"
WardrikStore.keys(mine, "settings/")
#=> ["settings/theme"]
```

A scope's name is lowercase letters, digits and underscores, like an OTP app's. A key can hold any
characters, and it never matches a key in another scope.

## Write conditionally

A write with `if_vsn:` lands only over the version you read, or only where nothing is written yet
when it's `nil`. Otherwise it returns `{:error, :conflict}`:

```elixir
{theme, vsn} = WardrikStore.lookup(mine, "settings/theme")
WardrikStore.put(mine, "settings/theme", "light", if_vsn: vsn)
```

Use this when two processes, or two nodes, might change the same key at once.

Once you write a key conditionally, keep writing it that way. EKV refuses an unconditional write
over it.

## Keep agents in it

`WardrikStore.Durable` keeps WardrikCore's agents in the same store as everything else, in its
`durable` scope:

```elixir
store = WardrikStore.Ecto.new(repo: MyApp.Repo)

children = [
  MyApp.Repo,
  {WardrikStore, store},
  {WardrikCore, backend: {WardrikStore.Durable, store: store}}
]
```

Use it over the Ecto or ETS store. It needs the `durable_server` dependency, which WardrikCore
already brings.

Over EKV, keep agents with DurableServer's own `EKVStore` instead, which is faster. The two can
share one EKV instance, since the store's keys sit under `wardrik_store/`:

```elixir
store = WardrikStore.EKV.new(name: :my_app)

children = [
  {EKV, name: :my_app, data_dir: "/var/lib/my_app", cluster_size: 1},
  {WardrikCore, backend: {DurableServer.Backends.EKVStore, name: :my_app}}
]
```

EKV is already in your children here, so leave the store out of them.

## Write an adapter

An adapter is a module that implements `WardrikStore.Adapter`, and a `new/1` that builds a store
with `WardrikStore.new(__MODULE__, config)`. Each callback gets that config, and a full path that
already holds the store's scopes:

| Callback | Does |
| --- | --- |
| `child_spec/1` | Returns the child that runs the adapter. |
| `put/4` | Writes a value, only over the version `if_vsn:` names. |
| `lookup/2` | Finds a value and its version, or returns `nil`. |
| `delete/3` | Removes a path, only at the version `if_vsn:` names. |
| `keys/2` | Lists every path that starts with a prefix. |
