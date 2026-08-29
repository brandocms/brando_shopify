defmodule BrandoShopify.MixProject do
  use Mix.Project

  @version "0.2.0-dev"
  @source_url "https://github.com/brandocms/brando_shopify"

  def project do
    [
      app: :brando_shopify,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A modern Shopify commerce integration for Brando CMS",
      package: package(),
      docs: docs(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {BrandoShopify.Application, []},
      extra_applications: [:crypto, :logger]
    ]
  end

  def cli do
    [preferred_envs: [quality: :test]]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:gettext, "~> 1.0"},
      {:html_sanitize_ex, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:oban, "~> 2.23"},
      {:phoenix_live_view, "~> 1.0"},
      {:plug, "~> 1.17"},
      {:postgrex, "~> 0.20 or ~> 1.0", optional: true},
      {:req, "~> 0.6"},
      {:telemetry, "~> 1.3"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :docs, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: [
        ".formatter.exs",
        "assets",
        "docs",
        "lib",
        "priv",
        "CHANGELOG.md",
        "LICENSE.md",
        "README.md",
        "mix.exs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "docs/architecture.md",
        "docs/brando-integration.md",
        "docs/cart.md",
        "docs/shopify-setup.md"
      ],
      groups_for_extras: [
        "Getting started": ["README.md", "docs/shopify-setup.md"],
        Guides: ["docs/brando-integration.md", "docs/cart.md"],
        Concepts: ["docs/architecture.md"]
      ]
    ]
  end

  defp aliases do
    [
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test"
      ]
    ]
  end
end
