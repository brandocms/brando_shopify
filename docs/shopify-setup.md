# Shopify setup

These steps describe the package's shop-specific custom-app path. A distributed
public app needs Shopify OAuth installation, mandatory compliance webhooks,
app-specific webhook subscriptions, and expiring offline-token rotation in
addition to this package.

## 0. Everything to grant, in one place

Grant all of these up front. They live in **three different places**, and each
one is discovered separately if you do not — every miss costs a version release,
a re-install, or a re-auth, and some of them fail late rather than at setup.

### Admin API — on the app version, in the Dev Dashboard

```
read_products,read_inventory,read_locations
```

Required, not optional. `read_locations` is the one that gets missed: the
`Location` object is reachable with `read_inventory`, but its `name` field is
not — and a store missing it imports products fine and then fails on the
**second** bulk phase.

### Storefront API — on the storefront, in the Headless channel

Not on the app version. **Headless channel → your storefront → Storefront API →
Manage**, next to the keys.

```
unauthenticated_read_product_listings
unauthenticated_read_product_inventory
unauthenticated_write_checkouts
unauthenticated_read_selling_plans     # only with sync_selling_plans: true
```

`unauthenticated_read_product_inventory` is not optional even if you never show
stock: both the context queries and the cart select `quantityAvailable`.

### Shopify CLI — only if you seed or inspect the store from the terminal

Unrelated to the app's own token. `shopify store auth` **replaces** the stored
set, so always pass the whole list:

```bash
shopify store auth --store shop.myshopify.com --scopes \
  read_products,write_products,read_inventory,write_inventory,\
  read_locations,read_locales,write_publications,read_product_listings
```

`read_locales` is needed to read `shopLocales` from the Admin API — the package
itself never asks for it, but you will want it when a catalog context refuses to
apply.

### Three more things that are not scopes

Each of these produces a failure that looks like a permissions problem:

- **Publish the catalogue to the Headless channel**, not just Online Store. A
  Storefront token only sees its own channel's products — `shop` answers while
  `products` comes back empty.
- **Publish the locale** any `catalog_contexts` language names. Shopify falls
  back to the primary locale silently; the sync catches it and refuses.
- **Re-install after changing scopes.** Releasing a new version does not apply
  them to an installed app, and the merchant prompt never appears for an app
  with no UI.

## 1. Create the app

Everything below was walked through against a live store on API version
2026-07. Where Shopify's own reference and reality disagreed, reality won and
the difference is noted.

### Which kind of app

Create the app in Shopify's **Dev Dashboard** (`dev.shopify.com`), reachable
from a store's admin at **Apps → Develop apps → Build apps in dev dashboard**.

Admin-created custom apps — the ones made in the store admin that handed out a
permanent `shpat_` token — can no longer be created as of **1 January 2026**.
Existing ones keep working, and a partner can still create one on a store they
have not yet transferred to the merchant, but nothing built that way can be
reproduced on a merchant-owned store. Prefer the Dev Dashboard for new work.

### Create a version

**Apps → Create app → Start from Dev Dashboard**, name it, then fill in the
**Create version** screen. Three of its defaults are wrong for this package,
which has no admin UI and no OAuth routes:

| Field | Value | Why |
|---|---|---|
| App URL | leave the placeholder | inert once the app is not embedded |
| **Embed app in Shopify admin** | **uncheck** | see below |
| Webhooks API version | match `api_version` in your config | |
| Scopes | see below, comma-separated | |
| Optional scopes | leave empty | see below |
| **Use legacy install flow** | **leave off** | see below |
| Allowed redirection URL(s) | leave empty | only the legacy flow uses them |

**Embed app in Shopify admin** is checked by default and must be turned off.
This package renders nothing in the Shopify admin. Shopify is explicit: "If your
app isn't rendered in the Shopify admin, then it shouldn't be configured to be."
Left on, the admin tries to iframe the app URL and shows a broken app page.

