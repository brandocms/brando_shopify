defmodule BrandoShopifyE2E.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BrandoShopifyE2E.Repo,
      BrandoShopifyE2E.ShopifyMock,
      {Phoenix.PubSub, name: BrandoShopifyE2E.PubSub},
      {Oban, Application.fetch_env!(:brando_shopify_e2e, BrandoShopifyE2E.Oban)},
      BrandoShopifyE2EWeb.Endpoint
    ]

    result =
      Supervisor.start_link(children,
        strategy: :one_for_one,
        name: BrandoShopifyE2E.Supervisor
      )

    if Application.get_env(:brando_shopify_e2e, :sql_sandbox, false) do
      Ecto.Adapters.SQL.Sandbox.mode(BrandoShopifyE2E.Repo, :auto)
    end

    result
  end

  @impl true
  def config_change(changed, _new, removed) do
    BrandoShopifyE2EWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
