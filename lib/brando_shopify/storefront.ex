defmodule BrandoShopify.Storefront do
  @moduledoc """
  Buyer-facing catalog queries against the Storefront GraphQL API.

  Background sync uses `product_by_id/2` to persist each configured
  country/language projection. The handle/ID helpers remain public for callers
  that deliberately need a live Storefront request, but catalog/template APIs
  never invoke them implicitly. Cart and checkout operations remain live.
  """

  alias BrandoShopify.GraphQL

  @product_fields """
  fragment StorefrontProduct on Product {
    id
    handle
    title
    description
    descriptionHtml
    availableForSale
    vendor
    productType
    requiresSellingPlan
    updatedAt
    seo {
      title
      description
    }
    featuredImage {
      url
      altText
      width
      height
    }
    options {
      id
      name
      optionValues {
        id
        name
        swatch {
          color
          image {
            previewImage {
              url
            }
          }
        }
      }
    }
    priceRange {
      minVariantPrice {
        amount
        currencyCode
      }
      maxVariantPrice {
        amount
        currencyCode
      }
    }
    variants(first: 250) {
      nodes {
        id
        title
        availableForSale
        quantityAvailable
        requiresShipping
        sku
        selectedOptions {
          name
          value
        }
        price {
          amount
          currencyCode
        }
        compareAtPrice {
          amount
          currencyCode
        }
        image {
          url
          altText
          width
          height
        }
      }
    }
  }
  """

  @by_handle """
  #{@product_fields}

  query StorefrontProductByHandle(
    $handle: String!,
    $country: CountryCode,
    $language: LanguageCode
  ) @inContext(country: $country, language: $language) {
    product(handle: $handle) {
      ...StorefrontProduct
    }
  }
  """

  @by_ids """
  #{@product_fields}

  query StorefrontProductsByIds(
    $ids: [ID!]!,
    $country: CountryCode,
    $language: LanguageCode
  ) @inContext(country: $country, language: $language) {
    nodes(ids: $ids) {
      ... on Product {
        ...StorefrontProduct
      }
    }
  }
  """

  @context_product_fields """
  id
  handle
  title
  description
  descriptionHtml
  availableForSale
  vendor
  productType
  requiresSellingPlan
  updatedAt
  seo {
    title
    description
  }
  featuredImage {
    url
    altText
    width
    height
  }
  options {
    id
    name
    optionValues {
      id
      name
      swatch {
        color
        image {
          previewImage {
            url
          }
        }
      }
    }
  }
  priceRange {
    minVariantPrice {
      amount
      currencyCode
    }
    maxVariantPrice {
      amount
      currencyCode
    }
  }
  """

  @context_variant_fields """
  id
  title
  availableForSale
  quantityAvailable
  requiresShipping
  sku
  selectedOptions {
    name
    value
  }
  price {
    amount
    currencyCode
  }
  compareAtPrice {
    amount
    currencyCode
  }
  image {
    url
    altText
    width
    height
  }
  """

  @selling_plan_group_fields """
  sellingPlanGroups(first: 250) {
    nodes {
      appName
      name
      options {
        name
        values
      }
      sellingPlans(first: 250) {
        nodes {
          id
          name
          description
          recurringDeliveries
          options {
            name
            value
          }
          priceAdjustments {
            orderCount
            adjustmentValue {
              ... on SellingPlanFixedAmountPriceAdjustment {
                adjustmentAmount {
                  amount
                  currencyCode
                }
              }
              ... on SellingPlanFixedPriceAdjustment {
                price {
                  amount
                  currencyCode
                }
              }
              ... on SellingPlanPercentagePriceAdjustment {
                adjustmentPercentage
              }
            }
          }
        }
      }
    }
  }
  """

  @selling_plan_allocation_fields """
  sellingPlanAllocations(first: 250) {
    nodes {
      sellingPlan {
        id
      }
      checkoutChargeAmount {
        amount
        currencyCode
      }
      remainingBalanceChargeAmount {
        amount
        currencyCode
      }
      priceAdjustments {
        compareAtPrice {
          amount
          currencyCode
        }
        perDeliveryPrice {
          amount
          currencyCode
        }
        price {
          amount
          currencyCode
        }
        unitPrice {
          amount
          currencyCode
        }
      }
    }
  }
  """

  @doc "Fetches one current, contextualized product by handle."
  @spec product_by_handle(String.t(), keyword()) ::
          {:ok, map() | nil} | {:error, BrandoShopify.Error.t()}
  def product_by_handle(handle, opts \\ []) when is_binary(handle) do
    variables =
      %{"handle" => handle}
      |> put_context(opts)

    with {:ok, response} <-
           GraphQL.request(:storefront, @by_handle, variables,
             operation_name: "StorefrontProductByHandle",
             store: opts[:store] || :default,
             config: opts[:config],
             http: opts[:http],
             buyer_ip: opts[:buyer_ip],
             req_options: opts[:req_options] || []
           ) do
      {:ok, response.data["product"]}
    end
  end

  @doc "Fetches up to 250 contextualized products by Shopify GID."
  @spec products_by_ids([String.t()], keyword()) ::
          {:ok, [map()]} | {:error, BrandoShopify.Error.t()}
  def products_by_ids(ids, opts \\ [])

  def products_by_ids(ids, opts) when is_list(ids) do
    if length(ids) <= 250,
      do: fetch_products_by_ids(ids, opts),
      else: too_many_ids()
  end

  defp fetch_products_by_ids(ids, opts) do
    variables =
      %{"ids" => ids}
      |> put_context(opts)

    with {:ok, response} <-
           GraphQL.request(:storefront, @by_ids, variables,
             operation_name: "StorefrontProductsByIds",
             store: opts[:store] || :default,
             config: opts[:config],
             http: opts[:http],
             buyer_ip: opts[:buyer_ip],
             req_options: opts[:req_options] || []
           ) do
      {:ok, Enum.reject(response.data["nodes"] || [], &is_nil/1)}
    end
  end

  defp too_many_ids do
    {:error,
     %BrandoShopify.Error{
       kind: :user,
       message: "Shopify accepts at most 250 IDs per request"
     }}
  end

  @doc """
  Fetches one product by GID for background contextual projection sync.

  This follows the variant connection. Selling-plan groups and allocations are
  included only when `include_selling_plans: true`; the Storefront token then
  needs Shopify's `unauthenticated_read_selling_plans` scope.
  """
  @spec product_by_id(String.t(), keyword()) ::
          {:ok, map() | nil} | {:error, BrandoShopify.Error.t()}
  def product_by_id(id, opts \\ []) when is_binary(id) do
    document = context_product_document(opts[:include_selling_plans] || false)

    variables =
      %{"id" => id}
      |> put_context(opts)

    with {:ok, response} <-
           GraphQL.request(:storefront, document, variables,
             operation_name: "StorefrontProductContextById",
             store: opts[:store] || :default,
             config: opts[:config],
             http: opts[:http],
             req_options: opts[:req_options] || []
           ),
         :ok <- validate_applied_context(response, opts),
         product when is_map(product) <- response.data["product"],
         {:ok, variants} <- complete_context_variants(product, id, opts) do
      {:ok, put_in(product, ["variants", "nodes"], variants)}
    else
      nil -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  defp complete_context_variants(product, id, opts) do
    connection = product["variants"] || %{}
    nodes = connection["nodes"] || []
    page_info = connection["pageInfo"] || %{}

    if page_info["hasNextPage"] do
      collect_context_variants(id, page_info["endCursor"], nodes, opts)
    else
      {:ok, nodes}
    end
  end

  defp collect_context_variants(id, cursor, acc, opts) do
    document = context_variants_document(opts[:include_selling_plans] || false)

    variables =
      %{"id" => id, "after" => cursor}
      |> put_context(opts)

    with {:ok, response} <-
           GraphQL.request(:storefront, document, variables,
             operation_name: "StorefrontProductContextVariants",
             store: opts[:store] || :default,
             config: opts[:config],
             http: opts[:http],
             req_options: opts[:req_options] || []
           ),
         :ok <- validate_applied_context(response, opts),
         connection when is_map(connection) <- get_in(response.data, ["product", "variants"]) do
      nodes = acc ++ (connection["nodes"] || [])
      page_info = connection["pageInfo"] || %{}

      if page_info["hasNextPage"] do
        collect_context_variants(id, page_info["endCursor"], nodes, opts)
      else
        {:ok, nodes}
      end
    else
      {:error, error} ->
        {:error, error}

      _ ->
        {:error,
         %BrandoShopify.Error{
           kind: :invalid_response,
           message: "Shopify omitted the contextual product variants connection"
         }}
    end
  end

  defp context_product_document(include_selling_plans?) do
    selling_plans = if include_selling_plans?, do: @selling_plan_group_fields, else: ""
    allocations = if include_selling_plans?, do: @selling_plan_allocation_fields, else: ""

    """
    query StorefrontProductContextById(
      $id: ID!,
      $country: CountryCode,
      $language: LanguageCode
    ) @inContext(country: $country, language: $language) {
      product(id: $id) {
        #{@context_product_fields}
        #{selling_plans}
        variants(first: 250) {
          nodes {
            #{@context_variant_fields}
            #{allocations}
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    }
    """
  end

  defp context_variants_document(include_selling_plans?) do
    allocations = if include_selling_plans?, do: @selling_plan_allocation_fields, else: ""

    """
    query StorefrontProductContextVariants(
      $id: ID!,
      $after: String,
      $country: CountryCode,
      $language: LanguageCode
    ) @inContext(country: $country, language: $language) {
      product(id: $id) {
        variants(first: 250, after: $after) {
          nodes {
            #{@context_variant_fields}
            #{allocations}
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    }
    """
  end

  defp put_context(variables, opts) do
    variables
    |> Map.put("country", normalize_code(opts[:country]))
    |> Map.put("language", normalize_code(opts[:language]))
  end

  defp normalize_code(nil), do: nil
  defp normalize_code(code) when is_atom(code), do: code |> Atom.to_string() |> String.upcase()
  defp normalize_code(code) when is_binary(code), do: String.upcase(code)

  defp validate_applied_context(response, opts) do
    expected = %{
      "country" => normalize_code(opts[:country]),
      "language" => normalize_code(opts[:language])
    }

    expected = Map.reject(expected, fn {_key, value} -> is_nil(value) end)
    applied = response.extensions["context"]

    cond do
      expected == %{} ->
        :ok

      not is_map(applied) ->
        context_error(expected, applied)

      Enum.all?(expected, fn {key, value} -> applied[key] == value end) ->
        :ok

      true ->
        context_error(expected, applied)
    end
  end

  defp context_error(expected, applied) do
    {:error,
     %BrandoShopify.Error{
       kind: :invalid_response,
       message: "Shopify did not apply the requested Storefront context",
       details: %{expected: expected, applied: applied}
     }}
  end
end
