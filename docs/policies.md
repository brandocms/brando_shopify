# Legal policies

Shopify stores five policy documents — refund, privacy, terms of service,
shipping and subscription — under Settings → Policies. This is how they reach a
headless storefront.

## Why Shopify owns them

The Shopify-hosted checkout links to whatever is in Settings → Policies. A
second copy kept anywhere else is a copy the checkout disagrees with, and
nobody notices until a customer reads two different refund policies on the same
purchase.

So Shopify is the source of truth, and the package keeps a local projection —
the same arrangement as products, for the same reason: rendering a page should
not wait on a Storefront request.

The alternative to rendering them yourself is linking to Shopify's own URLs.
Those live on `checkout.shopify.com`, undesigned and on someone else's domain,
which is a poor place to send a reader mid-purchase.

## Configuration

    policies: [
      path: "/vilkar",
      locales: %{"no" => "NB", "en" => "EN"},
      slugs: %{
        "no" => %{
          terms_of_service: "kjopsvilkar",
          refund_policy: "retur-og-angrerett",
          shipping_policy: "frakt",
          privacy_policy: "personvern"
        },
        "en" => %{
          terms_of_service: "purchase-terms",
          refund_policy: "returns",
          shipping_policy: "shipping",
          privacy_policy: "privacy"
        }
      }
    ]

`:path` carries no language prefix. Brando strips `/en` before routing, so one
path serves every locale and the package would only be guessing at a convention
it does not own.

`:locales` maps your locale onto Shopify's `LanguageCode`. They are different
alphabets — `"no"` is not `NB` — and the mapping has to be written down
somewhere. See the trap below for what happens when it is wrong.

`:slugs` are per locale, so the same document is `personvern` in Norwegian and
`privacy` in English. A slug that resolves in one locale deliberately misses in
another: `/en/vilkar/personvern` should 404 rather than serve a Norwegian
document under an English URL.

Configuration is validated at boot. A slug containing `/`, two policies sharing
a slug within one locale, or slugs for a locale with no language mapping all
fail there rather than at request time.

## The silent fallback

Asking Shopify for a language the store has not published does not fail. It
returns the primary language's text, with no error and no warning:

    @inContext(language: NB) → context: { language: "NB" }
    @inContext(language: DA) → context: { language: "EN" }   ← no error

A Danish buyer would receive English terms, and nothing would be logged.

`Storefront.shop_policies/1` therefore verifies the applied context against the
requested one and returns `{:error, %Error{kind: :invalid_response}}` on a
mismatch. Storing English text under `locale: "da"` is worse than not storing
it, so the sync fails instead.

**This catches an unpublished language, not untranslated content.** A published
locale with no translation for one policy returns the primary language's text
under the correct context code, and that is indistinguishable from a real
translation over the API. Publishing a locale is a decision; translating each
document is work that follows it, and only Translate & Adapt knows whether it
has been done.

## Syncing

There is no policy webhook. The only way to learn that a merchant edited their
refund policy is to look, so `BrandoShopify.Workers.Policy` refreshes all of
them on a schedule:

    %{store: "default"}
    |> BrandoShopify.Workers.Policy.new()
    |> Oban.insert()

A policy deleted in Shopify is deleted locally. A stale document that no longer
applies is worse than a missing one, because the checkout has already stopped
linking to it.

## Rendering

    BrandoShopify.Policies.list(locale)              # stored, in footer order
    BrandoShopify.Policies.get(:privacy_policy, locale)
    BrandoShopify.Policies.get_by_slug("personvern", locale)
    BrandoShopify.Policies.path(:privacy_policy, locale)   # "/vilkar/personvern"
    BrandoShopify.Policies.paths(locale)             # every configured link

`paths/2` is built from configuration rather than from what is stored, so a
missing sync shows up as a broken link instead of a silently absent footer
entry.

Bodies are HTML written by the merchant in Shopify Admin. Run them through
`Policies.sanitize/1` before `raw/1`. The policy is deliberately permissive —
legal text is full of lists, tables and links, and a sanitizer that quietly
eats a clause is worse than no sanitizer at all.

`mix brando_shopify.gen.shop --policies-path /vilkar` scaffolds a controller,
an HTML module and two templates wired to all of the above.
