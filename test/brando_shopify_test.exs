defmodule BrandoShopifyTest do
  use ExUnit.Case, async: true

  test "targets Shopify's current stable API version" do
    assert BrandoShopify.api_version() == "2026-07"
  end
end
