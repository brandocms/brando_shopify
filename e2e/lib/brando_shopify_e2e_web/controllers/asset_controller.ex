defmodule BrandoShopifyE2EWeb.AssetController do
  use BrandoShopifyE2EWeb, :controller

  def cart_js(conn, _params), do: send_asset(conn, "js/cart.js", "text/javascript")
  def cart_css(conn, _params), do: send_asset(conn, "css/cart.css", "text/css")

  defp send_asset(conn, relative_path, content_type) do
    path =
      :brando_shopify_e2e
      |> Application.fetch_env!(:assets_path)
      |> Path.join(relative_path)

    conn
    |> put_resp_content_type(content_type)
    |> send_file(200, path)
  end
end
