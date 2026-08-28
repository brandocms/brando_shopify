defmodule BrandoShopify.Workers.Inventory do
  @moduledoc false

  # Uniqueness debounces bursts of level updates for the same inventory item.
  # `states` must exclude `:completed`, which Oban includes by default: stock
  # would otherwise stop tracking for the whole period after each sync.
  use Oban.Worker,
    queue: :shopify,
    max_attempts: 10,
    unique: [
      period: 30,
      keys: [:store, :inventory_item_id],
      states: :incomplete
    ]

  alias BrandoShopify.Sync

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"store" => store, "inventory_item_id" => id}}) do
    case Sync.sync_inventory_item(id, store: store) do
      {:ok, _product} -> :ok
      :ok -> :ok
      {:error, error} -> {:error, inspect(error)}
    end
  end
end
