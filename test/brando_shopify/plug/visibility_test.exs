defmodule BrandoShopify.Plug.VisibilityTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Test
  import Plug.Conn

  alias BrandoShopify.Plug.Visibility

  @store :visibility_test

  setup context do
    put_store(Map.get(context, :visibility, :live))
    on_exit(fn -> Application.delete_env(:brando_shopify, :stores) end)
    :ok
  end

  defp put_store(visibility) do
    Application.put_env(:brando_shopify, :stores,
      visibility_test: [
        shop_domain: "demo-store.myshopify.com",
        storefront_access_token: "token",
        visibility: visibility
      ]
    )
  end

  defp run(conn, opts \\ []) do
    opts = Keyword.put_new(opts, :store, @store)
    Visibility.call(conn, Visibility.init(opts))
  end

  defp staff_conn, do: assign(conn(:get, "/butikk"), :current_user, %{id: 1})

  describe ":live" do
    test "lets everyone through and assigns the state" do
      conn = run(conn(:get, "/butikk"))

      refute conn.halted
      assert conn.assigns.shopify_visibility == :live
      assert get_resp_header(conn, "x-robots-tag") == []
    end
  end

  describe ":preview" do
    @describetag visibility: :preview

    test "lets a vouched-for visitor through, but keeps them out of search" do
      conn = run(staff_conn())

      refute conn.halted
      assert conn.assigns.shopify_visibility == :preview
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    end

    test "hides the store from everyone else" do
      conn = run(conn(:get, "/butikk"))

      assert conn.halted
      assert conn.status == 404
    end

    test "honours a custom :preview_when" do
      always = fn _conn -> true end

      refute run(conn(:get, "/butikk"), preview_when: always).halted
    end
  end

  describe ":off" do
    @describetag visibility: :off

    test "hides the store from staff too" do
      conn = run(staff_conn())

      assert conn.halted
      assert conn.status == 404
    end
  end

  describe ":on_hidden" do
    @describetag visibility: :off

    test "redirects" do
      conn = run(conn(:get, "/butikk"), on_hidden: {:redirect, "https://old.example.com"})

      assert conn.halted
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["https://old.example.com"]
    end

    test "halts with a given status" do
      assert run(conn(:get, "/butikk"), on_hidden: {:halt, 410}).status == 410
    end

    test "hands the conn to a function" do
      handler = fn conn -> conn |> send_resp(418, "closed") |> halt() end
      conn = run(conn(:get, "/butikk"), on_hidden: handler)

      assert conn.halted
      assert conn.status == 418
    end
  end

  describe "resolution" do
    @describetag visibility: {__MODULE__, :configured_visibility, []}

    test "resolves through an MFA source" do
      Process.put(:visibility, :off)
      assert run(staff_conn()).halted

      Process.put(:visibility, :live)
      refute run(conn(:get, "/butikk")).halted
    end

    test "closes the store when a callable returns nonsense" do
      Process.put(:visibility, :sometimes)

      log = capture_log(fn -> assert run(staff_conn()).halted end)

      assert log =~ "store visibility resolved to :sometimes"
    end
  end

  test "an unconfigured store is closed, not open" do
    Application.delete_env(:brando_shopify, :stores)

    conn = run(staff_conn())

    assert conn.assigns.shopify_visibility == :off
    assert conn.halted
  end

  @doc false
  def configured_visibility, do: Process.get(:visibility, :live)
end
