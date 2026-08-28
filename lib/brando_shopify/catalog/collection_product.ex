defmodule BrandoShopify.Catalog.CollectionProduct do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias BrandoShopify.Catalog.Collection
  alias BrandoShopify.Catalog.Product

  @primary_key false
  schema "shopify_collection_products" do
    field(:store, :string, primary_key: true)
    belongs_to(:collection, Collection, primary_key: true)
    belongs_to(:product, Product, primary_key: true)
    field(:position, :integer)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(join, attrs) do
    join
    |> cast(attrs, [:store, :collection_id, :product_id, :position])
    |> validate_required([:store, :collection_id, :product_id])
    |> unique_constraint([:store, :collection_id, :product_id])
  end
end
