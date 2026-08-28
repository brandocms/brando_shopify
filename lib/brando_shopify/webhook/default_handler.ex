defmodule BrandoShopify.Webhook.DefaultHandler do
  @moduledoc """
  Persists webhook idempotency receipts and enqueues small Oban jobs.

  The webhook request never performs an Admin API fetch. That keeps responses
  fast enough for Shopify while retries happen safely in the job queue.
  """

  @behaviour BrandoShopify.Webhook.Handler

  require Logger

  alias BrandoShopify.Catalog.Collection
  alias BrandoShopify.Catalog.Product
  alias BrandoShopify.Config
  alias BrandoShopify.Webhook.Receipt
  alias BrandoShopify.Workers.Bulk
  alias BrandoShopify.Workers.Collection, as: CollectionWorker
  alias BrandoShopify.Workers.Inventory, as: InventoryWorker
  alias BrandoShopify.Workers.Product, as: ProductWorker

  @impl true
  def handle(metadata, payload, %Config{} = config) do
    repo = Config.repo!(config)
    now = DateTime.utc_now()

    receipt = %{
      webhook_id: metadata.webhook_id,
      event_id: metadata.event_id,
      store: to_string(config.name),
      shop_domain: metadata.shop_domain,
      topic: metadata.topic,
      api_version: metadata.api_version,
      triggered_at: metadata.triggered_at,
      inserted_at: now
    }

    repo.transaction(fn -> persist_receipt(repo, receipt, metadata, payload, config) end)
    |> case do
      {:ok, result} -> result
      {:error, error} -> {:error, error}
    end
  end

  defp persist_receipt(repo, receipt, metadata, payload, config) do
    case repo.insert_all(Receipt, [receipt],
           on_conflict: :nothing,
           conflict_target: [:webhook_id]
         ) do
      {0, _} -> :duplicate
      {1, _} -> enqueue_job(repo, job(metadata.topic, payload, config.name), config)
    end
  end

  defp enqueue_job(_repo, nil, _config), do: :ignored

  defp enqueue_job(repo, changeset, config) do
    case Oban.insert(config.oban_name, changeset) do
      {:ok, %Oban.Job{conflict?: true} = job} ->
        # Debounced against an already-pending job for the same resource. Log it,
        # so a uniqueness window that is too wide never silently drops a change.
        Logger.debug("Shopify webhook job debounced: #{job.worker} #{inspect(job.args)}")

        :ok

      {:ok, _job} ->
        :ok

      {:error, changeset} ->
        repo.rollback(changeset)
    end
  end

  defp job(topic, payload, store) when topic in ["products/create", "products/update"] do
    with id when is_binary(id) <- resource_gid(payload, Product) do
      ProductWorker.new(%{store: to_string(store), action: "sync", product_id: id})
    end
  end

  defp job("products/delete", payload, store) do
    with id when is_binary(id) <- resource_gid(payload, Product) do
      ProductWorker.new(%{store: to_string(store), action: "delete", product_id: id})
    end
  end

  defp job(topic, payload, store)
       when topic in ["collections/create", "collections/update"] do
    with id when is_binary(id) <- resource_gid(payload, Collection) do
      CollectionWorker.new(%{
        store: to_string(store),
        action: "sync",
        collection_id: id
      })
    end
  end

  defp job("collections/delete", payload, store) do
    with id when is_binary(id) <- resource_gid(payload, Collection) do
      CollectionWorker.new(%{
        store: to_string(store),
        action: "delete",
        collection_id: id
      })
    end
  end

  defp job("bulk_operations/finish", payload, store) do
    case payload["admin_graphql_api_id"] || payload["id"] do
      id when is_binary(id) ->
        Bulk.new(%{store: to_string(store), operation_id: normalize_gid(id, "BulkOperation")})

      id when is_integer(id) ->
        Bulk.new(%{
          store: to_string(store),
          operation_id: normalize_gid(id, "BulkOperation")
        })

      _ ->
        nil
    end
  end

  defp job(topic, payload, store)
       when topic in [
              "inventory_levels/update",
              "inventory_levels/connect",
              "inventory_levels/disconnect",
              "inventory_items/update",
              "inventory_items/delete"
            ] do
    with id when not is_nil(id) <- inventory_item_id(payload),
         id when is_binary(id) <- normalize_integer(id) do
      InventoryWorker.new(%{store: to_string(store), inventory_item_id: id})
    end
  end

  defp job(_topic, _payload, _store), do: nil

  defp resource_gid(payload, Product),
    do: payload["admin_graphql_api_id"] || normalize_gid(payload["id"], "Product")

  defp resource_gid(payload, Collection),
    do: payload["admin_graphql_api_id"] || normalize_gid(payload["id"], "Collection")

  defp normalize_gid("gid://shopify/" <> _ = gid, _type), do: gid
  defp normalize_gid(id, type) when is_integer(id), do: "gid://shopify/#{type}/#{id}"
  defp normalize_gid(id, type) when is_binary(id), do: "gid://shopify/#{type}/#{id}"
  defp normalize_gid(_, _type), do: nil

  defp inventory_item_id(payload) do
    payload["inventory_item_id"] || payload["legacy_resource_id"] || payload["id"] ||
      legacy_id_from_gid(payload["admin_graphql_api_id"])
  end

  defp legacy_id_from_gid("gid://shopify/InventoryItem/" <> id), do: id
  defp legacy_id_from_gid(_), do: nil

  defp normalize_integer(id) when is_integer(id), do: Integer.to_string(id)

  defp normalize_integer(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> Integer.to_string(integer)
      _ -> nil
    end
  end

  defp normalize_integer(_), do: nil
end
