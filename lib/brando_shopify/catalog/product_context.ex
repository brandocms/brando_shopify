defmodule BrandoShopify.Catalog.ProductContext do
  @moduledoc """
  A locally persisted Storefront API view for one configured buyer context.

  Context records hold translated presentation and country-aware catalog values.
  They are populated by synchronization and are never fetched implicitly while a
  template renders.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BrandoShopify.Catalog.ContextVariant
  alias BrandoShopify.Catalog.Product

  schema "shopify_product_contexts" do
    field(:store, :string)
    field(:context_key, :string)
    field(:country_code, :string)
    field(:language_code, :string)
    field(:shopify_id, :string)
    field(:handle, :string)
    field(:title, :string)
    field(:description, :string)
    field(:description_html, :string)
    field(:vendor, :string)
    field(:product_type, :string)
    field(:available_for_sale, :boolean)
    field(:requires_selling_plan, :boolean)
    field(:seo, :map, default: %{})
    field(:featured_image, :map)
    field(:options, {:array, :map}, default: [])
    field(:min_price, :decimal)
    field(:max_price, :decimal)
    field(:currency_code, :string)
    field(:selling_plan_groups, {:array, :map}, default: [])
    field(:remote_updated_at, :utc_datetime_usec)
    field(:synced_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    field(:source_data, :map, default: %{})

    belongs_to(:product, Product)
    has_many(:variants, ContextVariant, where: [deleted_at: nil])
    has_many(:all_variants, ContextVariant)
    has_many(:collections, through: [:product, :collections])

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :store,
    :context_key,
    :country_code,
    :language_code,
    :shopify_id,
    :product_id,
    :handle,
    :title,
    :description,
    :description_html,
    :vendor,
    :product_type,
    :available_for_sale,
    :requires_selling_plan,
    :seo,
    :featured_image,
    :options,
    :min_price,
    :max_price,
    :currency_code,
    :selling_plan_groups,
    :remote_updated_at,
    :synced_at,
    :deleted_at,
    :source_data
  ]

  @doc false
  def changeset(context, attrs) do
    context
    |> cast(attrs, @fields)
    |> validate_required([
      :store,
      :context_key,
      :shopify_id,
      :product_id,
      :handle,
      :title,
      :synced_at
    ])
    |> unique_constraint([:store, :context_key, :product_id])
  end
end
