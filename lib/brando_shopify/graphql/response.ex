defmodule BrandoShopify.GraphQL.Response do
  @moduledoc "A successful Shopify GraphQL response."

  @type t :: %__MODULE__{
          data: map(),
          extensions: map(),
          status: non_neg_integer(),
          request_id: String.t() | nil,
          api_version: String.t() | nil,
          headers: Req.Headers.t()
        }

  defstruct data: %{},
            extensions: %{},
            status: 200,
            request_id: nil,
            api_version: nil,
            headers: %{}
end
