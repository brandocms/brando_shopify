defmodule BrandoShopify.Cart.Present do
  @moduledoc """
  Derived values for rendering a cart.

  Same idea as `BrandoShopify.Catalog.Present`: slots should receive something
  worth having, not the Storefront's JSON with its nested `cost.totalAmount.amount`
  and its `"Default Title"` sentinel.

  Works on the sanitized cart from `BrandoShopify.Cart.public_view/1`, which has
  already dropped the secret-bearing id and the checkout URL.
  """

  alias BrandoShopify.Catalog.Present, as: Money

  @doc """
  Flattens a cart for display.

      %{empty?:, count:, lines:, total:, subtotal:, discount:, discount_codes:, currency:}

  `total.estimated?` is Shopify's own `totalAmountEstimated`, and it is nearly
  always true: shipping is not known until checkout, and destination-dependent
  tax is not resolved either. Calling that figure a "total" in the UI is a small
  lie that gets found out one screen later, so the default renderer labels it a
  subtotal and says so.
  """
  def cart(cart, opts \\ [])

  def cart(nil, _opts), do: empty()

  def cart(cart, opts) when is_map(cart) do
    lines = cart |> get_in(["lines", "nodes"]) |> List.wrap()
    cost = cart["cost"] || %{}
    currency = get_in(cost, ["totalAmount", "currencyCode"])

    %{
      cart: cart,
      empty?: lines == [],
      count: cart["totalQuantity"] || 0,
      currency: currency,
      lines: Enum.map(lines, &line(&1, opts)),
      total: money(cost["totalAmount"], cost["totalAmountEstimated"], opts),
      subtotal: money(cost["subtotalAmount"], cost["subtotalAmountEstimated"], opts),
      discount: discount(lines, currency, opts),
      discount_codes: applied_codes(cart),
      note: cart["note"]
    }
  end

  def cart(_, _opts), do: empty()

  @doc """
  Flattens one cart line.

  `variant_title` is `nil` when Shopify's placeholder for an option-less product
  would otherwise be shown — a line reading "Default Title" under the product
  name is noise, not information.
  """
  def line(line, opts \\ []) when is_map(line) do
    merchandise = line["merchandise"] || %{}
    product = merchandise["product"] || %{}
    cost = line["cost"] || %{}
    currency = get_in(cost, ["totalAmount", "currencyCode"])
    compare_at = cost["compareAtAmountPerQuantity"]

    %{
      line: line,
      id: line["id"],
      quantity: line["quantity"] || 0,
      title: product["title"] || merchandise["title"],
      variant_title: variant_title(merchandise),
      handle: product["handle"],
      sku: merchandise["sku"],
      image: image(merchandise["image"]),
      available?: merchandise["availableForSale"] == true,
      quantity_available: merchandise["quantityAvailable"],
      options: Map.new(List.wrap(merchandise["selectedOptions"]), &{&1["name"], &1["value"]}),
      total: money(cost["totalAmount"], false, opts),
      unit: money(cost["amountPerQuantity"], false, opts),
      compare_at: compare_at && money(compare_at, false, opts),
      on_sale?: marked_down?(cost["amountPerQuantity"], compare_at),
      discount: discount([line], currency, opts)
    }
  end

  defp empty do
    %{
      cart: nil,
      empty?: true,
      count: 0,
      currency: nil,
      lines: [],
      total: nil,
      subtotal: nil,
      discount: nil,
      discount_codes: [],
      note: nil
    }
  end

  defp money(nil, _estimated, _opts), do: nil

  defp money(%{"amount" => amount, "currencyCode" => currency}, estimated, opts) do
    decimal = to_decimal(amount)

    %{
      amount: decimal,
      currency: currency,
      estimated?: estimated == true,
      formatted: Money.format_money(decimal, currency, opts)
    }
  end

  defp money(_, _estimated, _opts), do: nil

  # Discounts Shopify already applied, whether from a code or automatically.
  # Automatic ones need no code and are otherwise invisible: line prices simply
  # come back lower, with nothing saying why.
  defp discount(lines, currency, opts) do
    total =
      lines
      |> Enum.flat_map(&List.wrap(&1["discountAllocations"]))
      |> Enum.map(&get_in(&1, ["discountedAmount", "amount"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_decimal/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    if Decimal.compare(total, 0) == :gt do
      %{amount: total, currency: currency, formatted: Money.format_money(total, currency, opts)}
    end
  end

  defp applied_codes(cart) do
    cart
    |> Map.get("discountCodes")
    |> List.wrap()
    |> Enum.filter(& &1["applicable"])
    |> Enum.map(& &1["code"])
  end

  # Shopify's name for the only variant of a product with no options.
  defp variant_title(%{"title" => "Default Title"}), do: nil
  defp variant_title(%{"title" => title}), do: title
  defp variant_title(_), do: nil

  defp marked_down?(%{"amount" => price}, %{"amount" => compare_at}) do
    Decimal.compare(to_decimal(compare_at), to_decimal(price)) == :gt
  end

  defp marked_down?(_, _), do: false

  defp image(%{"url" => url} = image) when is_binary(url) do
    %{url: url, alt: image["altText"], width: image["width"], height: image["height"]}
  end

  defp image(_), do: nil

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(_), do: Decimal.new(0)
end
