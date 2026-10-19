defmodule Mix.Tasks.BrandoShopify.Install do
  @shortdoc "Installs the BrandoShopify migrations"

  @moduledoc """
  Copies the BrandoShopify migrations into the host application's
  `priv/repo/migrations`: the catalogue, the legal policies and the store
  settings. A migration already there is left alone, so rerunning the task after
  an upgrade adds only the new ones.

      mix brando_shopify.install

  A separate migration path is useful for package integration tests:

      mix brando_shopify.install --migrations-path priv/shopify_migrations
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args, strict: [migrations_path: :string])

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    migrations_path =
      opts[:migrations_path] ||
        Mix.Project.project_file()
        |> Path.dirname()
        |> Path.join("priv/repo/migrations")

    File.mkdir_p!(migrations_path)

    # Ordered oldest first. Each is copied only when the host does not already
    # have it, so running the task again after upgrading the package picks up
    # new tables without disturbing migrations that have already run. The
    # index offsets the timestamp so a fresh install orders them correctly.
    [
      {"migration.exs", "create_shopify_catalog"},
      {"policies_migration.exs", "create_shopify_policies"},
      {"settings_migration.exs", "create_shopify_settings"}
    ]
    |> Enum.with_index()
    |> Enum.each(fn {{template_name, migration_name}, index} ->
      install_migration(migrations_path, template_name, migration_name, index)
    end)
  end

  defp install_migration(migrations_path, template_name, migration_name, offset) do
    template =
      Application.app_dir(
        :brando_shopify,
        "priv/templates/brando_shopify.install/#{template_name}"
      )

    case Path.wildcard(Path.join(migrations_path, "*_#{migration_name}.exs")) do
      [] ->
        filename = "#{timestamp(offset)}_#{migration_name}.exs"
        destination = Path.join(migrations_path, filename)
        File.cp!(template, destination)
        Mix.shell().info([:green, "* creating ", :reset, Path.relative_to_cwd(destination)])

      [existing | _] ->
        Mix.shell().info([
          :yellow,
          "* already installed ",
          :reset,
          Path.relative_to_cwd(existing)
        ])
    end
  end

  defp timestamp(offset) do
    DateTime.utc_now()
    |> DateTime.add(offset, :second)
    |> Calendar.strftime("%Y%m%d%H%M%S")
  end
end
