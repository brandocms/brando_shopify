defmodule BrandoShopify.Admin.Documents do
  @moduledoc false

  @media_fields """
  id
  alt
  mediaContentType
  status
  preview {
    image {
      url
      altText
      width
      height
    }
  }
  ... on MediaImage {
    image {
      url
      altText
      width
      height
    }
  }
  ... on Video {
    sources {
      url
      mimeType
      format
      width
      height
    }
    originalSource {
      url
      mimeType
      format
      width
      height
    }
  }
  ... on ExternalVideo {
    host
    originUrl
  }
  ... on Model3d {
    sources {
      url
      mimeType
      format
    }
    originalSource {
      url
      mimeType
      format
    }
  }
  """

  @variant_fields """
  id
  legacyResourceId
  title
  displayName
  sku
  barcode
  price
  compareAtPrice
  inventoryQuantity
  inventoryPolicy
  availableForSale
  requiresComponents
  position
  taxable
  selectedOptions {
    name
    value
    optionValue {
      id
      name
      linkedMetafieldValue
    }
  }
  image {
    url
    altText
    width
    height
  }
  createdAt
  updatedAt
  inventoryItem {
    id
    legacyResourceId
    sku
    tracked
    requiresShipping
    updatedAt
    inventoryLevels(first: 250) {
      nodes {
        id
        isActive
        updatedAt
        location {
          id
          legacyResourceId
          name
        }
        quantities(names: ["available", "on_hand"]) {
          name
          quantity
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
  """

  @bulk_variant_fields """
  id
  legacyResourceId
  title
  displayName
  sku
  barcode
  price
  compareAtPrice
  inventoryQuantity
  inventoryPolicy
  availableForSale
  requiresComponents
  position
  taxable
  selectedOptions {
    name
    value
    optionValue {
      id
      name
      linkedMetafieldValue
    }
  }
  image {
    url
    altText
    width
    height
  }
  createdAt
  updatedAt
  inventoryItem {
    id
    legacyResourceId
    sku
    tracked
    requiresShipping
    updatedAt
  }
  """

  @collection_fields """
  id
  legacyResourceId
  handle
  title
  descriptionHtml
  updatedAt
  image {
    url
    altText
    width
    height
  }
  seo {
    title
    description
  }
  """

  @metafield_fields """
  id
  namespace
  key
  type
  value
  """

  @product_fields """
  id
  legacyResourceId
  handle
  title
  descriptionHtml
  vendor
  productType
  status
  templateSuffix
  isGiftCard
  combinedListingRole
  requiresSellingPlan
  hasOnlyDefaultVariant
  hasOutOfStockVariants
  hasVariantsThatRequiresComponents
  onlineStoreUrl
  tags
  totalInventory
  tracksInventory
  createdAt
  updatedAt
  publishedAt
  category {
    id
    name
    fullName
  }
  seo {
    title
    description
  }
  options {
    id
    name
    position
    values
    optionValues {
      id
      name
      hasVariants
      linkedMetafieldValue
      swatch {
        color
        image {
          id
          image {
            url
            altText
            width
            height
          }
        }
      }
    }
  }
  featuredMedia {
    #{@media_fields}
  }
  priceRangeV2 {
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

  def product do
    """
    query BrandoShopifyProduct($id: ID!) {
      product(id: $id) {
        #{@product_fields}
        variants(first: 250) {
          nodes {
            #{@variant_fields}
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
        media(first: 250) {
          nodes {
            #{@media_fields}
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
        collections(first: 250) {
          nodes {
            #{@collection_fields}
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
        metafields(first: 250) {
          nodes {
            #{@metafield_fields}
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

  def product_variants do
    """
    query BrandoShopifyProductVariants($id: ID!, $after: String) {
      product(id: $id) {
        variants(first: 250, after: $after) {
          nodes {
            #{@variant_fields}
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

  def product_media do
    """
    query BrandoShopifyProductMedia($id: ID!, $after: String) {
      product(id: $id) {
        media(first: 250, after: $after) {
          nodes {
            #{@media_fields}
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

  def product_collections do
    """
    query BrandoShopifyProductCollections($id: ID!, $after: String) {
      product(id: $id) {
        collections(first: 250, after: $after) {
          nodes {
            #{@collection_fields}
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

  def product_metafields do
    """
    query BrandoShopifyProductMetafields($id: ID!, $after: String) {
      product(id: $id) {
        metafields(first: 250, after: $after) {
          nodes {
            #{@metafield_fields}
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

  def inventory_item_levels do
    """
    query BrandoShopifyInventoryItemLevels($id: ID!, $after: String) {
      inventoryItem(id: $id) {
        inventoryLevels(first: 250, after: $after) {
          nodes {
            id
            isActive
            updatedAt
            location {
              id
              legacyResourceId
              name
            }
            quantities(names: ["available", "on_hand"]) {
              name
              quantity
            }
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

  def products_updated do
    """
    query BrandoShopifyProductsUpdated($after: String, $query: String!) {
      products(first: 250, after: $after, query: $query, sortKey: UPDATED_AT) {
        nodes {
          id
          updatedAt
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
    """
  end

  def collection do
    """
    query BrandoShopifyCollection($id: ID!, $after: String) {
      collection(id: $id) {
        #{@collection_fields}
        products(first: 250, after: $after) {
          nodes {
            id
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

  def bulk_products_query do
    """
    {
      products {
        edges {
          node {
            #{@product_fields}
            variants {
              edges {
                node {
                  #{@bulk_variant_fields}
                }
              }
            }
            media {
              edges {
                node {
                  #{@media_fields}
                }
              }
            }
            collections {
              edges {
                node {
                  #{@collection_fields}
                }
              }
            }
            metafields {
              edges {
                node {
                  #{@metafield_fields}
                }
              }
            }
          }
        }
      }
    }
    """
  end

  def bulk_inventory_query do
    """
    {
      inventoryItems {
        edges {
          node {
            id
            legacyResourceId
            sku
            tracked
            requiresShipping
            updatedAt
            variants {
              edges {
                node {
                  id
                }
              }
            }
            inventoryLevels {
              edges {
                node {
                  id
                  isActive
                  updatedAt
                  location {
                    id
                    legacyResourceId
                    name
                  }
                  quantities(names: ["available", "on_hand"]) {
                    name
                    quantity
                  }
                }
              }
            }
          }
        }
      }
    }
    """
  end

  def start_bulk_inventory_query do
    """
    mutation BrandoShopifyBulkInventory($query: String!) {
      bulkOperationRunQuery(query: $query) {
        bulkOperation {
          id
          status
          createdAt
        }
        userErrors {
          field
          message
        }
      }
    }
    """
  end

  def start_bulk_query do
    """
    mutation BrandoShopifyBulkProducts($query: String!) {
      bulkOperationRunQuery(query: $query) {
        bulkOperation {
          id
          status
          createdAt
        }
        userErrors {
          field
          message
        }
      }
    }
    """
  end

  def bulk_operation do
    """
    query BrandoShopifyBulkOperation($id: ID!) {
      bulkOperation(id: $id) {
        id
        status
        errorCode
        createdAt
        completedAt
        objectCount
        fileSize
        url
        partialDataUrl
      }
    }
    """
  end

  def webhook_subscription_create do
    """
    mutation BrandoShopifyWebhookSubscription(
      $topic: WebhookSubscriptionTopic!,
      $subscription: WebhookSubscriptionInput!
    ) {
      webhookSubscriptionCreate(
        topic: $topic,
        webhookSubscription: $subscription
      ) {
        webhookSubscription {
          id
          topic
          uri
        }
        userErrors {
          field
          message
        }
      }
    }
    """
  end
end
