defmodule BrandoShopify.Workers.Reconcile do
  @moduledoc false

  use Oban.Worker,
    queue: :shopify,
    max_attempts: 5,
    unique: [period: 3_600, keys: [:store]]

  alias BrandoShopify.Sync

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"store" => store} = args}) do
    since =
      case args["since"] do
        nil -> Sync.last_completed_at(store: store) || DateTime.add(DateTime.utc_now(), -86_400)
        iso8601 -> iso8601
      end

    Sync.reconcile(since, store: store)
  end
end
