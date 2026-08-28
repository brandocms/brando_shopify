defmodule BrandoShopifyE2EWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :brando_shopify_e2e

  @session_options [
    store: :cookie,
    key: "_brando_shopify_e2e",
    signing_salt: "brando-shopify-e2e"
  ]

  plug Phoenix.Ecto.SQL.Sandbox,
    at: "/sandbox",
    repo: BrandoShopifyE2E.Repo,
    timeout: 60_000

  # Shopify signs the exact request bytes, so this must precede Plug.Parsers.
  plug BrandoShopify.Plug.Webhook,
    at: "/shopify/webhooks",
    store: :default

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug BrandoShopifyE2EWeb.Router
end
