defmodule BrandoShopify.Admin do
  @moduledoc """
  Shopify Admin GraphQL queries used by catalog synchronization.

  REST is intentionally not used: Shopify classifies the REST Admin API as
  legacy, and new product capabilities land in GraphQL.
  """

  alias BrandoShopify.Admin.Documents
  alias BrandoShopify.Error
  alias BrandoShopify.GraphQL

  @connections %{
    "variants" => {&Documents.product_variants/0, "BrandoShopifyProductVariants"},
    "media" => {&Documents.product_media/0, "BrandoShopifyProductMedia"},
    "collections" => {&Documents.product_collections/0, "BrandoShopifyProductCollections"},
    "metafields" => {&Documents.product_metafields/0, "BrandoShopifyProductMetafields"}
  }

  @doc "Fetches a complete product, following every first-level connection."
  @spec fetch_product(String.t(), keyword()) :: {:ok, map() | nil} | {:error, Error.t()}
  def fetch_product(product_id, opts \\ []) when is_binary(product_id) do
    with {:ok, response} <-
           request(Documents.product(), %{"id" => product_id}, "BrandoShopifyProduct", opts),
         product when is_map(product) <- response.data["product"],
         {:ok, product} <- complete_connections(product_id, product, opts),
         {:ok, product} <- complete_inventory_levels(product, opts) do
      {:ok, product}
    else
      nil -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Lists product IDs updated at or after an ISO-8601 timestamp."
  @spec product_ids_updated_since(DateTime.t() | String.t(), keyword()) ::
          {:ok, [map()]} | {:error, Error.t()}
  def product_ids_updated_since(since, opts \\ []) do
    query = "updated_at:>=#{iso8601(since)}"
    collect_updated(nil, query, [], opts)
  end

  @doc "Fetches a collection and every product ID in its membership."
  def fetch_collection(collection_id, opts \\ []) when is_binary(collection_id) do
    collect_collection(collection_id, nil, nil, [], opts)
  end

  @doc "Starts an asynchronous bulk product export."
  def start_bulk_products(opts \\ []) do
    variables = %{"query" => Documents.bulk_products_query()}

    with {:ok, response} <-
           request(
             Documents.start_bulk_query(),
             variables,
             "BrandoShopifyBulkProducts",
             opts
           ),
         payload when is_map(payload) <- response.data["bulkOperationRunQuery"],
         [] <- payload["userErrors"] || [] do
      {:ok, payload["bulkOperation"]}
    else
      {:error, error} -> {:error, error}
      errors when is_list(errors) -> {:error, user_errors(errors)}
      _ -> {:error, invalid_response("Shopify did not return a bulk operation")}
    end
  end

  @doc "Starts the inventory-item/location phase of a full export."
  def start_bulk_inventory(opts \\ []) do
    variables = %{"query" => Documents.bulk_inventory_query()}

    with {:ok, response} <-
           request(
             Documents.start_bulk_inventory_query(),
             variables,
             "BrandoShopifyBulkInventory",
             opts
           ),
         payload when is_map(payload) <- response.data["bulkOperationRunQuery"],
         [] <- payload["userErrors"] || [] do
      {:ok, payload["bulkOperation"]}
    else
      {:error, error} -> {:error, error}
      errors when is_list(errors) -> {:error, user_errors(errors)}
      _ -> {:error, invalid_response("Shopify did not return an inventory bulk operation")}
    end
  end

  @doc "Retrieves an Admin bulk operation by GID."
  def bulk_operation(operation_id, opts \\ []) do
    with {:ok, response} <-
           request(
             Documents.bulk_operation(),
             %{"id" => operation_id},
             "BrandoShopifyBulkOperation",
             opts
           ) do
      {:ok, response.data["bulkOperation"]}
    end
  end

  @doc """
  Creates shop-specific HTTPS webhook subscriptions.

  This is the correct installation path for merchant-created custom apps. Public
  apps should prefer app-specific subscriptions in `shopify.app.toml`.
  """
  def subscribe_webhook(topic, uri, opts \\ [])
      when is_binary(topic) and is_binary(uri) do
    variables = %{
      "topic" => topic |> String.replace("/", "_") |> String.upcase(),
      "subscription" => %{"uri" => uri, "format" => "JSON"}
    }

    with {:ok, response} <-
           request(
             Documents.webhook_subscription_create(),
             variables,
             "BrandoShopifyWebhookSubscription",
             opts
           ),
         payload when is_map(payload) <- response.data["webhookSubscriptionCreate"],
         [] <- payload["userErrors"] || [] do
      {:ok, payload["webhookSubscription"]}
    else
      {:error, error} -> {:error, error}
      errors when is_list(errors) -> {:error, user_errors(errors)}
      _ -> {:error, invalid_response("Shopify did not return a webhook subscription")}
    end
  end

  defp complete_connections(product_id, product, opts) do
    Enum.reduce_while(
      @connections,
      {:ok, product},
      &complete_connection(product_id, opts, &1, &2)
    )
  end

  defp complete_connection(product_id, opts, {key, {document, operation}}, {:ok, product}) do
    connection = Map.get(product, key, %{})

    if get_in(connection, ["pageInfo", "hasNextPage"]),
      do: collect_remaining_connection(product_id, opts, key, document, operation, product),
      else: {:cont, {:ok, product}}
  end

  defp collect_remaining_connection(product_id, opts, key, document, operation, product) do
    connection = Map.fetch!(product, key)
    cursor = get_in(connection, ["pageInfo", "endCursor"])
    existing = connection["nodes"] || []

    case collect_connection(product_id, key, document.(), operation, cursor, existing, opts) do
      {:ok, nodes} ->
        complete = %{"nodes" => nodes, "pageInfo" => %{"hasNextPage" => false}}
        {:cont, {:ok, Map.put(product, key, complete)}}

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  defp complete_inventory_levels(product, opts) do
    variants = get_in(product, ["variants", "nodes"]) || []

    Enum.reduce_while(variants, {:ok, []}, fn variant, {:ok, acc} ->
      case complete_variant_inventory_levels(variant, opts) do
        {:ok, variant} -> {:cont, {:ok, [variant | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, variants} -> {:ok, put_in(product, ["variants", "nodes"], Enum.reverse(variants))}
      {:error, error} -> {:error, error}
    end
  end

  defp complete_variant_inventory_levels(%{"inventoryItem" => item} = variant, opts)
       when is_map(item) do
    connection = item["inventoryLevels"] || %{}
    page_info = connection["pageInfo"] || %{}

    if page_info["hasNextPage"] do
      case collect_inventory_levels(
             item["id"],
             page_info["endCursor"],
             connection["nodes"] || [],
             opts
           ) do
        {:ok, levels} ->
          {:ok, put_in(variant, ["inventoryItem", "inventoryLevels"], %{"nodes" => levels})}

        {:error, error} ->
          {:error, error}
      end
    else
      {:ok, variant}
    end
  end

  defp complete_variant_inventory_levels(variant, _opts), do: {:ok, variant}

  defp collect_inventory_levels(item_id, cursor, acc, opts) do
    variables = %{"id" => item_id, "after" => cursor}

    with {:ok, response} <-
           request(
             Documents.inventory_item_levels(),
             variables,
             "BrandoShopifyInventoryItemLevels",
             opts
           ),
         connection when is_map(connection) <-
           get_in(response.data, ["inventoryItem", "inventoryLevels"]) do
      levels = acc ++ (connection["nodes"] || [])
      page_info = connection["pageInfo"] || %{}

      if page_info["hasNextPage"] do
        collect_inventory_levels(item_id, page_info["endCursor"], levels, opts)
      else
        {:ok, levels}
      end
    else
      {:error, error} -> {:error, error}
      _ -> {:error, invalid_response("Shopify omitted inventoryItem.inventoryLevels")}
    end
  end

  defp collect_connection(product_id, key, document, operation, cursor, acc, opts) do
    variables = %{"id" => product_id, "after" => cursor}

    with {:ok, response} <- request(document, variables, operation, opts),
         connection when is_map(connection) <- get_in(response.data, ["product", key]) do
      nodes = acc ++ (connection["nodes"] || [])
      page_info = connection["pageInfo"] || %{}

      if page_info["hasNextPage"] do
        collect_connection(
          product_id,
          key,
          document,
          operation,
          page_info["endCursor"],
          nodes,
          opts
        )
      else
        {:ok, nodes}
      end
    else
      {:error, error} -> {:error, error}
      _ -> {:error, invalid_response("Shopify omitted product.#{key}")}
    end
  end

  defp collect_updated(cursor, query, acc, opts) do
    variables = %{"after" => cursor, "query" => query}

    with {:ok, response} <-
           request(
             Documents.products_updated(),
             variables,
             "BrandoShopifyProductsUpdated",
             opts
           ),
         connection when is_map(connection) <- response.data["products"] do
      products = acc ++ (connection["nodes"] || [])
      page_info = connection["pageInfo"] || %{}

      if page_info["hasNextPage"] do
        collect_updated(page_info["endCursor"], query, products, opts)
      else
        {:ok, products}
      end
    else
      {:error, error} -> {:error, error}
      _ -> {:error, invalid_response("Shopify omitted the products connection")}
    end
  end

  defp collect_collection(collection_id, cursor, collection, product_ids, opts) do
    variables = %{"id" => collection_id, "after" => cursor}

    with {:ok, response} <-
           request(
             Documents.collection(),
             variables,
             "BrandoShopifyCollection",
             opts
           ) do
      collect_collection_page(
        response.data["collection"],
        collection_id,
        collection,
        product_ids,
        opts
      )
    end
  end

  defp collect_collection_page(nil, _collection_id, _collection, _product_ids, _opts),
    do: {:ok, nil}

  defp collect_collection_page(node, collection_id, collection, product_ids, opts) do
    connection = node["products"] || %{}
    ids = product_ids ++ Enum.map(connection["nodes"] || [], & &1["id"])
    page_info = connection["pageInfo"] || %{}
    base = collection || Map.delete(node, "products")

    if page_info["hasNextPage"],
      do: collect_collection(collection_id, page_info["endCursor"], base, ids, opts),
      else: {:ok, Map.put(base, "productIds", ids)}
  end

  defp request(document, variables, operation_name, opts) do
    request_opts =
      [
        operation_name: operation_name,
        store: opts[:store] || :default,
        req_options: opts[:req_options] || []
      ]
      |> maybe_put(:config, opts[:config])
      |> maybe_put(:http, opts[:http])

    GraphQL.request(:admin, document, variables, request_opts)
  end

  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso8601(value) when is_binary(value), do: value

  defp user_errors(errors) do
    %Error{kind: :user, message: error_message(errors), errors: errors}
  end

  defp invalid_response(message), do: %Error{kind: :invalid_response, message: message}

  defp error_message([%{"message" => message} | _]), do: message
  defp error_message(_), do: "Shopify rejected the Admin API operation"

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
