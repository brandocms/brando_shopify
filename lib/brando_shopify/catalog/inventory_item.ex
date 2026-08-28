defmodule BrandoShopify.Catalog.InventoryItem do
  @moduledoc "A locally synchronized Shopify inventory item."

  use Ecto.Schema

  import Ecto.Changeset

  alias BrandoShopify.Catalog.InventoryLevel
  alias BrandoShopify.Catalog.Variant

  schema "shopify_inventory_items" do
    field(:store, :string)
    field(:shopify_id, :string)
    field(:legacy_resource_id, :integer)
    field(:sku, :string)
    field(:tracked, :boolean)
    field(:requires_shipping, :boolean)
    field(:remote_updated_at, :utc_datetime_usec)
    field(:synced_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    field(:source_data, :map, default: %{})

    belongs_to(:variant, Variant)
    has_many(:levels, InventoryLevel, where: [deleted_at: nil])
    has_many(:all_levels, InventoryLevel)

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :store,
    :shopify_id,
    :legacy_resource_id,
    :variant_id,
    :sku,
    :tracked,
    :requires_shipping,
    :remote_updated_at,
    :synced_at,
    :deleted_at,
    :source_data
  ]

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, @fields)
    |> validate_required([:store, :shopify_id, :variant_id, :synced_at])
    |> unique_constraint([:store, :shopify_id])
    |> unique_constraint([:store, :variant_id])
  end
end
