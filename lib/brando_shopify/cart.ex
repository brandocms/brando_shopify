defmodule BrandoShopify.Cart do
  @moduledoc """
  Server-side Shopify cart operations.

  The complete cart ID includes a secret query parameter. Treat it like a
  password and keep it in an encrypted server session; never render it into
  HTML, JavaScript, logs, analytics, or shareable URLs.
  """

  alias BrandoShopify.Cart.Result
  alias BrandoShopify.Error
  alias BrandoShopify.GraphQL

  @max_input_items 250

  @cart_fragment """
  fragment BrandoCart on Cart {
    id
    checkoutUrl
    totalQuantity
    note
    attributes {
      key
      value
    }
    buyerIdentity {
      countryCode
      email
      phone
    }
    discountCodes {
      code
      applicable
    }
    cost {
      subtotalAmount {
        amount
        currencyCode
      }
      subtotalAmountEstimated
      checkoutChargeAmount {
        amount
        currencyCode
      }
      totalAmount {
        amount
        currencyCode
      }
      totalAmountEstimated
    }
    lines(first: 250) {
      nodes {
        id
        quantity
        attributes {
          key
          value
        }
        sellingPlanAllocation {
          sellingPlan {
            id
            name
            description
            options {
              name
              value
            }
          }
          checkoutChargeAmount {
            amount
            currencyCode
          }
          remainingBalanceChargeAmount {
            amount
            currencyCode
          }
          priceAdjustments {
            compareAtPrice {
              amount
              currencyCode
            }
            perDeliveryPrice {
              amount
              currencyCode
            }
            price {
              amount
              currencyCode
            }
            unitPrice {
              amount
              currencyCode
            }
          }
        }
        cost {
          amountPerQuantity {
            amount
            currencyCode
          }
          compareAtAmountPerQuantity {
            amount
            currencyCode
          }
          subtotalAmount {
            amount
            currencyCode
          }
          totalAmount {
            amount
            currencyCode
          }
        }
        discountAllocations(lineLevelOnly: false) {
          discountedAmount {
            amount
            currencyCode
          }
        }
        merchandise {
          ... on ProductVariant {
            id
            title
            availableForSale
            quantityAvailable
            requiresShipping
            sku
            selectedOptions {
              name
              value
            }
            image {
              url
              altText
              width
              height
            }
            price {
              amount
              currencyCode
            }
            compareAtPrice {
              amount
              currencyCode
            }
            product {
              id
              handle
              title
              vendor
            }
          }
        }
      }
    }
  }
  """

  @cart_query """
  #{@cart_fragment}

  query BrandoCart($id: ID!, $language: LanguageCode)
  @inContext(language: $language) {
    cart(id: $id) {
      ...BrandoCart
    }
  }
  """

  @cart_create """
  #{@cart_fragment}

  mutation BrandoCartCreate($input: CartInput!, $language: LanguageCode)
  @inContext(language: $language) {
    cartCreate(input: $input) {
      cart {
        ...BrandoCart
      }
      userErrors {
        field
        message
        code
      }
      warnings {
        code
        message
        target
      }
    }
  }
  """

  @doc "Retrieves a cart by its private, complete cart ID."
  @spec get(String.t(), keyword()) :: {:ok, map() | nil} | {:error, Error.t()}
  def get(cart_id, opts \\ []) when is_binary(cart_id) do
    variables = %{"id" => cart_id, "language" => code(opts[:language])}

    with {:ok, response} <- request(@cart_query, variables, "BrandoCart", opts) do
      {:ok, response.data["cart"]}
    end
  end

  @doc "Creates a cart. Lines may be omitted."
  @spec create([map()], keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def create(lines \\ [], opts \\ []) when is_list(lines) do
    lines = normalize_keys(lines)

    with :ok <- validate_count(lines),
         :ok <- validate_lines(lines) do
      input =
        %{}
        |> put_unless_empty("lines", lines)
        |> put_if_present("buyerIdentity", opts[:buyer_identity])
        |> put_if_present("discountCodes", opts[:discount_codes])
        |> put_if_present("attributes", opts[:attributes])
        |> put_if_present("note", opts[:note])

      mutate(
        @cart_create,
        %{"input" => input, "language" => code(opts[:language])},
        "BrandoCartCreate",
        "cartCreate",
        opts
      )
    end
  end

  @doc "Adds merchandise lines to an existing cart."
  def add_lines(cart_id, lines, opts \\ []) when is_binary(cart_id) and is_list(lines) do
    lines = normalize_keys(lines)

    with :ok <- validate_count(lines),
         :ok <- validate_lines(lines) do
      mutate_cart(
        mutation(
          "BrandoCartLinesAdd",
          "cartLinesAdd",
          "$lines: [CartLineInput!]!",
          "lines: $lines"
        ),
        cart_id,
        %{"lines" => lines},
        "BrandoCartLinesAdd",
        "cartLinesAdd",
        opts
      )
    end
  end

  @doc "Replaces quantities or attributes on existing cart lines."
  def update_lines(cart_id, lines, opts \\ []) when is_binary(cart_id) and is_list(lines) do
    with :ok <- validate_count(lines) do
      mutate_cart(
        mutation(
          "BrandoCartLinesUpdate",
          "cartLinesUpdate",
          "$lines: [CartLineUpdateInput!]!",
          "lines: $lines"
        ),
        cart_id,
        %{"lines" => normalize_keys(lines)},
        "BrandoCartLinesUpdate",
        "cartLinesUpdate",
        opts
      )
    end
  end

  @doc "Removes lines from a cart."
  def remove_lines(cart_id, line_ids, opts \\ [])
      when is_binary(cart_id) and is_list(line_ids) do
    with :ok <- validate_count(line_ids) do
      mutate_cart(
        mutation(
          "BrandoCartLinesRemove",
          "cartLinesRemove",
          "$lineIds: [ID!]!",
          "lineIds: $lineIds"
        ),
        cart_id,
        %{"lineIds" => line_ids},
        "BrandoCartLinesRemove",
        "cartLinesRemove",
        opts
      )
    end
  end

  @doc "Replaces all discount codes on a cart. Pass an empty list to remove them."
  def update_discount_codes(cart_id, codes, opts \\ [])
      when is_binary(cart_id) and is_list(codes) do
    with :ok <- validate_count(codes) do
      mutate_cart(
        mutation(
          "BrandoCartDiscountsUpdate",
          "cartDiscountCodesUpdate",
          "$discountCodes: [String!]!",
          "discountCodes: $discountCodes"
        ),
        cart_id,
        %{"discountCodes" => codes},
        "BrandoCartDiscountsUpdate",
        "cartDiscountCodesUpdate",
        opts
      )
    end
  end

  @doc "Updates the note attached to a cart."
  def update_note(cart_id, note, opts \\ []) when is_binary(cart_id) do
    mutate_cart(
      mutation("BrandoCartNoteUpdate", "cartNoteUpdate", "$note: String", "note: $note"),
      cart_id,
      %{"note" => note},
      "BrandoCartNoteUpdate",
      "cartNoteUpdate",
      opts
    )
  end

  @doc "Updates buyer identity, country context, and checkout preferences."
  def update_buyer_identity(cart_id, buyer_identity, opts \\ [])
      when is_binary(cart_id) and is_map(buyer_identity) do
    mutate_cart(
      mutation(
        "BrandoCartBuyerUpdate",
        "cartBuyerIdentityUpdate",
        "$buyerIdentity: CartBuyerIdentityInput!",
        "buyerIdentity: $buyerIdentity"
      ),
      cart_id,
      %{"buyerIdentity" => normalize_keys(buyer_identity)},
      "BrandoCartBuyerUpdate",
      "cartBuyerIdentityUpdate",
      opts
    )
  end

  @doc """
  Requests a fresh checkout URL.

  Shopify recommends retrieving this URL only when the buyer is ready to leave
  for checkout because a previously returned URL can become stale.
  """
  @spec checkout_url(String.t(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def checkout_url(cart_id, opts \\ []) do
    case get(cart_id, opts) do
      {:ok, %{"checkoutUrl" => url}} when is_binary(url) -> {:ok, url}
      {:ok, nil} -> {:error, user_error("Shopify cart was not found")}
      {:ok, _} -> {:error, user_error("Shopify did not return a checkout URL")}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Removes the cart ID and checkout URL before returning cart data to a browser."
  @spec public_view(map() | nil) :: map() | nil
  def public_view(nil), do: nil

  def public_view(cart) when is_map(cart) do
    Map.drop(cart, ["id", "checkoutUrl"])
  end

  defp mutate_cart(document, cart_id, variables, operation_name, payload_key, opts) do
    variables =
      variables
      |> Map.put("cartId", cart_id)
      |> Map.put("language", code(opts[:language]))

    mutate(document, variables, operation_name, payload_key, opts)
  end

  defp mutate(document, variables, operation_name, payload_key, opts) do
    with {:ok, response} <- request(document, variables, operation_name, opts),
         payload when is_map(payload) <- response.data[payload_key],
         [] <- payload["userErrors"] || [] do
      {:ok, %Result{cart: payload["cart"], warnings: payload["warnings"] || []}}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      errors when is_list(errors) ->
        {:error,
         %Error{
           kind: :user,
           message: user_error_message(errors),
           errors: errors
         }}

      _ ->
        {:error,
         %Error{kind: :invalid_response, message: "Shopify returned an invalid cart payload"}}
    end
  end

  defp request(document, variables, operation_name, opts) do
    graphql_opts =
      [
        operation_name: operation_name,
        store: opts[:store] || :default,
        buyer_ip: opts[:buyer_ip],
        req_options: opts[:req_options] || []
      ]
      |> maybe_put(:config, opts[:config])
      |> maybe_put(:http, opts[:http])

    GraphQL.request(:storefront, document, variables, graphql_opts)
  end

  defp mutation(operation_name, field, variable_definition, argument) do
    """
    #{@cart_fragment}

    mutation #{operation_name}(
      $cartId: ID!,
      #{variable_definition},
      $language: LanguageCode
    ) @inContext(language: $language) {
      #{field}(cartId: $cartId, #{argument}) {
        cart {
          ...BrandoCart
        }
        userErrors {
          field
          message
          code
        }
        warnings {
          code
          message
          target
        }
      }
    }
    """
  end

  defp validate_count(items) do
    if length(items) <= @max_input_items,
      do: :ok,
      else: {:error, user_error("Shopify accepts at most 250 inputs")}
  end

  defp validate_lines(lines) do
    if Enum.all?(lines, &valid_line?/1),
      do: :ok,
      else: {:error, user_error("each cart line needs a merchandiseId and positive quantity")}
  end

  defp valid_line?(line) when is_map(line) do
    valid_identifier?(Map.get(line, "merchandiseId")) and
      valid_quantity?(Map.get(line, "quantity") || 1) and
      valid_selling_plan?(Map.get(line, "sellingPlanId"))
  end

  defp valid_line?(_), do: false

  defp valid_identifier?(value), do: is_binary(value) and value != ""
  defp valid_quantity?(value), do: is_integer(value) and value > 0
  defp valid_selling_plan?(nil), do: true
  defp valid_selling_plan?(value), do: valid_identifier?(value)

  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)

  defp normalize_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {camelize_key(key), normalize_keys(nested)} end)
  end

  defp normalize_keys(value), do: value

  defp camelize_key(key) when is_atom(key), do: key |> Atom.to_string() |> camelize_key()

  defp camelize_key(key) when is_binary(key) do
    case String.split(key, "_") do
      [head | tail] -> head <> Enum.map_join(tail, &String.capitalize/1)
      [] -> key
    end
  end

  defp put_unless_empty(map, _key, []), do: map
  defp put_unless_empty(map, key, value), do: Map.put(map, key, value)

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, normalize_keys(value))

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp code(nil), do: nil
  defp code(value) when is_atom(value), do: value |> Atom.to_string() |> String.upcase()
  defp code(value) when is_binary(value), do: String.upcase(value)

  defp user_error(message), do: %Error{kind: :user, message: message}

  defp user_error_message([%{"message" => message} | _]), do: message
  defp user_error_message(_), do: "Shopify rejected the cart operation"
end
