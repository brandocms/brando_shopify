defmodule BrandoShopify.Catalog.Present do
  @moduledoc """
  Derived values a storefront needs but Shopify does not hand over ready-made.

  These exist so component slots can expose something useful. Handing a consumer
  the raw `%Product{}` and letting them dig through `options`, `selected_options`
  and `featured_media` themselves would push the same JSON-shaped work into every
  template that overrides anything.

  Everything here is pure and works on already-synced records — no queries, no
  Shopify round trips.
  """

  alias BrandoShopify.Catalog.Product
  alias BrandoShopify.Catalog.Variant

  @doc """
  The price to show for a product or variant.

      %{min: Decimal, max: Decimal, currency: "NOK", range?: false, formatted: "949 kr"}

  `range?` is true when a product's variants are not all the same price, which is
  what turns "949 kr" into "fra 449 kr".
  """
  def price(subject, opts \\ [])

  def price(%Product{min_price: min, max_price: max, currency_code: currency}, opts) do
    range? = not is_nil(min) and not is_nil(max) and not Decimal.equal?(min, max)

    %{
      min: min,
      max: max,
      currency: currency,
      range?: range?,
      formatted: format_range(min, max, currency, range?, opts)
    }
  end

  def price(%Variant{price: amount, compare_at_price: compare_at}, opts) do
    currency = opts[:currency]

    %{
      min: amount,
      max: amount,
      currency: currency,
      range?: false,
      compare_at: compare_at,
      formatted: format_money(amount, currency, opts)
    }
  end

  @doc """
  The product's featured image, or `nil`.

  Shopify nests the usable URL differently depending on media type, so this
  flattens `featured_media` into one shape rather than making every template
  learn the difference.
  """
  def featured_image(%Product{featured_media: media}), do: image_from_media(media)

  def featured_image(_), do: nil

  @doc "Every image on the product, featured first."
  def images(%Product{featured_media: featured, media: media}) do
    [featured | List.wrap(media)]
    |> Enum.map(&image_from_media/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.url)
  end

  @doc """
  The product's option groups, with each value's availability resolved.

      [%{name: "Størrelse", values: [%{value: "M", available?: true, variant: %Variant{}}]}]

  `available?` means **the value appears in at least one purchasable variant**.
  Whether it is purchasable *right now* depends on what else the buyer has
  selected, and only the client knows that — see `variant_matrix/1`.

  `variant` is only set for single-option products, where a value maps to exactly
  one variant. With two or more options a value is not a variant, and pretending
  otherwise would put a lie in the API.

  Returns `[]` when variants are not preloaded.
  """
  def option_groups(%Product{options: options, variants: variants}) when is_list(variants) do
    single? = length(List.wrap(options)) == 1

    for option <- List.wrap(options) do
      name = option["name"]

      values =
        for value <- List.wrap(option["optionValues"]) do
          value_name = value["name"]
          matching = Enum.filter(variants, &selected?(&1, name, value_name))

          %{
            value: value_name,
            available?: Enum.any?(matching, & &1.available_for_sale),
            variant: if(single?, do: List.first(matching))
          }
        end

      %{name: name, values: values}
    end
  end

  def option_groups(_), do: []

  @doc """
  Every variant flattened for client-side lookup.

  A selection is a *combination* of option values, and resolving one to a variant
  has to happen in the browser. This is the table it resolves against.
  """
  def variant_matrix(%Product{variants: variants} = product) when is_list(variants) do
    currency = product.currency_code

    for variant <- variants do
      %{
        id: variant.shopify_id,
        sku: variant.sku,
        title: variant.title,
        available: variant.available_for_sale == true,
        quantity: variant.inventory_quantity,
        price: variant.price && Decimal.to_string(variant.price, :normal),
        compare_at: variant.compare_at_price && Decimal.to_string(variant.compare_at_price, :normal),
        currency: currency,
        options: Map.new(List.wrap(variant.selected_options), &{&1["name"], &1["value"]})
      }
    end
  end

  def variant_matrix(_), do: []

  @doc "True when no variant can be bought. Requires variants preloaded."
  def sold_out?(%Product{variants: variants}) when is_list(variants) do
    variants != [] and not Enum.any?(variants, & &1.available_for_sale)
  end

  def sold_out?(_), do: false

  @doc "True when the variant is marked down from its compare-at price."
  def on_sale?(%Variant{price: price, compare_at_price: compare_at})
      when not is_nil(price) and not is_nil(compare_at) do
    Decimal.compare(compare_at, price) == :gt
  end

  def on_sale?(_), do: false

  @doc """
  Formats an amount for display.

  The default is deliberately plain and currency-aware rather than clever. Set
  your own once for the whole application:

      config :brando_shopify, :money_formatter, {MyApp.Money, :format, []}

  It is called with `(amount, currency)` and must return a string. A `:format`
  option, which the components expose as an attribute, overrides it per call.
  """
  def format_money(amount, currency, opts \\ [])

  def format_money(nil, _currency, _opts), do: ""

  def format_money(amount, currency, opts) do
    case opts[:format] || Application.get_env(:brando_shopify, :money_formatter) do
      nil -> default_format(amount, currency)
      fun when is_function(fun, 2) -> fun.(amount, currency)
      {module, function, args} -> apply(module, function, [amount, currency | args])
    end
  end

  defp format_range(min, _max, currency, false, opts), do: format_money(min, currency, opts)

  defp format_range(min, _max, currency, true, opts) do
    # "from 449 kr" rather than "449–949 kr": the upper bound is rarely what a
    # buyer is deciding on, and the range reads as two prices at a glance.
    prefix = opts[:from_label] || "fra "
    prefix <> format_money(min, currency, opts)
  end

  # Norwegian conventions, because that is what Brando defaults to: space as the
  # thousands separator, comma for decimals, and whole amounts without ",00".
  defp default_format(amount, currency) do
    rounded = Decimal.round(amount, 2)
    whole? = Decimal.equal?(Decimal.round(amount, 0), rounded)

    digits =
      if whole? do
        amount |> Decimal.round(0) |> Decimal.to_string(:normal)
      else
        rounded |> Decimal.to_string(:normal) |> String.replace(".", ",")
      end

    "#{group_thousands(digits)} #{symbol(currency)}"
  end

  defp group_thousands(digits) do
    case String.split(digits, ",") do
      [int] -> space_groups(int)
      [int, frac] -> "#{space_groups(int)},#{frac}"
    end
  end

  defp space_groups(int) do
    int
    |> String.reverse()
    |> String.to_charlist()
    |> Enum.chunk_every(3)
    |> Enum.join(" ")
    |> String.reverse()
  end

  defp symbol("NOK"), do: "kr"
  defp symbol("SEK"), do: "kr"
  defp symbol("DKK"), do: "kr"
  defp symbol("EUR"), do: "€"
  defp symbol("USD"), do: "$"
  defp symbol("GBP"), do: "£"
  defp symbol(other), do: other || ""

  defp selected?(%Variant{selected_options: selected}, name, value) do
    Enum.any?(List.wrap(selected), &(&1["name"] == name and &1["value"] == value))
  end

  defp image_from_media(media) when is_map(media) do
    image = media["image"] || get_in(media, ["preview", "image"])

    case image && image["url"] do
      nil ->
        nil

      url ->
        %{
          url: url,
          alt: image["altText"] || media["alt"],
          width: image["width"],
          height: image["height"]
        }
    end
  end

  defp image_from_media(_), do: nil
end
