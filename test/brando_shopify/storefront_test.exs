defmodule BrandoShopify.StorefrontTest do
  use ExUnit.Case, async: true

  alias BrandoShopify.Config
  alias BrandoShopify.Storefront

  defmodule ContextMismatchHTTP do
    @behaviour BrandoShopify.HTTP

    @impl true
    def request(_options) do
      body = %{
        "data" => %{
          "product" => %{
            "id" => "gid://shopify/Product/1",
            "variants" => %{
              "nodes" => [],
              "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
            }
          }
        },
        "extensions" => %{"context" => %{"country" => "US", "language" => "EN"}}
      }

      {:ok, Req.Response.new(status: 200, body: body)}
    end
  end

  test "context sync rejects a response applied to a different country or language" do
    assert {:ok, config} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :none,
               http: ContextMismatchHTTP
             )

    assert {:error, error} =
             Storefront.product_by_id("gid://shopify/Product/1",
               config: config,
               country: "NO",
               language: "NB"
             )

    assert error.kind == :invalid_response
    assert error.details.expected == %{"country" => "NO", "language" => "NB"}
    assert error.details.applied == %{"country" => "US", "language" => "EN"}
  end
end
