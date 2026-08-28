defmodule BrandoShopifyE2EWeb.ProductController do
  use BrandoShopifyE2EWeb, :controller

  alias BrandoShopify.Catalog

  def show(conn, %{"handle" => handle}) do
    case Catalog.get_contextual_product_by_handle(handle, :norway, preload: [:variants, :product]) do
      nil ->
        send_resp(conn, 404, "Shopify product not found in the local projection")

      product ->
        conn
        |> assign(:product, product)
        |> assign(:variant, Enum.find(product.variants, &is_nil(&1.deleted_at)))
        |> render(:show)
    end
  end
end