**Use legacy install flow** off selects Shopify managed installation, where
Shopify handles installation and scope updates and the app needs no OAuth
callback route. On, it reverts to the `/admin/oauth/authorize` redirect, which
this package does not implement.

**Required, not optional, scopes.** Required scopes are guaranteed present after
installation. Optional scopes have to be requested dynamically at runtime, and
this package only ever sends the token it is given.

Then **Release**. An app needs at least one released version before it can be
installed at all.

### Select a distribution method

The first install attempt fails with *"This app can't be installed yet — the app
developer needs to select a distribution method first."*

Choose **Custom distribution**: a private app installed on one store (or several
in the same Plus organization) through a link. Public distribution is for the
App Store and requires app review.

**This cannot be changed afterwards.** Custom distribution also means one app per
store, so development and production want separate apps — which is what Shopify
recommends regardless.

Then **Home → Install app → select the store → Install**.

### Changing scopes later

Releasing a new version does **not** apply new scopes to an installed app:

> When you update scopes in a new version of your app, updates aren't applied
> automatically to the stores your app is installed on. Merchants still need to
> manually approve the new scopes.

Merchants are prompted "when they open your app" — which never happens for an
app with no UI. Re-run **Install app** instead; that re-prompts with the new
scope set.

## 2. Admin API scopes

All three are required for a full sync; none is optional.

| Scope | Covers | Used by |
|---|---|---|
| `read_products` | `Product`, `ProductVariant`, product media and metafields, `Collection` | the product bulk query, `sync_product/1`, `reconcile/2`, collection webhooks |
| `read_inventory` | `InventoryItem`, `InventoryLevel` | the inventory bulk query, `inventory_levels/*` and `inventory_items/*` webhooks |
| `read_locations` | `Location.name` | `bulk_inventory_query` and `@variant_fields`, both of which select it |

`read_locations` is easy to leave out, because Shopify's reference for the
`Location` **object** says it accepts "`read_locations`, `read_inventory`, or
`read_markets_home`" — and `read_inventory` does reach the object. Its *fields*
are gated separately, and `name` is not covered:

```
Access denied for name field.
Required access: `read_locations` access scope or `read_markets_home` access scope.
```

Verified against a live store: `location { id }` and
`location { legacyResourceId }` succeed with `read_inventory` alone;
`location { name }` does not. Because `name` appears only in the inventory
documents, a store missing this scope imports products successfully and then
fails on the **second** bulk phase — the more confusing of the two orderings.
`read_markets_home` also opens the field; `read_locations` is the narrowest scope
that works.

Webhook subscriptions need no separate Admin scope for a custom app;
`webhookSubscriptionCreate` is authorized by the app's own credentials.

## 3. Get an Admin API token

The three app types do not produce the same kind of token, and the difference
decides what happens when a store changes hands:

| How the app is authenticated | Token | Lifetime | Survives a store transfer |
|---|---|---|---|
| Client credentials grant | requested programmatically | **24 hours** | no — scoped to your organization |
| Authorization code grant | offline token from the install | non-expiring | yes |
| Admin-created custom app (legacy) | pre-generated `shpat_`, copied from the admin | non-expiring | yes, but cannot be created any more |

### Client credentials — stores in your own organization

The least setup: no redirect flow. Credentials are in **Dev Dashboard → your app
→ Settings** (Client ID and Client secret).

```
POST https://{shop}.myshopify.com/admin/oauth/access_token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&client_id={id}&client_secret={secret}
```

```json
{ "access_token": "…", "scope": "read_products,read_inventory", "expires_in": 86399 }
```

`expires_in` is always 86399. **This package does not implement the exchange and
does not refresh tokens** — but it resolves `admin_access_token` on every
request and accepts a zero-arity function or an MFA tuple, so the host supplies
something that caches a token and re-requests it before expiry:

