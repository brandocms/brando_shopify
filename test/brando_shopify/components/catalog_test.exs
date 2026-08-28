defmodule BrandoShopify.Components.CatalogTest do
  @moduledoc """
  The components are a public API, so these lock down the contract a consumer
  actually depends on: that every part is replaceable, that slots receive
  presented data rather than raw JSON, and that the defaults work with nothing
  configured.
  """

  use ExUnit.Case, async: true

  import BrandoShopify.Components.Catalog
  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias BrandoShopify.Catalog.Product
  alias BrandoShopify.Catalog.Variant

  defp variant(opts) do
    %Variant{
      shopify_id: opts[:id] || "gid://shopify/ProductVariant/1",
      title: opts[:title] || "M",
      price: Decimal.new(opts[:price] || "949.00"),
      compare_at_price: opts[:compare_at] && Decimal.new(opts[:compare_at]),
      available_for_sale: Keyword.get(opts, :available, true),
      selected_options: [%{"name" => "Størrelse", "value" => opts[:title] || "M"}]
    }
  end

  defp product(opts \\ []) do
    %Product{
      handle: opts[:handle] || "samarbeidsgenser",
      title: opts[:title] || "Samarbeidsgenser",
      currency_code: "NOK",
      min_price: Decimal.new(opts[:min] || "949.00"),
      max_price: Decimal.new(opts[:max] || "949.00"),
      options: opts[:options] || [%{"name" => "Størrelse", "optionValues" => [%{"name" => "M"}]}],
      variants: opts[:variants] || [variant([])],
      featured_media: opts[:media]
    }
  end

  describe "product_grid/1" do
    test "renders cards with nothing configured" do
      html = render_component(&product_grid/1, products: [product()])

      assert html =~ "brando-shop__grid"
      assert html =~ "Samarbeidsgenser"
      assert html =~ "949 kr"
    end

    test "cards are plain articles without an href, not empty links" do
      html = render_component(&product_grid/1, products: [product()])

      assert html =~ "<article"
      refute html =~ "<a href"
    end

    test "href as a function builds one link per product" do
      html =
        render_component(&product_grid/1,
          products: [product(handle: "a"), product(handle: "b")],
          href: &"/shop/#{&1.handle}"
        )

      assert html =~ ~s(href="/shop/a")
      assert html =~ ~s(href="/shop/b")
    end

    test "href as a string is used as-is" do
      html = render_component(&product_grid/1, products: [product()], href: "/shop")

      assert html =~ ~s(href="/shop")
    end

    test "the :card slot replaces the card and receives the product" do
      assigns = %{products: [product(title: "Hoodie")]}

      html =
        rendered_to_string(~H"""
        <.product_grid products={@products}>
          <:card :let={product}><span class="mine">{product.title}</span></:card>
        </.product_grid>
        """)

      assert html =~ ~s(<span class="mine">Hoodie</span>)
      refute html =~ "brando-shop__card-title"
    end

    test "the :empty slot shows instead of an empty grid" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.product_grid products={[]}>
          <:empty>Ingenting her</:empty>
        </.product_grid>
        """)

      assert html =~ "Ingenting her"
    end

    test "passes class and arbitrary attributes through" do
      html =
        render_component(&product_grid/1,
          products: [],
          class: "my-grid",
          id: "shop",
          "data-testid": "grid"
        )

      assert html =~ "brando-shop__grid my-grid"
      assert html =~ ~s(id="shop")
      assert html =~ ~s(data-testid="grid")
    end
  end

  describe "product_card/1 slots" do
    test ":badge receives presented data, not the raw struct" do
      assigns = %{product: product(variants: [variant(available: false)])}

      html =
        rendered_to_string(~H"""
        <.product_card product={@product}>
          <:badge :let={p}><span :if={p.sold_out?}>Utsolgt</span></:badge>
        </.product_card>
        """)

      assert html =~ "Utsolgt"
    end

    test ":info replaces the title and price row" do
      assigns = %{product: product()}

      html =
        rendered_to_string(~H"""
        <.product_card product={@product}>
          <:info :let={p}>{p.price.formatted} for {p.product.title}</:info>
        </.product_card>
        """)

      assert html =~ "949 kr for Samarbeidsgenser"
      refute html =~ "brando-shop__card-info"
    end

    test ":media replaces the image" do
      assigns = %{product: product()}

      html =
        rendered_to_string(~H"""
        <.product_card product={@product}>
          <:media><div class="custom-media"></div></:media>
        </.product_card>
        """)

      assert html =~ "custom-media"
      refute html =~ "brando-shop__image"
    end

    test "presented href is available to slots" do
      assigns = %{product: product(handle: "tee")}

      html =
        rendered_to_string(~H"""
        <.product_card product={@product} href={&"/shop/#{&1.handle}"}>
          <:footer :let={p}>{p.href}</:footer>
        </.product_card>
        """)

      assert html =~ "/shop/tee"
    end
  end

  describe "product_image/1" do
    test "renders the featured image with its alt text" do
      media = %{"preview" => %{"image" => %{"url" => "https://cdn/x.jpg", "altText" => "Foran"}}}

      html = render_component(&product_image/1, product: product(media: media))

      assert html =~ ~s(src="https://cdn/x.jpg")
      assert html =~ ~s(alt="Foran")
    end

    test "falls back to the product title when the image has no alt" do
      media = %{"preview" => %{"image" => %{"url" => "https://cdn/x.jpg"}}}

      html = render_component(&product_image/1, product: product(media: media, title: "Genser"))

      assert html =~ ~s(alt="Genser")
    end

    test "marks the empty state rather than rendering a broken image" do
      html = render_component(&product_image/1, product: product())

      assert html =~ "brando-shop__image--empty"
      refute html =~ "<img"
    end

    test "the :empty slot fills the empty state" do
      assigns = %{product: product()}

      html =
        rendered_to_string(~H"""
        <.product_image product={@product}>
          <:empty>Foto kommer</:empty>
        </.product_image>
        """)

      assert html =~ "Foto kommer"
    end
  end

  describe "price/1" do
    test "renders a product range" do
      html = render_component(&price/1, product: product(min: "449.00", max: "949.00"))

      assert html =~ "fra 449 kr"
    end

    test "strikes the compare-at price when a variant is marked down" do
      html =
        render_component(&price/1,
          variant: variant(price: "449.00", compare_at: "599.00"),
          currency: "NOK"
        )

      assert html =~ "449 kr"
      assert html =~ "brando-shop__price-compare"
      assert html =~ "599 kr"
    end

    test "no strike-through when there is no markdown" do
      html = render_component(&price/1, variant: variant([]), currency: "NOK")

      refute html =~ "brando-shop__price-compare"
    end
  end

  describe "variant_picker/1" do
    test "renders one control per option value" do
      html = render_component(&variant_picker/1, product: product())

      assert html =~ "Størrelse"
      assert html =~ ~s(data-value="M")
    end

    test "disables values with no purchasable variant" do
      p = product(variants: [variant(available: false)])
      html = render_component(&variant_picker/1, product: p)

      assert html =~ "brando-shop__option-value--unavailable"
      assert html =~ "disabled"
    end

    test "emits the variant matrix the client resolves combinations against" do
      # Parsed, not string-matched. The earlier version of this test asserted on
      # substrings that also appear in the buttons, so it stayed green while the
      # matrix was rendering as literal template source.
      html = render_component(&variant_picker/1, product: product())

      assert [row] = extract_matrix(html)
      assert row["id"] == "gid://shopify/ProductVariant/1"
      assert row["options"] == %{"Størrelse" => "M"}
      assert row["available"]
      assert row["price"] == "949.00"
    end

    test "the matrix survives values that need HTML escaping" do
      p =
        product(
          options: [%{"name" => "Størrelse", "optionValues" => [%{"name" => ~s(10" & opp)}]}],
          variants: [variant(title: ~s(10" & opp))]
        )

      assert [row] = extract_matrix(render_component(&variant_picker/1, product: p))
      assert row["options"] == %{"Størrelse" => ~s(10" & opp)}
    end

    test "the :option slot replaces a group and receives its values" do
      assigns = %{product: product()}

      html =
        rendered_to_string(~H"""
        <.variant_picker product={@product}>
          <:option :let={group}>
            <select name={group.name}>
              <option :for={v <- group.values} disabled={!v.available?}>{v.value}</option>
            </select>
          </:option>
        </.variant_picker>
        """)

      assert html =~ "<select"
      refute html =~ "brando-shop__option-value"
      # The matrix is still emitted — a custom control needs it just as much.
      assert [_row] = extract_matrix(html)
    end
  end

  # The matrix reaches the browser as an attribute, so it comes back HTML-escaped.
  defp extract_matrix(html) do
    [_, encoded] = Regex.run(~r/data-variants="([^"]*)"/, html)

    encoded
    |> String.replace("&quot;", ~s("))
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&#39;", "'")
    |> Jason.decode!()
  end
end
