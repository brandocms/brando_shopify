const DEFAULT_ENDPOINT = "/shopify/cart";

/**
 * Accessible, progressively enhanced Shopify cart drawer.
 *
 * The element talks only to Brando's same-origin cart endpoint. Shopify's
 * secret-bearing cart ID remains in the encrypted server session.
 *
 * Events: `cart:change`, `cart:error`, `cart:open`, `cart:close`,
 * `cart:checkout`.
 */
/**
 * Every string the default renderer puts on screen.
 *
 * Override what you need — the rest fall back to these:
 *
 *   cart.labels = { title: "Handlekurv", checkout: "Til kassen" }
 *
 * A custom `renderer` bypasses these entirely and owns its own copy.
 */
export const DEFAULT_LABELS = {
  region: "Shopping cart",
  title: "Your cart",
  close: "Close cart",
  loading: "Loading…",
  empty: "Your cart is empty.",
  product: "Product",
  // Shopify's name for the single variant of a product with no options. Matched
  // to hide it, so it is a Shopify value rather than UI copy — translate the
  // others, leave this one alone.
  defaultVariant: "Default Title",
  decrease: "Decrease quantity",
  increase: "Increase quantity",
  remove: "Remove",
  removeItem: "Remove item",
  subtotal: "Subtotal",
  total: "Total",
  discount: "Discount",
  unavailable: "No longer available",
  shipping_at_checkout: "Shipping is calculated at checkout.",
  updating: "Updating…",
  checkout: "Checkout",
};

export class BrandoShopifyCart extends HTMLElement {
  static observedAttributes = ["open"];

  constructor() {
    super();
    this.cart = null;
    this.warnings = [];
    this.loading = false;
    this.error = null;
    this.renderer = null;
    this.html = null;
    this.pending = null;
    this.labels = { ...DEFAULT_LABELS };
    this.queue = Promise.resolve();
    this.abortController = null;
  }

  connectedCallback() {
    // Labels can arrive as a JSON attribute so the server can translate them.
    // Gettext lives in Elixir and this renderer lives in the browser, so the
    // attribute is the bridge: `BrandoShopify.Cart.labels/0` produces the map,
    // the host renders it, and anything absent falls back to English.
    const attr = this.getAttribute("labels");
    if (attr) {
      try {
        this.labels = { ...this.labels, ...JSON.parse(attr) };
      } catch (error) {
        console.warn("brando-shopify-cart: could not parse labels attribute", error);
      }
    }

    this.onAction = this.handleAction.bind(this);
    this.addEventListener("click", this.onAction);

    this.setAttribute("role", "region");
    this.setAttribute("aria-label", this.getAttribute("aria-label") || this.labels.region);
    this.hidden = !this.hasAttribute("open");
    this.render();

    if (!this.hasAttribute("manual")) this.refresh();
  }

  disconnectedCallback() {
    this.abortController?.abort();
    if (this.onAction) this.removeEventListener("click", this.onAction);
  }

  attributeChangedCallback(name) {
    if (name !== "open" || !this.isConnected) return;

    this.hidden = !this.hasAttribute("open");
    this.dispatchEvent(
      new CustomEvent(this.hasAttribute("open") ? "cart:open" : "cart:close", {
        bubbles: true,
      }),
    );
  }

  get endpoint() {
    return (this.getAttribute("endpoint") || DEFAULT_ENDPOINT).replace(/\/$/, "");
  }

  get count() {
    return this.cart?.totalQuantity || 0;
  }

  open() {
    this.setAttribute("open", "");
  }

  close() {
    this.removeAttribute("open");
  }

  toggle(force) {
    this.toggleAttribute("open", force);
  }

  refresh() {
    return this.enqueue(() => this.request("", { method: "GET" }));
  }

