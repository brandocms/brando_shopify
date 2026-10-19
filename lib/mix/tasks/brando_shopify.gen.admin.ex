defmodule Mix.Tasks.BrandoShopify.Gen.Admin do
  @shortdoc "Generates Brando admin screens for the synced catalogue"

  @moduledoc """
  Generates Brando admin screens for what the sync stores: the products, the
  collections, and the sync runs, with buttons to start a sync.

      mix brando_shopify.gen.admin

  The screens are generated into your application rather than shipped
  compiled, because they are built on Brando's admin (`use BrandoAdmin,
  :live_view`, its workspace components) and this package does not depend on
  Brando: it is plain Ecto, Oban and Phoenix components, and publishable to
  Hex, which takes no git dependencies.

  The products and collections are read-only on purpose. Shopify owns them, so
  an edit made in the admin would be overwritten by the next webhook; each row
  links to the Shopify admin instead.

  ## What it writes

    * `<Admin>.Shopify.Catalogue` — the queries, the two sync actions, and the
      links to the Shopify admin and to your storefront.
    * `<Admin>.Shopify.Components` — the tabs between the screens, thumbnails,
      status badges, times.
    * `<Admin>.Shopify.ProductListLive`, `CollectionListLive` and `SyncLive`,
      for the catalogue.
    * `<Admin>.Shopify.SettingsLive`, for the store's settings: whether the
      shop is open (`BrandoShopify.Settings`, so it changes without a deploy),
      which collections are partner shops, fetching the legal policies, and
      how the store is connected. It needs the `shopify_settings` table from
      `mix brando_shopify.install`.

  ## Options

    * `--admin-module` — your Brando admin module. Defaults to `<App>Admin`.
    * `--path` — where the screens live under the admin. Defaults to
      `/shopify`, giving `/admin/shopify/products` and so on.
    * `--store` — the configured store to show. Defaults to `default`.
    * `--shop-path` — your storefront's URL prefix, as given to
      `mix brando_shopify.gen.shop`, so each product links to its page.
      Without it the products have no "View" link until you fill in
      `Catalogue.public_path/1`.
    * `--partner-collections` — the partner shops to use until an
      administrator saves any, as given to `mix brando_shopify.gen.shop`.
    * `--force` — overwrite existing files.

  ## Example

      mix brando_shopify.gen.admin --shop-path /butikk

  Nothing is written to your router or your admin menu — the task prints the
  lines to add, as `mix brando_shopify.gen.shop` does.
  """

  use Mix.Task

  @templates ~w(
    catalogue.ex components.ex
    product_list_live.ex collection_list_live.ex sync_live.ex settings_live.ex
  )

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          admin_module: :string,
          path: :string,
          store: :string,
          shop_path: :string,
          partner_collections: :string,
          force: :boolean
        ]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    bindings = bindings(opts)
    root = Path.dirname(Mix.Project.project_file())

    for template <- @templates do
      {source, destination} = paths(template, bindings, root)
      copy(source, destination, bindings, opts[:force] == true)
    end

    Mix.shell().info(instructions(bindings))
  end

  defp bindings(opts) do
    otp_app = Mix.Project.config()[:app] || Mix.raise("could not determine the application name")
    base = Macro.camelize(to_string(otp_app))
    admin_module = opts[:admin_module] || "#{base}Admin"
    path = "/" <> String.trim(opts[:path] || "/shopify", "/")

    [
      otp_app: otp_app,
      base: base,
      admin_module: admin_module,
      admin_dir: Macro.underscore(admin_module),
      # The screens link to each other with `navigate`, so they need the
      # admin's mount point too. Brando mounts its admin at /admin.
      admin_path: "/admin" <> path,
      path: path,
      store: opts[:store] || "default",
      partner_collections:
        (opts[:partner_collections] || "")
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "")),
      shop_path: opts[:shop_path] && String.trim_trailing(opts[:shop_path], "/")
    ]
  end

  defp paths(template, bindings, root) do
    source =
      Application.app_dir(
        :brando_shopify,
        "priv/templates/brando_shopify.gen.admin/#{template}.eex"
      )

    dir = bindings[:admin_dir]

    destination =
      case template do
        template when template in ["catalogue.ex", "components.ex"] ->
          "lib/#{dir}/shopify/#{template}"

        template ->
          "lib/#{dir}/live/shopify/#{template}"
      end

    {source, Path.join(root, destination)}
  end

  defp copy(source, destination, bindings, force?) do
    relative = Path.relative_to_cwd(destination)

    cond do
      not File.exists?(source) ->
        Mix.raise("missing template: #{source}")

      File.exists?(destination) and not force? ->
        Mix.shell().info([:yellow, "* skipping ", :reset, relative, " (exists, use --force)"])

      true ->
        File.mkdir_p!(Path.dirname(destination))
        File.write!(destination, render(source, bindings))
        Mix.shell().info([:green, "* creating ", :reset, relative])
    end
  end

  # Run through the formatter so the files arrive as `mix format` would leave
  # them. HEEx inside `~H` is left alone: that takes the host's formatter plugin.
  defp render(source, bindings) do
    source
    |> EEx.eval_file(assigns: bindings)
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  defp instructions(bindings) do
    admin = bindings[:admin_module]
    path = bindings[:path]
    admin_path = bindings[:admin_path]

    """

    Add the screens to your router, inside `admin_routes do … end`:

        scope "#{path}", #{admin}.Shopify do
          live "/products", ProductListLive
          live "/collections", CollectionListLive
          live "/sync", SyncLive
        end

        live "/config/shop", #{admin}.Shopify.SettingsLive

    And to your admin menu (`use BrandoAdmin.Menu`):

        menu_item t("Shop"), icon: "shopping-bag" do
          menu_subitem t("Products"), "#{admin_path}/products", icon: "package"
          menu_subitem t("Collections"), "#{admin_path}/collections", icon: "layers"
          menu_subitem t("Sync"), "#{admin_path}/sync", icon: "refresh-cw"
        end

        config_item t("Shop"), "/admin/config/shop", icon: "store", group: :operations

    `config_item` puts the settings under Configuration, and needs a Brando
    with `BrandoAdmin.Menu.config_item/3`. On an older one, add the screen to
    the Shop menu instead:

          menu_subitem t("Settings"), "/admin/config/shop", icon: "store"

    The settings are stored in `shopify_settings`: run `mix brando_shopify.install`
    and migrate if you have not since upgrading. To let the stored launch state
    open and close the shop, make it the store's `:visibility` source, with the
    state to use until one is saved, and mount `BrandoShopify.Plug.Visibility`
    on the shop's pipelines:

        visibility: {BrandoShopify.Settings, :visibility, [:default, :preview]}

    The screens' strings are English msgids in #{admin}.Gettext; extract
    and translate them as you do your other admin strings.
    #{if bindings[:shop_path], do: "", else: "\nProducts get a \"View\" link once `#{admin}.Shopify.Catalogue.public_path/1`\nreturns their storefront path.\n"}
    """
  end
end
