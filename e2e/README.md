# BrandoShopify E2E consumer

This is a standalone Phoenix consumer owned by `brando_shopify`. Brando does
not depend on this package or carry its test fixtures.

By default, `mix deps.get` fetches `brandocms/brando` from the `next` branch.
During local development, point the same dependency edge at a checkout:

```console
export BRANDO_PATH=/Users/trond/dev/elixir/brando_next
```

Prepare PostgreSQL, Elixir dependencies, Playwright, and Chromium:

```console
cd e2e
./setup_e2e.sh
```

Run the deterministic suite:

```console
./test_e2e.sh tests/catalog-cart.spec.js
```

The default database URL is
`postgres://postgres:postgres@localhost/brando_shopify_e2e`. Override it with
`SHOPIFY_E2E_DATABASE_URL`. The default HTTP port is 4455; override it with
`PLAYWRIGHT_PORT`.

The app intentionally starts only the integration surface it needs: its Repo,
Oban, Phoenix endpoint, Shopify transport simulator, and Brando-powered HTML
templates. It does not start Brando's full CMS supervisor because that would
turn this focused package contract into a test of every Brando schema and
runtime service.

See the [maintainer testing strategy](../dev/testing.md) for the boundary
between this deterministic suite and the opt-in live Shopify contract test.
