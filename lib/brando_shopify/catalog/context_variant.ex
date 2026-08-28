defmodule BrandoShopify.Catalog.ContextVariant do
  @moduledoc "A contextual, locally persisted Storefront view of a product variant."

  use Ecto.Schema

  import Ecto.Changeset

  alias BrandoShopify.Catalog.ProductContext
  alias BrandoShopify.Catalog.Variant

  schema "shopify_product_context_variants" do
    field(:store, :string)
    field(:context_key, :string)
    field(:shopify_id, :string)
    field(:title, :string)
    field(:sku, :string)
    field(:available_for_sale, :boolean)
    field(:quantity_available, :integer)
    field(:requires_shipping, :boolean)
    field(:selected_options, {:array, :map}, default: [])
    field(:price, :decimal)
    field(:compare_at_price, :decimal)
    field(:currency_code, :string)
    field(:image, :map)
    field(:selling_plan_allocations, {:array, :map}, default: [])
    field(:synced_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    field(:source_data, :map, default: %{})

    belongs_to(:product_context, ProductContext)
    belongs_to(:variant, Variant)
    has_one(:inventory_item, through: [:variant, :inventory_item])

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :store,
    :context_key,
    :shopify_id,
    :product_context_id,
    :variant_id,
    :title,
    :sku,
    :available_for_sale,
    :quantity_available,
    :requires_shipping,
    :selected_options,
    :price,
    :compare_at_price,
    :currency_code,
    :image,
    :selling_plan_allocations,
    :synced_at,
    :deleted_at,
    :source_data
  ]

  @doc false
  def changeset(variant, attrs) do
    variant
    |> cast(attrs, @fields)
    |> validate_required([
      :store,
      :context_key,
      :shopify_id,
      :product_context_id,
      :variant_id,
      :title,
      :synced_at
    ])
    |> unique_constraint([:store, :context_key, :shopify_id])
  end
end
