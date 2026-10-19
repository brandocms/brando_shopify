defmodule BrandoShopify.Settings do
  @moduledoc """
  What an administrator can change about a store without a deploy: its launch
  state and which of its collections are partner shops. One row per configured
  store, in `shopify_settings` (`mix brando_shopify.install`).

  A store with no row behaves as its configuration says, so installing the table
  changes nothing until someone saves. Neither does upgrading before running the
  migration: until `shopify_settings` exists, every store reads as unsaved, with
  one warning in the log.

  ## Launch state

  Point the store's `:visibility` at the stored value, with the state to use
  until one is saved:

      config :brando_shopify,
        stores: [
          default: [
            visibility: {BrandoShopify.Settings, :visibility, [:default, :preview]}
          ]
        ]

  ## Partner shops

  Collections whose products belong to a partner rather than to the house: a
  site can list them apart, and hide what belongs *only* to a partner from its
  main listing. Kept in order — a product in two partner collections belongs to
  the first.

      BrandoShopify.Settings.partner_collections(:default, ["sykkelforeningen"])

  ## Caching

  Both are read on every shop request, so a store's row is cached in
  `:persistent_term` for 30 seconds. `update/2` clears the cache on the node
  it runs on; other nodes see the change within the 30 seconds.
  """

  use Ecto.Schema

  import Ecto.Changeset

  require Logger

  alias BrandoShopify.Config

  @visibility_states [:off, :preview, :live]
  @ttl_ms 30_000

  @primary_key {:store, :string, autogenerate: false}
  schema "shopify_settings" do
    field(:visibility, Ecto.Enum, values: @visibility_states)
    field(:partner_collections, {:array, :string}, default: [])

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          store: String.t(),
          visibility: Config.visibility() | nil,
          partner_collections: [String.t()]
        }

  @doc "The launch states, in the order an admin screen offers them."
  def visibility_states, do: @visibility_states

  @doc "The store's saved settings, or nil when nothing has been saved."
  @spec get(atom() | String.t()) :: t() | nil
  def get(store \\ :default) do
    key = cache_key(store)
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(key, nil) do
      {settings, fetched_at} when now - fetched_at < @ttl_ms ->
        settings

      _ ->
        settings = load(store)
        :persistent_term.put(key, {settings, now})
        settings
    end
  end

  @doc """
  The store's launch state: the saved one, or `fallback` while none is saved.
  Shaped to be the store's `:visibility` source.
  """
  @spec visibility(atom() | String.t(), Config.visibility()) :: Config.visibility()
  def visibility(store \\ :default, fallback \\ :live) when fallback in @visibility_states do
    case get(store) do
      %__MODULE__{visibility: state} when state in @visibility_states -> state
      _ -> fallback
    end
  end

  @doc """
  The store's partner collections, by handle, in order: the saved ones, or
  `fallback` while none are saved. A saved empty list means no partner shops.
  """
  @spec partner_collections(atom() | String.t(), [String.t()]) :: [String.t()]
  def partner_collections(store \\ :default, fallback \\ []) do
    case get(store) do
      %__MODULE__{partner_collections: handles} when is_list(handles) -> handles
      nil -> fallback
    end
  end

  @doc "Saves the store's settings, creating its row on the first save."
  @spec update(atom() | String.t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(store, attrs) do
    repo = store |> config_name() |> Config.fetch!() |> Config.repo!()
    settings = repo.get(__MODULE__, to_string(store)) || %__MODULE__{store: to_string(store)}

    result =
      settings
      |> changeset(attrs)
      |> repo.insert_or_update()

    :persistent_term.erase(cache_key(store))
    result
  end

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:visibility, :partner_collections])
    |> update_change(:partner_collections, &normalize_handles/1)
    |> validate_change(:partner_collections, fn :partner_collections, handles ->
      if Enum.all?(handles, &(&1 =~ ~r/\A[a-z0-9][a-z0-9\-]*\z/)),
        do: [],
        else: [partner_collections: "must be collection handles"]
    end)
  end

  defp normalize_handles(handles) do
    handles
    |> List.wrap()
    |> Enum.map(&(&1 |> to_string() |> String.trim()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  # A store that is not configured — in a test environment, say — reads as
  # unsaved: there is no repo to read it from, and its fallbacks are the answer.
  defp load(store) do
    case store |> config_name() |> Config.fetch() do
      {:ok, config} -> Config.repo!(config).get(__MODULE__, to_string(store))
      {:error, _reason} -> nil
    end
  rescue
    # Matched by shape: Postgrex is an optional dependency.
    error ->
      if match?(%{postgres: %{code: :undefined_table}}, error) do
        warn_missing_table()
        nil
      else
        reraise error, __STACKTRACE__
      end
  end

  defp warn_missing_table do
    unless :persistent_term.get({__MODULE__, :warned_missing_table}, false) do
      :persistent_term.put({__MODULE__, :warned_missing_table}, true)

      Logger.warning(
        "BrandoShopify: shopify_settings does not exist yet; every store reads as unsaved. " <>
          "Run mix brando_shopify.install and migrate."
      )
    end
  end

  defp config_name(store) when is_atom(store), do: store
  defp config_name(store) when is_binary(store), do: String.to_existing_atom(store)

  defp cache_key(store), do: {__MODULE__, to_string(store)}
end
