defmodule BrandoShopify.WorkersTest do
  @moduledoc """
  Guards the uniqueness configuration of the webhook-driven sync workers.

  Oban's default unique `states` include `:completed`. With a wide `period`
  that means one finished sync silently swallows every later change to the same
  resource until the window expires — an editor adds a second product to a
  collection and the site never hears about it. These workers must therefore
  dedupe against pending work only.
  """

  use ExUnit.Case, async: true

  alias BrandoShopify.Workers.Collection, as: CollectionWorker
  alias BrandoShopify.Workers.Inventory, as: InventoryWorker
  alias BrandoShopify.Workers.Product, as: ProductWorker

  describe "unique configuration" do
    test "collection sync dedupes against pending jobs only" do
      unique = unique_for(CollectionWorker.new(collection_args()))

      refute :completed in unique.states
      assert unique.keys == [:store, :collection_id, :action]
      assert unique.period <= 60
    end

    test "product sync dedupes against pending jobs only" do
      unique = unique_for(ProductWorker.new(product_args()))

      refute :completed in unique.states
      assert unique.keys == [:store, :product_id, :action]
      assert unique.period <= 60
    end

    test "inventory sync dedupes against pending jobs only" do
      unique =
        unique_for(InventoryWorker.new(%{store: "default", inventory_item_id: "1234567890"}))

      refute :completed in unique.states
    end

    test "a repeated change to the same collection is a distinct job" do
      # Same resource, different action: uniqueness must not collapse a delete
      # into an earlier sync.
      sync = unique_args(CollectionWorker.new(collection_args()))
      delete = unique_args(CollectionWorker.new(collection_args(action: "delete")))

      refute sync == delete
    end
  end

  defp collection_args(opts \\ []) do
    %{
      store: "default",
      action: Keyword.get(opts, :action, "sync"),
      collection_id: "gid://shopify/Collection/1"
    }
  end

  defp product_args do
    %{store: "default", action: "sync", product_id: "gid://shopify/Product/1"}
  end

  defp unique_for(changeset), do: Ecto.Changeset.apply_changes(changeset).unique

  defp unique_args(changeset) do
    job = Ecto.Changeset.apply_changes(changeset)

    Map.new(job.unique.keys, fn key ->
      {key, job.args[key] || job.args[to_string(key)]}
    end)
  end
end
