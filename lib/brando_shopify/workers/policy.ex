defmodule BrandoShopify.Workers.Policy do
  @moduledoc false

  # Policies change rarely and there are at most five of them per locale, so
  # this refreshes all of them rather than tracking individual changes. There is
  # no policy webhook to react to, which is the other reason: the only way to
  # learn that a merchant edited their refund policy is to go and look.
  use Oban.Worker,
    queue: :shopify,
    max_attempts: 5,
    unique: [period: 300, keys: [:store], states: :incomplete]

  alias BrandoShopify.Policies

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"store" => store}}) do
    case Policies.sync(store: store) do
      {:ok, _tally} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
