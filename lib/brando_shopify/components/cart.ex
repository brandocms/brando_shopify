defmodule BrandoShopify.Components.Cart do
  @moduledoc """
  The cart drawer, as HEEx.

  Cart state lives in the browser and the markup is rendered here, on the server.
  `BrandoShopify.Plug.Cart` renders this component when a request asks for
  `text/html`, and `<brando-shopify-cart>` swaps the result in. So the whole
  drawer is a template you can read, override and style like any other — no DOM
  built in JavaScript, no binding convention to learn.

      import BrandoShopify.Components.Cart

      <.cart cart={@cart} labels={BrandoShopify.Cart.Labels.all()} />

  ## Actions

  Buttons carry `data-cart-action` and the element delegates from its root, so
  swapped-in markup needs no rebinding. Keep the attributes if you replace a
  slot, or wire your own with `element.update/remove/checkout/close`.

  | Attribute | Does |
  |---|---|
  | `data-cart-action="close"` | closes the drawer |
  | `data-cart-action="remove"` + `data-line-id` | removes a line |
  | `data-cart-action="quantity"` + `data-line-id` + `data-quantity` | sets a quantity |
  | `data-cart-action="checkout"` | fetches a fresh checkout URL and navigates |

  ## Slots

  All of them receive presented data from `BrandoShopify.Cart.Present` — prices
  formatted, images flattened, Shopify's `"Default Title"` placeholder already
  removed.
  """

  use Phoenix.Component

  alias BrandoShopify.Cart.Present

  @doc """
  The whole drawer.

  ## Examples

      <.cart cart={@cart} />

      <.cart cart={@cart}>
        <:line :let={line}>
          <div class="my-line">{line.title} × {line.quantity} — {line.total.formatted}</div>
        </:line>
        <:empty>Ingenting her ennå.</:empty>
      </.cart>

  `total.estimated?` says whether Shopify considers the figure final. It usually
  does not — shipping is settled at checkout — so the default footer calls it a
  subtotal and says where the rest is added. Calling it a total is a small lie
  the buyer finds out about one screen later.
  """
  attr(:cart, :map, default: nil, doc: "sanitized cart from Cart.public_view/1")
  attr(:labels, :map, default: %{}, doc: "from BrandoShopify.Cart.Labels.all/0")
  attr(:format, :any, default: nil, doc: "money formatter")
  attr(:loading, :boolean, default: false)
  attr(:error, :string, default: nil)
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  slot(:header, doc: "receives the presented cart")
  slot(:line, doc: "receives one presented line")
  slot(:empty)
  slot(:footer, doc: "receives the presented cart")

  def cart(assigns) do
    assigns =
      assigns
      |> assign(:presented, Present.cart(assigns.cart, format: assigns.format))
      |> assign_new(:label, fn -> &label(assigns.labels, &1, &2) end)

    ~H"""
    <div class={["brando-cart__panel", @class]} part="panel" {@rest}>
      <%= if @header != [] do %>
        {render_slot(@header, @presented)}
      <% else %>
        <header class="brando-cart__header" part="header">
          <h2 class="brando-cart__title">{@label.(:title, "Your cart")}</h2>
          <button
            type="button"
            class="brando-cart__close"
            part="close"
            data-cart-action="close"
            aria-label={@label.(:close, "Close cart")}
          >
            ×
          </button>
        </header>
      <% end %>

      <p :if={@error} class="brando-cart__error" part="error" role="alert">{@error}</p>

      <%= if @presented.empty? do %>
        <p class="brando-cart__empty" part="empty">
          <%= if @empty != [] do %>
            {render_slot(@empty)}
          <% else %>
            {if @loading,
              do: @label.(:loading, "Loading…"),
              else: @label.(:empty, "Your cart is empty.")}
          <% end %>
        </p>
      <% else %>
        <ul class="brando-cart__lines" part="lines">
          <li :for={line <- @presented.lines} class="brando-cart__line" part="line">
            <%= if @line != [] do %>
              {render_slot(@line, line)}
            <% else %>
              <.cart_line line={line} labels={@labels} />
            <% end %>
          </li>
        </ul>

        <%= if @footer != [] do %>
          {render_slot(@footer, @presented)}
        <% else %>
          <footer class="brando-cart__footer" part="footer">
            <div :if={@presented.discount} class="brando-cart__discount">
              <span>{@label.(:discount, "Discount")}</span>
              <span>−{@presented.discount.formatted}</span>
            </div>

            <div class="brando-cart__total">
              <%!-- Named for what it is. Shopify flags the figure as an estimate
                    whenever shipping is still unsettled, which is nearly always
                    before checkout. --%>
              <span>
                {if @presented.total && @presented.total.estimated?,
                  do: @label.(:subtotal, "Subtotal"),
                  else: @label.(:total, "Total")}
              </span>
              <data
                class="brando-cart__total-amount"
                value={@presented.total && Decimal.to_string(@presented.total.amount, :normal)}
              >
                {@presented.total && @presented.total.formatted}
              </data>
            </div>

            <p :if={@presented.total && @presented.total.estimated?} class="brando-cart__note">
              {@label.(:shipping_at_checkout, "Shipping is calculated at checkout.")}
            </p>

            <button
              type="button"
              class="brando-cart__checkout"
              part="checkout"
              data-cart-action="checkout"
              disabled={@loading}
            >
              {if @loading,
                do: @label.(:updating, "Updating…"),
                else: @label.(:checkout, "Checkout")}
            </button>
          </footer>
        <% end %>
      <% end %>
    </div>
    """
  end

  @doc """
  One line: image, what it is, how many, what it costs.

  Split out so a custom `:line` slot can still reuse it, or replace only part of
  it.
  """
  attr(:line, :map, required: true)
  attr(:labels, :map, default: %{})
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  slot(:media)
  slot(:details)
  slot(:quantity)

  def cart_line(assigns) do
    assigns = assign_new(assigns, :label, fn -> &label(assigns.labels, &1, &2) end)

    ~H"""
    <div class={["brando-cart__line-inner", @class]} {@rest}>
      <%= if @media != [] do %>
        {render_slot(@media, @line)}
      <% else %>
        <div class="brando-cart__image">
          <img
            :if={@line.image}
            src={@line.image.url}
            alt={@line.image.alt || @line.title}
            width={@line.image.width}
            height={@line.image.height}
            loading="lazy"
          />
        </div>
      <% end %>

      <div class="brando-cart__details">
        <%= if @details != [] do %>
          {render_slot(@details, @line)}
        <% else %>
          <div class="brando-cart__product">{@line.title}</div>
          <div :if={@line.variant_title} class="brando-cart__variant">{@line.variant_title}</div>
          <div :if={!@line.available?} class="brando-cart__unavailable">
            {@label.(:unavailable, "No longer available")}
          </div>
        <% end %>

        <%= if @quantity != [] do %>
          {render_slot(@quantity, @line)}
        <% else %>
          <div class="brando-cart__quantity" part="quantity">
            <button
              type="button"
              data-cart-action="quantity"
              data-line-id={@line.id}
              data-quantity={@line.quantity - 1}
              aria-label={@label.(:decrease, "Decrease quantity")}
            >
              −
            </button>
            <span class="brando-cart__quantity-value">{@line.quantity}</span>
            <button
              type="button"
              data-cart-action="quantity"
              data-line-id={@line.id}
              data-quantity={@line.quantity + 1}
              aria-label={@label.(:increase, "Increase quantity")}
            >
              +
            </button>
            <button
              type="button"
              class="brando-cart__remove"
              data-cart-action="remove"
              data-line-id={@line.id}
              aria-label={@label.(:removeItem, "Remove item")}
            >
              {@label.(:remove, "Remove")}
            </button>
          </div>
        <% end %>
      </div>

      <div class="brando-cart__line-total">
        {@line.total && @line.total.formatted}
        <s :if={@line.on_sale?} class="brando-cart__line-compare">
          {@line.compare_at && @line.compare_at.formatted}
        </s>
      </div>
    </div>
    """
  end

  # Labels come as a plain map so a host can pass Gettext output straight in
  # without this module depending on Gettext.
  defp label(labels, key, fallback) do
    Map.get(labels, key) || Map.get(labels, to_string(key)) || fallback
  end
end
