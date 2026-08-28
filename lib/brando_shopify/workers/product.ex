defmodule BrandoShopify.Workers.Product do
  @moduledoc false

  # Uniqueness debounces bursts of duplicate webhooks for the same product.
  # `states` must exclude `:completed`, which Oban includes by default: a single
  # finished sync would otherwise block every later edit of that product for the
  # whole period.
  use Oban.Worker,
    queue: :shopify,
    max_attempts: 12,
    unique: [
      period: 30,
      keys: [:store, :product_id, :action],
      states: :incomplete
    ]

  alias BrandoShopify.Sync

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"action" => "sync", "product_id" => product_id, "store" => store}
      }) do
    Sync.sync_product(product_id, store: store)
  end

  def perform(%Oban.Job{
        args: %{"action" => "delete", "product_id" => product_id, "store" => store}
      }) do
    Sync.delete_product(product_id, store: store)
  end
end
