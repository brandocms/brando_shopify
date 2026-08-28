defmodule BrandoShopifyE2E.Repo.Migrations.AddContextInventory do
  use Ecto.Migration

  def change do
    alter table(:shopify_sync_runs) do
      add(:phase, :text, null: false, default: "products")
    end

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
  end
end
