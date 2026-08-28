defmodule Mix.Tasks.BrandoShopify.Gen.Shop do
  @shortdoc "Generates shop pages wired to the synced catalogue"

  @moduledoc """
  Generates a context, a controller and templates for the storefront.

      mix brando_shopify.gen.shop

  What it writes is the wiring, not the markup: the grid, card, price and variant
  picker come from `BrandoShopify.Components.Catalog`, so they keep improving
  with the package rather than freezing into a copy. What lands in your
  application is the part the package cannot know — your routes, your partner
  collections, and the templates where you compose it all.

  ## Options

    * `--path` — URL prefix for the pages. Defaults to `/shop`.
    * `--partner-collections` — comma-separated collection handles that count as
      partner groups. Products belonging *only* to one are hidden from the main
      listing. Defaults to none.
    * `--context` — context module name. Defaults to `Shop`.
    * `--force` — overwrite existing files.

  ## Example

      mix brando_shopify.gen.shop --path /butikk \\
        --partner-collections sykkelforeningen,turlaget

  Nothing is written to your router — the task prints the routes to add, because
  where they go relative to a catch-all matters and only you know your router.
  """

  use Mix.Task

  @templates ~w(shop.ex shop_controller.ex shop_html.ex list.html.heex detail.html.heex collection.html.heex)

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          path: :string,
          partner_collections: :string,
          context: :string,
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
    context = opts[:context] || "Shop"

    partners =
      (opts[:partner_collections] || "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    path = String.trim_trailing(opts[:path] || "/shop", "/")

    [
      otp_app: otp_app,
      base: base,
      web_module: "#{base}Web",
      context_module: "#{base}.#{context}",
      html_module: "#{base}Web.#{context}HTML",
      controller_module: "#{base}Web.#{context}Controller",
      context_file: Macro.underscore(context),
      path: path,
      partner_collections: partners
    ]
  end

  defp paths(template, bindings, root) do
    source =
      Application.app_dir(
        :brando_shopify,
        "priv/templates/brando_shopify.gen.shop/#{template}.eex"
      )

    file = bindings[:context_file]

    destination =
      case template do
        "shop.ex" ->
          "lib/#{bindings[:otp_app]}/#{file}.ex"

        "shop_controller.ex" ->
          "lib/#{bindings[:otp_app]}_web/controllers/#{file}_controller.ex"

        "shop_html.ex" ->
          "lib/#{bindings[:otp_app]}_web/controllers/#{file}_html.ex"

        template ->
          "lib/#{bindings[:otp_app]}_web/controllers/#{file}_html/#{template}"
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
        File.write!(destination, EEx.eval_file(source, assigns: bindings))
        Mix.shell().info([:green, "* creating ", :reset, relative])
    end
  end

  defp instructions(bindings) do
    path = bindings[:path]
    controller = bindings[:controller_module]

    """

    Add these to your router, #{IO.ANSI.bright()}before#{IO.ANSI.reset()} any catch-all route.
    In a Brando application `page_routes/0` ends in `get "/*path"` and will
    swallow anything declared after it — a 404 with no hint as to why.

        get "#{path}", #{controller}, :list
        get "#{path}/product/:handle", #{controller}, :detail
        get "#{path}/:handle", #{controller}, :collection

    The product route has three segments and the collection route two, so they
    cannot collide.

    Then import the components wherever you render them:

        import BrandoShopify.Components.Catalog

    They emit `brando-shop__*` class names as styling hooks. Nothing is styled
    for you — see docs/brando-integration.md for the slots each one exposes.
    """
  end
end
