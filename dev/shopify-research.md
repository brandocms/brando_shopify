# Shopify platform research and decisions

> Maintainer note: this is repository research and decision context, not part
> of the published BrandoShopify API documentation.

Research completed 31 July 2026. Shopify changes quarterly; links below are the
source of truth and should be reviewed during every version upgrade.

## API surfaces

### Admin GraphQL API

The [Admin GraphQL API](https://shopify.dev/docs/api/admin-graphql/2026-07)
is the correct source for product synchronization and store administration.
BrandoShopify targets stable `2026-07` explicitly. Shopify versions APIs
quarterly, supports stable versions for at least twelve months, and can fall
forward unsupported requests, so the response API-version header is retained
for observability; see [API versioning](https://shopify.dev/docs/api/usage/versioning).

The REST Admin API is legacy, and new public apps have been required to use
GraphQL Admin since April 2025. The package therefore has no REST compatibility
layer; see Shopify's [GraphQL migration guide](https://shopify.dev/docs/apps/build/graphql/migrate).

Admin GraphQL is cost-throttled. Large initial imports should not page the whole
catalog through request/response calls. Shopify's
[bulk query operations](https://shopify.dev/docs/api/usage/bulk-operations/queries)
produce JSONL, support multiple concurrent operations on current versions, and
recommend webhook completion with polling as a fallback. Bulk queries allow at
most five connections, so BrandoShopify runs product and inventory exports as
two sequential phases. It streams both and keeps ordinary per-product pagination
for webhook updates.

### Storefront GraphQL API

The [Storefront API](https://shopify.dev/docs/api/storefront/2026-07) owns
buyer-facing product context, carts, and checkout handoff. It supports public,
private, and tokenless access depending on the schema field. A private token
must stay server-side, and buyer-originated server calls should include the
buyer-IP header; see [Shopify API authentication](https://shopify.dev/docs/api/usage/authentication).

Shopify does not apply the Admin calculated-query-cost model to Storefront API
requests, but still applies abuse controls and input limits. Arrays are capped
at 250 items; see [API limits](https://shopify.dev/docs/api/usage/limits#rate-limits).

The package does not use Storefront GraphQL for ordinary page rendering.
Instead, background sync persists configured views under Shopify's
[`@inContext`](https://shopify.dev/docs/storefronts/headless/building-with-the-storefront-api/in-context)
country/language model. This is the right escape hatch for
[Shopify Markets](https://shopify.dev/docs/storefronts/headless/building-with-the-storefront-api/markets),
where the same product can have a different price, currency, availability, or
publication state for each buyer context. Exact-context catalog queries do not
fall back to a global price. Direct Storefront helpers remain available for
explicit live work, but the template API never invokes them implicitly.

Shopify exposes inventory through `InventoryItem` and per-location
`InventoryLevel` resources. The projection stores both and subscribes to
inventory-item/level signals; see Shopify's
[InventoryItem](https://shopify.dev/docs/api/admin-graphql/latest/objects/InventoryItem),
[InventoryLevel](https://shopify.dev/docs/api/admin-graphql/latest/objects/InventoryLevel),
and [webhook topic enum](https://shopify.dev/docs/api/admin-graphql/latest/enums/WebhookSubscriptionTopic).

Selling plans require `unauthenticated_read_selling_plans` and are explicitly
opt-in per context. When enabled, group/plan definitions and variant allocations
are synchronized locally for selection UI. Shopify Cart still calculates the
authoritative result; see
[SellingPlan](https://shopify.dev/docs/api/storefront/latest/objects/SellingPlan)
and [SellingPlanAllocation](https://shopify.dev/docs/api/storefront/latest/objects/SellingPlanAllocation).

### Cart and checkout

Shopify's [Cart object](https://shopify.dev/docs/api/storefront/latest/objects/Cart)
and cart mutations are the modern headless cart. Shopify warns that a cart ID's
secret component must not be exposed; the
[cart management guide](https://shopify.dev/docs/storefronts/headless/building-with-the-storefront-api/cart/manage)
also recommends obtaining checkout URLs at checkout time. These requirements
drive the same-origin, session-backed Cart Plug.

Hydrogen's current cart is “server-side first,” with progressive enhancement
for mutations; see [Hydrogen cart](https://shopify.dev/docs/storefronts/headless/hydrogen/cart).
The included web component follows the same architectural idea without
requiring React or Hydrogen.

Storefront API `2026-07` adds the `lineLevelOnly` argument and expanded discount
allocation model. The cart fragment explicitly requests allocations with
`lineLevelOnly: false`; see Shopify's
[discount allocation change](https://shopify.dev/changelog/new-discount-fields-in-the-storefront-cart-graphql-api).

### Customer Account API

The [Customer Account API](https://shopify.dev/docs/api/customer/2026-01)
is Shopify's modern authenticated customer surface, built on OAuth 2.0/OIDC with
authorization-code + PKCE and discovery endpoints. It is a better future phase
than legacy customer access tokens. It is intentionally not coupled to phase
one catalog/cart code: customer login adds redirect URIs, token storage,
refresh/revocation, consent, and account UI that deserve a separate security
review.

### Storefront Web Components

Shopify now offers
[Storefront Web Components](https://shopify.dev/docs/api/storefront-web-components)
for quickly embedding product cards, collections, and cart controls into any
site. They are useful for simple buy-button scenarios and prototypes.

They are not the primary Brando abstraction because the API is unversioned,
presentation and data loading remain Shopify-driven, and Brando loses the
benefits of server rendering, local template data, editorial relationships, and
complete cart control. BrandoShopify's own small custom element is optional and
talks to a stable server contract.

### Checkout extensions and Functions

Headless carts still hand buyers to Shopify checkout. Checkout behavior should
be extended through Shopify's supported
[checkout technologies](https://shopify.dev/docs/apps/build/checkout/technologies),
not by cloning checkout in Brando. Many in-checkout UI extension surfaces are
Shopify Plus capabilities.

[Cart Transform Functions](https://shopify.dev/docs/api/functions/latest/cart-transform)
are appropriate for bundles, line expansion/merge, and presentation rules that
must be authoritative in Shopify. The Brando cart simply renders the resulting
cart lines and warnings.

### Near-future surfaces

Shopify introduced standard storefront events/actions in June 2026, primarily
for Liquid themes; headless Brando storefronts should keep their own event
adapter until the headless contract is clear. See
[standard storefront events and actions](https://shopify.dev/changelog/standard-storefront-events-and-actions).

Shopify is replacing Storefront MCP cart tools with UCP Cart MCP for agentic
commerce. This is promising for a later agent integration but not a dependency
for a human-facing CMS storefront; see the
[UCP Cart MCP announcement](https://shopify.dev/changelog/storefront-mcp-cart-tools-are-being-deprecated-in-favour-of-ucp-cart-mcp).

## Webhook reliability

Shopify explicitly recommends a reconciliation job because deliveries can be
delayed, duplicated, missed after repeated failures, or arrive out of order.
Applications should deduplicate by webhook ID and compare timestamps where
event payloads are applied directly; see
[webhook best practices](https://shopify.dev/docs/apps/build/webhooks) and
[verification](https://shopify.dev/docs/apps/build/webhooks/verify-deliveries).

BrandoShopify goes a step further: event bodies are only signals. The queued
worker retrieves the current resource, so processing an older update signal
later cannot reapply old product fields. Delete signals tombstone records.

For merchant-created custom apps, GraphQL-created shop-specific subscriptions
are appropriate; distributed apps should prefer app-specific configuration.
See [webhook subscription methods](https://shopify.dev/docs/apps/build/webhooks/subscribe).

## CMS inspiration

### Sanity Connect

[Sanity Connect for Shopify](https://www.sanity.io/docs/apis-and-sdks/sanity-connect-for-shopify)
can synchronize full product documents and optionally write selected Sanity
content back to Shopify metafields/metaobjects. Its
[custom sync handlers](https://www.sanity.io/docs/apis-and-sdks/custom-sync-handlers-for-sanity-connect)
also preserve deletion state. The useful lesson is a rich local commerce
document plus clear field ownership and tombstones.

BrandoShopify adopts the local rich document and tombstone ideas, but does not
sync editorial data back in phase one. A Brando Blueprint overlay is easier to
reason about than bidirectional ownership.

### Storyblok

Storyblok's [e-commerce integration model](https://www.storyblok.com/docs/concepts/e-commerce)
stores product references in content and commonly retrieves current product
details from the commerce platform. Product references are excellent for editor
selection, but live resolution on every page introduces latency and outage
coupling.

BrandoShopify stores the same kind of stable reference in blocks while resolving
it against a richer local catalog. Live hydration is opt-in for values that
really are contextual.

### commercetools Frontend

commercetools documents the
[CMS + dynamic-page pattern](https://docs.commercetools.com/frontend-development/integration-of-frontend-with-headless-cms):
commerce data defines product/category identity and the CMS supplies page
composition. Brando's application-owned editorial Blueprint related to a local
Shopify product follows this separation.

## Decision record

| Choice | Decision | Reason |
|---|---|---|
| Product reads in templates | Local Ecto projection | Fast, searchable, resilient, editor-friendly |
| Commerce authority | Shopify | Prevent conflicting inventory/price/order state |
| Initial import | Admin Bulk Operation JSONL | Scales without costly page loops |
| Incremental sync | Verified webhooks + current-resource fetch | Low latency and resistant to event reordering |
| Repair | Scheduled reconciliation | Webhooks alone are not guaranteed state |
| Product API | Admin GraphQL `2026-07` | Current capabilities; REST is legacy |
| Buyer context | Persist one Storefront `@inContext` projection per configured context | Markets data cannot be one global cached value, and templates should stay network-free |
| Cart | Server-side Storefront Cart API | Keeps private token and cart secret off the client |
| UI | Optional framework-free custom element | Works with Brando, LiveView, or custom JS |
| Checkout | Shopify-hosted checkout + extensions/functions | Security, payments, tax, discounts, extensibility |
| Customer accounts | Separate next phase using Customer Account API | OAuth/OIDC deserves an isolated security boundary |

## Upgrade watchlist

Before moving to each new stable API version:

1. run Shopify's release-candidate schema against all stored documents;
2. inspect deprecation and field-nullability changes;
3. validate Cart discount allocations and warnings;
4. check Markets/B2B context behavior;
5. check product publication changes—`2026-07` adds independent variant
   publication capabilities; see
   [variant publishing](https://shopify.dev/changelog/publish-and-unpublish-product-variants-independently-from-product);
6. review public-app token requirements. Shopify requires expiring offline
   tokens for public apps from 1 January 2027; see
   [offline access tokens](https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/offline-access-tokens).
