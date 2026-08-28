defmodule BrandoShopify.Components.Catalog do
  @moduledoc """
  Storefront components for the synced catalogue.

  Every component works with no slots at all, and every part of it can be
  replaced without giving up the rest. Slots receive **presented** data — prices
  already formatted, images flattened, availability resolved — so overriding the
  markup does not mean re-deriving what the default renderer had.

      import BrandoShopify.Components.Catalog

      <.product_grid products={@products} href={&~p"/shop/\#{&1.handle}"} />

  ## Class hooks

  Components emit stable `brando-shop__*` class names for styling, and pass any
  `class` you give them through alongside. Anything else you set — `data-*`,
  `id`, `phx-*` — lands on the outer element.

  ## Routes

  The package cannot know your URL structure, so links come from you. `href`
  takes either a string or a one-argument function receiving the product or
  collection. Without it, cards render as plain articles rather than links.

  ## Prices

  Formatting is currency-aware by default and overridable per call with `format`,
  or once for the application through `:money_formatter`. See
  `BrandoShopify.Catalog.Present.format_money/3`.
  """

  use Phoenix.Component

  alias BrandoShopify.Catalog.Present

  @doc """
  A grid of products.

  ## Examples

      <.product_grid products={@products} href={&"/shop/\#{&1.handle}"} />

      <.product_grid products={@products}>
        <:card :let={product}><MyCard.render product={product} /></:card>
        <:empty>Nothing here yet.</:empty>
      </.product_grid>

  The `:card` slot receives the raw `%Product{}` rather than presented data: you
  are replacing the card wholesale, and will usually hand it to your own
  component or to `product_card/1`, both of which present it themselves.
  """
  attr(:products, :list, required: true)
  attr(:href, :any, default: nil, doc: "string, or a function of the product")
  attr(:format, :any, default: nil, doc: "money formatter, see the module doc")
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  slot(:card, doc: "replaces the whole card; receives the %Product{}")
  slot(:empty, doc: "shown instead of the grid when there are no products")

  def product_grid(assigns) do
    ~H"""
    <div class={["brando-shop__grid", @class]} {@rest}>
      <%= if @products == [] do %>
        {render_slot(@empty)}
      <% else %>
        <%= for product <- @products do %>
          <%= if @card != [] do %>
            {render_slot(@card, product)}
          <% else %>
            <.product_card product={product} href={@href} format={@format} />
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  @doc """
  One product, as it appears in a listing.

  Slots receive the presented product:

      %{product: %Product{}, href: nil | String.t(), image: nil | map(),
        price: map(), sold_out?: boolean(), on_sale?: boolean(),
        option_groups: list()}

  ## Examples

      <.product_card product={@product} href={&"/shop/\#{&1.handle}"}>
        <:badge :let={p}><span :if={p.sold_out?}>Sold out</span></:badge>
      </.product_card>
  """
  attr(:product, :map, required: true)
  attr(:href, :any, default: nil)
  attr(:format, :any, default: nil)
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  slot(:media, doc: "replaces the image; receives the presented product")
  slot(:badge, doc: "rendered over the image; receives the presented product")
  slot(:info, doc: "replaces the title and price row")
  slot(:footer, doc: "rendered after everything else")

  def product_card(assigns) do
    assigns = assign(assigns, :presented, present(assigns.product, assigns.href, assigns.format))

    ~H"""
    <.maybe_link href={@presented.href} class={["brando-shop__card", @class]} {@rest}>
      <div class="brando-shop__card-media">
        <%= if @media != [] do %>
          {render_slot(@media, @presented)}
        <% else %>
          <.product_image product={@product} />
        <% end %>
        <div :if={@badge != []} class="brando-shop__card-badge">
          {render_slot(@badge, @presented)}
        </div>
      </div>

      <%= if @info != [] do %>
        {render_slot(@info, @presented)}
      <% else %>
        <div class="brando-shop__card-info">
          <h2 class="brando-shop__card-title">{@product.title}</h2>
          <div class="brando-shop__card-price">{@presented.price.formatted}</div>
        </div>
      <% end %>

      {render_slot(@footer, @presented)}
    </.maybe_link>
    """
  end

  @doc """
  A product image, with an honest empty state.

  Images stay on Shopify's CDN — the sync stores URLs, and re-hosting them would
  mean the CMS owning assets the merchant maintains in Shopify.

  The `:empty` slot is what a product with no photography shows. Leaving it out
  gives an empty box rather than a broken image icon, which is the right default
  for a catalogue still being filled.
  """
  attr(:product, :map, default: nil)
  attr(:image, :map, default: nil, doc: "overrides the product's featured image")
  attr(:alt, :string, default: nil)
  attr(:loading, :string, default: "lazy", values: ~w(lazy eager))
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  slot(:empty)

  def product_image(assigns) do
    image = assigns.image || (assigns.product && Present.featured_image(assigns.product))
    assigns = assign(assigns, :resolved, image)

    ~H"""
    <div
      class={["brando-shop__image", !@resolved && "brando-shop__image--empty", @class]}
      {@rest}
    >
      <img
        :if={@resolved}
        src={@resolved.url}
        alt={@alt || @resolved.alt || (@product && @product.title)}
        width={@resolved.width}
        height={@resolved.height}
        loading={@loading}
      />
      <%= if !@resolved do %>
        {render_slot(@empty)}
      <% end %>
    </div>
    """
  end

  @doc """
  A formatted price.

  Pass either a product, for its range, or a variant, for one amount.

      <.price product={@product} />
      <.price variant={@variant} currency={@product.currency_code} />

  When a variant is marked down, its compare-at price renders alongside as
  `<s>`, which is what screen readers and search engines expect for a struck
  price.
  """
  attr(:product, :map, default: nil)
  attr(:variant, :map, default: nil)
  attr(:currency, :string, default: nil)
  attr(:format, :any, default: nil)
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  def price(assigns) do
    subject = assigns.variant || assigns.product
    opts = [format: assigns.format, currency: assigns.currency]

    assigns =
      assigns
      |> assign(:presented, subject && Present.price(subject, opts))
      |> assign(:compare_at, compare_at(assigns.variant, assigns.currency, assigns.format))

    ~H"""
    <span class={["brando-shop__price", @class]} {@rest}>
      <span class="brando-shop__price-amount">{@presented && @presented.formatted}</span>
      <s :if={@compare_at} class="brando-shop__price-compare">{@compare_at}</s>
    </span>
    """
  end

  @doc """
  The option controls a buyer picks a variant with.

  Renders one group per product option — Size, Colour — and, alongside them, the
  full variant table as JSON. A selection is a *combination* of values, and
  resolving one to a variant can only happen in the browser, so this is the table
  it resolves against:

      [{"id": "gid://…", "options": {"Size": "M"}, "available": true, "price": "949.00"}]

  Read it with `JSON.parse(el.dataset.variants)`.

  It rides on an attribute rather than in a `<script type="application/json">`
  because HEEx does not interpolate inside script tags — it treats their content
  as raw text, so the expression would reach the page verbatim.

  ## Availability

  `available?` on a value means it appears in at least one purchasable variant —
  not that it is purchasable given the other selections. That depends on the
  combination, and the server does not know it.

  ## Examples

      <.variant_picker product={@product}>
        <:option :let={group}>
          <fieldset>
            <legend>{group.name}</legend>
            <button :for={v <- group.values} disabled={!v.available?}>{v.value}</button>
          </fieldset>
        </:option>
      </.variant_picker>
  """
  attr(:product, :map, required: true)
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  slot(:option, doc: "replaces one option group; receives %{name:, values:}")

  def variant_picker(assigns) do
    assigns =
      assigns
      |> assign(:groups, Present.option_groups(assigns.product))
      |> assign(:matrix, Jason.encode!(Present.variant_matrix(assigns.product)))

    ~H"""
    <div class={["brando-shop__variants", @class]} data-variants={@matrix} {@rest}>
      <%= for group <- @groups do %>
        <%= if @option != [] do %>
          {render_slot(@option, group)}
        <% else %>
          <fieldset class="brando-shop__option">
            <legend class="brando-shop__option-name">{group.name}</legend>
            <div class="brando-shop__option-values">
              <button
                :for={value <- group.values}
                type="button"
                class={[
                  "brando-shop__option-value",
                  !value.available? && "brando-shop__option-value--unavailable"
                ]}
                disabled={!value.available?}
                data-option={group.name}
                data-value={value.value}
                data-variant-id={value.variant && value.variant.shopify_id}
              >
                {value.value}
              </button>
            </div>
          </fieldset>
        <% end %>
      <% end %>

    </div>
    """
  end

  # A card is a link when it has somewhere to go, and an article when it does not.
  # Wrapping a non-link in an <a href> would put an empty target in the tab order.
  attr(:href, :string, default: nil)
  attr(:class, :any, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  defp maybe_link(%{href: nil} = assigns) do
    ~H"""
    <article class={@class} {@rest}>{render_slot(@inner_block)}</article>
    """
  end

  defp maybe_link(assigns) do
    ~H"""
    <a href={@href} class={@class} {@rest}>{render_slot(@inner_block)}</a>
    """
  end

  defp present(product, href, format) do
    %{
      product: product,
      href: resolve_href(href, product),
      image: Present.featured_image(product),
      price: Present.price(product, format: format),
      sold_out?: Present.sold_out?(product),
      on_sale?: false,
      option_groups: Present.option_groups(product)
    }
  end

  defp compare_at(nil, _currency, _format), do: nil

  defp compare_at(variant, currency, format) do
    if Present.on_sale?(variant) do
      Present.format_money(variant.compare_at_price, currency, format: format)
    end
  end

  defp resolve_href(nil, _subject), do: nil
  defp resolve_href(href, _subject) when is_binary(href), do: href
  defp resolve_href(href, subject) when is_function(href, 1), do: href.(subject)
end
