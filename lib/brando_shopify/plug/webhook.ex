defmodule BrandoShopify.Plug.Webhook do
  @moduledoc """
  Verifies and accepts Shopify HTTPS webhooks.

  Mount this plug before `Plug.Parsers`; HMAC verification requires the exact raw
  request body. Accepted events are persisted and enqueued by the configured
  handler before a `200` response is returned.

      plug BrandoShopify.Plug.Webhook,
        at: "/shopify/webhooks",
        store: :default

      plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], json_decoder: Jason
  """

  import Plug.Conn

  require Logger

  alias BrandoShopify.Config
  alias BrandoShopify.Webhook.DefaultHandler

  @max_body 2_000_000

  def init(opts) do
    %{
      at: Keyword.get(opts, :at, "/shopify/webhooks"),
      store: Keyword.get(opts, :store, :default),
      handler: Keyword.get(opts, :handler, DefaultHandler),
      max_body: Keyword.get(opts, :max_body, @max_body)
    }
  end

  def call(
        %Plug.Conn{request_path: request_path, method: "POST"} = conn,
        %{at: request_path} = opts
      ) do
    config = Config.fetch!(opts.store)

    with {:ok, body, conn} <- read_raw_body(conn, opts.max_body),
         :ok <- verify_hmac(conn, body, config),
         :ok <- verify_shop(conn, config),
         {:ok, payload} <- Jason.decode(body),
         {:ok, metadata} <- metadata(conn),
         result when result in [:ok, :duplicate, :ignored] <-
           opts.handler.handle(metadata, payload, config) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{accepted: true, result: result}))
      |> halt()
    else
      {:error, :invalid_hmac} -> reject(conn, 401, "invalid webhook signature")
      {:error, :wrong_shop} -> reject(conn, 401, "unexpected shop domain")
      {:error, :body_too_large} -> reject(conn, 413, "webhook body too large")
      {:error, %Jason.DecodeError{}} -> reject(conn, 422, "invalid JSON body")
      {:error, :missing_metadata} -> reject(conn, 400, "missing Shopify webhook headers")
      {:error, error} -> reject_handler_error(conn, error)
    end
  end

  def call(conn, _opts), do: conn

  @doc false
  def valid_hmac?(body, header, secret)
      when is_binary(body) and is_binary(header) and is_binary(secret) do
    computed =
      :crypto.mac(:hmac, :sha256, secret, body)
      |> Base.encode64()

    byte_size(computed) == byte_size(header) and Plug.Crypto.secure_compare(computed, header)
  end

  def valid_hmac?(_, _, _), do: false

  defp read_raw_body(conn, max_body), do: read_raw_body(conn, max_body, 0, [])

  defp read_raw_body(conn, max_body, size, chunks) when size <= max_body do
    case read_body(conn, length: max_body, read_length: 64_000, read_timeout: 15_000) do
      {:ok, chunk, conn} ->
        if size + byte_size(chunk) <= max_body do
          {:ok, chunks |> Enum.reverse([chunk]) |> IO.iodata_to_binary(), conn}
        else
          {:error, :body_too_large}
        end

      {:more, chunk, conn} ->
        next_size = size + byte_size(chunk)

        if next_size <= max_body do
          read_raw_body(conn, max_body, next_size, [chunk | chunks])
        else
          {:error, :body_too_large}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_hmac(conn, body, config) do
    header = first_header(conn, "x-shopify-hmac-sha256")
    secret = Config.resolve_secret(config.webhook_secret)
    if valid_hmac?(body, header, secret), do: :ok, else: {:error, :invalid_hmac}
  end

  defp verify_shop(conn, config) do
    case first_header(conn, "x-shopify-shop-domain") do
      shop when shop == config.shop_domain -> :ok
      _ -> {:error, :wrong_shop}
    end
  end

  defp metadata(conn) do
    with webhook_id when is_binary(webhook_id) <- first_header(conn, "x-shopify-webhook-id"),
         topic when is_binary(topic) <- first_header(conn, "x-shopify-topic") do
      {:ok,
       %{
         webhook_id: webhook_id,
         event_id: first_header(conn, "x-shopify-event-id"),
         shop_domain: first_header(conn, "x-shopify-shop-domain"),
         topic: topic,
         api_version: first_header(conn, "x-shopify-api-version"),
         triggered_at: parse_datetime(first_header(conn, "x-shopify-triggered-at"))
       }}
    else
      _ -> {:error, :missing_metadata}
    end
  end

  defp first_header(conn, name), do: conn |> get_req_header(name) |> List.first()

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        %{datetime | microsecond: {elem(datetime.microsecond, 0), 6}}

      _ ->
        nil
    end
  end

  defp reject(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{accepted: false, error: message}))
    |> halt()
  end

  defp reject_handler_error(conn, error) do
    Logger.error("Shopify webhook handler failed: #{inspect(error)}")
    reject(conn, 500, "could not enqueue webhook")
  end
end
