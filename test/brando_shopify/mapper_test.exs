defmodule BrandoShopify.Sync.MapperTest do
  use ExUnit.Case, async: true

  alias BrandoShopify.Sync.Mapper

  test "maps the complete selected product graph into typed local attributes" do
    now = ~U[2026-07-31 09:00:00.000000Z]

    node = %{
      "id" => "gid://shopify/Product/1",
      "legacyResourceId" => "1",
      "handle" => "linen-shirt",
      "title" => "Linen shirt",
      "descriptionHtml" => "<p>Airy.</p>",
      "vendor" => "Brando",
      "productType" => "Shirts",
      "status" => "ACTIVE",
      "tags" => ["summer"],
      "priceRangeV2" => %{
        "minVariantPrice" => %{"amount" => "1200.00", "currencyCode" => "NOK"},
        "maxVariantPrice" => %{"amount" => "1400.00", "currencyCode" => "NOK"}
      },
      "metafields" => %{
        "nodes" => [
          %{"namespace" => "details", "key" => "material", "type" => "single_line_text_field"}
        ]
      },
      "media" => %{"nodes" => [%{"id" => "gid://shopify/MediaImage/2"}]},
      "collections" => %{"nodes" => [%{"id" => "gid://shopify/Collection/3"}]},
      "variants" => %{"nodes" => [%{"id" => "gid://shopify/ProductVariant/4"}]},
      "createdAt" => "2026-07-01T10:00:00Z",
      "updatedAt" => "2026-07-30T10:00:00Z"
    }

    attrs = Mapper.product(:default, node, now)

    assert attrs.shopify_id == "gid://shopify/Product/1"
    assert attrs.status == :active
    assert attrs.min_price == "1200.00"
    assert attrs.max_price == "1400.00"
    assert attrs.currency_code == "NOK"
    assert attrs.media == [%{"id" => "gid://shopify/MediaImage/2"}]
    assert hd(attrs.metafields)["key"] == "material"
    assert attrs.synced_at == now
    refute Map.has_key?(attrs.source_data, "variants")
    refute Map.has_key?(attrs.source_data, "media")
  end

  test "maps variant commerce identifiers and values" do
    attrs =
      Mapper.variant(
        :default,
        42,
        %{
          "id" => "gid://shopify/ProductVariant/4",
          "title" => "Blue / M",
          "sku" => "SHIRT-BL-M",
          "price" => "1200.00",
          "inventoryQuantity" => 8,
          "availableForSale" => true,
          "requiresComponents" => false,
          "selectedOptions" => [
            %{"name" => "Color", "value" => "Blue"},
            %{"name" => "Size", "value" => "M"}
          ]
        },
        "NOK"
      )

    assert attrs.product_id == 42
    assert attrs.sku == "SHIRT-BL-M"
    assert attrs.price == "1200.00"
    assert attrs.currency_code == "NOK"
    assert attrs.inventory_quantity == 8
    assert attrs.available_for_sale
    refute attrs.requires_components
    assert length(attrs.selected_options) == 2
  end

  test "maps contextual product, variant, and selling-plan values" do
    now = ~U[2026-08-01 09:00:00.000000Z]
    context = %{key: "norway", country: "NO", language: "NB", sync_selling_plans: true}

    node = %{
      "id" => "gid://shopify/Product/1",
      "handle" => "linen-shirt",
      "title" => "Linskjorte",
      "description" => "Luftig.",
      "descriptionHtml" => "<p>Luftig.</p>",
      "availableForSale" => true,
      "priceRange" => %{
        "minVariantPrice" => %{"amount" => "1299.00", "currencyCode" => "NOK"},
        "maxVariantPrice" => %{"amount" => "1499.00", "currencyCode" => "NOK"}
      },
      "sellingPlanGroups" => %{"nodes" => [%{"name" => "Abonner"}]},
      "variants" => %{
        "nodes" => [
          %{
            "id" => "gid://shopify/ProductVariant/4",
            "title" => "Blå",
            "price" => %{"amount" => "1299.00", "currencyCode" => "NOK"},
            "quantityAvailable" => 4,
            "sellingPlanAllocations" => %{"nodes" => [%{"sellingPlan" => %{"id" => "sp1"}}]}
          }
        ]
      },
      "updatedAt" => "2026-08-01T08:00:00Z"
    }

    attrs = Mapper.product_context(:default, context, 10, node, now)

    variant =
      Mapper.context_variant(:default, context, 20, 30, hd(node["variants"]["nodes"]), now)

    assert attrs.context_key == "norway"
    assert attrs.title == "Linskjorte"
    assert attrs.min_price == "1299.00"
    assert attrs.currency_code == "NOK"
    assert attrs.selling_plan_groups == [%{"name" => "Abonner"}]
    assert variant.price == "1299.00"
    assert variant.quantity_available == 4
    assert variant.selling_plan_allocations == [%{"sellingPlan" => %{"id" => "sp1"}}]
  end

  test "maps inventory items and location quantities" do
    now = ~U[2026-08-01 09:00:00.000000Z]

    item =
      Mapper.inventory_item(
        :default,
        42,
        %{
          "id" => "gid://shopify/InventoryItem/9",
          "legacyResourceId" => "9",
          "tracked" => true
        },
        now
      )

    level =
      Mapper.inventory_level(
        :default,
        11,
        %{
          "id" => "gid://shopify/InventoryLevel/8?inventory_item_id=9",
          "isActive" => true,
          "location" => %{
            "id" => "gid://shopify/Location/8",
            "legacyResourceId" => "8",
            "name" => "Oslo"
          },
          "quantities" => [
            %{"name" => "available", "quantity" => 7},
            %{"name" => "on_hand", "quantity" => 9}
          ]
        },
        now
      )

    assert item.variant_id == 42
    assert item.shopify_id == "gid://shopify/InventoryItem/9"
    assert level.location_name == "Oslo"
    assert level.available == 7
    assert level.on_hand == 9
  end
end
