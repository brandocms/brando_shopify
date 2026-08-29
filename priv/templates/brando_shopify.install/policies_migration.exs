defmodule BrandoShopify.Repo.Migrations.CreateShopifyPolicies do
  use Ecto.Migration

  def change do
    create table(:shopify_policies) do
      add(:store, :text, null: false)
      add(:type, :text, null: false)
      add(:locale, :text, null: false)
      add(:language_code, :text)
      add(:shopify_id, :text)
      add(:handle, :text)
      add(:title, :text, null: false)
      add(:body, :text, null: false)
      add(:shopify_url, :text)
      add(:synced_at, :utc_datetime_usec, null: false)
      add(:source_data, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:shopify_policies, [:store, :type, :locale]))
    create(index(:shopify_policies, [:store, :locale]))
  end
end
