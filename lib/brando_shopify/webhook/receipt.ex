defmodule BrandoShopify.Webhook.Receipt do
  @moduledoc "Persistent idempotency record for a Shopify webhook delivery."

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:webhook_id, :string, autogenerate: false}
  schema "shopify_webhook_receipts" do
    field(:event_id, :string)
    field(:store, :string)
    field(:shop_domain, :string)
    field(:topic, :string)
    field(:api_version, :string)
    field(:triggered_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [
      :webhook_id,
      :event_id,
      :store,
      :shop_domain,
      :topic,
      :api_version,
      :triggered_at
    ])
    |> validate_required([:webhook_id, :store, :topic])
    |> unique_constraint(:webhook_id)
  end
end
