defmodule BrandoShopify.Catalog.InventoryLevel do
  @moduledoc "A locally synchronized inventory item quantity at one Shopify location."

  use Ecto.Schema

  import Ecto.Changeset

  alias BrandoShopify.Catalog.InventoryItem

  schema "shopify_inventory_levels" do
    field(:store, :string)
    field(:shopify_id, :string)
    field(:location_shopify_id, :string)
    field(:location_legacy_resource_id, :integer)
    field(:location_name, :string)
    field(:active, :boolean)
    field(:available, :integer)
    field(:on_hand, :integer)
    field(:quantities, :map, default: %{})
    field(:remote_updated_at, :utc_datetime_usec)
    field(:synced_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    field(:source_data, :map, default: %{})

    belongs_to(:inventory_item, InventoryItem)

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :store,
    :shopify_id,
    :inventory_item_id,
    :location_shopify_id,
    :location_legacy_resource_id,
    :location_name,
    :active,
    :available,
    :on_hand,
    :quantities,
    :remote_updated_at,
    :synced_at,
    :deleted_at,
    :source_data
  ]

  @doc false
  def changeset(level, attrs) do
    level
    |> cast(attrs, @fields)
    |> validate_required([
      :store,
      :shopify_id,
      :inventory_item_id,
      :location_shopify_id,
      :synced_at
    ])
    |> unique_constraint([:store, :inventory_item_id, :location_shopify_id])
  end
end
