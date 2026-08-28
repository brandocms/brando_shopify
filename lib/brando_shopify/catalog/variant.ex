defmodule BrandoShopify.Catalog.Variant do
  @moduledoc "Read-only local projection of a Shopify product variant."

  use Ecto.Schema

  import Ecto.Changeset

  alias BrandoShopify.Catalog.InventoryItem
  alias BrandoShopify.Catalog.Product

  schema "shopify_product_variants" do
    field(:store, :string)
    field(:shopify_id, :string)
    field(:legacy_resource_id, :integer)
    field(:title, :string)
    field(:display_name, :string)
    field(:sku, :string)
    field(:barcode, :string)
    field(:price, :decimal)
    field(:compare_at_price, :decimal)
    field(:currency_code, :string)
    field(:inventory_quantity, :integer)
    field(:inventory_policy, :string)
    field(:available_for_sale, :boolean)
    field(:requires_components, :boolean)
    field(:position, :integer)
    field(:taxable, :boolean)
    field(:selected_options, {:array, :map}, default: [])
    field(:image, :map)
    field(:metafields, {:array, :map}, default: [])
    field(:remote_created_at, :utc_datetime_usec)
    field(:remote_updated_at, :utc_datetime_usec)
    field(:synced_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    field(:source_data, :map, default: %{})

    belongs_to(:product, Product)
    has_one(:inventory_item, InventoryItem, where: [deleted_at: nil])
    has_one(:all_inventory_item, InventoryItem)

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :store,
    :shopify_id,
    :legacy_resource_id,
    :product_id,
    :title,
    :display_name,
    :sku,
    :barcode,
    :price,
    :compare_at_price,
    :currency_code,
    :inventory_quantity,
    :inventory_policy,
    :available_for_sale,
    :requires_components,
    :position,
    :taxable,
    :selected_options,
    :image,
    :metafields,
    :remote_created_at,
    :remote_updated_at,
    :synced_at,
    :deleted_at,
    :source_data
  ]

  @doc false
  def changeset(variant, attrs) do
    variant
    |> cast(attrs, @fields)
    |> validate_required([:store, :shopify_id, :product_id, :title])
    |> unique_constraint([:store, :shopify_id])
  end
end
