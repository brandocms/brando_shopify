defmodule BrandoShopify.HTTP do
  @moduledoc """
  Injectable HTTP transport used by the GraphQL client.

  The default implementation delegates to `Req.request/1`. Implement the
  callback to add a project-specific transport or deterministic contract tests.
  """

  @callback request(keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}

  def request(options), do: Req.request(options)
end
