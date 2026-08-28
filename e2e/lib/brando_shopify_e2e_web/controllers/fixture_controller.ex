defmodule BrandoShopifyE2EWeb.FixtureController do
  @moduledoc false

  use BrandoShopifyE2EWeb, :controller

  alias BrandoShopify.Sync
  alias BrandoShopifyE2E.ShopifyMock

  def reset(conn, _params) do
    with false <- live?(),
         :ok <- ShopifyMock.reset(),
         {:ok, product} <- Sync.sync_product(ShopifyMock.product_id()),
         :ok <- ShopifyMock.clear_requests() do
      json(conn, %{
        product: %{id: product.shopify_id, handle: product.handle, title: product.title}
      })
    else
      true -> conn |> put_status(409) |> json(%{error: "mock reset is disabled in live mode"})
      {:error, error} -> conn |> put_status(502) |> json(%{error: inspect(error)})
    end
  end

  def update_product(conn, params) do
    if live?() do
      conn |> put_status(409) |> json(%{error: "mock mutation is disabled in live mode"})
    else
      {:ok, product} = ShopifyMock.update_product(params)
      json(conn, %{product: %{id: product["id"], title: product["title"]}})
    end
  end

  def state(conn, _params), do: json(conn, ShopifyMock.snapshot())

  def live_sync(conn, _params) do
    if live?() do
      product_id = System.fetch_env!("SHOPIFY_E2E_PRODUCT_ID")

      case Sync.sync_product(product_id) do
        {:ok, product} ->
          json(conn, %{
            product: %{id: product.shopify_id, handle: product.handle, title: product.title}
          })

        {:error, error} ->
          conn |> put_status(502) |> json(%{error: inspect(error)})
      end
    else
      conn |> put_status(409) |> json(%{error: "live sync is disabled in mock mode"})
    end
  end

  def checkout(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(
      200,
      "<!doctype html><html><body><main><h1>Shopify test checkout</h1><p>No payment is attempted.</p></main></body></html>"
    )
  end

  defp live?, do: Application.get_env(:brando_shopify_e2e, :shopify_live, false)
end