```elixir
admin_access_token: {MyApp.Shopify.Token, :admin, [:default]}
```

Two things to know:

- `scope` in the response is a readback of the app **version**, not of what the
  request asked for. A version whose scope change the store has not approved yet
  keeps handing out the old set.
- `shop_not_permitted` means the store is not in the same organization as the
  app. That is not a typo — it is the wrong grant for that store.

### Offline token — merchant-owned stores

When the store belongs to the merchant rather than to your organization, the
authorization code grant is the path. It produces a non-expiring offline token
(`expiring=0` is the default), which is a plain string in the environment:

```elixir
admin_access_token: System.fetch_env!("SHOPIFY_ADMIN_ACCESS_TOKEN")
```

Runtime is simpler than the client credentials case — nothing to refresh. The
work is a one-time OAuth redirect per store to obtain it.

A host that supports both keeps one config line across environments: prefer the
offline token when it is set, fall back to client credentials otherwise.

### Confirm what was actually granted

Never trust what was ticked in the dashboard:

```graphql
query { currentAppInstallation { accessScopes { handle } } }
```

## 4. Get a Storefront API token

Only needed when `storefront_token_type` is not `:none`. With `:none` the
package runs Admin-sync only, which is a reasonable way to bring a store up in
two steps — the catalogue lands in Postgres and listing pages work before any
Storefront credential exists.

**The private token does not come from the Dev Dashboard.** The path is:

1. Install the free **Headless** app in the store admin — it appears as the
   **Headless** sales channel
2. Open the channel → **Create storefront**
3. **Storefront API → Manage** — the keys are there, public and private

(A delegate access token, or unauthenticated scopes on an existing Admin token,
also produce a private token.)

| Token | Header | Use |
|---|---|---|
| Private | `Shopify-Storefront-Private-Token` | server-side — what this package's cart and context sync use |
| Public | `X-Shopify-Storefront-Access-Token` | browsers and mobile apps; created with `storefrontAccessTokenCreate` |

Use the **private** token: the included cart runs server-side, and a public token
is rate-limited per buyer IP.

### Publish the catalogue to the Headless channel

A Storefront API token only returns products published to **its own** channel,
and adding a storefront creates a *separate* publication alongside Online Store.
Products published only to Online Store are invisible to it.

The symptom is misleading: `{ shop { name } }` answers perfectly while
`{ products { nodes { … } } }` comes back empty, which reads like a scope or
token problem rather than an unpublished catalogue. Check the publications before
suspecting the token:

```graphql
query { publications(first: 25) { nodes { id name } } }
```

Publish to every channel that serves a storefront — `publishablePublish` takes a
list of publication ids. For requests caused by buyer traffic, pass
`:buyer_ip` so the package forwards `Shopify-Storefront-Buyer-IP`; Shopify uses
it for bot and volume protection.

### Storefront API scopes

**These are set on the storefront, not on the app version.** The Admin scopes in
section 2 live on the Dev Dashboard app; these live in the Headless channel under
**Storefront API → Manage**, next to the keys. Setting them in the wrong place is
easy and the symptom is an `ACCESS_DENIED` on a field, not on the token.

| Scope | Covers | When |
|---|---|---|
| `unauthenticated_read_product_listings` | `Product` and `Collection` | any configured `catalog_contexts` |
| `unauthenticated_read_product_inventory` | `quantityAvailable` on `ProductVariant` | always — both the context queries and the cart select this field. Verified: without it `Cart.create/2` fails with "Access denied for quantityAvailable field" |
| `unauthenticated_write_checkouts` | the `Cart` object | the included server-side cart |
| `unauthenticated_read_selling_plans` | selling-plan content on `Product` | only with `sync_selling_plans: true` on a context |

Store the Admin token, the private Storefront token, and the app client secret in
the deployment secret manager; do not commit them.

## 5. Know which kind of store you have

The Dev Dashboard's **Stores** tab separates three kinds, and the distinction
matters more than it looks:

