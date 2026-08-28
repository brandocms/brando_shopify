defmodule BrandoShopify.Error do
  @moduledoc """
  Structured error returned by Shopify clients.

  Request headers and tokens are never stored in the error.
  """

  defexception [
    :kind,
    :message,
    :status,
    :request_id,
    :api_version,
    errors: [],
    details: nil
  ]

  @type t :: %__MODULE__{
          kind: :configuration | :transport | :http | :graphql | :user | :invalid_response,
          message: String.t(),
          status: non_neg_integer() | nil,
          request_id: String.t() | nil,
          api_version: String.t() | nil,
          errors: [map()],
          details: term()
        }
end
