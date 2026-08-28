defmodule BrandoShopify.Repo.Migrations.CreateShopifyCatalog do
  use Ecto.Migration

  def change do
    create table(:shopify_products) do
      add(:store, :text, null: false)
      add(:shopify_id, :text, null: false)
      add(:legacy_resource_id, :bigint)
      add(:handle, :text, null: false)
      add(:title, :text, null: false)
      add(:description_html, :text)
      add(:vendor, :text)
      add(:product_type, :text)
      add(:status, :text, null: false, default: "draft")
      add(:template_suffix, :text)
      add(:category, :map)
      add(:gift_card, :boolean)
      add(:combined_listing_role, :text)
      add(:requires_selling_plan, :boolean)
      add(:has_only_default_variant, :boolean)
      add(:has_out_of_stock_variants, :boolean)
      add(:has_variants_that_requires_components, :boolean)
      add(:online_store_url, :text)
      add(:tags, {:array, :text}, null: false, default: [])
      add(:options, {:array, :map}, null: false, default: [])
      add(:metafields, {:array, :map}, null: false, default: [])
      add(:seo, :map, null: false, default: %{})
      add(:featured_media, :map)
      add(:media, {:array, :map}, null: false, default: [])
      add(:min_price, :decimal)
      add(:max_price, :decimal)
      add(:currency_code, :text)
      add(:total_inventory, :integer)
      add(:tracks_inventory, :boolean)
      add(:published_at, :utc_datetime_usec)
      add(:remote_created_at, :utc_datetime_usec)
      add(:remote_updated_at, :utc_datetime_usec)
      add(:synced_at, :utc_datetime_usec, null: false)
      add(:deleted_at, :utc_datetime_usec)
      add(:source_data, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:shopify_products, [:store, :shopify_id]))
    create(unique_index(:shopify_products, [:store, :handle], where: "deleted_at IS NULL"))
    create(index(:shopify_products, [:store, :status], where: "deleted_at IS NULL"))
    create(index(:shopify_products, [:store, :remote_updated_at]))
    create(index(:shopify_products, [:store, :legacy_resource_id]))
    create(index(:shopify_products, [:tags], using: :gin))

    create table(:shopify_product_variants) do
      add(:store, :text, null: false)
      add(:shopify_id, :text, null: false)
      add(:legacy_resource_id, :bigint)
      add(:product_id, references(:shopify_products, on_delete: :delete_all), null: false)
      add(:title, :text, null: false)
      add(:display_name, :text)
      add(:sku, :text)
      add(:barcode, :text)
      add(:price, :decimal)
      add(:compare_at_price, :decimal)
      add(:currency_code, :text)
      add(:inventory_quantity, :integer)
      add(:inventory_policy, :text)
      add(:available_for_sale, :boolean)
      add(:requires_components, :boolean)
      add(:position, :integer)
      add(:taxable, :boolean)
      add(:selected_options, {:array, :map}, null: false, default: [])
      add(:image, :map)
      add(:metafields, {:array, :map}, null: false, default: [])
      add(:remote_created_at, :utc_datetime_usec)
      add(:remote_updated_at, :utc_datetime_usec)
      add(:synced_at, :utc_datetime_usec, null: false)
      add(:deleted_at, :utc_datetime_usec)
      add(:source_data, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:shopify_product_variants, [:store, :shopify_id]))
    create(index(:shopify_product_variants, [:product_id]))
    create(index(:shopify_product_variants, [:store, :sku]))
    create(index(:shopify_product_variants, [:store, :barcode]))

    create table(:shopify_inventory_items) do
      add(:store, :text, null: false)
      add(:shopify_id, :text, null: false)
      add(:legacy_resource_id, :bigint)

      add(:variant_id, references(:shopify_product_variants, on_delete: :delete_all), null: false)

      add(:sku, :text)
      add(:tracked, :boolean)
      add(:requires_shipping, :boolean)
      add(:remote_updated_at, :utc_datetime_usec)
      add(:synced_at, :utc_datetime_usec, null: false)
      add(:deleted_at, :utc_datetime_usec)
      add(:source_data, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:shopify_inventory_items, [:store, :shopify_id]))
    create(unique_index(:shopify_inventory_items, [:store, :variant_id]))
    create(index(:shopify_inventory_items, [:store, :legacy_resource_id]))

    create table(:shopify_inventory_levels) do
      add(:store, :text, null: false)

      add(:inventory_item_id, references(:shopify_inventory_items, on_delete: :delete_all),
        null: false
      )

      add(:shopify_id, :text, null: false)
      add(:location_shopify_id, :text, null: false)
      add(:location_legacy_resource_id, :bigint)
      add(:location_name, :text)
      add(:active, :boolean)
      add(:available, :integer)
      add(:on_hand, :integer)
      add(:quantities, :map, null: false, default: %{})
      add(:remote_updated_at, :utc_datetime_usec)
      add(:synced_at, :utc_datetime_usec, null: false)
      add(:deleted_at, :utc_datetime_usec)
      add(:source_data, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:shopify_inventory_levels, [
        :store,
        :inventory_item_id,
        :location_shopify_id
      ])
    )

    create(index(:shopify_inventory_levels, [:store, :location_shopify_id]))
    create(index(:shopify_inventory_levels, [:store, :location_legacy_resource_id]))

    create table(:shopify_product_contexts) do
      add(:store, :text, null: false)
      add(:context_key, :text, null: false)
      add(:country_code, :text)
      add(:language_code, :text)
      add(:shopify_id, :text, null: false)
      add(:product_id, references(:shopify_products, on_delete: :delete_all), null: false)
      add(:handle, :text, null: false)
      add(:title, :text, null: false)
      add(:description, :text)
      add(:description_html, :text)
      add(:vendor, :text)
      add(:product_type, :text)
      add(:available_for_sale, :boolean)
      add(:requires_selling_plan, :boolean)
      add(:seo, :map, null: false, default: %{})
      add(:featured_image, :map)
      add(:options, {:array, :map}, null: false, default: [])
      add(:min_price, :decimal)
      add(:max_price, :decimal)
      add(:currency_code, :text)
      add(:selling_plan_groups, {:array, :map}, null: false, default: [])
      add(:remote_updated_at, :utc_datetime_usec)
      add(:synced_at, :utc_datetime_usec, null: false)
      add(:deleted_at, :utc_datetime_usec)
      add(:source_data, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:shopify_product_contexts, [:store, :context_key, :product_id]))
    create(index(:shopify_product_contexts, [:store, :context_key, :shopify_id]))
    create(index(:shopify_product_contexts, [:store, :context_key, :handle]))

    create table(:shopify_product_context_variants) do
      add(:store, :text, null: false)
      add(:context_key, :text, null: false)
      add(:shopify_id, :text, null: false)

      add(:product_context_id, references(:shopify_product_contexts, on_delete: :delete_all),
        null: false
      )

      add(:variant_id, references(:shopify_product_variants, on_delete: :delete_all), null: false)
      add(:title, :text, null: false)
      add(:sku, :text)
      add(:available_for_sale, :boolean)
      add(:quantity_available, :integer)
      add(:requires_shipping, :boolean)
      add(:selected_options, {:array, :map}, null: false, default: [])
      add(:price, :decimal)
      add(:compare_at_price, :decimal)
      add(:currency_code, :text)
      add(:image, :map)
      add(:selling_plan_allocations, {:array, :map}, null: false, default: [])
      add(:synced_at, :utc_datetime_usec, null: false)
      add(:deleted_at, :utc_datetime_usec)
      add(:source_data, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:shopify_product_context_variants, [:store, :context_key, :shopify_id]))

    create(index(:shopify_product_context_variants, [:product_context_id]))
    create(index(:shopify_product_context_variants, [:variant_id]))

    create table(:shopify_collections) do
      add(:store, :text, null: false)
      add(:shopify_id, :text, null: false)
      add(:legacy_resource_id, :bigint)
      add(:handle, :text, null: false)
      add(:title, :text, null: false)
      add(:description_html, :text)
      add(:image, :map)
      add(:seo, :map, null: false, default: %{})
      add(:remote_updated_at, :utc_datetime_usec)
      add(:synced_at, :utc_datetime_usec, null: false)
      add(:deleted_at, :utc_datetime_usec)
      add(:source_data, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:shopify_collections, [:store, :shopify_id]))
    create(unique_index(:shopify_collections, [:store, :handle], where: "deleted_at IS NULL"))

    create table(:shopify_collection_products, primary_key: false) do
      add(:store, :text, primary_key: true)

      add(:collection_id, references(:shopify_collections, on_delete: :delete_all),
        primary_key: true
      )

      add(:product_id, references(:shopify_products, on_delete: :delete_all), primary_key: true)

      add(:position, :integer)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:shopify_collection_products, [:product_id]))

    create table(:shopify_sync_runs, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:store, :text, null: false)
      add(:kind, :text, null: false)
      add(:phase, :text, null: false, default: "products")
      add(:status, :text, null: false, default: "pending")
      add(:shopify_operation_id, :text)
      add(:object_count, :integer, null: false, default: 0)
      add(:file_size, :bigint)
      add(:error, :map)
      add(:started_at, :utc_datetime_usec)
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:shopify_sync_runs, [:shopify_operation_id],
        where: "shopify_operation_id IS NOT NULL"
      )
    )

    create(index(:shopify_sync_runs, [:store, :status, :completed_at]))

    create table(:shopify_webhook_receipts, primary_key: false) do
      add(:webhook_id, :text, primary_key: true)
      add(:event_id, :text)
      add(:store, :text, null: false)
      add(:shop_domain, :text)
      add(:topic, :text, null: false)
      add(:api_version, :text)
      add(:triggered_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:shopify_webhook_receipts, [:store, :inserted_at]))
    create(index(:shopify_webhook_receipts, [:event_id]))
  end
end
