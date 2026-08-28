defmodule BrandoShopify.Admin.DocumentsTest do
  use ExUnit.Case, async: true

  alias BrandoShopify.Admin.Documents

  test "full export is split to respect Shopify's five-connection bulk limit" do
    products = Documents.bulk_products_query()
    inventory = Documents.bulk_inventory_query()

    for connection <- ["products", "variants", "media", "collections", "metafields"] do
      assert products =~ "#{connection} {"
    end

    refute products =~ "inventoryLevels {"
    assert inventory =~ "inventoryItems {"
    assert inventory =~ "variants {"
    assert inventory =~ "inventoryLevels {"
  end

  test "ordinary product sync selects complete inventory metadata" do
    product = Documents.product()

    assert product =~ "inventoryItem {"
    assert product =~ "inventoryLevels(first: 250)"
    assert product =~ "quantities(names: [\"available\", \"on_hand\"])"
  end
end
