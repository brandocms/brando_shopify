defmodule BrandoShopify.Workers.Collection do
  @moduledoc false

  # Uniqueness debounces bursts of duplicate webhooks for the same collection.
  # `states` must exclude `:completed`, which Oban includes by default: a single
  # finished sync would otherwise block every later change to that collection
  # for the whole period.
  use Oban.Worker,
    queue: :shopify,
    max_attempts: 12,
    unique: [
      period: 30,
      keys: [:store, :collection_id, :action],
      states: :incomplete
    ]

  alias BrandoShopify.Sync

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"action" => "sync", "collection_id" => collection_id, "store" => store}
      }) do
    Sync.sync_collection(collection_id, store: store)
  end

  def perform(%Oban.Job{
        args: %{"action" => "delete", "collection_id" => collection_id, "store" => store}
      }) do
    Sync.delete_collection(collection_id, store: store)
  end
end
