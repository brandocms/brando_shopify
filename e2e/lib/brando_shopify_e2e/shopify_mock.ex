defmodule BrandoShopifyE2E.ShopifyMock do
  @moduledoc false

  use GenServer

  @behaviour BrandoShopify.HTTP

  @product_id "gid://shopify/Product/1001"
  @variant_id "gid://shopify/ProductVariant/2001"
  @inventory_item_id "gid://shopify/InventoryItem/4001"
  @location_id "gid://shopify/Location/5001"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def reset, do: GenServer.call(__MODULE__, :reset)
  def clear_requests, do: GenServer.call(__MODULE__, :clear_requests)
  def update_product(attrs), do: GenServer.call(__MODULE__, {:update_product, attrs})
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)
  def product_id, do: @product_id

  @impl BrandoShopify.HTTP
  def request(options), do: GenServer.call(__MODULE__, {:request, options})

  @impl GenServer
  def init(:ok), do: {:ok, initial_state()}

  @impl GenServer
  def handle_call(:reset, _from, _state), do: {:reply, :ok, initial_state()}

  def handle_call(:clear_requests, _from, state) do
    {:reply, :ok, %{state | requests: %{}}}
  end

  def handle_call({:update_product, attrs}, _from, state) do
    attrs = stringify_keys(attrs)
    product = update_product_fixture(state.product, attrs)
    context_title = attrs["context_title"] || state.context_title
    context_price = attrs["context_price"] || state.context_price

    {:reply, {:ok, product},
     %{state | product: product, context_title: context_title, context_price: context_price}}
  end

  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      requests: state.requests,
      request_count: state.requests |> Map.values() |> Enum.sum(),
      cart_count: map_size(state.carts),
      product: %{
        id: state.product["id"],
        title: state.product["title"],
        updated_at: state.product["updatedAt"]
      },
      context: %{
        title: state.context_title,
        price: state.context_price
      }
    }

    {:reply, snapshot, state}
  end

  def handle_call({:request, options}, _from, state) do
    request = Keyword.fetch!(options, :json)
    operation = Map.get(request, "operationName")
    variables = Map.get(request, "variables", %{})
    state = update_in(state.requests[operation], fn count -> (count || 0) + 1 end)
    {body, state} = dispatch(operation, variables, state)

    response =
      Req.Response.new(
        status: 200,
        headers: [
          {"x-request-id", "brando-shopify-e2e"},
          {"x-shopify-api-version", "2026-07"}
        ],
        body: body
      )

    {:reply, {:ok, response}, state}
  end

  defp dispatch("BrandoShopifyProduct", %{"id" => @product_id}, state) do
    {%{"data" => %{"product" => state.product}}, state}
  end

  defp dispatch("BrandoShopifyProduct", _variables, state) do
    {%{"data" => %{"product" => nil}}, state}
  end

  defp dispatch("StorefrontProductContextById", %{"id" => @product_id}, state) do
    body = %{
      "data" => %{"product" => contextual_product(state)},
      "extensions" => %{"context" => %{"country" => "NO", "language" => "NB"}}
    }

    {body, state}
  end

  defp dispatch("StorefrontProductContextById", _variables, state) do
    {%{"data" => %{"product" => nil}}, state}
  end

  defp dispatch("BrandoCart", %{"id" => id}, state) do
    cart = state.carts |> Map.get(id) |> render_cart(state.product)
    {%{"data" => %{"cart" => cart}}, state}
  end

  defp dispatch("BrandoCartCreate", variables, state) do
    input = variables["input"] || %{}
    id = "gid://shopify/Cart/e2e-#{state.next_cart}?key=never-expose-this"
    {lines, state} = add_lines([], input["lines"] || [], state)

    cart = %{
      id: id,
      lines: lines,
      note: input["note"],
      buyer_identity: input["buyerIdentity"] || %{},
      discount_codes: input["discountCodes"] || []
    }

    state = %{state | carts: Map.put(state.carts, id, cart), next_cart: state.next_cart + 1}
    mutation_response("cartCreate", cart, state)
  end

  defp dispatch("BrandoCartLinesAdd", variables, state) do
    update_cart(state, variables["cartId"], "cartLinesAdd", fn cart, state ->
      {lines, state} = add_lines(cart.lines, variables["lines"] || [], state)
      {%{cart | lines: lines}, state}
    end)
  end

  defp dispatch("BrandoCartLinesUpdate", variables, state) do
    updates = Map.new(variables["lines"] || [], &{&1["id"], &1})

    update_cart(state, variables["cartId"], "cartLinesUpdate", fn cart, state ->
      lines = Enum.map(cart.lines, &apply_line_update(&1, Map.get(updates, &1.id)))

      {%{cart | lines: lines}, state}
    end)
  end

  defp dispatch("BrandoCartLinesRemove", variables, state) do
    ids = MapSet.new(variables["lineIds"] || [])

    update_cart(state, variables["cartId"], "cartLinesRemove", fn cart, state ->
      {%{cart | lines: Enum.reject(cart.lines, &MapSet.member?(ids, &1.id))}, state}
    end)
  end

  defp dispatch("BrandoCartDiscountsUpdate", variables, state) do
    update_cart(state, variables["cartId"], "cartDiscountCodesUpdate", fn cart, state ->
      {%{cart | discount_codes: variables["discountCodes"] || []}, state}
    end)
  end

  defp dispatch("BrandoCartNoteUpdate", variables, state) do
    update_cart(state, variables["cartId"], "cartNoteUpdate", fn cart, state ->
      {%{cart | note: variables["note"]}, state}
    end)
  end

  defp dispatch("BrandoCartBuyerUpdate", variables, state) do
    update_cart(state, variables["cartId"], "cartBuyerIdentityUpdate", fn cart, state ->
      {%{cart | buyer_identity: variables["buyerIdentity"] || %{}}, state}
    end)
  end

  defp dispatch(operation, _variables, state) do
    body = %{"errors" => [%{"message" => "Unhandled E2E operation #{inspect(operation)}"}]}
    {body, state}
  end

  defp apply_line_update(line, nil), do: line

  defp apply_line_update(line, update) do
    line = %{line | quantity: update["quantity"] || line.quantity}

    if Map.has_key?(update, "sellingPlanId"),
      do: %{line | selling_plan_id: update["sellingPlanId"]},
      else: line
  end

  defp update_cart(state, id, payload_key, updater) do
    case Map.fetch(state.carts, id) do
      {:ok, cart} ->
        {cart, state} = updater.(cart, state)
        state = %{state | carts: Map.put(state.carts, id, cart)}
        mutation_response(payload_key, cart, state)

      :error ->
        payload = %{
          "cart" => nil,
          "userErrors" => [%{"field" => ["cartId"], "message" => "Cart not found"}],
          "warnings" => []
        }

        {%{"data" => %{payload_key => payload}}, state}
    end
  end

  defp mutation_response(payload_key, cart, state) do
    payload = %{
      "cart" => render_cart(cart, state.product),
      "userErrors" => [],
      "warnings" => []
    }

    {%{"data" => %{payload_key => payload}}, state}
  end

  defp add_lines(existing, inputs, state) do
    inputs
    |> Enum.map_reduce(state, fn input, state ->
      line = %{
        id: "gid://shopify/CartLine/#{state.next_line}",
        merchandise_id: input["merchandiseId"],
        selling_plan_id: input["sellingPlanId"],
        quantity: input["quantity"] || 1,
        attributes: input["attributes"] || []
      }

      {line, %{state | next_line: state.next_line + 1}}
    end)
    |> then(fn {new_lines, state} -> {existing ++ new_lines, state} end)
  end

  defp render_cart(nil, _product), do: nil

  defp render_cart(cart, product) do
    lines = Enum.map(cart.lines, &render_line(&1, product))
    total = lines |> Enum.map(&get_in(&1, ["cost", "totalAmount", "amount"])) |> sum_money()

    %{
      "id" => cart.id,
      "checkoutUrl" => "http://localhost:#{System.get_env("PORT") || "4455"}/__shopify/checkout",
      "totalQuantity" => Enum.sum(Enum.map(cart.lines, & &1.quantity)),
      "note" => cart.note,
      "attributes" => [],
      "buyerIdentity" => cart.buyer_identity,
      "discountCodes" =>
        Enum.map(cart.discount_codes, &%{"code" => &1, "applicable" => &1 == "BRANDO10"}),
      "cost" => cart_cost(total),
      "lines" => %{"nodes" => lines}
    }
  end

  defp render_line(line, product) do
    variant =
      product
      |> get_in(["variants", "nodes"])
      |> Enum.find(&(&1["id"] == line.merchandise_id))
      |> Kernel.||(%{})

    price = variant["price"] || "0.00"
    total = multiply_money(price, line.quantity)

    %{
      "id" => line.id,
      "quantity" => line.quantity,
      "attributes" => line.attributes,
      "sellingPlanAllocation" => selling_plan_allocation(line.selling_plan_id, price),
      "cost" => %{
        "amountPerQuantity" => money(price),
        "compareAtAmountPerQuantity" => nil,
        "subtotalAmount" => money(total),
        "totalAmount" => money(total)
      },
      "discountAllocations" => [],
      "merchandise" => %{
        "id" => line.merchandise_id,
        "title" => variant["title"] || "Unknown variant",
        "availableForSale" => true,
        "quantityAvailable" => variant["inventoryQuantity"] || 0,
        "requiresShipping" => true,
        "sku" => variant["sku"],
        "selectedOptions" => variant["selectedOptions"] || [],
        "image" => variant["image"],
        "price" => money(price),
        "compareAtPrice" => nil,
        "product" => %{
          "id" => product["id"],
          "handle" => product["handle"],
          "title" => product["title"],
          "vendor" => product["vendor"]
        }
      }
    }
  end

  defp cart_cost(total) do
    %{
      "subtotalAmount" => money(total),
      "subtotalAmountEstimated" => false,
      "checkoutChargeAmount" => money(total),
      "totalAmount" => money(total),
      "totalAmountEstimated" => false
    }
  end

  defp selling_plan_allocation(nil, _price), do: nil

  defp selling_plan_allocation(id, price) do
    %{
      "sellingPlan" => %{
        "id" => id,
        "name" => "Monthly delivery",
        "description" => "Mock subscription",
        "options" => [%{"name" => "Delivery every", "value" => "Month"}]
      },
      "checkoutChargeAmount" => money(price),
      "remainingBalanceChargeAmount" => money("0.00"),
      "priceAdjustments" => []
    }
  end

  defp money(amount), do: %{"amount" => amount, "currencyCode" => "NOK"}

  defp multiply_money(amount, quantity) do
    amount
    |> Decimal.new()
    |> Decimal.mult(Decimal.new(quantity))
    |> Decimal.to_string(:normal)
  end

  defp sum_money(amounts) do
    amounts
    |> Enum.reduce(Decimal.new(0), &Decimal.add(Decimal.new(&1), &2))
    |> Decimal.to_string(:normal)
  end

  defp update_product_fixture(product, attrs) do
    product
    |> update_title(attrs["title"])
    |> update_inventory(attrs["inventory"])
    |> update_price(attrs["price"])
    |> Map.put("updatedAt", DateTime.utc_now() |> DateTime.to_iso8601())
  end

  defp update_title(product, title) when is_binary(title) and title != "",
    do: Map.put(product, "title", title)

  defp update_title(product, _title), do: product

  defp update_inventory(product, inventory) when is_integer(inventory) do
    product
    |> put_in(["variants", "nodes", Access.at(0), "inventoryQuantity"], inventory)
    |> put_in(
      [
        "variants",
        "nodes",
        Access.at(0),
        "inventoryItem",
        "inventoryLevels",
        "nodes",
        Access.at(0),
        "quantities",
        Access.at(0),
        "quantity"
      ],
      inventory
    )
    |> Map.put("totalInventory", inventory)
  end

  defp update_inventory(product, _inventory), do: product

  defp update_price(product, price) when is_binary(price) and price != "" do
    product
    |> put_in(["variants", "nodes", Access.at(0), "price"], price)
    |> put_in(["priceRangeV2", "minVariantPrice", "amount"], price)
    |> put_in(["priceRangeV2", "maxVariantPrice", "amount"], price)
  end

  defp update_price(product, _price), do: product

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp initial_state do
    %{
      product: product_fixture(),
      context_title: "Brando feltstøvel",
      context_price: "1499.00",
      carts: %{},
      requests: %{},
      next_cart: 1,
      next_line: 1
    }
  end

  defp product_fixture do
    image = %{
      "url" =>
        "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='96' height='96'%3E%3Crect width='96' height='96' fill='%23ede7df'/%3E%3C/svg%3E",
      "altText" => "A Brando field boot",
      "width" => 96,
      "height" => 96
    }

    media = %{
      "id" => "gid://shopify/MediaImage/3001",
      "alt" => "A Brando field boot",
      "mediaContentType" => "IMAGE",
      "status" => "READY",
      "preview" => %{"image" => image},
      "image" => image
    }

    variant = %{
      "id" => @variant_id,
      "legacyResourceId" => 2001,
      "title" => "Walnut / 42",
      "displayName" => "Brando Field Boot - Walnut / 42",
      "sku" => "BRANDO-BOOT-42",
      "barcode" => "7090000002001",
      "price" => "1299.00",
      "compareAtPrice" => nil,
      "inventoryQuantity" => 12,
      "inventoryPolicy" => "DENY",
      "availableForSale" => true,
      "requiresComponents" => false,
      "position" => 1,
      "taxable" => true,
      "selectedOptions" => [
        %{"name" => "Color", "value" => "Walnut"},
        %{"name" => "Size", "value" => "42"}
      ],
      "image" => image,
      "createdAt" => "2026-07-01T10:00:00Z",
      "updatedAt" => "2026-07-31T10:00:00Z",
      "inventoryItem" => %{
        "id" => @inventory_item_id,
        "legacyResourceId" => 4001,
        "sku" => "BRANDO-BOOT-42",
        "tracked" => true,
        "requiresShipping" => true,
        "updatedAt" => "2026-07-31T10:00:00Z",
        "inventoryLevels" => %{
          "nodes" => [
            %{
              "id" => "gid://shopify/InventoryLevel/5001?inventory_item_id=4001",
              "isActive" => true,
              "updatedAt" => "2026-07-31T10:00:00Z",
              "location" => %{
                "id" => @location_id,
                "legacyResourceId" => 5001,
                "name" => "Oslo warehouse"
              },
              "quantities" => [
                %{"name" => "available", "quantity" => 12},
                %{"name" => "on_hand", "quantity" => 14}
              ]
            }
          ],
          "pageInfo" => page_info()
        }
      }
    }

    %{
      "id" => @product_id,
      "legacyResourceId" => 1001,
      "handle" => "brando-field-boot",
      "title" => "Brando Field Boot",
      "descriptionHtml" => "<p>A locally rendered product from the Shopify projection.</p>",
      "vendor" => "Brando Goods",
      "productType" => "Footwear",
      "status" => "ACTIVE",
      "templateSuffix" => nil,
      "isGiftCard" => false,
      "combinedListingRole" => nil,
      "requiresSellingPlan" => false,
      "hasOnlyDefaultVariant" => false,
      "hasOutOfStockVariants" => false,
      "hasVariantsThatRequiresComponents" => false,
      "onlineStoreUrl" => nil,
      "tags" => ["e2e", "footwear"],
      "totalInventory" => 12,
      "tracksInventory" => true,
      "createdAt" => "2026-07-01T10:00:00Z",
      "updatedAt" => "2026-07-31T10:00:00Z",
      "publishedAt" => "2026-07-01T10:00:00Z",
      "category" => %{
        "id" => "gid://shopify/TaxonomyCategory/aa",
        "name" => "Boots",
        "fullName" => "Apparel > Boots"
      },
      "seo" => %{"title" => "Brando Field Boot", "description" => "Made for E2E testing"},
      "options" => [
        %{
          "id" => "gid://shopify/ProductOption/1",
          "name" => "Color",
          "position" => 1,
          "values" => ["Walnut"],
          "optionValues" => []
        },
        %{
          "id" => "gid://shopify/ProductOption/2",
          "name" => "Size",
          "position" => 2,
          "values" => ["42"],
          "optionValues" => []
        }
      ],
      "featuredMedia" => media,
      "priceRangeV2" => %{
        "minVariantPrice" => money("1299.00"),
        "maxVariantPrice" => money("1299.00")
      },
      "variants" => %{"nodes" => [variant], "pageInfo" => page_info()},
      "media" => %{"nodes" => [media], "pageInfo" => page_info()},
      "collections" => %{"nodes" => [], "pageInfo" => page_info()},
      "metafields" => %{
        "nodes" => [
          %{
            "id" => "gid://shopify/Metafield/1",
            "namespace" => "custom",
            "key" => "material",
            "type" => "single_line_text_field",
            "value" => "Leather"
          }
        ],
        "pageInfo" => page_info()
      }
    }
  end

  defp page_info, do: %{"hasNextPage" => false, "endCursor" => nil}

  defp contextual_product(state) do
    variant = state.product |> get_in(["variants", "nodes"]) |> hd()

    %{
      "id" => state.product["id"],
      "handle" => state.product["handle"],
      "title" => state.context_title,
      "description" => "En lokalt synkronisert markedsvisning.",
      "descriptionHtml" => "<p>En lokalt synkronisert markedsvisning.</p>",
      "availableForSale" => variant["inventoryQuantity"] > 0,
      "vendor" => state.product["vendor"],
      "productType" => state.product["productType"],
      "requiresSellingPlan" => false,
      "updatedAt" => state.product["updatedAt"],
      "seo" => %{"title" => state.context_title, "description" => "Norsk markedsvisning"},
      "featuredImage" => get_in(state.product, ["featuredMedia", "image"]),
      "options" => state.product["options"],
      "priceRange" => %{
        "minVariantPrice" => money(state.context_price),
        "maxVariantPrice" => money(state.context_price)
      },
      "sellingPlanGroups" => %{
        "nodes" => [
          %{
            "appName" => "Brando subscriptions",
            "name" => "Subscribe and save",
            "options" => [%{"name" => "Delivery every", "values" => ["Month"]}],
            "sellingPlans" => %{
              "nodes" => [
                %{
                  "id" => "gid://shopify/SellingPlan/6001",
                  "name" => "Monthly delivery",
                  "description" => "Delivered monthly",
                  "recurringDeliveries" => true,
                  "options" => [%{"name" => "Delivery every", "value" => "Month"}],
                  "priceAdjustments" => []
                }
              ]
            }
          }
        ]
      },
      "variants" => %{
        "nodes" => [
          %{
            "id" => variant["id"],
            "title" => variant["title"],
            "availableForSale" => variant["inventoryQuantity"] > 0,
            "quantityAvailable" => variant["inventoryQuantity"],
            "requiresShipping" => true,
            "sku" => variant["sku"],
            "selectedOptions" => variant["selectedOptions"],
            "price" => money(state.context_price),
            "compareAtPrice" => nil,
            "image" => variant["image"],
            "sellingPlanAllocations" => %{
              "nodes" => [
                %{
                  "sellingPlan" => %{"id" => "gid://shopify/SellingPlan/6001"},
                  "checkoutChargeAmount" => money(state.context_price),
                  "remainingBalanceChargeAmount" => money("0.00"),
                  "priceAdjustments" => []
                }
              ]
            }
          }
        ],
        "pageInfo" => page_info()
      }
    }
  end
end
