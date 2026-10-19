defmodule BrandoShopify.Repo.Migrations.CreateShopifySettings do
  use Ecto.Migration

  # One row per configured store: what an administrator can change without a
  # deploy. A store with no row uses its configuration's values.
  def change do
    create table(:shopify_settings, primary_key: false) do
      add(:store, :text, primary_key: true)
      add(:visibility, :text)
      # In order: a product in two partner collections belongs to the first.
      add(:partner_collections, {:array, :text}, null: false, default: [])

      timestamps(type: :utc_datetime_usec)
    end
  end
end
