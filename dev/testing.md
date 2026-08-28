# Maintainer testing

This guide documents BrandoShopify's repository test strategy and release
contract. It is intentionally not included in the Hex package or ExDoc guides.

Shopify does not provide a supported hermetic local Shopify runtime. Its
supported app-testing target is a password-protected development store, which
allows test products and orders but does not process real transactions. The
BrandoShopify test strategy therefore has two layers:

1. a deterministic local transport simulator on every CI run; and
2. a small opt-in contract suite against a real Shopify development store.

Official setup references:

- [Development stores](https://shopify.dev/docs/storefronts/themes/tools/development-stores/index)
- [Test apps locally with Shopify CLI](https://shopify.dev/docs/apps/build/cli-for-apps/test-apps-locally)
- [Storefront API and Headless channel setup](https://shopify.dev/docs/storefronts/headless/building-with-the-storefront-api/getting-started)
- [Test Shopify Payments](https://help.shopify.com/en/manual/payments/shopify-payments/testing-shopify-payments)

## What the deterministic suite exercises

The simulator is injected at `BrandoShopify.HTTP`, the package's real network
boundary. It does not replace `Sync`, `Catalog`, the GraphQL documents, the
webhook handler, Oban jobs, Cart, or the browser component.

| Path | Real code under test | Replaced part |
|---|---|---|
| Product page | Admin document → mapper → Ecto upsert → Catalog → Brando template | Shopify HTTP response |
| Product webhook | Raw HMAC verification → receipt idempotency → Oban worker → sync | Shopify HTTP response |
| Context projection | Storefront `@inContext` document → Ecto upsert → local template | Shopify HTTP response |
| Inventory webhook | Receipt → Oban → owning-product refresh → inventory/context rows | Shopify HTTP response |
| Cart UI | Shipped web component → CSRF/session Plug → Storefront Cart operations | Shopify HTTP response |
| Checkout handoff | Fresh checkout query → same-origin JSON → browser navigation | Final Shopify checkout page |

The Playwright assertions pin down these invariants:

- a normal product render performs zero Shopify requests;
- changing the simulated remote product has no visible effect before sync;
- configured translated content and market prices are rendered locally and
  make no request during page rendering;
- invalid HMAC deliveries are rejected;
- valid update webhooks synchronize the complete product and duplicates do not
  fetch it twice;
- inventory-level webhooks refresh location inventory and contextual
  availability through the real worker path;
- cart create, reload, quantity update, removal, and checkout work through the
  actual UI;
- the complete secret-bearing cart ID is encrypted in the session and never
  appears in browser JSON; and
- host CSS cannot expand cart media out of the drawer.

The consumer application lives inside this package at `e2e/`. It depends on
Brando's `next` branch and on the parent `brando_shopify` package. Brando never
depends on this package and its own E2E schema, configuration, assets, and tests
remain untouched.

The E2E application is intentionally narrow. It starts its own Repo, Oban,
Phoenix endpoint, and Shopify simulator, and renders the product page through
Brando's HTML layer. It compiles the integration against Brando `next` without
starting the full CMS supervisor or requiring Brando's unrelated content
schema.

By default Mix fetches `github.com/brandocms/brando` at the `next` branch. For
local development, point that same dependency edge at a checkout:

```console
export BRANDO_PATH=/Users/trond/dev/elixir/brando_next
```

Prepare the isolated database and Playwright once:

```console
cd e2e
./setup_e2e.sh
```

Run the deterministic suite:

```console
cd e2e
./test_e2e.sh tests/catalog-cart.spec.js
```

The harness defaults to port 4455 and a `brando_shopify_e2e` PostgreSQL
database. `PLAYWRIGHT_PORT` and `SHOPIFY_E2E_DATABASE_URL` override those
defaults. Every Playwright test runs in its own Phoenix SQL Sandbox transaction.

## Live development-store contract

The live suite is intentionally small. It catches access-scope, GraphQL schema,
API-version, product-feature, and Storefront cart behavior drift that a fixture
cannot prove. It synchronizes one known product through Admin GraphQL, renders
the local projection, then creates a real development-store cart through
Storefront GraphQL. It retrieves but does not visit or pay through checkout.

Create a development store and a custom app, add a Storefront private token
through the Headless channel, and provide:

```console
export SHOPIFY_E2E_LIVE=1
export SHOPIFY_E2E_SHOP_DOMAIN=example.myshopify.com
export SHOPIFY_E2E_ADMIN_TOKEN=...
export SHOPIFY_E2E_STOREFRONT_TOKEN=...
export SHOPIFY_E2E_PRODUCT_ID=gid://shopify/Product/123
```

Optional values are `SHOPIFY_E2E_STOREFRONT_DOMAIN`,
`SHOPIFY_E2E_API_VERSION`, and `SHOPIFY_E2E_WEBHOOK_SECRET`. Keep credentials in
the CI secret store, never in `.envrc` committed to source control.

Run only the live contract:

```console
cd e2e
PLAYWRIGHT_PORT=4456 ./test_e2e.sh tests/live-contract.spec.js
```

Use a Shopify development store's Bogus Gateway or payment test mode for a
separate manual checkout smoke test. Do not place a real transaction in a
development store.

## Recommended CI schedule

- Every pull request: package unit tests, warnings-as-errors compile, frontend
  consumer build, and deterministic Playwright suite.
- Nightly or before release: live development-store contract.
- Before each quarterly Shopify API upgrade: run the live contract against the
  next release candidate, then update stored fixtures only after reviewing the
  schema changes.

Run the package quality gate locally with:

```console
mix quality
```

This verifies formatting, compiles with warnings as errors, runs the package's
strict Credo and ExSlop rules across both `lib/` and `e2e/lib/`, and executes the
unit suite.
