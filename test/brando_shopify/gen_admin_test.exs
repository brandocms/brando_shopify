defmodule Mix.Tasks.BrandoShopify.Gen.AdminTest do
  @moduledoc """
  Runs the generator against a temporary project.

  The generated screens are built on Brando's admin, which this package does not
  depend on, so they cannot be compiled here. What can be checked is that every
  file is valid Elixir and names the host's modules.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @tmp Path.join(System.tmp_dir!(), "brando_shopify_gen_admin_test")

  @files [
    "lib/admin_demo_admin/shopify/catalogue.ex",
    "lib/admin_demo_admin/shopify/components.ex",
    "lib/admin_demo_admin/live/shopify/product_list_live.ex",
    "lib/admin_demo_admin/live/shopify/collection_list_live.ex",
    "lib/admin_demo_admin/live/shopify/sync_live.ex",
    "lib/admin_demo_admin/live/shopify/settings_live.ex"
  ]

  setup do
    File.rm_rf!(@tmp)
    File.mkdir_p!(@tmp)

    # Not :demo_shop like gen_shop_test: Mix caches a project module's file, so
    # two suites sharing DemoShop.MixProject write into each other's directory.
    File.write!(Path.join(@tmp, "mix.exs"), """
    defmodule AdminDemo.MixProject do
      use Mix.Project
      def project, do: [app: :admin_demo, version: "0.1.0"]
    end
    """)

    on_exit(fn -> File.rm_rf!(@tmp) end)

    %{}
  end

  defp generate(args) do
    Mix.Project.in_project(:admin_demo, @tmp, fn _module ->
      capture_io(fn -> Mix.Tasks.BrandoShopify.Gen.Admin.run(args) end)
    end)
  end

  defp read(path), do: File.read!(Path.join(@tmp, path))

  test "writes the catalogue, the components and four screens" do
    generate([])

    for path <- @files, do: assert(File.exists?(Path.join(@tmp, path)), "missing #{path}")
  end

  test "every file is valid Elixir" do
    generate(["--shop-path", "/butikk"])

    for path <- @files do
      assert {:ok, _} = Code.string_to_quoted(read(path)), "#{path} does not parse"
    end
  end

  test "names modules from the host application" do
    generate([])

    assert read("lib/admin_demo_admin/shopify/catalogue.ex") =~
             "defmodule AdminDemoAdmin.Shopify.Catalogue do"

    assert read("lib/admin_demo_admin/live/shopify/sync_live.ex") =~
             "use Gettext, backend: AdminDemoAdmin.Gettext"
  end

  test "HEEx comments survive EEx" do
    generate([])

    assert read("lib/admin_demo_admin/shopify/components.ex") =~ "<%!-- Styled inline"
  end

  test "--shop-path gives products a link to their page" do
    generate(["--shop-path", "/butikk/"])

    assert read("lib/admin_demo_admin/shopify/catalogue.ex") =~
             ~s("/butikk/product/\#{product.handle}")
  end

  test "without --shop-path, products have no storefront link" do
    output = generate([])

    assert read("lib/admin_demo_admin/shopify/catalogue.ex") =~
             ~r/def public_path\(%Product\{\} = _product\) do\s+nil/

    assert output =~ "public_path/1"
  end

  test "--path and --store reach the tabs and the queries" do
    output = generate(["--path", "butikk", "--store", "norway"])

    assert read("lib/admin_demo_admin/shopify/components.ex") =~ ~s("/admin/butikk/products")
    assert read("lib/admin_demo_admin/shopify/catalogue.ex") =~ ~s(@store "norway")
    assert output =~ ~s(scope "/butikk", AdminDemoAdmin.Shopify do)
  end

  test "--partner-collections is the fallback until settings are saved" do
    generate(["--partner-collections", "sykkelforeningen, turlaget"])

    assert read("lib/admin_demo_admin/shopify/catalogue.ex") =~
             ~s{BrandoShopify.Settings.partner_collections(@store, ["sykkelforeningen", "turlaget"])}
  end

  test "prints the settings route and both ways to put it in the menu" do
    output = generate([])

    assert output =~ ~s(live "/config/shop", AdminDemoAdmin.Shopify.SettingsLive)
    assert output =~ ~s{config_item t("Shop"), "/admin/config/shop"}
    assert output =~ ~s{menu_subitem t("Settings"), "/admin/config/shop"}
  end

  test "an existing file is kept unless --force" do
    generate([])
    path = Path.join(@tmp, "lib/admin_demo_admin/shopify/catalogue.ex")
    File.write!(path, "# mine")

    assert generate([]) =~ "skipping"
    assert File.read!(path) == "# mine"

    generate(["--force"])
    refute File.read!(path) == "# mine"
  end
end