  /**
   * Draws a line before the server has confirmed it.
   *
   * A cart mutation is a Storefront round trip — measured at around 600ms
   * against a real store — and the drawer would otherwise open empty for all of
   * it. Shopify names this as the cost of rendering the cart server-side and
   * gives the same remedy: show what the page already knows, reconcile when the
   * response lands.
   *
   * `price` is passed in already formatted, taken from the page. Formatting it
   * here would put money logic back in the browser, which is what rendering on
   * the server was meant to avoid.
   */
  showPending(item) {
    if (this.hasAttribute("headless") || !item?.title) return;

    // Held in state, not just inserted: every render replaces innerHTML with
    // the server's markup, and the request starts with one. Without this the
    // row was created and destroyed in the same tick.
    this.pending = item;
    this.renderPending();
  }

  renderPending() {
    const { title, variant, price, image } = this.pending || {};
    if (!title) return;

    const row = document.createElement("div");
    row.className = "brando-cart__pending";
    row.setAttribute("data-cart-pending", "");
    // Announced, because the visual cue is off-screen for a screen reader.
    row.setAttribute("aria-live", "polite");

    if (image) {
      const img = document.createElement("img");
      img.src = image;
      img.alt = "";
      row.append(img);
    }

    const details = document.createElement("div");
    const name = document.createElement("div");
    name.className = "brando-cart__pending-title";
    name.textContent = title;
    details.append(name);

    if (variant) {
      const sub = document.createElement("div");
      sub.className = "brando-cart__pending-variant";
      sub.textContent = variant;
      details.append(sub);
    }

    row.append(details);

    if (price) {
      const amount = document.createElement("div");
      amount.className = "brando-cart__pending-price";
      amount.textContent = price;
      row.append(amount);
    }

    // Into the line list when there is one, so it reads as a line.
    const lines = this.querySelector(".brando-cart__lines");
    if (lines) {
      lines.prepend(row);
      return;
    }

    // An empty cart renders no line list — and that is the most common case for
    // a first add, so getting it wrong would miss the point. Put the row inside
    // the panel, under the header; prepending to the element itself would place
    // it above the drawer's own chrome.
    const panel = this.querySelector(".brando-cart__panel");
    if (!panel) {
      this.prepend(row);
      return;
    }

    const header = panel.querySelector(".brando-cart__header");
    if (header) header.after(row);
    else panel.prepend(row);
  }

  add(merchandiseId, quantity = 1, attributes = [], options = {}) {
    if (options.pending) {
      this.open();
      this.showPending(options.pending);
    }

    const line = { merchandiseId, quantity, attributes }
    if (options.sellingPlanId) line.sellingPlanId = options.sellingPlanId

    return this.enqueue(() =>
      this.request("/lines", {
        method: "POST",
        body: { lines: [line] },
      }),
    );
  }

  update(lineId, quantity, options = {}) {
    if (Number(quantity) <= 0) return this.remove(lineId);

    const line = { id: lineId, quantity: Number(quantity), ...options }

    return this.enqueue(() =>
      this.request("/lines", {
        method: "PATCH",
        body: { lines: [line] },
      }),
    );
  }

  remove(lineId) {
    return this.enqueue(() =>
      this.request("/lines", {
        method: "DELETE",
        body: { lineIds: [lineId] },
      }),
    );
  }

  discounts(codes) {
    return this.enqueue(() =>
      this.request("/discounts", {
        method: "PUT",
        body: { discountCodes: Array.isArray(codes) ? codes : [codes] },
      }),
    );
  }

  buyer(buyerIdentity) {
    return this.enqueue(() =>
      this.request("/buyer", {
        method: "PUT",
        body: { buyerIdentity },
      }),
    );
  }

  checkout() {
    return this.enqueue(async () => {
      const payload = await this.fetchJSON("/checkout", { method: "POST" });
      this.dispatchEvent(
        new CustomEvent("cart:checkout", { detail: payload, bubbles: true }),
      );
      if (payload.checkoutUrl) window.location.assign(payload.checkoutUrl);
      return payload;
    });
  }

