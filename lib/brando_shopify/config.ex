defmodule BrandoShopify.Config do
  @moduledoc """
  Runtime configuration for one Shopify store.

  Secrets can be strings, zero-arity functions, or MFA tuples. A callable source
  makes token rotation possible without recompiling configuration:

      config :brando_shopify,
        stores: [
          default: [
            shop_domain: "example.myshopify.com",
            admin_access_token: {MyApp.Secrets, :shopify_admin_token, []},
            storefront_access_token: fn ->
              System.fetch_env!("SHOPIFY_STOREFRONT_PRIVATE_TOKEN")
            end,
            storefront_token_type: :private,
            webhook_secret: fn -> System.fetch_env!("SHOPIFY_CLIENT_SECRET") end,
            repo: MyApp.Repo
          ]
        ]

  `:visibility` uses the same callable sources, for the same reason. A store is
  filled with products long before it opens, so its launch state belongs
  wherever the people doing that work can reach it — usually the CMS:

      visibility: {MyApp.Shop, :visibility, []}

  See `BrandoShopify.Plug.Visibility` for enforcement.
  """

  require Logger

  @default_version "2026-07"
  @token_types [:private, :public, :none]
  @visibility_states [:off, :preview, :live]
  @domain_regex ~r/^(?:[a-z0-9][a-z0-9-]*\.)+[a-z]{2,}$/i
  @config_keys [
    :shop_domain,
    :storefront_domain,
    :customer_account_domain,
    :api_version,
    :admin_access_token,
    :storefront_access_token,
    :storefront_token_type,
    :webhook_secret,
    :repo,
    :oban_name,
    :http,
    :req_options,
    :catalog_contexts,
    :policies,
    :visibility
  ]
  @context_keys [:key, :country, :language, :sync_selling_plans]

  @type secret_source ::
          String.t()
          | nil
          | (-> String.t() | nil)
          | {module(), atom(), [term()]}

  @typedoc """
  Whether a store is open to buyers.

    * `:live` — open to everyone
    * `:preview` — visible only to those the host app vouches for
    * `:off` — closed to everyone, including staff
  """
  @type visibility :: :off | :preview | :live

  @type visibility_source ::
          visibility()
          | (-> visibility())
          | {module(), atom(), [term()]}

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          shop_domain: String.t(),
          storefront_domain: String.t(),
          customer_account_domain: String.t(),
          api_version: String.t(),
          admin_access_token: secret_source(),
          storefront_access_token: secret_source(),
          storefront_token_type: :private | :public | :none,
          webhook_secret: secret_source(),
          repo: module() | nil,
          oban_name: term(),
          http: module(),
          req_options: keyword(),
          catalog_contexts: [catalog_context()],
          policies: policies(),
          visibility: visibility_source()
        }

  @typedoc """
  Where the host application publishes the shop's legal policies.

    * `:path` — URL prefix, without a trailing slash. Language prefixes are the
      host framework's business, not ours: Brando strips `/en` before routing,
      so one path serves every locale.
    * `:locales` — host locale to Shopify `LanguageCode`. `%{"no" => "NB"}`.
      Shopify's codes are not the host's, and guessing between them is how a
      Danish buyer ends up reading English.
    * `:slugs` — per locale, the URL segment for each policy type. A locale
      with no entry falls back to nothing: it is better to 404 than to serve a
      Norwegian document under an English URL.
  """
  @type policies :: %{
          path: String.t(),
          locales: %{String.t() => String.t()},
          slugs: %{String.t() => %{atom() => String.t()}}
        }

  @type catalog_context :: %{
          key: String.t(),
          country: String.t() | nil,
          language: String.t() | nil,
          sync_selling_plans: boolean()
        }

  @enforce_keys [:name, :shop_domain]
  defstruct name: :default,
            shop_domain: nil,
            storefront_domain: nil,
            customer_account_domain: nil,
            api_version: @default_version,
            admin_access_token: nil,
            storefront_access_token: nil,
            storefront_token_type: :private,
            webhook_secret: nil,
            repo: nil,
            oban_name: Oban,
            http: BrandoShopify.HTTP,
            req_options: [],
            catalog_contexts: [],
            policies: %{path: "/policies", locales: %{}, slugs: %{}},
            visibility: :live

  @doc "Loads a named store from `config :brando_shopify, :stores`."
  @spec fetch(atom() | String.t()) :: {:ok, t()} | {:error, term()}
  def fetch(name \\ :default) do
    stores = Application.get_env(:brando_shopify, :stores, [])

    case fetch_store(stores, name) do
      nil -> {:error, {:store_not_configured, name}}
      config -> new(name, config)
    end
  end

  @doc "Loads a store and raises when it is missing or invalid."
  @spec fetch!(atom() | String.t()) :: t()
  def fetch!(name \\ :default) do
    case fetch(name) do
      {:ok, config} ->
        config

      {:error, reason} ->
        raise ArgumentError, "invalid Shopify store configuration: #{inspect(reason)}"
    end
  end

  @doc "Builds a validated configuration struct."
  @spec new(atom() | String.t(), keyword() | map() | t()) :: {:ok, t()} | {:error, term()}
  def new(_name, %__MODULE__{} = config), do: validate(config)

  def new(name, values) when is_list(values) or is_map(values) do
    values = normalize_known_keys(values, @config_keys)
    shop_domain = normalize_domain(values.shop_domain)

    config = %__MODULE__{
      name: name,
      shop_domain: shop_domain,
      storefront_domain: normalize_domain(value_or(values.storefront_domain, shop_domain)),
      customer_account_domain:
        normalize_domain(
          value_or(
            values.customer_account_domain,
            value_or(values.storefront_domain, shop_domain)
          )
        ),
      api_version: value_or(values.api_version, @default_version),
      admin_access_token: values.admin_access_token,
      storefront_access_token: values.storefront_access_token,
      storefront_token_type: value_or(values.storefront_token_type, :private),
      webhook_secret: values.webhook_secret,
      repo: values.repo,
      oban_name: value_or(values.oban_name, Oban),
      http: value_or(values.http, BrandoShopify.HTTP),
      req_options: value_or(values.req_options, []),
      catalog_contexts: normalize_catalog_contexts(value_or(values.catalog_contexts, [])),
      policies: normalize_policies(values.policies),
      visibility: value_or(values.visibility, :live)
    }

    validate(config)
  end

  @doc "Returns the endpoint for a Shopify GraphQL surface."
  @spec endpoint(t(), :admin | :storefront) :: String.t()
  def endpoint(%__MODULE__{} = config, :admin) do
    "https://#{config.shop_domain}/admin/api/#{config.api_version}/graphql.json"
  end

  def endpoint(%__MODULE__{} = config, :storefront) do
    "https://#{config.storefront_domain}/api/#{config.api_version}/graphql.json"
  end

  @doc "Resolves a configured secret at request time."
  @spec resolve_secret(secret_source()) :: String.t() | nil
  def resolve_secret(secret) when is_binary(secret), do: secret
  def resolve_secret(nil), do: nil
  def resolve_secret(fun) when is_function(fun, 0), do: fun.()
  def resolve_secret({module, function, args}), do: apply(module, function, args)

  @doc """
  Resolves a store's launch state at request time.

  A callable source that returns something other than `:off`, `:preview` or
  `:live` is logged and treated as `:off`. Literal sources are rejected when the
  configuration is built, so this only guards against a misbehaving callback.

  The fallback is deliberately closed rather than open: a store that is down is
  reversible, whereas an unfinished store that reached buyers and search engines
  is not.
  """
  @spec resolve_visibility(visibility_source()) :: visibility()
  def resolve_visibility(state) when state in @visibility_states, do: state
  def resolve_visibility(fun) when is_function(fun, 0), do: cast_visibility(fun.())

  def resolve_visibility({module, function, args}),
    do: cast_visibility(apply(module, function, args))

  defp cast_visibility(state) when state in @visibility_states, do: state

  defp cast_visibility(other) do
    Logger.error("""
    BrandoShopify: store visibility resolved to #{inspect(other)}.

    Expected one of #{inspect(@visibility_states)}. Treating the store as :off.
    """)

    :off
  end

  @doc "Returns the configured repo or raises with an actionable message."
  @spec repo!(t()) :: module()
  def repo!(%__MODULE__{repo: repo}) when is_atom(repo) and not is_nil(repo), do: repo

  def repo!(%__MODULE__{name: name}) do
    raise ArgumentError,
          "Shopify store #{inspect(name)} has no :repo; configure your application's Ecto repo"
  end

  defp validate(%__MODULE__{} = config) do
    with :ok <- validate_domains(config),
         :ok <- validate_api_version(config),
         :ok <- validate_token_type(config),
         :ok <- validate_storefront_token(config),
         :ok <- validate_req_options(config),
         :ok <- validate_http(config),
         :ok <- validate_catalog_contexts(config),
         :ok <- validate_policies(config),
         :ok <- validate_visibility(config) do
      {:ok, config}
    end
  end

  defp validate_domains(config) do
    cond do
      not valid_domain?(config.shop_domain) ->
        {:error, {:invalid_shop_domain, config.shop_domain}}

      not valid_domain?(config.storefront_domain) ->
        {:error, {:invalid_storefront_domain, config.storefront_domain}}

      not valid_domain?(config.customer_account_domain) ->
        {:error, {:invalid_customer_account_domain, config.customer_account_domain}}

      true ->
        :ok
    end
  end

  defp validate_api_version(%{api_version: version}) do
    if Regex.match?(~r/^\d{4}-(01|04|07|10)$/, version),
      do: :ok,
      else: {:error, {:invalid_api_version, version}}
  end

  defp validate_token_type(%{storefront_token_type: token_type}) when token_type in @token_types,
    do: :ok

  defp validate_token_type(%{storefront_token_type: token_type}),
    do: {:error, {:invalid_storefront_token_type, token_type}}

  defp validate_storefront_token(%{storefront_token_type: :none}), do: :ok

  defp validate_storefront_token(config) do
    if blank?(resolve_secret(config.storefront_access_token)),
      do: {:error, :missing_storefront_access_token},
      else: :ok
  end

  defp validate_req_options(%{req_options: options}) when is_list(options), do: :ok

  defp validate_req_options(%{req_options: options}),
    do: {:error, {:invalid_req_options, options}}

  defp validate_http(%{http: http}) when is_atom(http) and not is_nil(http), do: :ok
  defp validate_http(%{http: http}), do: {:error, {:invalid_http, http}}

  defp validate_catalog_contexts(%{catalog_contexts: contexts}) do
    if valid_catalog_contexts?(contexts),
      do: :ok,
      else: {:error, {:invalid_catalog_contexts, contexts}}
  end

  defp validate_visibility(%{visibility: state}) when state in @visibility_states, do: :ok
  defp validate_visibility(%{visibility: fun}) when is_function(fun, 0), do: :ok

  defp validate_visibility(%{visibility: {module, function, args}})
       when is_atom(module) and is_atom(function) and is_list(args),
       do: :ok

  defp validate_visibility(%{visibility: state}), do: {:error, {:invalid_visibility, state}}

  defp fetch_store(stores, name) when is_list(stores) do
    if(is_atom(name), do: Keyword.get(stores, name), else: nil) ||
      Enum.find_value(stores, fn {key, value} ->
        if to_string(key) == to_string(name), do: value
      end)
  end

  defp fetch_store(stores, name) when is_map(stores) do
    Map.get(stores, name) || Map.get(stores, to_string(name))
  end

  defp fetch_store(_, _), do: nil

  defp normalize_domain(nil), do: nil

  defp normalize_domain(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.replace(~r{^https?://}i, "")
    |> String.trim_trailing("/")
    |> String.downcase()
  end

  defp valid_domain?(domain) when is_binary(domain), do: Regex.match?(@domain_regex, domain)
  defp valid_domain?(_), do: false

  defp blank?(value), do: not (is_binary(value) and String.trim(value) != "")

  @policy_types BrandoShopify.Policies.Policy.types()

  defp normalize_policies(nil), do: %{path: "/policies", locales: %{}, slugs: %{}}

  defp normalize_policies(values) when is_list(values) or is_map(values) do
    values = Map.new(values, fn {key, value} -> {to_string(key), value} end)

    %{
      path: normalize_policies_path(Map.get(values, "path")),
      locales: normalize_policy_locales(Map.get(values, "locales")),
      slugs: normalize_policy_slugs(Map.get(values, "slugs"))
    }
  end

  defp normalize_policies(invalid), do: invalid

  defp normalize_policies_path(nil), do: "/policies"

  defp normalize_policies_path(path) when is_binary(path) do
    path = path |> String.trim() |> String.trim_trailing("/")

    if String.starts_with?(path, "/"), do: path, else: "/" <> path
  end

  defp normalize_policies_path(path), do: path

  defp normalize_policy_locales(nil), do: %{}

  defp normalize_policy_locales(locales) when is_list(locales) or is_map(locales) do
    Map.new(locales, fn {locale, code} ->
      {to_string(locale), normalize_context_code(code)}
    end)
  end

  defp normalize_policy_locales(invalid), do: invalid

  defp normalize_policy_slugs(nil), do: %{}

  defp normalize_policy_slugs(slugs) when is_list(slugs) or is_map(slugs) do
    Map.new(slugs, fn {locale, types} -> {to_string(locale), normalize_policy_types(types)} end)
  end

  defp normalize_policy_slugs(invalid), do: invalid

  defp normalize_policy_types(types) when is_list(types) or is_map(types) do
    Map.new(types, fn {type, slug} ->
      {normalize_policy_type(type), normalize_policy_slug(slug)}
    end)
  end

  defp normalize_policy_types(invalid), do: invalid

  defp normalize_policy_type(type) when is_atom(type), do: type

  defp normalize_policy_type(type) when is_binary(type) do
    Enum.find(@policy_types, type, &(Atom.to_string(&1) == type))
  end

  defp normalize_policy_type(type), do: type

  defp normalize_policy_slug(slug) when is_binary(slug),
    do: slug |> String.trim() |> String.trim("/")

  defp normalize_policy_slug(slug), do: slug

  defp validate_policies(%{policies: %{path: path, locales: locales, slugs: slugs}}) do
    # A slug for a locale we have no Shopify language for can never be filled,
    # so the route would exist and always 404. Reject it at boot instead.
    orphans =
      if is_map(slugs) and is_map(locales),
        do: Map.keys(slugs) -- Map.keys(locales),
        else: []

    cond do
      not valid_policies_path?(path) ->
        {:error, {:invalid_policies_path, path}}

      not valid_policy_locales?(locales) ->
        {:error, {:invalid_policy_locales, locales}}

      not valid_policy_slugs?(slugs) ->
        {:error, {:invalid_policy_slugs, slugs}}

      orphans != [] ->
        {:error, {:policy_slugs_without_locale, orphans}}

      true ->
        :ok
    end
  end

  defp validate_policies(%{policies: policies}), do: {:error, {:invalid_policies, policies}}

  defp valid_policies_path?(path) when is_binary(path),
    do: String.starts_with?(path, "/") and not String.ends_with?(path, "/")

  defp valid_policies_path?(_), do: false

  defp valid_policy_locales?(locales) when is_map(locales) do
    Enum.all?(locales, fn {locale, code} ->
      is_binary(locale) and locale != "" and
        is_binary(code) and Regex.match?(~r/^[A-Z]{2,3}(?:_[A-Z]{2})?$/, code)
    end)
  end

  defp valid_policy_locales?(_), do: false

  defp valid_policy_slugs?(slugs) when is_map(slugs) do
    Enum.all?(slugs, fn {locale, types} ->
      is_binary(locale) and locale != "" and valid_policy_type_slugs?(types)
    end)
  end

  defp valid_policy_slugs?(_), do: false

  defp valid_policy_type_slugs?(types) when is_map(types) do
    slugs = Map.values(types)

    Enum.all?(types, fn {type, slug} ->
      type in @policy_types and is_binary(slug) and slug != "" and
        not String.contains?(slug, "/")
    end) and Enum.uniq(slugs) == slugs
  end

  defp valid_policy_type_slugs?(_), do: false

  defp normalize_catalog_contexts(contexts) when is_list(contexts) do
    Enum.map(contexts, fn
      {key, values} when is_list(values) or is_map(values) ->
        context(key, normalize_known_keys(values, @context_keys))

      values when is_map(values) ->
        values = normalize_known_keys(values, @context_keys)
        context(values.key, values)

      invalid ->
        invalid
    end)
  end

  defp normalize_catalog_contexts(invalid), do: invalid

  defp context(key, values) do
    %{
      key: normalize_context_key(key),
      country: normalize_context_code(values.country),
      language: normalize_context_code(values.language),
      sync_selling_plans: values.sync_selling_plans || false
    }
  end

  defp normalize_known_keys(values, keys) do
    values = Map.new(values)

    string_values =
      Map.new(keys, fn key ->
        {key, Map.get(values, Atom.to_string(key))}
      end)

    Map.merge(string_values, Map.take(values, keys))
  end

  defp value_or(value, default) when value in [nil, false], do: default
  defp value_or(value, _default), do: value

  defp normalize_context_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_context_key(key) when is_binary(key), do: String.trim(key)
  defp normalize_context_key(key), do: key

  defp normalize_context_code(nil), do: nil
  defp normalize_context_code(code) when is_atom(code), do: code |> to_string() |> String.upcase()

  defp normalize_context_code(code) when is_binary(code),
    do: code |> String.trim() |> String.upcase()

  defp normalize_context_code(code), do: code

  defp valid_catalog_contexts?(contexts) when is_list(contexts) do
    keys = Enum.map(contexts, &context_key/1)

    Enum.all?(contexts, &valid_catalog_context?/1) and
      Enum.uniq(keys) == keys
  end

  defp valid_catalog_contexts?(_), do: false

  defp valid_catalog_context?(%{
         key: key,
         country: country,
         language: language,
         sync_selling_plans: sync_selling_plans
       }) do
    is_binary(key) and key != "" and
      (is_nil(country) or (is_binary(country) and Regex.match?(~r/^[A-Z]{2}$/, country))) and
      (is_nil(language) or
         (is_binary(language) and Regex.match?(~r/^[A-Z]{2,3}(?:_[A-Z]{2})?$/, language))) and
      is_boolean(sync_selling_plans)
  end

  defp valid_catalog_context?(_), do: false
  defp context_key(%{key: key}), do: key
  defp context_key(_), do: nil
end
