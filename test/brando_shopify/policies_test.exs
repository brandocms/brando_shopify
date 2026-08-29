defmodule BrandoShopify.PoliciesTest do
  use ExUnit.Case, async: true

  alias BrandoShopify.Config
  alias BrandoShopify.Policies
  alias BrandoShopify.Storefront

  defp config!(policies) do
    {:ok, config} =
      Config.new(:default,
        shop_domain: "demo.myshopify.com",
        storefront_token_type: :none,
        policies: policies
      )

    config
  end

  defp full_config do
    config!(
      path: "vilkar/",
      locales: %{"no" => "nb", "en" => "en"},
      slugs: %{
        "no" => %{
          terms_of_service: "kjopsvilkar",
          refund_policy: "retur-og-angrerett",
          privacy_policy: "personvern"
        },
        "en" => %{terms_of_service: "purchase-terms", privacy_policy: "privacy"}
      }
    )
  end

  test "the path is normalized to one leading and no trailing slash" do
    assert full_config().policies.path == "/vilkar"
    assert config!(path: "/a/b/").policies.path == "/a/b"
    assert config!([]).policies.path == "/policies"
  end

  test "locales are upcased into Shopify language codes" do
    assert full_config().policies.locales == %{"no" => "NB", "en" => "EN"}
  end

  test "a slug containing a path separator is rejected" do
    assert {:error, {:invalid_policy_slugs, _}} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :none,
               policies: [
                 locales: %{"no" => "NB"},
                 slugs: %{"no" => %{privacy_policy: "vilkar/personvern"}}
               ]
             )
  end

  test "two policies cannot share a slug within one locale" do
    assert {:error, {:invalid_policy_slugs, _}} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :none,
               policies: [
                 locales: %{"no" => "NB"},
                 slugs: %{"no" => %{privacy_policy: "vilkar", terms_of_service: "vilkar"}}
               ]
             )
  end

  test "slugs for a locale with no Shopify language are rejected at boot" do
    assert {:error, {:policy_slugs_without_locale, ["da"]}} =
             Config.new(:default,
               shop_domain: "demo.myshopify.com",
               storefront_token_type: :none,
               policies: [
                 locales: %{"no" => "NB"},
                 slugs: %{"da" => %{privacy_policy: "privatliv"}}
               ]
             )
  end

  test "slugs resolve per locale, in both directions" do
    config = full_config()

    assert Policies.path(:privacy_policy, "no", config: config) == "/vilkar/personvern"
    assert Policies.path(:privacy_policy, "en", config: config) == "/vilkar/privacy"
    assert Policies.slug(:refund_policy, "no", config: config) == "retur-og-angrerett"

    assert Policies.type_for_slug("personvern", "no", config: config) == :privacy_policy
    assert Policies.type_for_slug("privacy", "en", config: config) == :privacy_policy
  end

  test "a slug from another locale does not resolve" do
    config = full_config()

    # "personvern" is Norwegian. Asking for it in English must miss, or an
    # English URL would serve a Norwegian document.
    assert Policies.type_for_slug("personvern", "en", config: config) == nil
    assert Policies.path(:refund_policy, "en", config: config) == nil
  end

  test "paths are listed in footer order" do
    assert Policies.paths("no", config: full_config()) == [
             {:terms_of_service, "/vilkar/kjopsvilkar"},
             {:refund_policy, "/vilkar/retur-og-angrerett"},
             {:privacy_policy, "/vilkar/personvern"}
           ]
  end

  test "configured locales are reported" do
    assert Policies.locales(config: full_config()) == ["en", "no"]
  end

  defmodule FallbackHTTP do
    @behaviour BrandoShopify.HTTP

    # What Shopify actually does for an unpublished locale: it answers with the
    # primary language and reports that in the context, without an error.
    @impl true
    def request(_options) do
      body = %{
        "data" => %{
          "shop" => %{
            "privacyPolicy" => %{
              "id" => "gid://shopify/ShopPolicy/1",
              "title" => "Privacy Policy",
              "body" => "<p>English text</p>",
              "url" => "https://checkout.shopify.com/1/policies/1.html",
              "handle" => "privacy-policy"
            },
            "refundPolicy" => nil,
            "shippingPolicy" => nil,
            "subscriptionPolicy" => nil,
            "termsOfService" => nil
          }
        },
        "extensions" => %{"context" => %{"language" => "EN"}}
      }

      {:ok, Req.Response.new(status: 200, body: body)}
    end
  end

  test "asking for an unpublished language fails instead of storing the fallback" do
    {:ok, config} =
      Config.new(:default,
        shop_domain: "demo.myshopify.com",
        storefront_token_type: :none,
        http: FallbackHTTP
      )

    assert {:error, error} = Storefront.shop_policies(config: config, language: "DA")

    assert error.kind == :invalid_response
    assert error.details.expected == %{"language" => "DA"}
    assert error.details.applied == %{"language" => "EN"}
  end

  test "a matching language is accepted and returns the policies" do
    {:ok, config} =
      Config.new(:default,
        shop_domain: "demo.myshopify.com",
        storefront_token_type: :none,
        http: FallbackHTTP
      )

    assert {:ok, shop} = Storefront.shop_policies(config: config, language: "EN")
    assert shop["privacyPolicy"]["title"] == "Privacy Policy"
    assert shop["refundPolicy"] == nil
  end
end
