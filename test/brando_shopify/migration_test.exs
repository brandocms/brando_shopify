defmodule BrandoShopify.MigrationTest do
  use ExUnit.Case, async: true

  test "installer migration is valid Elixir and declares every projection table" do
    path =
      Application.app_dir(
        :brando_shopify,
        "priv/templates/brando_shopify.install/migration.exs"
      )

    source = File.read!(path)

    assert [{BrandoShopify.Repo.Migrations.CreateShopifyCatalog, _bytecode}] =
             Code.compile_string(source, path)

    for table <- [
          "shopify_products",
          "shopify_product_variants",
          "shopify_product_contexts",
          "shopify_product_context_variants",
          "shopify_inventory_items",
          "shopify_inventory_levels",
          "shopify_collections",
          "shopify_collection_products",
          "shopify_sync_runs",
          "shopify_webhook_receipts"
        ] do
      assert source =~ "table(:#{table}"
    end
  end
end
