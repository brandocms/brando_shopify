defmodule BrandoShopify.Catalog.PresentTest do
  use ExUnit.Case, async: true

  alias BrandoShopify.Catalog.Present
  alias BrandoShopify.Catalog.Product
  alias BrandoShopify.Catalog.Variant

  defp variant(opts) do
    options =
      opts
      |> Keyword.get(:options, [])
      |> Enum.map(fn {name, value} -> %{"name" => name, "value" => value} end)

    %Variant{
      shopify_id: opts[:id] || "gid://shopify/ProductVariant/#{System.unique_integer([:positive])}",
      title: opts[:title],
      sku: opts[:sku],
      price: opts[:price] && Decimal.new(opts[:price]),
      compare_at_price: opts[:compare_at] && Decimal.new(opts[:compare_at]),
      available_for_sale: Keyword.get(opts, :available, true),
      selected_options: options
    }
  end

  defp product(opts) do
    %Product{
      handle: "tee",
      title: "Tee",
      currency_code: opts[:currency] || "NOK",
      min_price: opts[:min] && Decimal.new(opts[:min]),
      max_price: opts[:max] && Decimal.new(opts[:max]),
      options: opts[:options] || [],
      variants: opts[:variants] || [],
      featured_media: opts[:media]
    }
  end

  describe "price/2" do
    test "one amount when every variant costs the same" do
      p = Present.price(product(min: "949.00", max: "949.00"))

      refute p.range?
      assert p.formatted == "949 kr"
    end

    test "reads as a floor when variants differ" do
      p = Present.price(product(min: "449.00", max: "949.00"))

      assert p.range?
      assert p.formatted == "fra 449 kr"
    end

    test "groups thousands with a space, the Norwegian way" do
      assert Present.price(product(min: "1898.00", max: "1898.00")).formatted == "1 898 kr"
    end

    test "keeps ører when there are any, with a comma" do
      assert Present.price(product(min: "949.50", max: "949.50")).formatted == "949,50 kr"
    end

    test "knows other currencies" do
      assert Present.price(product(min: "20.00", max: "20.00", currency: "EUR")).formatted ==
               "20 €"
    end

    test "an unknown currency prints its code rather than guessing a symbol" do
      assert Present.price(product(min: "20.00", max: "20.00", currency: "XYZ")).formatted ==
               "20 XYZ"
    end

    test "a per-call formatter wins over the default" do
      p = Present.price(product(min: "949.00", max: "949.00"), format: fn a, c -> "#{a} #{c}" end)

      assert p.formatted == "949.00 NOK"
    end
  end

  describe "option_groups/1 — single option" do
    setup do
      variants = [
        variant(title: "S", options: [{"Størrelse", "S"}]),
        variant(title: "M", options: [{"Størrelse", "M"}], available: false)
      ]

      options = [
        %{"name" => "Størrelse", "optionValues" => [%{"name" => "S"}, %{"name" => "M"}]}
      ]

      %{product: product(options: options, variants: variants)}
    end

    test "maps each value to its variant", %{product: product} do
      [group] = Present.option_groups(product)

      assert group.name == "Størrelse"
      assert [s, m] = group.values
      assert s.value == "S"
      assert s.variant.title == "S"
      assert m.variant.title == "M"
    end

    test "marks a sold-out value unavailable rather than dropping it", %{product: product} do
      [group] = Present.option_groups(product)
      [s, m] = group.values

      assert s.available?
      refute m.available?
    end
  end

  describe "option_groups/1 — several options" do
    setup do
      # Size x Colour, with one combination missing entirely and one sold out.
      variants = [
        variant(options: [{"Størrelse", "S"}, {"Farge", "Sort"}]),
        variant(options: [{"Størrelse", "M"}, {"Farge", "Sort"}], available: false),
        variant(options: [{"Størrelse", "M"}, {"Farge", "Hvit"}])
      ]

      options = [
        %{"name" => "Størrelse", "optionValues" => [%{"name" => "S"}, %{"name" => "M"}]},
        %{"name" => "Farge", "optionValues" => [%{"name" => "Sort"}, %{"name" => "Hvit"}]}
      ]

      %{product: product(options: options, variants: variants)}
    end

    test "returns one group per option", %{product: product} do
      assert [%{name: "Størrelse"}, %{name: "Farge"}] = Present.option_groups(product)
    end

    test "does not pretend a value is a variant", %{product: product} do
      # This is the heart of it: with two options, a value is not a variant, and
      # claiming otherwise would send the wrong id to the cart.
      for group <- Present.option_groups(product),
          value <- group.values do
        assert value.variant == nil
      end
    end

    test "a value is available when any purchasable variant carries it", %{product: product} do
      [sizes, colours] = Present.option_groups(product)

      # M is sold out in Sort but in stock in Hvit, so M itself is available.
      assert Enum.all?(sizes.values, & &1.available?)
      # Sort exists only in S (available) and M (sold out), so Sort is available.
      assert Enum.all?(colours.values, & &1.available?)
    end

    test "a value with no purchasable variant at all is unavailable" do
      variants = [variant(options: [{"Farge", "Rød"}], available: false)]
      options = [%{"name" => "Farge", "optionValues" => [%{"name" => "Rød"}]}]

      [group] = Present.option_groups(product(options: options, variants: variants))

      refute hd(group.values).available?
    end

    test "returns [] when variants are not preloaded" do
      assert Present.option_groups(%Product{variants: %Ecto.Association.NotLoaded{}}) == []
    end
  end

  describe "variant_matrix/1" do
    test "flattens what the client needs to resolve a combination" do
      variants = [
        variant(id: "gid://v/1", sku: "tee-s", price: "449.00",
                options: [{"Størrelse", "S"}, {"Farge", "Sort"}])
      ]

      assert [row] = Present.variant_matrix(product(variants: variants))
      assert row.id == "gid://v/1"
      assert row.available
      assert row.price == "449.00"
      assert row.currency == "NOK"
      assert row.options == %{"Størrelse" => "S", "Farge" => "Sort"}
    end

    test "survives JSON encoding, which is how it reaches the browser" do
      variants = [variant(price: "449.00", options: [{"Størrelse", "S"}])]

      json = product(variants: variants) |> Present.variant_matrix() |> Jason.encode!()

      assert [%{"options" => %{"Størrelse" => "S"}}] = Jason.decode!(json)
    end
  end

  describe "sold_out?/1" do
    test "true only when nothing can be bought" do
      assert Present.sold_out?(product(variants: [variant(available: false)]))
      refute Present.sold_out?(product(variants: [variant(available: false), variant([])]))
    end

    test "a product with no variants is not sold out — it is unconfigured" do
      refute Present.sold_out?(product(variants: []))
    end
  end

  describe "on_sale?/1" do
    test "true when compare-at is above the price" do
      assert Present.on_sale?(variant(price: "449.00", compare_at: "599.00"))
    end

    test "false when compare-at merely equals the price" do
      refute Present.on_sale?(variant(price: "449.00", compare_at: "449.00"))
    end

    test "false without a compare-at price" do
      refute Present.on_sale?(variant(price: "449.00"))
    end
  end

  describe "featured_image/1" do
    test "reads the image nested under preview" do
      media = %{"preview" => %{"image" => %{"url" => "https://cdn/x.jpg", "altText" => "Tee"}}}

      assert %{url: "https://cdn/x.jpg", alt: "Tee"} = Present.featured_image(product(media: media))
    end

    test "reads a direct image too, since media types nest differently" do
      media = %{"image" => %{"url" => "https://cdn/y.jpg"}, "alt" => "Fallback"}

      assert %{url: "https://cdn/y.jpg", alt: "Fallback"} =
               Present.featured_image(product(media: media))
    end

    test "nil when there is no photography" do
      assert Present.featured_image(product([])) == nil
    end
  end
end
