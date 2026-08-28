defmodule BrandoShopify.Webhook.Handler do
  @moduledoc "Callback contract for accepted, verified Shopify webhooks."

  alias BrandoShopify.Config

  @callback handle(map(), map(), Config.t()) ::
              :ok | :duplicate | :ignored | {:error, term()}
end
