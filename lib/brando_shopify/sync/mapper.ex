defmodule BrandoShopify.Sync.Mapper do
  @moduledoc false

  @doc "Maps an Admin GraphQL product into local projection attributes."
  def product(store, node, now \\ DateTime.utc_now()) do
    min_price = get_in(node, ["priceRangeV2", "minVariantPrice"])
    max_price = get_in(node, ["priceRangeV2", "maxVariantPrice"])

    %{
      store: to_string(store),
      shopify_id: node["id"],
      legacy_resource_id: node["legacyResourceId"],
      handle: node["handle"],
      title: node["title"],
      description_html: node["descriptionHtml"],
      vendor: node["vendor"],
      product_type: node["productType"],
      status: status(node["status"]),
      template_suffix: node["templateSuffix"],
      category: node["category"],
      gift_card: node["isGiftCard"],
      combined_listing_role: node["combinedListingRole"],
      requires_selling_plan: node["requiresSellingPlan"],
      has_only_default_variant: node["hasOnlyDefaultVariant"],
      has_out_of_stock_variants: node["hasOutOfStockVariants"],
      has_variants_that_requires_components: node["hasVariantsThatRequiresComponents"],
      online_store_url: node["onlineStoreUrl"],
      tags: node["tags"] || [],
      options: node["options"] || [],
      metafields: nodes(node["metafields"]),
      seo: node["seo"] || %{},
      featured_media: node["featuredMedia"],
      media: nodes(node["media"]),
      min_price: money_amount(min_price),
      max_price: money_amount(max_price),
      currency_code: money_currency(min_price) || money_currency(max_price),
      total_inventory: node["totalInventory"],
      tracks_inventory: node["tracksInventory"],
      published_at: datetime(node["publishedAt"]),
      remote_created_at: datetime(node["createdAt"]),
      remote_updated_at: datetime(node["updatedAt"]),
      synced_at: now,
      deleted_at: nil,
      source_data: Map.drop(node, ["variants", "media", "collections", "metafields"])
    }
  end

  @doc "Maps an Admin GraphQL variant into local projection attributes."
  def variant(store, product_id, node, currency_code, now \\ DateTime.utc_now()) do
    %{
      store: to_string(store),
      shopify_id: node["id"],
      legacy_resource_id: node["legacyResourceId"],
      product_id: product_id,
      title: node["title"],
      display_name: node["displayName"],
      sku: node["sku"],
      barcode: node["barcode"],
      price: node["price"],
      compare_at_price: node["compareAtPrice"],
      currency_code: currency_code,
      inventory_quantity: node["inventoryQuantity"],
      inventory_policy: node["inventoryPolicy"],
      available_for_sale: node["availableForSale"],
      requires_components: node["requiresComponents"],
      position: node["position"],
      taxable: node["taxable"],
      selected_options: node["selectedOptions"] || [],
      image: node["image"],
      metafields: nodes(node["metafields"]),
      remote_created_at: datetime(node["createdAt"]),
      remote_updated_at: datetime(node["updatedAt"]),
      synced_at: now,
      deleted_at: nil,
      source_data: Map.drop(node, ["inventoryItem"])
    }
  end

  @doc "Maps a Storefront product into one configured contextual projection."
  def product_context(store, context, product_id, node, now \\ DateTime.utc_now()) do
    min_price = get_in(node, ["priceRange", "minVariantPrice"])
    max_price = get_in(node, ["priceRange", "maxVariantPrice"])

    %{
      store: to_string(store),
      context_key: context.key,
      country_code: context.country,
      language_code: context.language,
      shopify_id: node["id"],
      product_id: product_id,
      handle: node["handle"],
      title: node["title"],
      description: node["description"],
      description_html: node["descriptionHtml"],
      vendor: node["vendor"],
      product_type: node["productType"],
      available_for_sale: node["availableForSale"],
      requires_selling_plan: node["requiresSellingPlan"],
      seo: node["seo"] || %{},
      featured_image: node["featuredImage"],
      options: node["options"] || [],
      min_price: money_amount(min_price),
      max_price: money_amount(max_price),
      currency_code: money_currency(min_price) || money_currency(max_price),
      selling_plan_groups: nodes(node["sellingPlanGroups"]),
      remote_updated_at: datetime(node["updatedAt"]),
      synced_at: now,
      deleted_at: nil,
      source_data: Map.drop(node, ["variants", "sellingPlanGroups"])
    }
  end

  @doc "Maps a Storefront variant into a contextual local variant."
  def context_variant(
        store,
        context,
        product_context_id,
        variant_id,
        node,
        now \\ DateTime.utc_now()
      ) do
    price = node["price"]
    compare_at_price = node["compareAtPrice"]

    %{
      store: to_string(store),
      context_key: context.key,
      shopify_id: node["id"],
      product_context_id: product_context_id,
      variant_id: variant_id,
      title: node["title"],
      sku: node["sku"],
      available_for_sale: node["availableForSale"],
      quantity_available: node["quantityAvailable"],
      requires_shipping: node["requiresShipping"],
      selected_options: node["selectedOptions"] || [],
      price: money_amount(price),
      compare_at_price: money_amount(compare_at_price),
      currency_code: money_currency(price) || money_currency(compare_at_price),
      image: node["image"],
      selling_plan_allocations: nodes(node["sellingPlanAllocations"]),
      synced_at: now,
      deleted_at: nil,
      source_data: Map.drop(node, ["sellingPlanAllocations"])
    }
  end

  @doc "Maps a Shopify inventory item attached to a local variant."
  def inventory_item(store, variant_id, node, now \\ DateTime.utc_now()) do
    %{
      store: to_string(store),
      shopify_id: node["id"],
      legacy_resource_id: node["legacyResourceId"],
      variant_id: variant_id,
      sku: node["sku"],
      tracked: node["tracked"],
      requires_shipping: node["requiresShipping"],
      remote_updated_at: datetime(node["updatedAt"]),
      synced_at: now,
      deleted_at: nil,
      source_data: Map.drop(node, ["inventoryLevels"])
    }
  end

  @doc "Maps one location-level inventory snapshot."
  def inventory_level(store, inventory_item_id, node, now \\ DateTime.utc_now()) do
    location = node["location"] || %{}
    quantities = quantity_map(node["quantities"] || [])

    %{
      store: to_string(store),
      shopify_id: node["id"],
      inventory_item_id: inventory_item_id,
      location_shopify_id: location["id"],
      location_legacy_resource_id: location["legacyResourceId"],
      location_name: location["name"],
      active: node["isActive"],
      available: quantities["available"],
      on_hand: quantities["on_hand"],
      quantities: quantities,
      remote_updated_at: datetime(node["updatedAt"]),
      synced_at: now,
      deleted_at: nil,
      source_data: node
    }
  end

  @doc "Maps an Admin GraphQL collection into local projection attributes."
  def collection(store, node, now \\ DateTime.utc_now()) do
    %{
      store: to_string(store),
      shopify_id: node["id"],
      legacy_resource_id: node["legacyResourceId"],
      handle: node["handle"],
      title: node["title"],
      description_html: node["descriptionHtml"],
      image: node["image"],
      seo: node["seo"] || %{},
      remote_updated_at: datetime(node["updatedAt"]),
      synced_at: now,
      deleted_at: nil,
      source_data: node
    }
  end

  def nodes(nil), do: []
  def nodes(nodes) when is_list(nodes), do: nodes
  def nodes(%{"nodes" => nodes}) when is_list(nodes), do: nodes

  def nodes(%{"edges" => edges}) when is_list(edges) do
    Enum.map(edges, & &1["node"])
  end

  def nodes(_), do: []

  defp quantity_map(quantities) do
    Map.new(quantities, fn quantity ->
      {quantity["name"], quantity["quantity"]}
    end)
  end

  defp status("ACTIVE"), do: :active
  defp status("ARCHIVED"), do: :archived
  defp status("DRAFT"), do: :draft
  defp status(:active), do: :active
  defp status(:archived), do: :archived
  defp status(:draft), do: :draft
  defp status(_), do: :draft

  defp money_amount(%{"amount" => amount}), do: amount
  defp money_amount(_), do: nil

  defp money_currency(%{"currencyCode" => code}), do: code
  defp money_currency(_), do: nil

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = datetime), do: datetime

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end
end
