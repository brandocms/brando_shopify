defmodule BrandoShopify.Workers.Bulk do
  @moduledoc false

  use Oban.Worker,
    queue: :shopify,
    max_attempts: 12,
    unique: [period: 86_400, keys: [:store, :operation_id]]

  alias BrandoShopify.Sync

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"operation_id" => operation_id, "store" => store}}) do
    case Sync.complete_bulk(operation_id, store: store) do
      {:error,
       %BrandoShopify.Error{
         kind: :invalid_response,
         details: %{"status" => status}
       } = error}
      when status in ["FAILED", "CANCELED", "EXPIRED"] ->
        {:discard, error}

      result ->
        result
    end
  end
end
