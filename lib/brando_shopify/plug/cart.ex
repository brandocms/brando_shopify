defmodule BrandoShopify.Plug.Cart do
  @moduledoc """
  A session-backed JSON cart endpoint for Phoenix or any Plug application.

  Mount this behind a JSON pipeline with session and CSRF protection. The
  endpoint must run after `Plug.Parsers`, which is normally in the endpoint:

      pipeline :shopify_cart do
        plug :accepts, ["json"]
        plug :fetch_session
        plug :protect_from_forgery
        plug :put_secure_browser_headers
      end

      scope "/shopify" do
        pipe_through :shopify_cart

        forward "/cart", BrandoShopify.Plug.Cart,
          store: :default
      end

  The storefront layout must render a `meta[name="csrf-token"]` value for the
  supplied web component.

  Routes relative to the mount:

    * `GET /` — current cart
    * `POST /lines` — add lines, creating a cart if necessary
    * `PATCH /lines` — update line quantities
    * `DELETE /lines` — remove line IDs
    * `PUT /discounts` — replace discount codes
    * `PUT /note` — update cart note
    * `PUT /buyer` — update buyer identity
    * `POST /checkout` — request a fresh checkout URL

  The complete Shopify cart ID is encrypted with the endpoint's
  `secret_key_base` before it enters the Phoenix session. This protects it even
  when the host uses a signed-but-readable cookie session. It is stripped from
  every JSON response.
  """

  @behaviour Plug

  import Plug.Conn

  alias BrandoShopify.Cart
  alias BrandoShopify.Cart.Result
  alias BrandoShopify.Error

  @impl Plug
  def init(opts) do
    %{
      store: Keyword.get(opts, :store, :default),
      session_key: Keyword.get(opts, :session_key, "brando_shopify_cart_id"),
      encryption_salt: Keyword.get(opts, :encryption_salt, "brando_shopify/cart/session/v1"),
      max_age: Keyword.get(opts, :max_age, 14 * 24 * 60 * 60)
    }
  end

  @impl Plug
  def call(conn, opts) do
    conn
    |> fetch_session()
    |> dispatch(opts)
  end

  defp dispatch(%{method: "GET", path_info: []} = conn, opts), do: show(conn, opts)
  defp dispatch(%{method: "GET", path_info: [""]} = conn, opts), do: show(conn, opts)
  defp dispatch(%{method: "POST", path_info: ["lines"]} = conn, opts), do: add_lines(conn, opts)

  defp dispatch(%{method: "PATCH", path_info: ["lines"]} = conn, opts),
    do: update_lines(conn, opts)

  defp dispatch(%{method: "DELETE", path_info: ["lines"]} = conn, opts),
    do: remove_lines(conn, opts)

  defp dispatch(%{method: "PUT", path_info: ["discounts"]} = conn, opts),
    do: update_discounts(conn, opts)

  defp dispatch(%{method: "PUT", path_info: ["note"]} = conn, opts),
    do: update_note(conn, opts)

  defp dispatch(%{method: "PUT", path_info: ["buyer"]} = conn, opts),
    do: update_buyer(conn, opts)

  defp dispatch(%{method: "POST", path_info: ["checkout"]} = conn, opts),
    do: checkout(conn, opts)

  defp dispatch(conn, _opts),
    do: json(conn, 404, %{error: %{message: "cart endpoint not found"}})

  defp show(conn, opts) do
    case cart_id(conn, opts) do
      nil ->
        conn
        |> delete_session(opts.session_key)
        |> cart_json(nil)

      id ->
        case Cart.get(id, cart_options(conn, opts)) do
          {:ok, nil} -> conn |> delete_session(opts.session_key) |> cart_json(nil)
          {:ok, cart} -> cart_json(conn, cart)
          {:error, error} -> error_json(conn, error)
        end
    end
  end

  defp add_lines(conn, opts) do
    lines = body_value(conn, "lines", [])

    result =
      case cart_id(conn, opts) do
        nil -> Cart.create(lines, cart_options(conn, opts))
        id -> Cart.add_lines(id, lines, cart_options(conn, opts))
      end

    mutation_json(conn, result, opts)
  end

  defp update_lines(conn, opts) do
    with_cart(conn, opts, fn id ->
      Cart.update_lines(id, body_value(conn, "lines", []), cart_options(conn, opts))
    end)
  end

  defp remove_lines(conn, opts) do
    with_cart(conn, opts, fn id ->
      line_ids = body_value(conn, "lineIds", body_value(conn, "line_ids", []))
      Cart.remove_lines(id, line_ids, cart_options(conn, opts))
    end)
  end

  defp update_discounts(conn, opts) do
    with_cart(conn, opts, fn id ->
      Cart.update_discount_codes(
        id,
        body_value(conn, "discountCodes", body_value(conn, "discount_codes", [])),
        cart_options(conn, opts)
      )
    end)
  end

  defp update_note(conn, opts) do
    with_cart(conn, opts, fn id ->
      Cart.update_note(id, body_value(conn, "note"), cart_options(conn, opts))
    end)
  end

  defp update_buyer(conn, opts) do
    with_cart(conn, opts, fn id ->
      Cart.update_buyer_identity(
        id,
        body_value(conn, "buyerIdentity", body_value(conn, "buyer_identity", %{})),
        cart_options(conn, opts)
      )
    end)
  end

  defp checkout(conn, opts) do
    case cart_id(conn, opts) do
      nil ->
        json(conn, 409, %{error: %{message: "cart is empty"}})

      id ->
        case Cart.checkout_url(id, cart_options(conn, opts)) do
          {:ok, url} -> json(conn, 200, %{checkoutUrl: url})
          {:error, error} -> error_json(conn, error)
        end
    end
  end

  defp with_cart(conn, opts, fun) do
    case cart_id(conn, opts) do
      nil -> json(conn, 409, %{error: %{message: "cart is empty"}})
      id -> mutation_json(conn, fun.(id), opts)
    end
  end

  defp mutation_json(conn, {:ok, %Result{} = result}, opts) do
    conn =
      case result.cart do
        %{"id" => id} when is_binary(id) -> put_cart_id(conn, opts, id)
        _ -> conn
      end

    json(conn, 200, %{
      cart: Cart.public_view(result.cart),
      warnings: result.warnings
    })
  end

  defp mutation_json(conn, {:error, %Error{} = error}, _opts), do: error_json(conn, error)

  defp cart_json(conn, cart) do
    json(conn, 200, %{cart: Cart.public_view(cart), warnings: []})
  end

  defp error_json(conn, %Error{} = error) do
    status =
      case error.kind do
        :user -> 422
        :configuration -> 500
        :transport -> 502
        :http -> 502
        :graphql -> 502
        :invalid_response -> 502
      end

    json(conn, status, %{
      error: %{
        kind: error.kind,
        message: error.message,
        errors: error.errors,
        requestId: error.request_id
      }
    })
  end

  defp cart_options(conn, opts) do
    [store: opts.store, buyer_ip: buyer_ip(conn)]
  end

  defp buyer_ip(%Plug.Conn{remote_ip: remote_ip}) when is_tuple(remote_ip) do
    remote_ip |> :inet.ntoa() |> to_string()
  end

  defp buyer_ip(_), do: nil

  defp cart_id(conn, opts) do
    token = get_session(conn, opts.session_key)

    with key when is_binary(key) <- conn.secret_key_base,
         {:ok, cart_id} <-
           unprotect_cart_id(token, key, opts.encryption_salt, opts.max_age) do
      cart_id
    else
      _ -> nil
    end
  end

  defp put_cart_id(%Plug.Conn{secret_key_base: key} = conn, opts, cart_id)
       when is_binary(key) do
    token = protect_cart_id(cart_id, key, opts.encryption_salt, opts.max_age)
    put_session(conn, opts.session_key, token)
  end

  defp put_cart_id(_conn, _opts, _cart_id) do
    raise ArgumentError,
          "BrandoShopify.Plug.Cart requires Plug.Conn.secret_key_base to encrypt the cart ID"
  end

  @doc "Encrypts a complete Shopify cart ID for storage in a browser session."
  @spec protect_cart_id(String.t(), String.t(), String.t(), non_neg_integer()) :: String.t()
  def protect_cart_id(cart_id, secret_key_base, salt, max_age)
      when is_binary(cart_id) and is_binary(secret_key_base) and is_binary(salt) do
    Plug.Crypto.encrypt(secret_key_base, salt, cart_id, max_age: max_age)
  end

  @doc "Decrypts and verifies a Shopify cart ID previously produced by `protect_cart_id/4`."
  @spec unprotect_cart_id(String.t(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, :expired | :invalid}
  def unprotect_cart_id(token, secret_key_base, salt, max_age)
      when is_binary(secret_key_base) and is_binary(salt) do
    Plug.Crypto.decrypt(secret_key_base, salt, token, max_age: max_age)
  end

  defp body_value(conn, key, default \\ nil)

  defp body_value(%Plug.Conn{body_params: params}, key, default) when is_map(params) do
    Map.get(params, key, default)
  end

  defp body_value(_conn, _key, default), do: default

  defp json(conn, status, payload) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
    |> halt()
  end
end