  enqueue(operation) {
    this.queue = this.queue.then(operation, operation);
    return this.queue;
  }

  async request(path, options) {
    this.loading = true;
    this.error = null;
    this.render();

    try {
      const payload = await this.fetchJSON(path, options);
      this.html = typeof payload.html === "string" ? payload.html : null;
      this.cart = payload.cart;
      this.warnings = payload.warnings || [];
      this.dispatchEvent(
        new CustomEvent("cart:change", {
          detail: { cart: this.cart, warnings: this.warnings },
          bubbles: true,
        }),
      );
      return payload;
    } catch (error) {
      this.error = error;
      this.dispatchEvent(
        new CustomEvent("cart:error", { detail: { error }, bubbles: true }),
      );
      throw error;
    } finally {
      this.loading = false;
      this.pending = null;
      this.render();
    }
  }

  async fetchJSON(path, { body, ...options }) {
    this.abortController?.abort();
    this.abortController = new AbortController();

    const response = await fetch(`${this.endpoint}${path}`, {
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        // Asks the plug to render its cart component and return the markup
        // alongside the JSON. Headless consumers never send it, so they never
        // pay for rendering they would throw away.
        ...(this.hasAttribute("headless") ? {} : { "x-brando-cart-html": "1" }),
        "Content-Type": "application/json",
        ...this.csrfHeader(),
      },
      signal: this.abortController.signal,
      ...options,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      const error = new Error(payload.error?.message || `Cart request failed (${response.status})`);
      error.status = response.status;
      error.payload = payload;
      throw error;
    }

    return payload;
  }

  csrfHeader() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    return token ? { "x-csrf-token": token } : {};
  }

  render() {
    // A cart mutation is a Storefront round trip, around 600ms. The optimistic
    // row covers adding; quantity changes and removals have nothing to stand in
    // for them, so the element carries the state and the stylesheet decides what
    // it looks like.
    this.toggleAttribute("data-loading", this.loading);

    const actions = {
      update: (id, quantity) => this.update(id, quantity),
      remove: (id) => this.remove(id),
      checkout: () => this.checkout(),
      close: () => this.close(),
    };

    if (typeof this.renderer === "function") {
      this.renderer(this, this.state(), actions);
    } else if (this.hasAttribute("headless")) {
      // Nothing to draw.
    } else if (this.html !== null) {
      // Rendered from the server's cart component. Its buttons carry
      // data-cart-action and are handled by the delegated listener, so swapping
      // the markup needs no rebinding.
      //
      // There is deliberately no client-side fallback renderer. Two renderers
      // drift, and the drift would only ever show when the server one failed —
      // exactly when nobody is looking. Shopify's own themes render the cart on
      // the server too, through the Section Rendering API.
      this.innerHTML = this.html;
      if (this.pending) this.renderPending();
    }
  }

  // One listener on the element, not one per button: the markup is replaced on
  // every cart change, and per-node listeners would go with it.
  handleAction(event) {
    const trigger = event.target.closest("[data-cart-action]");
    if (!trigger || !this.contains(trigger)) return;

    const lineId = trigger.getAttribute("data-line-id");

    switch (trigger.getAttribute("data-cart-action")) {
      case "close":
        this.close();
        break;
      case "checkout":
        this.checkout();
        break;
      case "remove":
        if (lineId) this.remove(lineId);
        break;
      case "quantity":
        if (lineId) {
          this.update(lineId, Number(trigger.getAttribute("data-quantity")));
        }
        break;
    }
  }

  state() {
    return {
      cart: this.cart,
      count: this.count,
      loading: this.loading,
      error: this.error,
      warnings: this.warnings,
      open: this.hasAttribute("open"),
    };
  }

}




if (!customElements.get("brando-shopify-cart")) {
  customElements.define("brando-shopify-cart", BrandoShopifyCart);
}
