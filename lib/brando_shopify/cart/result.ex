defmodule BrandoShopify.Cart.Result do
  @moduledoc "The result of a Storefront cart mutation."

  @type t :: %__MODULE__{cart: map() | nil, warnings: [map()]}
  defstruct cart: nil, warnings: []
end
