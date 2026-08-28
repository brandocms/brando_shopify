defmodule BrandoShopify.Plug.Visibility do
  @moduledoc """
  Gates buyer-facing commerce routes on a store's launch state.

  A store is filled with products long before it opens. `:preview` lets the
  people doing that work see it on the real site, with real data, while everyone
  else is sent where they went before — usually the shop being replaced.

      pipeline :shop do
        plug :fetch_current_user

        plug BrandoShopify.Plug.Visibility,
          store: :default,
          preview_when: &MyApp.Shop.staff?/1,
          on_hidden: {:redirect, "https://old-shop.example.com"}
      end

  ## Options

    * `:store` — configured store name. Defaults to `:default`.
    * `:preview_when` — `(Plug.Conn.t() -> boolean())` deciding who may see a
      `:preview` store. Defaults to any assigned `:current_user`.
    * `:on_hidden` — what everyone else gets: `:not_found` (default),
      `{:redirect, url}`, `{:halt, status}`, or a `(Plug.Conn.t() ->
      Plug.Conn.t())` function for anything else.

  The resolved state is assigned as `:shopify_visibility`, so templates can
  branch on it without resolving it a second time. `:preview` responses carry
  `x-robots-tag: noindex, nofollow`.

  ## Hiding the store the way your framework does

  `:not_found` sends a bare 404, because this package depends on Plug alone. To
  get a Phoenix application's own error page, hand it back to the router:

      on_hidden: fn conn ->
        raise Phoenix.Router.NoRouteError, conn: conn, router: conn.private.phoenix_router
      end

  ## Where to mount it

  Mount this on buyer-facing pipelines and on the cart pipeline.

  Never mount it on the webhook pipeline. Sync has to keep running while the
  store is closed — that is the point of closing it rather than not building it
  yet, and it is what makes the catalog warm on launch day.

  ## `:off` and `:preview`

  `:off` closes the store for everyone, staff included. It is the state for
  routes that exist in code before anything is ready to look at. `:preview` is
  the working state, and the one worth reaching for.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts) do
    %{
      store: Keyword.get(opts, :store, :default),
      preview_when: Keyword.get(opts, :preview_when, &__MODULE__.assigned_user?/1),
      on_hidden: Keyword.get(opts, :on_hidden, :not_found)
    }
  end

  @impl Plug
  def call(conn, opts) do
    visibility = BrandoShopify.visibility(opts.store)
    conn = assign(conn, :shopify_visibility, visibility)

    case visibility do
      :live -> conn
      :preview -> preview(conn, opts)
      :off -> hide(conn, opts)
    end
  end

  @doc "The default `:preview_when` check: any assigned `:current_user`."
  @spec assigned_user?(Plug.Conn.t()) :: boolean()
  def assigned_user?(%Plug.Conn{} = conn), do: not is_nil(conn.assigns[:current_user])

  defp preview(conn, opts) do
    if opts.preview_when.(conn) do
      put_resp_header(conn, "x-robots-tag", "noindex, nofollow")
    else
      hide(conn, opts)
    end
  end

  defp hide(conn, %{on_hidden: {:redirect, url}}) do
    conn
    |> put_resp_header("location", url)
    |> send_resp(302, "")
    |> halt()
  end

  defp hide(conn, %{on_hidden: {:halt, status}}) do
    conn
    |> send_resp(status, "")
    |> halt()
  end

  defp hide(conn, %{on_hidden: fun}) when is_function(fun, 1) do
    fun.(conn)
  end

  defp hide(conn, %{on_hidden: :not_found}) do
    conn
    |> send_resp(404, "")
    |> halt()
  end
end
