defmodule BrandoShopify.Components.CartTest do
  use ExUnit.Case, async: true

  import BrandoShopify.Components.Cart
  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias BrandoShopify.Cart.Present

  defp money(amount, currency \\ "NOK"), do: %{"amount" => amount, "currencyCode" => currency}

  defp line(opts \\ []) do
    %{
      "id" => opts[:id] || "gid://shopify/CartLine/1",
      "quantity" => opts[:quantity] || 2,
      "discountAllocations" => opts[:discounts] || [],
      "cost" => %{
        "totalAmount" => money(opts[:total] || "1898.0"),
        "amountPerQuantity" => money(opts[:unit] || "949.0"),
        "compareAtAmountPerQuantity" => opts[:compare_at] && money(opts[:compare_at])
      },
      "merchandise" => %{
        "title" => Keyword.get(opts, :variant_title, "M"),
        "availableForSale" => Keyword.get(opts, :available, true),
        "quantityAvailable" => 42,
        "sku" => "samarbeidsgenser-M",
        "selectedOptions" => [%{"name" => "Størrelse", "value" => "M"}],
        "image" => opts[:image],
        "product" => %{"title" => "Samarbeidsgenser", "handle" => "samarbeidsgenser"}
      }
    }
  end

  defp a_cart(opts \\ []) do
    lines = Keyword.get(opts, :lines, [line()])

    %{
      "totalQuantity" => Enum.sum(Enum.map(lines, & &1["quantity"])),
      "lines" => %{"nodes" => lines},
      "discountCodes" => opts[:codes] || [],
      "note" => nil,
      "cost" => %{
        "totalAmount" => money(opts[:total] || "1898.0"),
        "totalAmountEstimated" => Keyword.get(opts, :estimated, true),
        "subtotalAmount" => money(opts[:total] || "1898.0"),
        "subtotalAmountEstimated" => Keyword.get(opts, :estimated, true)
      }
    }
  end

  defp text(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  describe "Present.cart/2" do
    test "flattens what a template needs" do
      p = Present.cart(a_cart())

      refute p.empty?
      assert p.count == 2
      assert p.total.formatted == "1 898 kr"
      assert p.total.estimated?
      assert [%{title: "Samarbeidsgenser", quantity: 2}] = p.lines
    end

    test "a nil cart is empty rather than a crash" do
      p = Present.cart(nil)

      assert p.empty?
      assert p.count == 0
      assert p.lines == []
    end

    test "drops Shopify's Default Title placeholder" do
      # A line reading "Default Title" under the product name is noise.
      p = Present.cart(a_cart(lines: [line(variant_title: "Default Title")]))

      assert hd(p.lines).variant_title == nil
    end

    test "keeps a real variant title" do
      assert hd(Present.cart(a_cart()).lines).variant_title == "M"
    end

    test "sums discounts Shopify already applied" do
      allocations = [%{"discountedAmount" => money("100.0")}]
      p = Present.cart(a_cart(lines: [line(discounts: allocations)]))

      assert p.discount.formatted == "100 kr"
    end

    test "no discount key when nothing was discounted" do
      assert Present.cart(a_cart()).discount == nil
    end

    test "lists only applicable discount codes" do
      codes = [
        %{"code" => "GOOD", "applicable" => true},
        %{"code" => "EXPIRED", "applicable" => false}
      ]

      assert Present.cart(a_cart(codes: codes)).discount_codes == ["GOOD"]
    end

    test "marks a line down against its compare-at price" do
      p = Present.cart(a_cart(lines: [line(unit: "449.0", compare_at: "599.0")]))

      assert hd(p.lines).on_sale?
      assert hd(p.lines).compare_at.formatted == "599 kr"
    end
  end

  describe "cart/1" do
    test "renders lines, quantity and total" do
      html = render_component(&cart/1, cart: a_cart())

      assert text(html) =~ "Samarbeidsgenser"
      assert text(html) =~ "1 898 kr"
      assert html =~ "brando-cart__panel"
    end

    test "calls an estimated figure a subtotal, and says why" do
      # Shopify flags the amount as an estimate until shipping is settled. Naming
      # it "Total" is a small lie the buyer finds out about one screen later.
      html = render_component(&cart/1, cart: a_cart(estimated: true))

      assert text(html) =~ "Subtotal"
      assert text(html) =~ "Shipping is calculated at checkout"
      refute text(html) =~ "Total 1 898"
    end

    test "calls a settled figure a total" do
      html = render_component(&cart/1, cart: a_cart(estimated: false))

      assert text(html) =~ "Total"
      refute text(html) =~ "Shipping is calculated at checkout"
    end

    test "every control carries a delegated action" do
      # The markup is replaced on every change, so per-node listeners would go
      # with it. The element delegates from its root instead.
      html = render_component(&cart/1, cart: a_cart())

      for action <- ~w(close checkout remove quantity) do
        assert html =~ ~s(data-cart-action="#{action}")
      end
    end

    test "quantity buttons carry the line and the target quantity" do
      html = render_component(&cart/1, cart: a_cart(lines: [line(quantity: 3)]))

      assert html =~ ~s(data-quantity="2")
      assert html =~ ~s(data-quantity="4")
      assert html =~ ~s(data-line-id="gid://shopify/CartLine/1")
    end

    test "an empty cart says so instead of rendering a footer" do
      html = render_component(&cart/1, cart: a_cart(lines: []))

      assert text(html) =~ "Your cart is empty"
      refute html =~ ~s(data-cart-action="checkout")
    end

    test "labels override every default string" do
      html =
        render_component(&cart/1,
          cart: a_cart(),
          labels: %{"title" => "Handlekurv", "checkout" => "Til kassen", "subtotal" => "Delsum"}
        )

      assert text(html) =~ "Handlekurv"
      assert text(html) =~ "Til kassen"
      assert text(html) =~ "Delsum"
    end

    test "labels work as atoms too, since a host may build them either way" do
      html = render_component(&cart/1, cart: a_cart(), labels: %{title: "Handlekurv"})

      assert text(html) =~ "Handlekurv"
    end

    test "shows an error without losing the cart" do
      html = render_component(&cart/1, cart: a_cart(), error: "Noe gikk galt")

      assert text(html) =~ "Noe gikk galt"
      assert text(html) =~ "Samarbeidsgenser"
    end

    test "marks a line that can no longer be bought" do
      html = render_component(&cart/1, cart: a_cart(lines: [line(available: false)]))

      assert text(html) =~ "No longer available"
    end
  end

  describe "cart/1 slots" do
    test ":line replaces one line and receives presented data" do
      assigns = %{cart: a_cart()}

      html =
        rendered_to_string(~H"""
        <.cart cart={@cart}>
          <:line :let={line}>{line.title} × {line.quantity} = {line.total.formatted}</:line>
        </.cart>
        """)

      assert text(html) =~ "Samarbeidsgenser × 2 = 1 898 kr"
      refute html =~ "brando-cart__quantity"
    end

    test ":footer replaces the total and checkout" do
      assigns = %{cart: a_cart()}

      html =
        rendered_to_string(~H"""
        <.cart cart={@cart}>
          <:footer :let={c}>Sum for {c.count}: {c.total.formatted}</:footer>
        </.cart>
        """)

      assert text(html) =~ "Sum for 2: 1 898 kr"
      refute html =~ ~s(data-cart-action="checkout")
    end

    test ":header replaces the title and close button" do
      assigns = %{cart: a_cart()}

      html =
        rendered_to_string(~H"""
        <.cart cart={@cart}>
          <:header :let={c}><h1>Kurv ({c.count})</h1></:header>
        </.cart>
        """)

      assert text(html) =~ "Kurv (2)"
      refute html =~ ~s(data-cart-action="close")
    end

    test ":empty replaces the empty message" do
      assigns = %{cart: a_cart(lines: [])}

      html =
        rendered_to_string(~H"""
        <.cart cart={@cart}>
          <:empty>Ingenting her ennå</:empty>
        </.cart>
        """)

      assert text(html) =~ "Ingenting her ennå"
    end
  end

  describe "cart_line/1 slots" do
    test ":quantity replaces the stepper but keeps the rest" do
      assigns = %{line: Present.line(line())}

      html =
        rendered_to_string(~H"""
        <.cart_line line={@line}>
          <:quantity :let={l}><input type="number" value={l.quantity} /></:quantity>
        </.cart_line>
        """)

      assert html =~ ~s(type="number")
      assert text(html) =~ "Samarbeidsgenser"
      refute html =~ ~s(data-cart-action="quantity")
    end
  end
end
