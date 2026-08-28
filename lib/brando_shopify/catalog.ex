defmodule BrandoShopify.Catalog do
  @moduledoc """
  Queries Brando's local Shopify catalog projection.

  All queries hide tombstoned records by default. Pass `include_deleted: true`
  for administrative repair work.
  """

  import Ecto.Query, only: [from: 2]

  alias BrandoShopify.Catalog.Product
  alias BrandoShopify.Catalog.ProductContext
  alias BrandoShopify.Catalog.Variant
  alias BrandoShopify.Config

  @doc "Lists locally synced products with optional search and preloads."
  def list_products(opts \\ []) do
    config = Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)
    limit = min(max(opts[:limit] || 50, 1), 250)

    Product
    |> where_store(config)
    |> maybe_hide_deleted(opts)
    |> maybe_search(opts[:search])
    |> from(order_by: [asc: :title], limit: ^limit)
    |> repo.all()
    |> maybe_preload(repo, opts[:preload])
  end

  @doc "Fetches a local product by its Shopify GID."
  def get_product(shopify_id, opts \\ []) when is_binary(shopify_id) do
    config = Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)

    Product
    |> where_store(config)
    |> maybe_hide_deleted(opts)
    |> from(where: [shopify_id: ^shopify_id])
    |> repo.one()
    |> maybe_preload_one(repo, opts[:preload])
  end

  @doc "Fetches a local product by handle."
  def get_product_by_handle(handle, opts \\ []) when is_binary(handle) do
    config = Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)

    Product
    |> where_store(config)
    |> maybe_hide_deleted(opts)
    |> from(where: [handle: ^handle])
    |> repo.one()
    |> maybe_preload_one(repo, opts[:preload])
  end

  @doc "Fetches a local product by handle and raises when it is missing."
  def get_product_by_handle!(handle, opts \\ []) when is_binary(handle) do
    case get_product_by_handle(handle, opts) do
      %Product{} = product -> product
      nil -> raise Ecto.NoResultsError, queryable: Product
    end
  end

  @doc """
  Fetches a locally synchronized product in a configured Storefront context.

  The returned `ProductContext` exposes translated content, contextual prices,
  contextual variants, and optional selling plans without making a Shopify API
  request. It does not fall back to base prices when the requested context is
  missing.
  """
  def get_contextual_product_by_handle(handle, context_key, opts \\ [])
      when is_binary(handle) do
    config = Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)
    context_key = to_string(context_key)

    from(
      context in ProductContext,
      as: :context,
      join: product in assoc(context, :product),
      as: :product,
      where:
        context.store == ^to_string(config.name) and context.context_key == ^context_key and
          (product.handle == ^handle or context.handle == ^handle)
    )
    |> maybe_hide_context_deleted(opts)
    |> repo.one()
    |> maybe_preload_one(repo, opts[:preload] || [:variants, :product])
  end

  @doc "Fetches location-level inventory for a local variant."
  def inventory_levels(%Variant{} = variant, opts \\ []) do
    config = Config.fetch!(opts[:store] || variant.store || :default)
    repo = Config.repo!(config)

    from(level in BrandoShopify.Catalog.InventoryLevel,
      join: item in assoc(level, :inventory_item),
      where:
        item.variant_id == ^variant.id and level.store == ^to_string(config.name) and
          (is_nil(level.deleted_at) or ^Keyword.get(opts, :include_deleted, false)),
      order_by: [asc: level.location_name]
    )
    |> repo.all()
  end

  @doc "Returns true when a projected record was synchronized within `:max_age` seconds."
  def fresh?(record, opts \\ [])

  def fresh?(%{synced_at: %DateTime{} = synced_at}, opts) do
    now = opts[:now] || DateTime.utc_now()
    max_age = opts[:max_age] || 900
    DateTime.diff(now, synced_at, :second) <= max_age
  end

  def fresh?(_record, _opts), do: false

  @doc "The inverse of `fresh?/2`."
  def stale?(record, opts \\ []), do: not fresh?(record, opts)

  @doc "Creates the small, stable snapshot useful in Brando content references."
  def reference(%Product{} = product) do
    %{
      "id" => product.shopify_id,
      "handle" => product.handle,
      "title" => product.title,
      "image" => image_url(product.featured_media),
      "type" => "shopify_product"
    }
  end

  defp where_store(query, config),
    do: from(product in query, where: product.store == ^to_string(config.name))

  defp maybe_hide_deleted(query, opts) do
    if opts[:include_deleted],
      do: query,
      else: from(product in query, where: is_nil(product.deleted_at))
  end

  defp maybe_hide_context_deleted(query, opts) do
    if opts[:include_deleted] do
      query
    else
      from([context: context, product: product] in query,
        where: is_nil(context.deleted_at) and is_nil(product.deleted_at)
      )
    end
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    pattern = "%#{search}%"

    from(product in query,
      where:
        ilike(product.title, ^pattern) or ilike(product.handle, ^pattern) or
          ilike(product.vendor, ^pattern)
    )
  end

  defp maybe_preload(products, _repo, nil), do: products
  defp maybe_preload(products, repo, preloads), do: repo.preload(products, preloads)

  defp maybe_preload_one(nil, _repo, _preloads), do: nil
  defp maybe_preload_one(product, _repo, nil), do: product
  defp maybe_preload_one(product, repo, preloads), do: repo.preload(product, preloads)

  defp image_url(%{"preview" => %{"image" => %{"url" => url}}}), do: url
  defp image_url(%{"image" => %{"url" => url}}), do: url
  defp image_url(_), do: nil
end
