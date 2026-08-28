defmodule BrandoShopify.GraphQL do
  @moduledoc """
  Thin, observable GraphQL transport for Shopify APIs.

  The client uses `Req` directly rather than a Shopify wrapper so API versions,
  headers, response extensions, and new GraphQL fields stay visible.
  """

  alias BrandoShopify.Config
  alias BrandoShopify.Error
  alias BrandoShopify.GraphQL.Response

  @type surface :: :admin | :storefront

  @doc """
  Executes a Shopify GraphQL request.

  Options:

    * `:store` — configured store name, defaults to `:default`
    * `:config` — an already built `BrandoShopify.Config`
    * `:buyer_ip` — required for private Storefront requests caused by buyer traffic
    * `:operation_name` — GraphQL operation name
    * `:http` — transport module implementing `BrandoShopify.HTTP`
    * `:req_options` — final request overrides, mainly useful in tests
  """
  @spec request(surface(), String.t(), map(), keyword()) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def request(surface, document, variables \\ %{}, opts \\ [])
      when surface in [:admin, :storefront] and is_binary(document) and is_map(variables) do
    started_at = System.monotonic_time()
    metadata = %{surface: surface, store: Keyword.get(opts, :store, :default)}

    :telemetry.execute(
      [:brando_shopify, :graphql, :request, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result =
      with {:ok, config} <- config(opts),
           :ok <- validate_surface(config, surface),
           {:ok, response} <- perform_request(config, surface, document, variables, opts) do
        decode_response(response)
      else
        {:error, %Error{} = error} -> {:error, error}
        {:error, reason} -> {:error, configuration_error(reason)}
      end

    duration = System.monotonic_time() - started_at

    stop_metadata =
      case result do
        {:ok, response} ->
          Map.merge(metadata, %{status: response.status, result: :ok})

        {:error, error} ->
          Map.merge(metadata, %{status: error.status, result: :error, kind: error.kind})
      end

    :telemetry.execute(
      [:brando_shopify, :graphql, :request, :stop],
      %{duration: duration},
      stop_metadata
    )

    result
  end

  defp perform_request(config, surface, document, variables, opts) do
    body =
      %{"query" => document, "variables" => variables}
      |> maybe_put_operation_name(opts[:operation_name])

    request_options =
      [
        method: :post,
        url: Config.endpoint(config, surface),
        headers: headers(config, surface, opts),
        json: body,
        retry: false,
        receive_timeout: 30_000
      ]
      |> Keyword.merge(config.req_options)
      |> Keyword.merge(Keyword.get(opts, :req_options, []))

    http = Keyword.get(opts, :http) || config.http

    case http.request(request_options) do
      {:ok, %Req.Response{} = response} ->
        {:ok, response}

      {:error, exception} ->
        {:error,
         %Error{
           kind: :transport,
           message: Exception.message(exception)
         }}
    end
  end

  defp decode_response(%Req.Response{status: status, body: body} = response)
       when status in 200..299 and is_map(body) do
    errors = Map.get(body, "errors", [])

    if errors == [] do
      {:ok,
       %Response{
         data: Map.get(body, "data", %{}),
         extensions: Map.get(body, "extensions", %{}),
         status: status,
         request_id: response_header(response, "x-request-id"),
         api_version: response_header(response, "x-shopify-api-version"),
         headers: response.headers
       }}
    else
      {:error,
       %Error{
         kind: :graphql,
         message: graphql_message(errors),
         status: status,
         request_id: response_header(response, "x-request-id"),
         api_version: response_header(response, "x-shopify-api-version"),
         errors: errors
       }}
    end
  end

  defp decode_response(%Req.Response{status: status, body: body} = response) do
    {:error,
     %Error{
       kind: :http,
       message: "Shopify returned HTTP #{status}",
       status: status,
       request_id: response_header(response, "x-request-id"),
       api_version: response_header(response, "x-shopify-api-version"),
       details: redact_body(body)
     }}
  end

  defp headers(config, :admin, _opts) do
    [
      {"accept", "application/json"},
      {"content-type", "application/json"},
      {"x-shopify-access-token", Config.resolve_secret(config.admin_access_token) || ""}
    ]
  end

  defp headers(config, :storefront, opts) do
    base = [{"accept", "application/json"}, {"content-type", "application/json"}]
    token = Config.resolve_secret(config.storefront_access_token)

    base =
      case config.storefront_token_type do
        :private -> [{"shopify-storefront-private-token", token} | base]
        :public -> [{"x-shopify-storefront-access-token", token} | base]
        :none -> base
      end

    case Keyword.get(opts, :buyer_ip) do
      ip when is_binary(ip) and ip != "" ->
        [{"shopify-storefront-buyer-ip", ip} | base]

      _ ->
        base
    end
  end

  defp validate_surface(config, :admin) do
    if present?(Config.resolve_secret(config.admin_access_token)),
      do: :ok,
      else: {:error, :missing_admin_access_token}
  end

  defp validate_surface(_config, :storefront), do: :ok

  defp config(opts) do
    case Keyword.get(opts, :config) do
      %Config{} = config -> {:ok, config}
      nil -> Config.fetch(Keyword.get(opts, :store, :default))
      value -> {:error, {:invalid_config, value}}
    end
  end

  defp response_header(response, name) do
    response
    |> Req.Response.get_header(name)
    |> List.first()
  end

  defp maybe_put_operation_name(body, nil), do: body
  defp maybe_put_operation_name(body, name), do: Map.put(body, "operationName", name)

  defp graphql_message([%{"message" => message} | _]), do: message
  defp graphql_message(_), do: "Shopify returned GraphQL errors"

  defp configuration_error(reason) do
    %Error{
      kind: :configuration,
      message: "invalid Shopify configuration: #{inspect(reason)}",
      details: reason
    }
  end

  defp redact_body(body) when is_map(body) do
    Map.drop(body, ["access_token", "refresh_token", "token"])
  end

  defp redact_body(body) when is_binary(body), do: String.slice(body, 0, 1_000)
  defp redact_body(body), do: body

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
