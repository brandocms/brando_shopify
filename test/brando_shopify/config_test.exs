defmodule BrandoShopify.ConfigTest do
  use ExUnit.Case, async: true

  alias BrandoShopify.Config

  test "normalizes domains and accepts runtime secret sources" do
    token = fn -> "storefront-token" end

    assert {:ok, config} =
             Config.new(:norway,
               shop_domain: "https://Demo-Store.myshopify.com/",
               storefront_domain: "https://shop.example.no/",
               admin_access_token: {__MODULE__, :admin_token, []},
               storefront_access_token: token,
               storefront_token_type: :private,
               catalog_contexts: [
                 norway: [country: :no, language: :nb],
                 united_states: [country: "us", language: "en", sync_selling_plans: true],
                 philippines: [country: "ph", language: "fil"]
               ],
               repo: __MODULE__
             )

    assert config.shop_domain == "demo-store.myshopify.com"
    assert config.storefront_domain == "shop.example.no"
    assert config.oban_name == Oban
    assert config.http == BrandoShopify.HTTP
    assert Config.resolve_secret(config.storefront_access_token) == "storefront-token"
    assert Config.resolve_secret(config.admin_access_token) == "admin-token"

    assert config.catalog_contexts == [
             %{key: "norway", country: "NO", language: "NB", sync_selling_plans: false},
             %{
               key: "united_states",
               country: "US",
               language: "EN",
               sync_selling_plans: true
             },
             %{key: "philippines", country: "PH", language: "FIL", sync_selling_plans: false}
           ]

    assert Config.endpoint(config, :admin) ==
             "https://demo-store.myshopify.com/admin/api/2026-07/graphql.json"

    assert Config.endpoint(config, :storefront) ==
             "https://shop.example.no/api/2026-07/graphql.json"
  end

  test "allows tokenless Storefront configuration" do
    assert {:ok, config} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :none
             )

    assert config.storefront_access_token == nil
  end

  test "normalizes string-keyed runtime maps at the configuration boundary" do
    assert {:ok, config} =
             Config.new("default", %{
               "shop_domain" => "demo.myshopify.com",
               "storefront_token_type" => :none,
               "repo" => __MODULE__,
               "catalog_contexts" => [
                 %{
                   "key" => "norway",
                   "country" => "no",
                   "language" => "nb",
                   "sync_selling_plans" => true
                 }
               ]
             })

    assert config.repo == __MODULE__

    assert config.catalog_contexts == [
             %{key: "norway", country: "NO", language: "NB", sync_selling_plans: true}
           ]
  end

  test "rejects missing private Storefront credentials" do
    assert {:error, :missing_storefront_access_token} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :private
             )
  end

  test "rejects unversioned and malformed API versions" do
    assert {:error, {:invalid_api_version, "latest"}} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               api_version: "latest",
               storefront_token_type: :none
             )
  end

  test "accepts an application-owned HTTP transport" do
    assert {:ok, config} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :none,
               http: __MODULE__
             )

    assert config.http == __MODULE__
  end

  test "rejects duplicate and malformed catalog contexts" do
    assert {:error, {:invalid_catalog_contexts, _contexts}} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :none,
               catalog_contexts: [norway: [country: "NOR"], norway: [country: "NO"]]
             )
  end

  test "a store is live unless it says otherwise" do
    assert {:ok, config} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :none
             )

    assert config.visibility == :live
    assert Config.resolve_visibility(config.visibility) == :live
  end

  test "accepts callable visibility sources" do
    assert {:ok, config} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :none,
               visibility: {__MODULE__, :preview_visibility, []}
             )

    assert Config.resolve_visibility(config.visibility) == :preview

    assert {:ok, config} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :none,
               visibility: fn -> :off end
             )

    assert Config.resolve_visibility(config.visibility) == :off
  end

  test "rejects an unknown visibility at configuration time" do
    assert {:error, {:invalid_visibility, :hidden}} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :none,
               visibility: :hidden
             )
  end

  def admin_token, do: "admin-token"
  def preview_visibility, do: :preview
end
