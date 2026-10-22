# WardrikStore

A durable key-value store that Wardrik packages keep their data in.

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

EKV is optional. Add it only if you keep your data with it:

```elixir
{:ekv, "~> 0.4"}
```

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
{grant, vsn} = WardrikStore.lookup(vault, "github/jon")
WardrikStore.put(vault, "github/jon", refreshed(grant), if_vsn: vsn)
```

Once you write a key conditionally, keep writing it that way. EKV refuses an unconditional write
over it.

## Write an adapter

An adapter implements `WardrikStore.Adapter`.
