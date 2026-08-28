import Config

config :brando_shopify_e2e,
  ecto_repos: [BrandoShopifyE2E.Repo],
  sql_sandbox: true,
  shopify_live: System.get_env("SHOPIFY_E2E_LIVE") in ["1", "true"],
  assets_path: Path.expand("../../assets", __DIR__)

config :brando_shopify_e2e, BrandoShopifyE2EWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4455")],
  render_errors: [formats: [html: BrandoShopifyE2EWeb.ErrorHTML], layout: false],
  pubsub_server: BrandoShopifyE2E.PubSub,
  server: true,
  secret_key_base:
    System.get_env("SHOPIFY_E2E_SECRET_KEY_BASE") ||
      "zH6V7EtMvQ6rJZsY5o7jQ9wLxC2pK8uF4dN1aB3cG0iE6tR9yU5mS7vW2xP8kL4q"

config :brando_shopify_e2e, BrandoShopifyE2E.Repo,
  url:
    System.get_env("SHOPIFY_E2E_DATABASE_URL") ||
      "postgres://postgres:postgres@localhost/brando_shopify_e2e",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 20,
  queue_target: 5_000,
  queue_interval: 10_000

config :brando_shopify_e2e, BrandoShopifyE2E.Oban,
  name: BrandoShopifyE2E.Oban,
  repo: BrandoShopifyE2E.Repo,
  queues: false,
  plugins: false,
  testing: :inline

config :brando,
  env: :e2e,
  app_name: "BrandoShopifyE2E",
  otp_app: :brando_shopify_e2e,
  app_module: BrandoShopifyE2E,
  web_module: BrandoShopifyE2EWeb,
  repo_module: BrandoShopifyE2E.Repo,
  default_language: "en",
  languages: [[value: "en", text: "English"]],
  default_admin_language: "en",
  admin_languages: [[value: "en", text: "English"]],
  timezone: "Europe/Oslo",
  media_path: Path.expand("../tmp/media", __DIR__),
  media_url: "/media",
  use_default_errors: true

shopify_live? = System.get_env("SHOPIFY_E2E_LIVE") in ["1", "true"]

shopify_store =
  if shopify_live? do
    [
      shop_domain: System.fetch_env!("SHOPIFY_E2E_SHOP_DOMAIN"),
      storefront_domain:
        System.get_env("SHOPIFY_E2E_STOREFRONT_DOMAIN") ||
          System.fetch_env!("SHOPIFY_E2E_SHOP_DOMAIN"),
      api_version: System.get_env("SHOPIFY_E2E_API_VERSION") || "2026-07",
      admin_access_token: System.fetch_env!("SHOPIFY_E2E_ADMIN_TOKEN"),
      storefront_access_token: System.fetch_env!("SHOPIFY_E2E_STOREFRONT_TOKEN"),
      storefront_token_type: :private,
      webhook_secret: System.get_env("SHOPIFY_E2E_WEBHOOK_SECRET") || "live-webhooks-disabled",
      repo: BrandoShopifyE2E.Repo,
      oban_name: BrandoShopifyE2E.Oban,
      http: BrandoShopify.HTTP,
      catalog_contexts: [
        norway: [
          country: System.get_env("SHOPIFY_E2E_COUNTRY"),
          language: System.get_env("SHOPIFY_E2E_LANGUAGE")
        ]
      ]
    ]
  else
    [
      shop_domain: "brando-e2e.myshopify.com",
      storefront_domain: "brando-e2e.myshopify.com",
      api_version: "2026-07",
      admin_access_token: "e2e-admin-token",
      storefront_access_token: "e2e-storefront-token",
      storefront_token_type: :private,
      webhook_secret: "brando-e2e-webhook-secret",
      repo: BrandoShopifyE2E.Repo,
      oban_name: BrandoShopifyE2E.Oban,
      http: BrandoShopifyE2E.ShopifyMock,
      catalog_contexts: [
        norway: [country: "NO", language: "NB", sync_selling_plans: true]
      ]
    ]
  end

config :brando_shopify, stores: [default: shopify_store]

config :logger, level: :warning
config :phoenix, :json_library, Jason
