defmodule BrandoShopify.Cart.Labels do
  @moduledoc """
  The strings the bundled cart element renders, translated.

  Gettext runs on the server and the cart renderer runs in the browser, so the
  map crosses as a JSON attribute:

      <brando-shopify-cart
        endpoint="/shopify/cart"
        labels={Jason.encode!(BrandoShopify.Cart.Labels.all())}
      ></brando-shopify-cart>

  Anything omitted falls back to the element's English defaults, so a partial
  map is fine.

  `defaultVariant` is deliberately absent: it is not UI copy but Shopify's own
  name for the single variant of an option-less product, matched so the cart can
  hide it. Translating it would stop the match working.
  """

  use Gettext, backend: BrandoShopify.Gettext

  @doc "Every cart label, in the current Gettext locale."
  @spec all() :: %{String.t() => String.t()}
  def all do
    %{
      "region" => dgettext("cart", "Shopping cart"),
      "title" => dgettext("cart", "Your cart"),
      "close" => dgettext("cart", "Close cart"),
      "loading" => dgettext("cart", "Loading…"),
      "empty" => dgettext("cart", "Your cart is empty."),
      "product" => dgettext("cart", "Product"),
      "decrease" => dgettext("cart", "Decrease quantity"),
      "increase" => dgettext("cart", "Increase quantity"),
      "remove" => dgettext("cart", "Remove"),
      "removeItem" => dgettext("cart", "Remove item"),
      "total" => dgettext("cart", "Total"),
      "updating" => dgettext("cart", "Updating…"),
      "checkout" => dgettext("cart", "Checkout")
    }
  end

  @doc "`all/0` as a JSON string, ready for the element's `labels` attribute."
  @spec to_json() :: String.t()
  def to_json, do: Jason.encode!(all())
end
