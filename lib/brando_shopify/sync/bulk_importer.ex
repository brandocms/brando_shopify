defmodule BrandoShopify.Sync.BulkImporter do
  @moduledoc """
  Streams Shopify bulk-operation JSONL into the local catalog.

  Shopify writes each product followed by its connection children and annotates
  child records with `__parentId`. Only one product is accumulated at a time, so
  imports stay memory-bounded even for large catalogs.
  """

  alias BrandoShopify.Error
  alias BrandoShopify.Sync.Persister

  @product_prefix "gid://shopify/Product/"
  @variant_prefix "gid://shopify/ProductVariant/"
  @collection_prefix "gid://shopify/Collection/"

  @type import_result :: %{products: non_neg_integer(), objects: non_neg_integer()}

  @doc "Imports an enumerable of JSONL lines."
  @spec import_stream(module(), atom() | String.t(), Enumerable.t()) ::
          {:ok, import_result()} | {:error, term()}
  def import_stream(repo, store, lines) do
    result =
      Enum.reduce_while(lines, {:ok, empty_state()}, &reduce_line(repo, store, &1, &2))

    with {:ok, state} <- result,
         {:ok, state} <- flush(repo, store, state) do
      {:ok, %{products: state.products, objects: state.objects}}
    end
  rescue
    exception -> {:error, exception}
  end

  defp reduce_line(repo, store, line, {:ok, state}) do
    case decode_line(line) do
      {:ok, nil} -> {:cont, {:ok, state}}
      {:ok, node} -> consume_line(repo, store, state, node)
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp consume_line(repo, store, state, node) do
    case consume(repo, store, state, node) do
      {:ok, next_state} -> {:cont, {:ok, next_state}}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  @doc "Downloads a signed Shopify JSONL URL and imports it as a stream."
  @spec download_and_import(module(), atom() | String.t(), String.t(), keyword()) ::
          {:ok, import_result()} | {:error, term()}
  def download_and_import(repo, store, url, opts \\ []) when is_binary(url) do
    path =
      Path.join(
        System.tmp_dir!(),
        "brando-shopify-#{System.unique_integer([:positive, :monotonic])}.jsonl"
      )

    try do
      req_options =
        [
          url: url,
          into: File.stream!(path),
          retry: :transient,
          max_retries: 3
        ]
        |> Keyword.merge(opts)

      case Req.get(req_options) do
        {:ok, %Req.Response{status: status}} when status in 200..299 ->
          import_stream(repo, store, File.stream!(path, [], :line))

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error,
           %Error{
             kind: :http,
             message: "Shopify bulk download returned HTTP #{status}",
             status: status,
             details: body
           }}

        {:error, exception} ->
          {:error,
           %Error{
             kind: :transport,
             message: Exception.message(exception)
           }}
      end
    after
      File.rm(path)
    end
  end

  defp consume(repo, store, state, %{"id" => @product_prefix <> _} = product)
       when not is_map_key(product, "__parentId") do
    with {:ok, state} <- flush(repo, store, state) do
      {:ok,
       %{
         state
         | current: product,
           variants: [],
           media: [],
           collections: [],
           metafields: [],
           objects: state.objects + 1
       }}
    end
  end

  defp consume(_repo, _store, %{current: nil} = state, _node),
    do: {:ok, %{state | objects: state.objects + 1}}

  defp consume(_repo, _store, state, node) do
    next_state =
      case classify(node) do
        :variant -> %{state | variants: [strip_parent(node) | state.variants]}
        :collection -> %{state | collections: [strip_parent(node) | state.collections]}
        :metafield -> %{state | metafields: [strip_parent(node) | state.metafields]}
        :media -> %{state | media: [strip_parent(node) | state.media]}
        :unknown -> state
      end

    {:ok, %{next_state | objects: next_state.objects + 1}}
  end

  defp flush(_repo, _store, %{current: nil} = state), do: {:ok, state}

  defp flush(repo, store, state) do
    product =
      state.current
      |> Map.put("variants", connection(state.variants))
      |> Map.put("media", connection(state.media))
      |> Map.put("collections", connection(state.collections))
      |> Map.put("metafields", connection(state.metafields))

    case Persister.persist_product(repo, store, product) do
      {:ok, _product} ->
        {:ok,
         %{
           state
           | current: nil,
             variants: [],
             media: [],
             collections: [],
             metafields: [],
             products: state.products + 1
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp decode_line(line) when is_binary(line) do
    case String.trim(line) do
      "" ->
        {:ok, nil}

      json ->
        case Jason.decode(json) do
          {:ok, node} ->
            {:ok, node}

          {:error, error} ->
            {:error, %Error{kind: :invalid_response, message: Exception.message(error)}}
        end
    end
  end

  defp classify(%{"id" => @variant_prefix <> _}), do: :variant
  defp classify(%{"id" => @collection_prefix <> _}), do: :collection
  defp classify(%{"namespace" => _, "key" => _, "type" => _}), do: :metafield
  defp classify(%{"mediaContentType" => _}), do: :media
  defp classify(_), do: :unknown

  defp strip_parent(node), do: Map.delete(node, "__parentId")
  defp connection(nodes), do: %{"nodes" => Enum.reverse(nodes)}

  defp empty_state do
    %{
      current: nil,
      variants: [],
      media: [],
      collections: [],
      metafields: [],
      products: 0,
      objects: 0
    }
  end
end
