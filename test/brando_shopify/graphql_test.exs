defmodule BrandoShopify.GraphQLTest do
  use ExUnit.Case, async: true

  alias BrandoShopify.Cart
  alias BrandoShopify.Cart.Result
  alias BrandoShopify.Config
  alias BrandoShopify.Error
  alias BrandoShopify.GraphQL
  alias BrandoShopify.Plug.Cart, as: CartPlug

  defmodule FakeHTTP do
    @behaviour BrandoShopify.HTTP

    @impl true
    def request(options) do
      send(self(), {:shopify_request, options})

      case Process.get(:shopify_responses, []) do
        [response | rest] ->
          Process.put(:shopify_responses, rest)
          response

        [] ->
          {:ok, Req.Response.new(status: 200, body: %{"data" => %{}})}
      end
    end
  end

  setup do
    {:ok, config} =
      Config.new(:default,
        shop_domain: "demo.myshopify.com",
        admin_access_token: "admin-token",
        storefront_access_token: "private-token",
        storefront_token_type: :private
      )

    %{config: config}
  end

  test "uses private Storefront authentication and forwards buyer IP", %{config: config} do
    response =
      Req.Response.new(
        status: 200,
        headers: [
          {"x-request-id", "request-1"},
          {"x-shopify-api-version", "2026-07"}
        ],
        body: %{"data" => %{"shop" => %{"name" => "Demo"}}, "extensions" => %{"cost" => %{}}}
      )

    Process.put(:shopify_responses, [{:ok, response}])

    assert {:ok, result} =
             GraphQL.request(:storefront, "query Shop { shop { name } }", %{},
               config: config,
               http: FakeHTTP,
               buyer_ip: "203.0.113.5",
               operation_name: "Shop"
             )

    assert result.data["shop"]["name"] == "Demo"
    assert result.request_id == "request-1"
    assert result.api_version == "2026-07"

    assert_receive {:shopify_request, options}
    headers = options[:headers]
    assert {"shopify-storefront-private-token", "private-token"} in headers
    assert {"shopify-storefront-buyer-ip", "203.0.113.5"} in headers
    refute Enum.any?(headers, fn {name, _} -> name == "x-shopify-access-token" end)
  end

  test "turns GraphQL errors into structured errors", %{config: config} do
    response =
      Req.Response.new(
        status: 200,
        body: %{"data" => nil, "errors" => [%{"message" => "Access denied"}]}
      )

    Process.put(:shopify_responses, [{:ok, response}])

    assert {:error, %Error{kind: :graphql, message: "Access denied"}} =
             GraphQL.request(:admin, "query Product { product(id: \"x\") { id } }", %{},
               config: config,
               http: FakeHTTP
             )
  end

  test "creates a cart and strips its secret-bearing fields from the public view", %{
    config: config
  } do
    cart = %{
      "id" => "gid://shopify/Cart/abc?key=secret",
      "checkoutUrl" => "https://checkout.example/secret",
      "totalQuantity" => 1,
      "lines" => %{"nodes" => []}
    }

    response =
      Req.Response.new(
        status: 200,
        body: %{
          "data" => %{
            "cartCreate" => %{
              "cart" => cart,
              "userErrors" => [],
              "warnings" => [%{"code" => "NOTE", "message" => "Example"}]
            }
          }
        }
      )

    Process.put(:shopify_responses, [{:ok, response}])

    assert {:ok, %Result{cart: ^cart}} =
             Cart.create(
               [%{merchandise_id: "gid://shopify/ProductVariant/123", quantity: 1}],
               config: config,
               http: FakeHTTP,
               buyer_ip: "203.0.113.5"
             )

    public = Cart.public_view(cart)
    refute Map.has_key?(public, "id")
    refute Map.has_key?(public, "checkoutUrl")
    assert public["totalQuantity"] == 1

    assert_receive {:shopify_request, options}
    assert options[:json]["operationName"] == "BrandoCartCreate"

    assert get_in(options, [:json, "variables", "input", "lines"]) == [
             %{"merchandiseId" => "gid://shopify/ProductVariant/123", "quantity" => 1}
           ]
  end

  test "rejects oversized input before making an API call", %{config: config} do
    lines =
      for id <- 1..251 do
        %{merchandise_id: "gid://shopify/ProductVariant/#{id}", quantity: 1}
      end

    assert {:error, %Error{kind: :user, message: message}} =
             Cart.create(lines, config: config, http: FakeHTTP)

    assert message =~ "250"
    refute_received {:shopify_request, _}
  end

  test "encrypts the complete cart ID before it enters a browser session" do
    cart_id = "gid://shopify/Cart/abc?key=do-not-expose"
    secret_key_base = String.duplicate("secret-key-base-", 8)
    salt = "brando-shopify-cart-test"

    token = CartPlug.protect_cart_id(cart_id, secret_key_base, salt, 60)

    refute token =~ cart_id
    refute token =~ "do-not-expose"
    assert {:ok, ^cart_id} = CartPlug.unprotect_cart_id(token, secret_key_base, salt, 60)

    assert {:error, :invalid} =
             CartPlug.unprotect_cart_id(token <> "tampered", secret_key_base, salt, 60)
  end
end
