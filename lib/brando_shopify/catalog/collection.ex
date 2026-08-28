defmodule BrandoShopify.Catalog.Collection do
  @moduledoc "Read-only local projection of a Shopify collection."

  use Ecto.Schema

  import Ecto.Changeset

  alias BrandoShopify.Catalog.CollectionProduct
  alias BrandoShopify.Catalog.Product

  schema "shopify_collections" do
    field(:store, :string)
    field(:shopify_id, :string)
    field(:legacy_resource_id, :integer)
    field(:handle, :string)
    field(:title, :string)
    field(:description_html, :string)
    field(:image, :map)
    field(:seo, :map, default: %{})
    field(:remote_updated_at, :utc_datetime_usec)
    field(:synced_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    field(:source_data, :map, default: %{})

    many_to_many(:products, Product,
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
    :image,
    :seo,
    :remote_updated_at,
    :synced_at,
    :deleted_at,
    :source_data
  ]

  @doc false
  def changeset(collection, attrs) do
    collection
    |> cast(attrs, @fields)
    |> validate_required([:store, :shopify_id, :handle, :title])
    |> unique_constraint([:store, :shopify_id])
    |> unique_constraint([:store, :handle])
  end
end
