defmodule BrandoShopify.Sync.InventoryBulkImporter do
  @moduledoc false

  alias BrandoShopify.Error
  alias BrandoShopify.Sync.Persister

  @inventory_item_prefix "gid://shopify/InventoryItem/"
  @inventory_level_prefix "gid://shopify/InventoryLevel/"
  @variant_prefix "gid://shopify/ProductVariant/"

  @doc "Imports an inventory bulk-operation JSONL stream."
  def import_stream(repo, store, lines) do
    result =
      Enum.reduce_while(lines, {:ok, empty_state()}, fn line, {:ok, state} ->
        case decode_line(line) do
          {:ok, nil} -> {:cont, {:ok, state}}
          {:ok, node} -> consume(repo, store, state, node)
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    with {:ok, state} <- result,
         {:ok, state} <- flush(repo, store, state) do
      {:ok, %{items: state.items, levels: state.level_count, objects: state.objects}}
    end
  rescue
    exception -> {:error, exception}
  end

  @doc "Downloads and imports Shopify's signed inventory JSONL result."
  def download_and_import(repo, store, url, opts \\ []) do
    path =
      Path.join(
        System.tmp_dir!(),
        "brando-shopify-inventory-#{System.unique_integer([:positive, :monotonic])}.jsonl"
      )

    try do
      request =
        [url: url, into: File.stream!(path), retry: :transient, max_retries: 3]
        |> Keyword.merge(opts)

      case Req.get(request) do
        {:ok, %Req.Response{status: status}} when status in 200..299 ->
          import_stream(repo, store, File.stream!(path, [], :line))

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error,
           %Error{
             kind: :http,
             message: "Shopify inventory bulk download returned HTTP #{status}",
             status: status,
             details: body
           }}

        {:error, exception} ->
          {:error, %Error{kind: :transport, message: Exception.message(exception)}}
      end
    after
      File.rm(path)
    end
  end

  defp consume(repo, store, state, %{"id" => @inventory_item_prefix <> _} = item)
       when not is_map_key(item, "__parentId") do
    case flush(repo, store, state) do
      {:ok, state} ->
        {:cont,
         {:ok,
          %{
            state
            | current: item,
              variant_ids: [],
              levels: [],
              objects: state.objects + 1
          }}}

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  defp consume(_repo, _store, state, %{"id" => @variant_prefix <> _} = variant) do
    {:cont,
     {:ok,
      %{
        state
        | variant_ids: [variant["id"] | state.variant_ids],
          objects: state.objects + 1
      }}}
  end

  defp consume(_repo, _store, state, %{"id" => @inventory_level_prefix <> _} = level) do
    {:cont,
     {:ok,
      %{
        state
        | levels: [Map.delete(level, "__parentId") | state.levels],
          level_count: state.level_count + 1,
          objects: state.objects + 1
      }}}
  end

  defp consume(_repo, _store, state, _node) do
    {:cont, {:ok, %{state | objects: state.objects + 1}}}
  end

  defp flush(_repo, _store, %{current: nil} = state), do: {:ok, state}

  defp flush(repo, store, state) do
    case Persister.persist_inventory_projection(
           repo,
           store,
           state.current,
           Enum.reverse(state.variant_ids),
           Enum.reverse(state.levels)
         ) do
      {:ok, _} ->
        {:ok,
         %{
           state
           | current: nil,
             variant_ids: [],
             levels: [],
             items: state.items + 1
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp decode_line(line) do
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

  defp empty_state do
    %{current: nil, variant_ids: [], levels: [], items: 0, level_count: 0, objects: 0}
  end
end
