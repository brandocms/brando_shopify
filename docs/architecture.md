# Architecture

## Design goal

Product content must be available to Brando templates, editor tooling, search,
and page caches without a Shopify network dependency on every request. At the
same time, Brando must not become a second commerce authority.

The integration therefore uses a **local read projection with live commerce
edges**:

| Concern | Authority | Request-time Shopify call? |
|---|---|---:|
| Title, handle, descriptions, vendor, tags, options, SEO | Local synchronized catalog | No |
| Variant identity, SKU, barcode, base price | Local synchronized catalog | No |
| Product media, product metafields, collections | Local synchronized catalog | No |
| Inventory items and per-location levels | Local synchronized catalog | No |
| Configured country/language price, translation, availability | Local contextual projection | No |
| Optional selling plans for a configured context | Local contextual projection | No |
| Cart lines, discounts, calculated totals | Storefront Cart API | Yes |
| Checkout | Shopify checkout | Yes |
| Customer identity/order history | Customer Account API, future module | Yes |
| Brando storytelling/layout/editorial fields | Application Blueprint | No |

## Catalog projection

The base product tables, contextual product tables, inventory tables, collection
tables, and joins are read-only from the CMS perspective. Sync owns commerce
fields. Application Blueprints should relate to the local product row for
Brando-authored content rather than writing into Shopify-owned columns.

The projection has three deliberate layers:

- `shopify_products` and `shopify_product_variants` contain the shop-wide Admin
  graph and base prices;
- `shopify_product_contexts` and `shopify_product_context_variants` contain the
  Storefront view for each configured country/language key; and
- `shopify_inventory_items` and `shopify_inventory_levels` preserve the
  inventory-item/location model instead of collapsing every location into one
  ambiguous integer.

`Catalog.get_contextual_product_by_handle/3` returns only an exact synchronized
context. There is intentionally no fallback to the base product: a fallback can
show the wrong currency, publication state, or translated content while looking
plausibly correct. Sync also checks Shopify's Storefront response `context`
extension and rejects the write when Shopify applied a different country or
language than requested.

Records are tombstoned on delete. That preserves a product's database identity
and prevents an existing CMS relation from suddenly pointing at an unrelated
record. Public catalog queries hide tombstones by default.

Every projected record includes:

- normalized, typed columns for common queries and templates;
- `remote_updated_at`, `synced_at`, and `deleted_at` lifecycle timestamps; and
- `source_data`, preserving the returned Shopify node for forward-compatible
  access to fields already present in the query.

Adding a new Shopify field is deliberate: add it to the Admin selection,
migration/schema, mapper, tests, and documentation. GraphQL has no safe
“select everything” operation, and an unbounded product graph includes
buyer-specific or separately permissioned resources that should not be cached
as a single global value.

## Synchronization

There are three complementary paths:

1. Initial/full import uses two sequential Admin Bulk Operations: one for the
   five-connection product graph and one for inventory items/levels. Their JSONL
   responses are streamed one root resource at a time. Splitting the phases
   respects Shopify's five-connection bulk-query limit.
2. HTTPS webhooks provide low-latency create, update, and delete signals. The
   raw body is HMAC-verified, the shop domain is checked, and the webhook ID is
   stored before an Oban job is acknowledged.
3. Reconciliation queries product IDs changed since the last completed run and
   re-fetches each complete product. This repairs delayed, missed, duplicated,
   or out-of-order delivery.

Product updates are transactionally upserted. Missing variants, inventory
items/levels, and contextual variants are tombstoned. Collection memberships
are replaced only after all pages of the relevant Shopify connection have been
fetched. Product variant and inventory-level pagination is followed explicitly.

After the Admin projection commits, sync fetches every configured Storefront
context. That request is synchronization work, not template-side hydration.
The context stores localized presentation, contextual price/currency and
availability, and optionally selling-plan groups plus variant allocations.
Full bulk imports hydrate the same contexts before the run is marked complete.

Inventory-level and inventory-item webhooks enqueue a sync of the owning
product. This deliberately re-fetches current Admin and contextual state instead
of trusting a partial webhook body. Product reconciliation remains the repair
path for missed signals.

`synced_at` is the local freshness watermark. `Catalog.fresh?/2` and
`Catalog.stale?/2` make page-level freshness policies explicit. A local
inventory or availability value is a display snapshot, never a reservation;
the live Cart API remains authoritative when a buyer acts.

Webhooks are signals, not authoritative product payloads. Workers re-fetch the
current product graph, so an older webhook processed after a newer one cannot
overwrite the database with stale event data.

## Cart security

Shopify cart IDs contain a secret query component. `Plug.Cart` stores the
complete ID only after encrypting it with the endpoint's `secret_key_base`.
Consequently, a signed-but-readable cookie session still doesn't disclose it.
JSON returned to the browser removes both `id` and `checkoutUrl`; checkout
obtains a fresh URL only after a same-origin, CSRF-protected action.

Private Storefront tokens stay on the server. The buyer IP is forwarded for
buyer-originated private-token requests as Shopify requires. The optional web
component contains no Shopify credentials and can be replaced by any frontend
that follows the same JSON endpoint.

## Failure model

- Admin and Storefront operations return structured `BrandoShopify.Error`
  values. Tokens and request headers are never included.
- Mutations are not automatically retried at the HTTP layer. Oban retries the
  complete idempotent sync operation instead.
- Bulk files are streamed to a temporary file and deleted after import.
- `shopify_webhook_receipts` provides durable delivery idempotency.
- Telemetry events bracket every GraphQL call:
  `[:brando_shopify, :graphql, :request, :start | :stop]`.

## Extension points

- multiple named stores in `config :brando_shopify, :stores`;
- runtime secret functions or MFA values for rotation;
- `BrandoShopify.Webhook.Handler` for custom topic handling;
- custom Req options and a store-level or per-call injectable HTTP module;
- a headless or fully custom cart renderer;
- application-owned Brando Blueprints related to local product IDs.
