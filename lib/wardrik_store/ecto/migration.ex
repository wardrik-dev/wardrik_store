if Code.ensure_loaded?(Ecto.Migration) do
  defmodule WardrikStore.Ecto.Migration do
    @moduledoc """
    Creates the table `WardrikStore.Ecto` keeps its keys in, from a migration of your own.

        defmodule MyApp.Repo.Migrations.AddWardrikStore do
          use Ecto.Migration

          def up, do: WardrikStore.Ecto.Migration.up(version: 1)
          def down, do: WardrikStore.Ecto.Migration.down(version: 1)
        end

    Each version is a step in the table's shape. A later release adds a version, and you add a
    migration that runs it.
    """

    use Ecto.Migration

    @versions [1]

    @doc "Creates what `version` needs."
    @spec up(keyword()) :: :ok
    def up(opts) do
      opts |> version() |> change(:up)
      :ok
    end

    @doc "Drops what `version` created."
    @spec down(keyword()) :: :ok
    def down(opts) do
      opts |> version() |> change(:down)
      :ok
    end

    defp version(opts) do
      version = Keyword.fetch!(opts, :version)

      if version in @versions,
        do: version,
        else:
          raise(ArgumentError, "WardrikStore.Ecto.Migration has no version #{inspect(version)}")
    end

    defp change(1, :up) do
      execute("""
      CREATE TABLE IF NOT EXISTS wardrik_store (
        key text COLLATE "C" PRIMARY KEY,
        value bytea NOT NULL,
        vsn bigint NOT NULL
      )
      """)
    end

    defp change(1, :down), do: execute("DROP TABLE IF EXISTS wardrik_store")
  end
end
