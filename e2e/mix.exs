defmodule BrandoShopifyE2E.MixProject do
  use Mix.Project

  def project do
    [
      app: :brando_shopify_e2e,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: false,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {BrandoShopifyE2E.Application, []},
      extra_applications: [:crypto, :logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      brando_dependency(),
      {:brando_shopify, path: "../"},
      {:bandit, "~> 1.0"},
      {:phoenix_ecto, "~> 4.0"},
      {:postgrex, "~> 0.20"}
    ]
  end

  # CI and a clean checkout exercise the actual next branch. BRANDO_PATH keeps
  # local package development fast while preserving the same dependency edge.
  defp brando_dependency do
    case System.get_env("BRANDO_PATH") do
      nil -> {:brando, github: "brandocms/brando", branch: "next"}
      path -> {:brando, path: Path.expand(path)}
    end
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
