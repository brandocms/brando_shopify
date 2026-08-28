defmodule BrandoShopify.Plug.WebhookTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias BrandoShopify.Plug.Webhook

  defmodule AcceptHandler do
    @behaviour BrandoShopify.Webhook.Handler

    @impl true
    def handle(metadata, payload, _config) do
      send(self(), {:accepted_webhook, metadata, payload})
      :ok
    end
  end

  setup do
    previous = Application.get_env(:brando_shopify, :stores)

    Application.put_env(:brando_shopify, :stores,
      default: [
        shop_domain: "demo.myshopify.com",
        storefront_token_type: :none,
        webhook_secret: "webhook-secret"
      ]
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:brando_shopify, :stores, previous)
      else
        Application.delete_env(:brando_shopify, :stores)
      end
    end)

    :ok
  end

  test "accepts an authentic raw request and exposes normalized metadata" do
    body = Jason.encode!(%{"id" => 123, "title" => "Product"})
    signature = signature(body)

    conn =
      conn(:post, "/shopify/webhooks", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-shopify-hmac-sha256", signature)
      |> put_req_header("x-shopify-shop-domain", "demo.myshopify.com")
      |> put_req_header("x-shopify-topic", "products/update")
      |> put_req_header("x-shopify-webhook-id", "webhook-1")
      |> put_req_header("x-shopify-event-id", "event-1")
      |> put_req_header("x-shopify-api-version", "2026-07")
      |> put_req_header("x-shopify-triggered-at", "2026-07-31T10:30:00Z")
      |> Webhook.call(
        Webhook.init(
          at: "/shopify/webhooks",
          store: :default,
          handler: AcceptHandler
        )
      )

    assert conn.status == 200
    assert conn.halted

    assert_receive {:accepted_webhook, metadata, %{"id" => 123}}
    assert metadata.webhook_id == "webhook-1"
    assert metadata.topic == "products/update"
    assert metadata.triggered_at == ~U[2026-07-31 10:30:00.000000Z]
  end

  test "rejects a bad signature before invoking the handler" do
    conn =
      conn(:post, "/shopify/webhooks", ~s({"id":123}))
      |> put_req_header("x-shopify-hmac-sha256", Base.encode64("wrong"))
      |> put_req_header("x-shopify-shop-domain", "demo.myshopify.com")
      |> put_req_header("x-shopify-topic", "products/update")
      |> put_req_header("x-shopify-webhook-id", "webhook-2")
      |> Webhook.call(
        Webhook.init(
          at: "/shopify/webhooks",
          store: :default,
          handler: AcceptHandler
        )
      )

    assert conn.status == 401
    refute_received {:accepted_webhook, _, _}
  end

  test "constant-time verifier validates a Shopify HMAC" do
    body = ~s({"hello":"shopify"})
    assert Webhook.valid_hmac?(body, signature(body), "webhook-secret")
    refute Webhook.valid_hmac?(body <> "!", signature(body), "webhook-secret")
  end

  defp signature(body) do
    :crypto.mac(:hmac, :sha256, "webhook-secret", body)
    |> Base.encode64()
  end
end
