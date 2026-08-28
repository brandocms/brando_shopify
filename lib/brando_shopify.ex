defmodule BrandoShopify do
  @moduledoc """
  Shopify commerce primitives for Brando CMS.

  `BrandoShopify` deliberately keeps Shopify as the commerce source of truth:

    * the Admin GraphQL API feeds a local, read-only catalog projection;
    * background Storefront GraphQL sync feeds explicit country/language
      projections, while live Storefront operations own carts and checkout;
    * Shopify webhooks drive low-latency sync and reconciliation jobs repair gaps.

  The package ships a server-side cart API and an optional, progressively enhanced
  cart element. The secret portion of a Shopify cart ID never needs to enter browser
  code.
  """

  alias BrandoShopify.Config
  alias BrandoShopify.GraphQL

  @api_version "2026-07"

  @doc "The Shopify API version this release targets."
  @spec api_version() :: String.t()
  def api_version, do: @api_version

  @doc "Loads and validates a named store from application configuration."
  @spec config(atom() | String.t()) :: {:ok, Config.t()} | {:error, term()}
  def config(store \\ :default), do: Config.fetch(store)

  @doc """
  Resolves whether a store is `:off`, in `:preview`, or `:live`.

  The state is resolved on every call rather than cached, because it lives
  wherever the host app put it — often the CMS, where someone flips it to launch
  the store without a deploy.

  An unconfigured store reports `:off`, so a missing configuration cannot open a
  storefront by accident.
  """
  @spec visibility(atom() | String.t()) :: Config.visibility()
  def visibility(store \\ :default) do
    case Config.fetch(store) do
      {:ok, config} -> Config.resolve_visibility(config.visibility)
      {:error, _reason} -> :off
    end
  end

  @doc """
  Whether a store is open to the public.

  This is what templates, navigation and sitemaps want; only
  `BrandoShopify.Plug.Visibility` needs the three states themselves.
  """
  @spec live?(atom() | String.t()) :: boolean()
  def live?(store \\ :default), do: visibility(store) == :live

  @doc "Executes a GraphQL Admin API operation."
  @spec admin_query(String.t(), map(), keyword()) ::
          {:ok, BrandoShopify.GraphQL.Response.t()} | {:error, BrandoShopify.Error.t()}
  def admin_query(document, variables \\ %{}, opts \\ []) do
    GraphQL.request(:admin, document, variables, opts)
  end

  @doc "Executes a GraphQL Storefront API operation."
  @spec storefront_query(String.t(), map(), keyword()) ::
          {:ok, BrandoShopify.GraphQL.Response.t()} | {:error, BrandoShopify.Error.t()}
  def storefront_query(document, variables \\ %{}, opts \\ []) do
    GraphQL.request(:storefront, document, variables, opts)
  end
end
