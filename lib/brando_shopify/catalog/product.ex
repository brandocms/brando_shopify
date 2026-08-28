defmodule BrandoShopify.Catalog.Product do
  @moduledoc """
  Read-only local projection of a Shopify product.

  Commerce-owned fields are updated only by sync. Put Brando-authored editorial
  content in an application-owned Blueprint related by `product_id`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BrandoShopify.Catalog.Collection
  alias BrandoShopify.Catalog.CollectionProduct
  alias BrandoShopify.Catalog.ProductContext
  alias BrandoShopify.Catalog.Variant

  schema "shopify_products" do
    field(:store, :string)
    field(:shopify_id, :string)
    field(:legacy_resource_id, :integer)
    field(:handle, :string)
    field(:title, :string)
    field(:description_html, :string)
    field(:vendor, :string)
    field(:product_type, :string)
    field(:status, Ecto.Enum, values: [:active, :archived, :draft])
    field(:template_suffix, :string)
    field(:category, :map)
    field(:gift_card, :boolean)
    field(:combined_listing_role, :string)
    field(:requires_selling_plan, :boolean)
    field(:has_only_default_variant, :boolean)
    field(:has_out_of_stock_variants, :boolean)
    field(:has_variants_that_requires_components, :boolean)
    field(:online_store_url, :string)
    field(:tags, {:array, :string}, default: [])
    field(:options, {:array, :map}, default: [])
    field(:metafields, {:array, :map}, default: [])
    field(:seo, :map, default: %{})
    field(:featured_media, :map)
    field(:media, {:array, :map}, default: [])
    field(:min_price, :decimal)
    field(:max_price, :decimal)
    field(:currency_code, :string)
    field(:total_inventory, :integer)
    field(:tracks_inventory, :boolean)
    field(:published_at, :utc_datetime_usec)
    field(:remote_created_at, :utc_datetime_usec)
    field(:remote_updated_at, :utc_datetime_usec)
    field(:synced_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    field(:source_data, :map, default: %{})

    has_many(:variants, Variant, where: [deleted_at: nil])
    has_many(:all_variants, Variant)
    has_many(:contexts, ProductContext, where: [deleted_at: nil])
    has_many(:all_contexts, ProductContext)

    many_to_many(:collections, Collection,
      join_through: CollectionProduct,
      on_replace: :delete
    )

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :store,
    :shopify_id,
    :legacy_resource_id,
    :handle,
    :title,
    :description_html,
    :vendor,
    :product_type,
    :status,
    :template_suffix,
    :category,
    :gift_card,
    :combined_listing_role,
    :requires_selling_plan,
    :has_only_default_variant,
    :has_out_of_stock_variants,
    :has_variants_that_requires_components,
    :online_store_url,
    :tags,
    :options,
    :metafields,
    :seo,
    :featured_media,
    :media,
    :min_price,
    :max_price,
    :currency_code,
    :total_inventory,
    :tracks_inventory,
    :published_at,
    :remote_created_at,
    :remote_updated_at,
    :synced_at,
    :deleted_at,
    :source_data
  ]

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, @fields)
    |> validate_required([:store, :shopify_id, :handle, :title])
    |> unique_constraint([:store, :shopify_id])
    |> unique_constraint([:store, :handle])
  end
end
