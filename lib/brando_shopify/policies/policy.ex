defmodule BrandoShopify.Policies.Policy do
  @moduledoc """
  Read-only local projection of one Shopify shop policy, in one locale.

  Shopify is the source of truth. Policies are cached here for the same reason
  products are: the storefront renders them, and rendering must not depend on a
  live Storefront request. Caching also means the site shows the same text the
  Shopify-hosted checkout links to, without anyone maintaining two copies.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @types [
    :privacy_policy,
    :refund_policy,
    :shipping_policy,
    :subscription_policy,
    :terms_of_service
  ]

  schema "shopify_policies" do
    field(:store, :string)
    field(:type, Ecto.Enum, values: @types)
    # The host application's locale ("no", "en"), not Shopify's LanguageCode.
    field(:locale, :string)
    # The Shopify LanguageCode the body was actually fetched under ("NB").
    field(:language_code, :string)
    field(:shopify_id, :string)
    field(:handle, :string)
    field(:title, :string)
    field(:body, :string)
    # Shopify's own hosted URL, on checkout.shopify.com. Kept for reference and
    # for reconciling against what the checkout links to — not for linking to.
    field(:shopify_url, :string)
    field(:synced_at, :utc_datetime_usec)
    field(:source_data, :map, default: %{})

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :store,
    :type,
    :locale,
    :language_code,
    :shopify_id,
    :handle,
    :title,
    :body,
    :shopify_url,
    :synced_at,
    :source_data
  ]

  @doc "Every policy type the Storefront API exposes."
  @spec types() :: [atom()]
  def types, do: @types

  @doc false
  def changeset(policy, attrs) do
    policy
    |> cast(attrs, @fields)
    |> validate_required([:store, :type, :locale, :title, :body, :synced_at])
    |> unique_constraint([:store, :type, :locale])
  end
end