- **Dev stores** — testing environments you own. **Cannot be transferred to a
  client.**
- **Client transfer stores** — built on behalf of a client and handed over.
  "After the transfer, the merchant takes full ownership and the store exits your
  organization" — which is exactly when a client credentials token stops working.
- **Collaborations** — stores a merchant already owns.

The Admin API cannot tell the first two apart: a client transfer store still in
development reports `plan.partnerDevelopment: true` and
`plan.displayName: "Development"`, the same as a dev store. **The Dev Dashboard
tab is the only reliable answer.**

Shopify's documentation says custom apps cannot be installed on a client transfer
store while it is still in your organization. In practice a
custom-distribution app installed without complaint on one.


## 6. Configure BrandoShopify

Put the store configuration in the host Brando application's
`config/runtime.exs` so deployment secrets are read when the application starts:

```elixir
# config/runtime.exs
import Config

config :brando_shopify,
  stores: [
    default: [
      shop_domain: "example.myshopify.com",
      storefront_domain: "shop.example.com",
      api_version: "2026-07",
      # A Dev Dashboard app has no token to paste — see section 3.
      # An offline token is a plain System.fetch_env!("SHOPIFY_ADMIN_ACCESS_TOKEN").
      admin_access_token: {MyApp.Shopify.Token, :admin, [:default]},
      storefront_access_token: System.fetch_env!("SHOPIFY_STOREFRONT_PRIVATE_TOKEN"),
      storefront_token_type: :private,
      webhook_secret: System.fetch_env!("SHOPIFY_CLIENT_SECRET"),
      repo: MyApp.Repo,
      oban_name: Oban,
      catalog_contexts: [
        norway: [country: "NO", language: "NB"],
        united_states: [
          country: "US",
          language: "EN",
          sync_selling_plans: true
        ]
      ]
    ]
  ]
```

`shop_domain` must remain the stable `*.myshopify.com` Admin domain.
`storefront_domain` may be the custom storefront domain.
Set `oban_name` to the host's named Oban instance when it isn't the default
`Oban`. That instance must use the same Repo configured for the store so webhook
receipts and unique job insertion share one transaction.

For credentials that must rotate without restarting the running application,
the three secret fields also accept zero-arity functions or MFA tuples, resolved
on every request. That is not only for rotation: a Dev Dashboard app's Admin
token expires every 24 hours, so it is the only way to configure one. A plain
string is fine for the Storefront token and for a legacy `shpat_`.

Each `catalog_contexts` key names one persisted Storefront projection. Product
sync writes translations and country-aware price, currency, publication, and
availability for that exact context.

**A context's `language` must be a locale the store has published.** Shopify
silently falls back to the primary locale otherwise, so the sync verifies what
came back and refuses the result rather than storing English text labelled as
another language:

```
Shopify did not apply the requested Storefront context
expected: %{"country" => "NO", "language" => "NB"}
applied:  %{"country" => "NO", "language" => "EN"}
```

Add the locale under **Settings → Languages** in the store admin and publish it.
The Storefront API reports what is actually available, and needs no extra Admin
scope to do so:

```graphql
query { localization { availableLanguages { isoCode } availableCountries { isoCode } } }
```

Reading the same thing from the Admin API (`shopLocales`) needs `read_locales` or
`read_markets_home`. `sync_selling_plans: true` additionally
stores selling-plan groups and per-variant allocations. Configure only contexts
the storefront actually renders; sync cost grows with products × contexts.

## 7. Create webhook subscriptions

Webhooks need a public HTTPS URL, which in development means a tunnel.

`shopify app dev` does start a Cloudflare tunnel, but it is tied to a
CLI-managed app project — it builds and previews *that* app, and cannot point at
an arbitrary local server. `--tunnel-url` expects you to be running your own
tunnel already. So for a Brando host, run one directly:

