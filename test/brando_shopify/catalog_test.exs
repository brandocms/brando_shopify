defmodule BrandoShopify.CatalogTest do
  use ExUnit.Case, async: true

  alias BrandoShopify.Catalog

  test "freshness is explicit and deterministic" do
    now = ~U[2026-08-01 10:00:00Z]

    assert Catalog.fresh?(%{synced_at: ~U[2026-08-01 09:55:00Z]},
             now: now,
             max_age: 300
           )

    assert Catalog.stale?(%{synced_at: ~U[2026-08-01 09:54:59Z]},
             now: now,
             max_age: 300
           )

    assert Catalog.stale?(%{synced_at: nil}, now: now)
  end
end
