defmodule BrandoShopify.Sync.Persister do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias BrandoShopify.Catalog.Collection
  alias BrandoShopify.Catalog.CollectionProduct
  alias BrandoShopify.Catalog.ContextVariant
  alias BrandoShopify.Catalog.InventoryItem
  alias BrandoShopify.Catalog.InventoryLevel
  alias BrandoShopify.Catalog.Product
  alias BrandoShopify.Catalog.ProductContext
  alias BrandoShopify.Catalog.Variant
  alias BrandoShopify.Sync.Mapper

  @doc "Atomically replaces the local projection of one complete product."
  def persist_product(repo, store, node) do
    repo.transaction(fn -> do_persist_product(repo, store, node) end)
  end

  defp do_persist_product(repo, store, node) do
    now = DateTime.utc_now()
    product_attrs = Mapper.product(store, node, now)
    product = upsert(repo, Product.changeset(%Product{}, product_attrs))
    variants = Mapper.nodes(node["variants"])
    collections = Mapper.nodes(node["collections"])

    {variant_ids, inventory_item_ids} =
      Enum.map_reduce(variants, [], fn variant_node, inventory_item_ids ->
        attrs = Mapper.variant(store, product.id, variant_node, product.currency_code, now)
        variant = upsert(repo, Variant.changeset(%Variant{}, attrs))

        case persist_inventory_item(repo, store, variant, variant_node["inventoryItem"], now) do
          nil -> {variant.shopify_id, inventory_item_ids}
          inventory_item_id -> {variant.shopify_id, [inventory_item_id | inventory_item_ids]}
        end
      end)

    tombstone_missing_variants(repo, product, variant_ids, now)
    tombstone_missing_inventory_items(repo, product, inventory_item_ids, now)

    collection_rows =
      Enum.map(collections, fn collection_node ->
        attrs = Mapper.collection(store, collection_node, now)
        collection = upsert(repo, Collection.changeset(%Collection{}, attrs))

        %{
          store: to_string(store),
          product_id: product.id,
          collection_id: collection.id,
          inserted_at: now
        }
      end)

    from(join in CollectionProduct,
      where: join.store == ^to_string(store) and join.product_id == ^product.id
    )
    |> repo.delete_all()

    if collection_rows != [] do
      repo.insert_all(CollectionProduct, collection_rows,
        on_conflict: :nothing,
        conflict_target: [:store, :collection_id, :product_id]
      )
    end

    product
  end

  @doc "Atomically replaces one locally configured Storefront context."
  def persist_product_context(repo, store, context, %Product{} = product, node) do
    repo.transaction(fn ->
      now = DateTime.utc_now()

      context_attrs = Mapper.product_context(store, context, product.id, node, now)

      product_context =
        upsert(
          repo,
          ProductContext.changeset(%ProductContext{}, context_attrs),
          [:store, :context_key, :product_id]
        )

      local_variants =
        from(variant in Variant,
          where:
            variant.store == ^to_string(store) and variant.product_id == ^product.id and
              is_nil(variant.deleted_at),
          select: {variant.shopify_id, variant.id}
        )
        |> repo.all()
        |> Map.new()

      context_variant_ids =
        node
        |> Map.get("variants", %{})
        |> Mapper.nodes()
        |> Enum.map(fn variant_node ->
          variant_id =
            Map.get(local_variants, variant_node["id"]) ||
              repo.rollback({:missing_local_variant, variant_node["id"]})

          attrs =
            Mapper.context_variant(
              store,
              context,
              product_context.id,
              variant_id,
              variant_node,
              now
            )

          upsert(
            repo,
            ContextVariant.changeset(%ContextVariant{}, attrs),
            [:store, :context_key, :shopify_id]
          ).shopify_id
        end)

      tombstone_missing_context_variants(repo, product_context, context_variant_ids, now)
      product_context
    end)
  end

  @doc "Tombstones a context that Shopify no longer publishes."
  def delete_product_context(repo, store, context_key, product_id) do
    now = DateTime.utc_now()

    repo.transaction(fn ->
      query =
        from(context in ProductContext,
          where:
            context.store == ^to_string(store) and context.context_key == ^to_string(context_key) and
              context.product_id == ^product_id
        )

      case repo.one(query) do
        nil ->
          :ok

        context ->
          from(variant in ContextVariant,
            where: variant.product_context_id == ^context.id and is_nil(variant.deleted_at)
          )
          |> repo.update_all(set: [deleted_at: now, synced_at: now])

          context
          |> ProductContext.changeset(%{deleted_at: now, synced_at: now})
          |> repo.update!()
      end
    end)
  end

  @doc "Persists one inventory bulk node against its locally synchronized variant."
  def persist_inventory_projection(repo, store, item_node, variant_ids, level_nodes) do
    repo.transaction(fn ->
      variant =
        from(variant in Variant,
          where:
            variant.store == ^to_string(store) and variant.shopify_id in ^variant_ids and
              is_nil(variant.deleted_at),
          order_by: [asc: variant.id],
          limit: 1
        )
        |> repo.one()

      if variant do
        now = DateTime.utc_now()
        node = Map.put(item_node, "inventoryLevels", %{"nodes" => level_nodes})
        persist_inventory_item(repo, store, variant, node, now)
      else
        :ok
      end
    end)
  end

  @doc "Tombstones inventory items absent from a completed inventory bulk export."
  def tombstone_inventory_synced_before(repo, store, cutoff) do
    now = DateTime.utc_now()

    repo.transaction(fn ->
      item_ids =
        from(item in InventoryItem,
          where:
            item.store == ^to_string(store) and item.synced_at < ^cutoff and
              is_nil(item.deleted_at),
          select: item.id
        )
        |> repo.all()

      {level_count, _} =
        from(level in InventoryLevel,
          where: level.inventory_item_id in ^item_ids and is_nil(level.deleted_at)
        )
        |> repo.update_all(set: [deleted_at: now, synced_at: now])

      {item_count, _} =
        from(item in InventoryItem, where: item.id in ^item_ids and is_nil(item.deleted_at))
        |> repo.update_all(set: [deleted_at: now, synced_at: now])

      %{inventory_items: item_count, inventory_levels: level_count}
    end)
  end

  @doc "Tombstones a product and its variants without breaking CMS references."
  def delete_product(repo, store, shopify_id) do
    now = DateTime.utc_now()

    repo.transaction(fn ->
      product_query =
        from(product in Product,
          where: product.store == ^to_string(store) and product.shopify_id == ^shopify_id
        )

      repo.update_all(product_query, set: [deleted_at: now, synced_at: now])

      from(variant in Variant,
        join: product in assoc(variant, :product),
        where: product.store == ^to_string(store) and product.shopify_id == ^shopify_id
      )
      |> repo.update_all(set: [deleted_at: now, synced_at: now])

      from(context in ProductContext,
        where: context.store == ^to_string(store) and context.shopify_id == ^shopify_id
      )
      |> repo.update_all(set: [deleted_at: now, synced_at: now])

      from(context_variant in ContextVariant,
        join: context in ProductContext,
        on: context_variant.product_context_id == context.id,
        where: context.store == ^to_string(store) and context.shopify_id == ^shopify_id
      )
      |> repo.update_all(set: [deleted_at: now, synced_at: now])

      tombstone_product_inventory(repo, store, shopify_id, now)
    end)
  end

  @doc "Replaces a collection and its complete local product membership."
  def persist_collection(repo, store, node) do
    repo.transaction(fn ->
      now = DateTime.utc_now()
      attrs = Mapper.collection(store, node, now)
      collection = upsert(repo, Collection.changeset(%Collection{}, attrs))
      product_ids = node["productIds"] || []

      local_products =
        from(product in Product,
          where:
            product.store == ^to_string(store) and product.shopify_id in ^product_ids and
              is_nil(product.deleted_at),
          select: product.id
        )
        |> repo.all()

      from(join in CollectionProduct,
        where: join.store == ^to_string(store) and join.collection_id == ^collection.id
      )
      |> repo.delete_all()

      rows =
        Enum.map(local_products, fn product_id ->
          %{
            store: to_string(store),
            collection_id: collection.id,
            product_id: product_id,
            inserted_at: now
          }
        end)

      if rows != [] do
        repo.insert_all(CollectionProduct, rows,
          on_conflict: :nothing,
          conflict_target: [:store, :collection_id, :product_id]
        )
      end

      collection
    end)
  end

  @doc "Tombstones a collection and removes its local membership."
  def delete_collection(repo, store, shopify_id) do
    now = DateTime.utc_now()

    repo.transaction(fn ->
      query =
        from(collection in Collection,
          where: collection.store == ^to_string(store) and collection.shopify_id == ^shopify_id
        )

      case repo.one(query) do
        nil ->
          :ok

        collection ->
          from(join in CollectionProduct,
            where: join.store == ^to_string(store) and join.collection_id == ^collection.id
          )
          |> repo.delete_all()

          collection
          |> Collection.changeset(%{deleted_at: now, synced_at: now})
          |> repo.update!()
      end
    end)
  end

  @doc """
  Tombstones active products absent from a completed full export.

  Every imported product receives a `synced_at` later than the run start.
  Products synchronized by a concurrent webhook are therefore preserved.
  """
  def tombstone_products_synced_before(repo, store, cutoff) do
    now = DateTime.utc_now()

    repo.transaction(fn ->
      stale_product_ids = stale_product_ids(repo, store, cutoff)
      context_counts = tombstone_stale_contexts(repo, stale_product_ids, now)
      inventory_counts = tombstone_stale_inventory(repo, stale_product_ids, now)

      Map.merge(context_counts, inventory_counts)
      |> Map.put(:variants, tombstone_stale_variants(repo, store, cutoff, now))
      |> Map.put(:products, tombstone_stale_products(repo, store, cutoff, now))
    end)
  end

  defp stale_product_ids(repo, store, cutoff) do
    from(product in Product,
      where:
        product.store == ^to_string(store) and product.synced_at < ^cutoff and
          is_nil(product.deleted_at),
      select: product.id
    )
    |> repo.all()
  end

  defp tombstone_stale_contexts(repo, product_ids, now) do
    context_ids =
      from(context in ProductContext,
        where: context.product_id in ^product_ids,
        select: context.id
      )
      |> repo.all()

    {context_variant_count, _} =
      from(variant in ContextVariant,
        where: variant.product_context_id in ^context_ids and is_nil(variant.deleted_at)
      )
      |> repo.update_all(set: [deleted_at: now, synced_at: now])

    {context_count, _} =
      from(context in ProductContext,
        where: context.id in ^context_ids and is_nil(context.deleted_at)
      )
      |> repo.update_all(set: [deleted_at: now, synced_at: now])

    %{contexts: context_count, context_variants: context_variant_count}
  end

  defp tombstone_stale_inventory(repo, product_ids, now) do
    item_ids =
      from(item in InventoryItem,
        join: variant in Variant,
        on: item.variant_id == variant.id,
        where: variant.product_id in ^product_ids,
        select: item.id
      )
      |> repo.all()

    {level_count, _} =
      from(level in InventoryLevel,
        where: level.inventory_item_id in ^item_ids and is_nil(level.deleted_at)
      )
      |> repo.update_all(set: [deleted_at: now, synced_at: now])

    {item_count, _} =
      from(item in InventoryItem,
        where: item.id in ^item_ids and is_nil(item.deleted_at)
      )
      |> repo.update_all(set: [deleted_at: now, synced_at: now])

    %{inventory_items: item_count, inventory_levels: level_count}
  end

  defp tombstone_stale_variants(repo, store, cutoff, now) do
    from(variant in Variant,
      join: product in Product,
      on: variant.product_id == product.id,
      where:
        product.store == ^to_string(store) and product.synced_at < ^cutoff and
          is_nil(product.deleted_at) and is_nil(variant.deleted_at)
    )
    |> repo.update_all(set: [deleted_at: now, synced_at: now])
    |> elem(0)
  end

  defp tombstone_stale_products(repo, store, cutoff, now) do
    from(product in Product,
      where:
        product.store == ^to_string(store) and product.synced_at < ^cutoff and
          is_nil(product.deleted_at)
    )
    |> repo.update_all(set: [deleted_at: now, synced_at: now])
    |> elem(0)
  end

  defp upsert(repo, changeset, conflict_target \\ [:store, :shopify_id]) do
    case repo.insert(changeset,
           on_conflict: {:replace_all_except, [:id, :inserted_at]},
           conflict_target: conflict_target,
           returning: true
         ) do
      {:ok, struct} -> struct
      {:error, changeset} -> repo.rollback(changeset)
    end
  end

  defp tombstone_missing_variants(repo, product, [], now) do
    from(variant in Variant,
      where:
        variant.store == ^product.store and variant.product_id == ^product.id and
          is_nil(variant.deleted_at)
    )
    |> repo.update_all(set: [deleted_at: now, synced_at: now])
  end

  defp tombstone_missing_variants(repo, product, variant_ids, now) do
    from(variant in Variant,
      where:
        variant.store == ^product.store and variant.product_id == ^product.id and
          variant.shopify_id not in ^variant_ids and is_nil(variant.deleted_at)
    )
    |> repo.update_all(set: [deleted_at: now, synced_at: now])
  end

  defp persist_inventory_item(_repo, _store, _variant, nil, _now), do: nil

  defp persist_inventory_item(repo, store, variant, node, now) when is_map(node) do
    attrs = Mapper.inventory_item(store, variant.id, node, now)

    item =
      upsert(
        repo,
        InventoryItem.changeset(%InventoryItem{}, attrs),
        [:store, :variant_id]
      )

    if Map.has_key?(node, "inventoryLevels") do
      levels = Mapper.nodes(node["inventoryLevels"])

      level_ids =
        Enum.map(levels, fn level_node ->
          attrs = Mapper.inventory_level(store, item.id, level_node, now)

          upsert(
            repo,
            InventoryLevel.changeset(%InventoryLevel{}, attrs),
            [:store, :inventory_item_id, :location_shopify_id]
          ).location_shopify_id
        end)

      tombstone_missing_inventory_levels(repo, item, level_ids, now)
    end

    item.shopify_id
  end

  defp tombstone_missing_inventory_items(repo, product, inventory_item_ids, now) do
    query =
      from(item in InventoryItem,
        join: variant in Variant,
        on: item.variant_id == variant.id,
        where:
          variant.product_id == ^product.id and item.store == ^product.store and
            is_nil(item.deleted_at)
      )

    query =
      if inventory_item_ids == [] do
        query
      else
        from(item in query, where: item.shopify_id not in ^inventory_item_ids)
      end

    stale_item_ids = from(item in query, select: item.id) |> repo.all()

    if stale_item_ids != [] do
      from(level in InventoryLevel, where: level.inventory_item_id in ^stale_item_ids)
      |> repo.update_all(set: [deleted_at: now, synced_at: now])

      repo.update_all(query, set: [deleted_at: now, synced_at: now])
    end
  end

  defp tombstone_missing_inventory_levels(repo, item, level_ids, now) do
    query =
      from(level in InventoryLevel,
        where: level.inventory_item_id == ^item.id and is_nil(level.deleted_at)
      )

    query =
      if level_ids == [] do
        query
      else
        from(level in query, where: level.location_shopify_id not in ^level_ids)
      end

    repo.update_all(query, set: [deleted_at: now, synced_at: now])
  end

  defp tombstone_missing_context_variants(repo, context, variant_ids, now) do
    query =
      from(variant in ContextVariant,
        where: variant.product_context_id == ^context.id and is_nil(variant.deleted_at)
      )

    query =
      if variant_ids == [] do
        query
      else
        from(variant in query, where: variant.shopify_id not in ^variant_ids)
      end

    repo.update_all(query, set: [deleted_at: now, synced_at: now])
  end

  defp tombstone_product_inventory(repo, store, shopify_id, now) do
    item_ids =
      from(item in InventoryItem,
        join: variant in Variant,
        on: item.variant_id == variant.id,
        join: product in Product,
        on: variant.product_id == product.id,
        where: product.store == ^to_string(store) and product.shopify_id == ^shopify_id,
        select: item.id
      )
      |> repo.all()

    if item_ids != [] do
      from(level in InventoryLevel, where: level.inventory_item_id in ^item_ids)
      |> repo.update_all(set: [deleted_at: now, synced_at: now])

      from(item in InventoryItem, where: item.id in ^item_ids)
      |> repo.update_all(set: [deleted_at: now, synced_at: now])
    end
  end
end