```bash
cloudflared tunnel --url http://localhost:4000   # what the CLI uses internally
ngrok http 4000                                  # equivalent
```

Use the resulting HTTPS URL as the subscription endpoint. A free tunnel's
hostname changes on restart, so re-subscribe after each one, or pin a named
tunnel.

Expose the endpoint over HTTPS and subscribe the following topics:

- `products/create`
- `products/update`
- `products/delete`
- `collections/create`
- `collections/update`
- `collections/delete`
- `bulk_operations/finish`
- `inventory_levels/update`
- `inventory_levels/connect`
- `inventory_levels/disconnect`
- `inventory_items/update`
- `inventory_items/delete`

For a merchant-created custom app, subscriptions can be created with:

```elixir
topics = [
  "products/create",
  "products/update",
  "products/delete",
  "collections/create",
  "collections/update",
  "collections/delete",
  "bulk_operations/finish",
  "inventory_levels/update",
  "inventory_levels/connect",
  "inventory_levels/disconnect",
  "inventory_items/update",
  "inventory_items/delete"
]

for topic <- topics do
  BrandoShopify.Admin.subscribe_webhook(
    topic,
    "https://www.example.com/shopify/webhooks"
  )
end
```

For a public app, declare app-specific subscriptions in `shopify.app.toml`
instead. Keep the webhook Plug before `Plug.Parsers` so it can authenticate the
raw bytes. Shopify's client secret is the HMAC secret — the same
`SHOPIFY_CLIENT_SECRET` used by the client credentials grant, so one value covers
both.

In a Brando host, mount the route ahead of `page_routes/0`. That ends in
`get "/*path"` and swallows anything declared after it. Note also that a site
with `lockdown: true` gates every new public route.

## 8. Run the initial import

```elixir
{:ok, run} = BrandoShopify.Sync.start_full()
```

This starts the product Admin Bulk Operation. Its finish webhook streams the
short-lived JSONL result and starts a second inventory bulk operation. After the
inventory finish webhook, the worker stores items/levels, hydrates configured
Storefront contexts, tombstones resources absent from the completed export, and
marks the run complete.

For a small development store, individual products can be synchronized directly:

```elixir
BrandoShopify.Sync.sync_product("gid://shopify/Product/123")
```

## 9. Schedule reconciliation

Webhooks are not a transactional event log. Run reconciliation periodically,
with a small overlap if the application supplies its own `since` value:

```elixir
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"*/15 * * * *", BrandoShopify.Workers.Reconcile,
        args: %{store: "default"}}
     ]}
  ]
```

In a Brando host this goes in `config :brando, Oban` instead, alongside the
queues — and that key replaces Brando's default rather than merging with it. See
the Oban section of the README before writing it.

The default worker uses the most recent completed full sync or the previous 24
hours. Large catalogs may prefer an explicit cursor/checkpoint table and a
longer cadence.

## 10. Validate before production

### Inspecting a store without writing code

Shopify's CLI talks to a store directly, which is the fastest way to check what
the API actually returns before blaming the sync:

```bash
shopify store auth --store shop.myshopify.com --scopes read_products,read_inventory,read_locations
shopify store execute --store shop.myshopify.com \
  --query 'query { products(first: 5) { nodes { handle status } } }'
```

`store auth` is interactive and idempotent, but it **replaces** the stored
scopes — always pass the whole set. Add `--allow-mutations` for writes. This
token is the CLI's own and is unrelated to the app's; a store can be seeded
through the CLI while the app is still being set up.

### Checklist

Use a development store to verify:

1. the Admin documents against the exact enabled scopes and store features;
2. initial bulk import counts and product/variant/collection samples;
3. create, update, delete, duplicate, and deliberately delayed webhooks;
4. market/country pricing and language context;
5. carts with variants, discounts, out-of-stock changes, and checkout;
6. app token revocation/rotation and queue retry behavior; and
7. API-version release-candidate tests before each quarterly upgrade.
