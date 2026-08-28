defmodule BrandoShopify.Gettext do
  @moduledoc """
  Translations for the strings this package puts in front of a buyer.

  Only the cart UI needs this. Everything else in the package is either
  developer-facing or comes from Shopify already localised.

  Add or override translations from the host by pointing Gettext at your own
  priv directory, or merge the `cart` domain into your application's catalogues.
  """

  use Gettext.Backend, otp_app: :brando_shopify
end
