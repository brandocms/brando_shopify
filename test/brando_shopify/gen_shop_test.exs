defmodule Mix.Tasks.BrandoShopify.Gen.ShopTest do
  @moduledoc """
  Runs the generator against a temporary project.

  Compiling the task proves nothing about what it writes. The `--force` bug it
  caught — `not nil` raising on the second run — only appeared when the files
  already existed.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @tmp Path.join(System.tmp_dir!(), "brando_shopify_gen_shop_test")

  setup do
    File.rm_rf!(@tmp)
    File.mkdir_p!(@tmp)

    # The task reads the host's app name and root from Mix.Project.
    File.write!(Path.join(@tmp, "mix.exs"), """
    defmodule DemoShop.MixProject do
      use Mix.Project
      def project, do: [app: :demo_shop, version: "0.1.0"]
    end
    """)

    on_exit(fn -> File.rm_rf!(@tmp) end)

    %{}
  end

  defp generate(args) do
    Mix.Project.in_project(:demo_shop, @tmp, fn _module ->
      capture_io(fn -> Mix.Tasks.BrandoShopify.Gen.Shop.run(args) end)
    end)
  end

  defp read(path), do: File.read!(Path.join(@tmp, path))

  describe "run/1" do
    test "writes a context, controller, html module and three templates" do
      generate([])

      for path <- [
            "lib/demo_shop/shop.ex",
            "lib/demo_shop_web/controllers/shop_controller.ex",
            "lib/demo_shop_web/controllers/shop_html.ex",
            "lib/demo_shop_web/controllers/shop_html/list.html.heex",
            "lib/demo_shop_web/controllers/shop_html/detail.html.heex",
            "lib/demo_shop_web/controllers/shop_html/collection.html.heex"
          ] do
        assert File.exists?(Path.join(@tmp, path)), "missing #{path}"
      end
    end

    test "names modules from the host application" do
      generate([])

      assert read("lib/demo_shop/shop.ex") =~ "defmodule DemoShop.Shop do"
      assert read("lib/demo_shop/shop.ex") =~ "alias DemoShop.Repo"

      assert read("lib/demo_shop_web/controllers/shop_html.ex") =~
               "defmodule DemoShopWeb.ShopHTML do"
    end

    test "bakes the path into the route helpers" do
      generate(["--path", "/butikk"])

      html = read("lib/demo_shop_web/controllers/shop_html.ex")
      assert html =~ ~s[def product_path(product), do: "/butikk/product/\#{product.handle}"]
      assert html =~ ~s[def collection_path(collection), do: "/butikk/\#{collection.handle}"]
    end

    test "trims a trailing slash rather than producing a double one" do
      generate(["--path", "/butikk/"])

      assert read("lib/demo_shop_web/controllers/shop_html.ex") =~ ~s["/butikk/product/]
    end

    test "bakes partner collections into the context" do
      generate(["--partner-collections", "sykkelforeningen, turlaget"])

      assert read("lib/demo_shop/shop.ex") =~
               ~s(def partner_handles, do: ["sykkelforeningen", "turlaget"])
    end

    test "no partner collections is an empty list, not a crash" do
      generate([])

      assert read("lib/demo_shop/shop.ex") =~ "def partner_handles, do: []"
    end

    test "honours a custom context name" do
      generate(["--context", "Store"])

      assert File.exists?(Path.join(@tmp, "lib/demo_shop/store.ex"))
      assert read("lib/demo_shop/store.ex") =~ "defmodule DemoShop.Store do"

      assert read("lib/demo_shop_web/controllers/store_html.ex") =~
               ~s(embed_templates "store_html/*")
    end

    test "HEEx expressions survive EEx rather than being evaluated by it" do
      generate([])

      list = read("lib/demo_shop_web/controllers/shop_html/list.html.heex")

      assert list =~ "<.product_grid products={@products}"
      assert list =~ "<:card :let={product}>"

      detail = read("lib/demo_shop_web/controllers/shop_html/detail.html.heex")
      assert detail =~ "{@entry.title}"
      # A HEEx comment, escaped in the EEx template so it reaches the output.
      assert detail =~ "<%!--"
    end

    test "skips existing files instead of overwriting them" do
      generate([])
      File.write!(Path.join(@tmp, "lib/demo_shop/shop.ex"), "# mine")

      output = generate([])

      assert output =~ "skipping"
      assert read("lib/demo_shop/shop.ex") == "# mine"
    end

    test "--force overwrites" do
      generate([])
      File.write!(Path.join(@tmp, "lib/demo_shop/shop.ex"), "# mine")

      generate(["--force"])

      assert read("lib/demo_shop/shop.ex") =~ "defmodule DemoShop.Shop do"
    end

    test "prints the routes, with the catch-all warning" do
      output = generate(["--path", "/butikk"])

      assert output =~ ~s(get "/butikk", DemoShopWeb.ShopController, :list)
      assert output =~ ~s(get "/butikk/product/:handle", DemoShopWeb.ShopController, :detail)
      assert output =~ ~s(get "/butikk/:handle", DemoShopWeb.ShopController, :collection)
      assert output =~ "catch-all"
    end

    test "rejects unknown options rather than ignoring them" do
      assert_raise Mix.Error, fn -> generate(["--nope", "x"]) end
    end
  end
end
