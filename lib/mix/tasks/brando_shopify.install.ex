defmodule Mix.Tasks.BrandoShopify.Install do
  @shortdoc "Installs the BrandoShopify catalog migration"

  @moduledoc """
  Copies the BrandoShopify migration into the host application's `priv/repo/migrations`.

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

    template =
      Application.app_dir(:brando_shopify, "priv/templates/brando_shopify.install/migration.exs")

    File.mkdir_p!(migrations_path)

    case Path.wildcard(Path.join(migrations_path, "*_create_shopify_catalog.exs")) do
      [] ->
        filename = "#{timestamp()}_create_shopify_catalog.exs"
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

  defp timestamp do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d%H%M%S")
  end
end
