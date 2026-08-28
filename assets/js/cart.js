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
  total: "Total",
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

    this.setAttribute("role", "region");
    this.setAttribute("aria-label", this.getAttribute("aria-label") || this.labels.region);
    this.hidden = !this.hasAttribute("open");
    this.render();

    if (!this.hasAttribute("manual")) this.refresh();
  }

  disconnectedCallback() {
    this.abortController?.abort();
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

  add(merchandiseId, quantity = 1, attributes = [], options = {}) {
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
    const actions = {
      update: (id, quantity) => this.update(id, quantity),
      remove: (id) => this.remove(id),
      checkout: () => this.checkout(),
      close: () => this.close(),
    };

    if (typeof this.renderer === "function") {
      this.renderer(this, this.state(), actions);
    } else if (!this.hasAttribute("headless")) {
      this.renderDefault(actions);
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

  renderDefault(actions) {
    this.replaceChildren();
    const panel = element("div", { class: "brando-cart__panel", part: "panel" });
    const header = element("header", { class: "brando-cart__header", part: "header" });
    header.append(
      element("h2", { class: "brando-cart__title", text: this.labels.title }),
      button(this.labels.close, "brando-cart__close", actions.close, "close", "×"),
    );
    panel.append(header);

    if (this.error) {
      panel.append(
        element("p", {
          class: "brando-cart__error",
          part: "error",
          text: this.error.message,
          role: "alert",
        }),
      );
    }

    const lines = this.cart?.lines?.nodes || [];

    if (lines.length === 0) {
      panel.append(
        element("p", {
          class: "brando-cart__empty",
          part: "empty",
          text: this.loading ? this.labels.loading : this.labels.empty,
        }),
      );
    } else {
      const list = element("ul", { class: "brando-cart__lines", part: "lines" });
      lines.forEach((line) => list.append(this.renderLine(line, actions)));
      panel.append(list, this.renderFooter(actions));
    }

    panel.setAttribute("aria-busy", String(this.loading));
    this.append(panel);
  }

  renderLine(line, actions) {
    const variant = line.merchandise || {};
    const item = element("li", { class: "brando-cart__line", part: "line" });

    if (variant.image?.url) {
      item.append(
        element("img", {
          class: "brando-cart__image",
          src: variant.image.url,
          alt: variant.image.altText || "",
          loading: "lazy",
          width: "96",
          height: "96",
        }),
      );
    }

    const details = element("div", { class: "brando-cart__details" });
    details.append(
      element("p", {
        class: "brando-cart__product",
        text: variant.product?.title || variant.title || this.labels.product,
      }),
    );

    if (variant.title && variant.title !== this.labels.defaultVariant) {
      details.append(
        element("p", { class: "brando-cart__variant", text: variant.title }),
      );
    }

    const controls = element("div", { class: "brando-cart__quantity", part: "quantity" });
    controls.append(
      button(this.labels.decrease, "", () => actions.update(line.id, line.quantity - 1), "", "−"),
      element("span", {
        class: "brando-cart__quantity-value",
        text: String(line.quantity),
        "aria-live": "polite",
      }),
      button(this.labels.increase, "", () => actions.update(line.id, line.quantity + 1), "", "+"),
      button(this.labels.removeItem, "brando-cart__remove", () => actions.remove(line.id), "", this.labels.remove),
    );
    details.append(controls);

    item.append(
      details,
      element("data", {
        class: "brando-cart__line-total",
        value: line.cost?.totalAmount?.amount || "",
        text: money(line.cost?.totalAmount),
      }),
    );
    return item;
  }

  renderFooter(actions) {
    const footer = element("footer", { class: "brando-cart__footer", part: "footer" });
    footer.append(
      element("div", { class: "brando-cart__total", text: this.labels.total }),
      element("data", {
        class: "brando-cart__total-amount",
        value: this.cart?.cost?.totalAmount?.amount || "",
        text: money(this.cart?.cost?.totalAmount),
      }),
      button(
        this.loading ? this.labels.updating : this.labels.checkout,
        "brando-cart__checkout",
        actions.checkout,
        "checkout",
      ),
    );
    return footer;
  }
}

function element(tag, attributes = {}) {
  const node = document.createElement(tag);
  Object.entries(attributes).forEach(([key, value]) => {
    if (key === "text") node.textContent = value;
    else if (value !== undefined && value !== null && value !== "") node.setAttribute(key, value);
  });
  return node;
}

function button(label, className, onClick, part = "", text = label) {
  const node = element("button", {
    type: "button",
    class: className,
    part,
    "aria-label": label,
    text,
  });
  node.addEventListener("click", onClick);
  return node;
}

function money(value) {
  if (!value?.amount || !value?.currencyCode) return "";
  return new Intl.NumberFormat(document.documentElement.lang || undefined, {
    style: "currency",
    currency: value.currencyCode,
  }).format(Number(value.amount));
}

if (!customElements.get("brando-shopify-cart")) {
  customElements.define("brando-shopify-cart", BrandoShopifyCart);
}
