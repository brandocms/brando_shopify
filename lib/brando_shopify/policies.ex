defmodule BrandoShopify.Policies do
  @moduledoc """
  The shop's legal policies: fetching them from Shopify, and serving them.

  Shopify is the source of truth. That is a deliberate choice rather than a
  convenience: the Shopify-hosted checkout links to whatever is in
  Settings → Policies, so any second copy would be a copy the checkout
  disagrees with. Editing happens in Shopify Admin; this module keeps a local
  projection so rendering a page never waits on a Storefront request.

  Shopify's own policy URLs point at `checkout.shopify.com`, which is an
  undesigned page on someone else's domain. `path/3` exists so a storefront can
  link to its own rendering instead.

  ## Configuration

      config :brando_shopify,
        stores: [
          default: [
            # ...
            policies: [
              path: "/vilkar",
              locales: %{"no" => "NB", "en" => "EN"},
              slugs: %{
                "no" => %{
                  terms_of_service: "kjopsvilkar",
                  refund_policy: "retur-og-angrerett",
                  privacy_policy: "personvern",
                  shipping_policy: "frakt"
                },
                "en" => %{
                  terms_of_service: "purchase-terms",
                  refund_policy: "returns",
                  privacy_policy: "privacy",
                  shipping_policy: "shipping"
                }
              }
            ]
          ]
        ]

  A locale with no `:slugs` entry is synced but has no URL, which is the right
  default: a document exists before anyone has decided what to call it.
  """

  import Ecto.Query, only: [from: 2]

  alias BrandoShopify.Config
  alias BrandoShopify.Policies.Policy
  alias BrandoShopify.Storefront

  # Storefront field name to local type. The subscription policy is included
  # because Shopify exposes it; a store without subscriptions simply has none.
  @storefront_fields %{
    "privacyPolicy" => :privacy_policy,
    "refundPolicy" => :refund_policy,
    "shippingPolicy" => :shipping_policy,
    "subscriptionPolicy" => :subscription_policy,
    "termsOfService" => :terms_of_service
  }

  @doc "Every policy type the Storefront API exposes."
  @spec types() :: [atom()]
  defdelegate types, to: Policy

  @doc "The host locales policies are configured for."
  @spec locales(keyword()) :: [String.t()]
  def locales(opts \\ []) do
    opts |> policies_config() |> Map.fetch!(:locales) |> Map.keys() |> Enum.sort()
  end

  @doc """
  Refreshes every configured locale from Shopify.

  Returns `{:ok, %{synced: n, removed: n}}`. A policy the merchant has since
  deleted in Shopify is removed locally rather than left behind — a stale
  document that no longer applies is worse than a missing one, because the
  checkout has already stopped linking to it.

  Fails loudly when Shopify does not apply the requested language. That is not
  pedantry: an unpublished locale silently returns the primary language's text,
  so the alternative to failing is storing English under `locale: "da"`.
  """
  @spec sync(keyword()) :: {:ok, map()} | {:error, BrandoShopify.Error.t()}
  def sync(opts \\ []) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)
    locales = config.policies.locales

    Enum.reduce_while(locales, {:ok, %{synced: 0, removed: 0}}, fn {locale, language},
                                                                   {:ok, tally} ->
      case sync_locale(repo, config, locale, language) do
        {:ok, counts} ->
          {:cont,
           {:ok, %{synced: tally.synced + counts.synced, removed: tally.removed + counts.removed}}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp sync_locale(repo, config, locale, language) do
    with {:ok, shop} <- Storefront.shop_policies(config: config, language: language) do
      now = DateTime.utc_now()

      {present, absent} =
        Enum.split_with(@storefront_fields, fn {field, _type} -> is_map(shop[field]) end)

      Enum.each(present, fn {field, type} ->
        upsert(repo, config.name, type, locale, language, shop[field], now)
      end)

      removed = delete_absent(repo, config.name, locale, Enum.map(absent, &elem(&1, 1)))

      {:ok, %{synced: length(present), removed: removed}}
    end
  end

  defp upsert(repo, store, type, locale, language, policy, now) do
    attrs = %{
      store: to_string(store),
      type: type,
      locale: locale,
      language_code: language,
      shopify_id: policy["id"],
      handle: policy["handle"],
      title: policy["title"],
      body: policy["body"],
      shopify_url: policy["url"],
      synced_at: now,
      source_data: policy
    }

    %Policy{}
    |> Policy.changeset(attrs)
    |> repo.insert!(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:store, :type, :locale]
    )
  end

  defp delete_absent(_repo, _store, _locale, []), do: 0

  defp delete_absent(repo, store, locale, types) do
    {count, _} =
      from(p in Policy,
        where: p.store == ^to_string(store) and p.locale == ^locale and p.type in ^types
      )
      |> repo.delete_all()

    count
  end

  @doc """
  Lists the policies stored for one locale, in a stable order.

  The order is the one a footer wants: terms, then returns, then shipping, then
  privacy.
  """
  @spec list(String.t(), keyword()) :: [Policy.t()]
  def list(locale, opts \\ []) when is_binary(locale) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)

    from(p in Policy,
      where: p.store == ^to_string(config.name) and p.locale == ^locale
    )
    |> repo.all()
    |> Enum.sort_by(&type_order/1)
  end

  defp type_order(%Policy{type: type}) do
    Enum.find_index(
      [
        :terms_of_service,
        :refund_policy,
        :shipping_policy,
        :privacy_policy,
        :subscription_policy
      ],
      &(&1 == type)
    ) || 99
  end

  @doc "Fetches one policy by type and locale."
  @spec get(atom(), String.t(), keyword()) :: Policy.t() | nil
  def get(type, locale, opts \\ []) when is_atom(type) and is_binary(locale) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    repo = Config.repo!(config)

    repo.get_by(Policy, store: to_string(config.name), type: type, locale: locale)
  end

  @doc """
  Fetches one policy by its configured slug.

  Slugs are per locale, so the same document is `personvern` in Norwegian and
  `privacy` in English. Returns `nil` for a slug this locale does not define,
  which is what makes an unconfigured locale 404 rather than serve the wrong
  language's document.
  """
  @spec get_by_slug(String.t(), String.t(), keyword()) :: Policy.t() | nil
  def get_by_slug(slug, locale, opts \\ []) when is_binary(slug) and is_binary(locale) do
    case type_for_slug(slug, locale, opts) do
      nil -> nil
      type -> get(type, locale, opts)
    end
  end

  @doc "Resolves a slug back to its policy type for one locale."
  @spec type_for_slug(String.t(), String.t(), keyword()) :: atom() | nil
  def type_for_slug(slug, locale, opts \\ []) when is_binary(slug) and is_binary(locale) do
    opts
    |> policies_config()
    |> get_in([:slugs, locale])
    |> Kernel.||(%{})
    |> Enum.find_value(fn {type, configured} -> if configured == slug, do: type end)
  end

  @doc "The configured slug for a policy type in one locale, or `nil`."
  @spec slug(atom(), String.t(), keyword()) :: String.t() | nil
  def slug(type, locale, opts \\ []) when is_atom(type) and is_binary(locale) do
    opts
    |> policies_config()
    |> get_in([:slugs, locale, type])
  end

  @doc """
  The storefront path for a policy, or `nil` when the locale defines no slug.

  Returns the path without a language prefix. Adding `/en` is the host
  framework's business — Brando strips it before routing, so the package would
  only be guessing at a convention it does not own.

      iex> BrandoShopify.Policies.path(:privacy_policy, "no")
      "/vilkar/personvern"
  """
  @spec path(atom(), String.t(), keyword()) :: String.t() | nil
  def path(type, locale, opts \\ []) when is_atom(type) and is_binary(locale) do
    config = policies_config(opts)

    case get_in(config, [:slugs, locale, type]) do
      nil -> nil
      slug -> config.path <> "/" <> slug
    end
  end

  @doc """
  Every configured path for one locale, as `{type, path}` pairs.

  Built from configuration rather than from what is stored, so a missing sync
  shows up as a broken link instead of a silently absent footer entry.
  """
  @spec paths(String.t(), keyword()) :: [{atom(), String.t()}]
  def paths(locale, opts \\ []) when is_binary(locale) do
    config = policies_config(opts)

    config
    |> get_in([:slugs, locale])
    |> Kernel.||(%{})
    |> Enum.map(fn {type, slug} -> {type, config.path <> "/" <> slug} end)
    |> Enum.sort_by(fn {type, _} -> type_order(%Policy{type: type}) end)
  end

  @doc """
  Sanitizes a policy body for rendering.

  The author is the merchant, so this is not defending against a hostile
  writer — it defends against a compromised Shopify account or a policy written
  through the API, where the blast radius is every page on the site. The `html5`
  policy is deliberately permissive: legal text is full of lists, tables and
  links, and a sanitizer that quietly eats a clause is worse than no sanitizer
  at all.
  """
  @spec sanitize(String.t() | nil) :: String.t()
  def sanitize(nil), do: ""
  def sanitize(body) when is_binary(body), do: HtmlSanitizeEx.html5(body)

  defp policies_config(opts) do
    config = opts[:config] || Config.fetch!(opts[:store] || :default)
    config.policies
  end
end
