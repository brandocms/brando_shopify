defmodule BrandoShopify.Sync.Run do
  @moduledoc "Tracks full imports and reconciliation runs."

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "shopify_sync_runs" do
    field(:store, :string)
    field(:kind, Ecto.Enum, values: [:full, :reconcile, :product, :collection])
    field(:phase, Ecto.Enum, values: [:products, :inventory], default: :products)

    field(:status, Ecto.Enum,
      values: [:pending, :running, :completed, :failed, :cancelled],
      default: :pending
    )

    field(:shopify_operation_id, :string)
    field(:object_count, :integer, default: 0)
    field(:file_size, :integer)
    field(:error, :map)
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :store,
      :kind,
      :phase,
      :status,
      :shopify_operation_id,
      :object_count,
      :file_size,
      :error,
      :started_at,
      :completed_at
    ])
    |> validate_required([:store, :kind, :status])
    |> unique_constraint(:shopify_operation_id)
  end
end
