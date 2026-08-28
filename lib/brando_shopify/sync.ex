defmodule BrandoShopify.Sync do
  @moduledoc """
  Catalog synchronization entry points.

  Product webhooks call `sync_product/2`; scheduled reconciliation calls
  `reconcile/2`; initial and large resyncs use Shopify bulk operations.
  """

  import Ecto.Query, only: [from: 2]

  alias BrandoShopify.Admin
  alias BrandoShopify.Catalog.InventoryItem
  alias BrandoShopify.Catalog.Product
  alias BrandoShopify.Catalog.Variant
  alias BrandoShopify.Config
  alias BrandoShopify.Error
  alias BrandoShopify.Storefront
  alias BrandoShopify.Sync.BulkImporter
  alias BrandoShopify.Sync.InventoryBulkImporter
  alias BrandoShopify.Sync.Persister
  alias BrandoShopify.Sync.Run

  @doc "Fetches and atomically upserts one complete Shopify product."
  def sync_product(product_id, opts \\ []) when is_binary(product_id) do
    store = opts[:store] || :default
    config = opts[:config] || Config.fetch!(store)
    repo = Config.repo!(config)

    case Admin.fetch_product(product_id,
           config: config,
           req_options: opts[:req_options] || []
         ) do
      {:ok, nil} -> Persister.delete_product(repo, config.name, product_id)
      {:ok, remote_product} -> persist_synced_product(repo, config, remote_product, opts)
      {:error, error} -> {:error, error}
    end
  end

  defp persist_synced_product(repo, config, remote_product, opts) do
    with {:ok, product} <- Persister.persist_product(repo, config.name, remote_product),
         :ok <- sync_product_contexts(product, config, opts) do
      {:ok, product}
    end
  end

  @doc "Re-syncs the product owning a legacy Shopify inventory item ID."
  def sync_inventory_item(inventory_item_id, opts \\ []) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)

    with {:ok, legacy_resource_id} <- normalize_legacy_id(inventory_item_id) do
      product_id =
        from(item in InventoryItem,
          join: variant in Variant,
          on: item.variant_id == variant.id,
          join: product in Product,
          on: variant.product_id == product.id,
          where:
            item.store == ^to_string(config.name) and
              item.legacy_resource_id == ^legacy_resource_id,
          select: product.shopify_id,
          limit: 1
        )
        |> repo.one()

      if product_id do
        sync_product(product_id, Keyword.put(opts, :config, config))
      else
        :ok
      end
    end
  end

  @doc "Tombstones one product after a `products/delete` webhook."
  def delete_product(product_id, opts \\ []) when is_binary(product_id) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    Persister.delete_product(Config.repo!(config), config.name, product_id)
  end

  @doc "Fetches and atomically replaces one Shopify collection and its membership."
  def sync_collection(collection_id, opts \\ []) when is_binary(collection_id) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)

    case Admin.fetch_collection(collection_id, config: config) do
      {:ok, nil} ->
        Persister.delete_collection(repo, config.name, collection_id)

      {:ok, collection} ->
        with :ok <- sync_missing_products(collection["productIds"] || [], config) do
          Persister.persist_collection(repo, config.name, collection)
        end

      {:error, error} ->
        {:error, error}
    end
  end

  @doc "Tombstones one collection after a `collections/delete` webhook."
  def delete_collection(collection_id, opts \\ []) when is_binary(collection_id) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    Persister.delete_collection(Config.repo!(config), config.name, collection_id)
  end

  @doc "Starts a scalable Shopify bulk export and records the run."
  def start_full(opts \\ []) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)
    now = DateTime.utc_now()

    with {:ok, run} <-
           insert_run(repo, config, :full, :pending, now) do
      case Admin.start_bulk_products(config: config) do
        {:ok, operation} ->
          run
          |> Run.changeset(%{
            status: :running,
            shopify_operation_id: operation["id"]
          })
          |> repo.update()

        {:error, error} ->
          fail_run(repo, run, error)
          {:error, error}
      end
    end
  end

  @doc """
  Finishes a recorded bulk run after Shopify reports it complete.

  The result URL is a short-lived signed URL, so callers should invoke this
  promptly from the `bulk_operations/finish` webhook worker.
  """
  def complete_bulk(operation_id, opts \\ []) when is_binary(operation_id) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)

    with %Run{} = run <- run_for_operation(repo, config, operation_id),
         {:ok, operation} <- Admin.bulk_operation(operation_id, config: config),
         {:ok, _run} = result <- complete_bulk_phase(repo, config, run, operation) do
      result
    else
      nil ->
        {:error,
         %Error{
           kind: :invalid_response,
           message: "No local sync run exists for Shopify operation #{operation_id}"
         }}

      {:error, error} ->
        mark_bulk_failed(repo, config, operation_id, error)
        {:error, error}
    end
  end

  defp complete_bulk_phase(repo, config, %Run{phase: :products} = run, operation) do
    with {:ok, result} <- import_completed_products(repo, config, operation),
         {:ok, inventory_operation} <- Admin.start_bulk_inventory(config: config) do
      run
      |> Run.changeset(%{
        phase: :inventory,
        status: :running,
        shopify_operation_id: inventory_operation["id"],
        object_count: result.products,
        file_size: integer(operation["fileSize"]),
        error: nil
      })
      |> repo.update()
    end
  end

  defp complete_bulk_phase(repo, config, %Run{phase: :inventory} = run, operation) do
    with {:ok, _result} <- import_completed_inventory(repo, config, operation),
         {:ok, _inventory_tombstones} <-
           Persister.tombstone_inventory_synced_before(repo, config.name, run.updated_at),
         {:ok, _product_tombstones} <-
           Persister.tombstone_products_synced_before(repo, config.name, run.started_at),
         :ok <- sync_contexts_since(repo, config, run.started_at) do
      run
      |> Run.changeset(%{
        status: :completed,
        file_size: (run.file_size || 0) + (integer(operation["fileSize"]) || 0),
        completed_at: DateTime.utc_now(),
        error: nil
      })
      |> repo.update()
    end
  end

  @doc "Re-fetches everything Shopify reports as updated since a timestamp."
  def reconcile(since, opts \\ []) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)
    now = DateTime.utc_now()

    with {:ok, run} <- insert_run(repo, config, :reconcile, :running, now) do
      case reconcile_products(since, config) do
        {:ok, count} = result ->
          run
          |> Run.changeset(%{
            status: :completed,
            object_count: count,
            completed_at: DateTime.utc_now()
          })
          |> repo.update!()

          result

        {:error, error} = result ->
          fail_run(repo, run, error)
          result
      end
    end
  end

  @doc "Returns the most recent completed synchronization time."
  def last_completed_at(opts \\ []) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)

    from(run in Run,
      where: run.store == ^to_string(config.name) and run.status == :completed,
      order_by: [desc: run.completed_at],
      limit: 1,
      select: run.completed_at
    )
    |> repo.one()
  end

  defp run_for_operation(repo, config, operation_id) do
    from(run in Run,
      where:
        run.store == ^to_string(config.name) and
          run.shopify_operation_id == ^operation_id,
      limit: 1
    )
    |> repo.one()
  end

  defp import_completed_products(repo, config, %{"status" => "COMPLETED", "url" => url})
       when is_binary(url) do
    BulkImporter.download_and_import(
      repo,
      config.name,
      url,
      config.req_options
    )
  end

  defp import_completed_products(_repo, _config, %{"status" => "COMPLETED", "url" => nil}) do
    {:ok, %{products: 0, objects: 0}}
  end

  defp import_completed_products(_repo, _config, operation) do
    {:error,
     %Error{
       kind: :invalid_response,
       message:
         "Shopify bulk operation is #{if is_map(operation), do: operation["status"], else: "unavailable"}",
       details: operation
     }}
  end

  defp import_completed_inventory(repo, config, %{"status" => "COMPLETED", "url" => url})
       when is_binary(url) do
    InventoryBulkImporter.download_and_import(
      repo,
      config.name,
      url,
      config.req_options
    )
  end

  defp import_completed_inventory(_repo, _config, %{"status" => "COMPLETED", "url" => nil}) do
    {:ok, %{items: 0, levels: 0, objects: 0}}
  end

  defp import_completed_inventory(_repo, _config, operation) do
    {:error,
     %Error{
       kind: :invalid_response,
       message:
         "Shopify inventory bulk operation is #{if is_map(operation), do: operation["status"], else: "unavailable"}",
       details: operation
     }}
  end

  defp mark_bulk_failed(repo, config, operation_id, error) do
    case run_for_operation(repo, config, operation_id) do
      %Run{} = run ->
        fail_run(repo, run, error)

      nil ->
        :ok
    end
  end

  defp error_payload(%Error{} = error),
    do: %{kind: error.kind, message: error.message, status: error.status}

  defp error_payload(error), do: %{message: inspect(error)}

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp integer(_), do: nil

  defp insert_run(repo, config, kind, status, started_at) do
    repo.insert(
      Run.changeset(%Run{}, %{
        store: to_string(config.name),
        kind: kind,
        status: status,
        started_at: started_at
      })
    )
  end

  defp fail_run(repo, run, error) do
    run
    |> Run.changeset(%{
      status: :failed,
      completed_at: DateTime.utc_now(),
      error: error_payload(error)
    })
    |> repo.update()
  end

  defp reconcile_products(since, config) do
    case Admin.product_ids_updated_since(since, config: config) do
      {:ok, products} -> reconcile_product_list(products, config)
      {:error, error} -> {:error, error}
    end
  end

  defp reconcile_product_list(products, config) do
    Enum.reduce_while(products, {:ok, 0}, fn %{"id" => id}, {:ok, count} ->
      reconcile_product(id, count, config)
    end)
  end

  defp reconcile_product(id, count, config) do
    case sync_product(id, config: config) do
      {:ok, _} -> {:cont, {:ok, count + 1}}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp sync_missing_products(product_ids, config) do
    repo = Config.repo!(config)

    existing =
      from(product in BrandoShopify.Catalog.Product,
        where:
          product.store == ^to_string(config.name) and product.shopify_id in ^product_ids and
            is_nil(product.deleted_at),
        select: product.shopify_id
      )
      |> repo.all()
      |> MapSet.new()

    product_ids
    |> Enum.reject(&MapSet.member?(existing, &1))
    |> Enum.reduce_while(:ok, fn product_id, :ok ->
      case sync_product(product_id, config: config) do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp sync_product_contexts(product, config, opts) do
    Enum.reduce_while(config.catalog_contexts, :ok, fn context, :ok ->
      sync_product_context(product, context, config, opts)
    end)
  end

  defp sync_product_context(product, context, config, opts) do
    storefront_opts = [
      config: config,
      country: context.country,
      language: context.language,
      include_selling_plans: context.sync_selling_plans,
      req_options: opts[:req_options] || []
    ]

    case Storefront.product_by_id(product.shopify_id, storefront_opts) do
      {:ok, nil} -> delete_product_context(product, context, config)
      {:ok, remote_product} -> persist_product_context(product, context, config, remote_product)
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp delete_product_context(product, context, config) do
    Config.repo!(config)
    |> Persister.delete_product_context(config.name, context.key, product.id)
    |> context_sync_result()
  end

  defp persist_product_context(product, context, config, remote_product) do
    Config.repo!(config)
    |> Persister.persist_product_context(config.name, context, product, remote_product)
    |> context_sync_result()
  end

  defp context_sync_result({:ok, _}), do: {:cont, :ok}
  defp context_sync_result({:error, error}), do: {:halt, {:error, error}}

  defp sync_contexts_since(_repo, %{catalog_contexts: []}, _since), do: :ok

  defp sync_contexts_since(repo, config, since) do
    from(product in Product,
      where:
        product.store == ^to_string(config.name) and product.synced_at >= ^since and
          is_nil(product.deleted_at),
      order_by: [asc: product.id]
    )
    |> repo.all()
    |> Enum.reduce_while(:ok, fn product, :ok ->
      case sync_product_contexts(product, config, []) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp normalize_legacy_id(id) when is_integer(id), do: {:ok, id}

  defp normalize_legacy_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> {:ok, integer}
      _ -> {:error, {:invalid_inventory_item_id, id}}
    end
  end

  defp normalize_legacy_id(id), do: {:error, {:invalid_inventory_item_id, id}}
end
