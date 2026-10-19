defmodule BrandoShopify.SettingsTest do
  @moduledoc """
  The rules that need no database: what a save accepts, and what a read falls
  back to. Reads are exercised through the cache, primed directly, since this
  suite has no repo.
  """

  use ExUnit.Case, async: true

  alias BrandoShopify.Settings

  defp prime(store, settings) do
    :persistent_term.put({Settings, store}, {settings, System.monotonic_time(:millisecond)})
    on_exit(fn -> :persistent_term.erase({Settings, store}) end)
  end

  describe "changeset/2" do
    test "trims, drops blanks and duplicates, and keeps the order given" do
      changeset =
        Settings.changeset(%Settings{store: "default"}, %{
          partner_collections: [" sykkelforeningen", "", "turlaget", "sykkelforeningen"]
        })

      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :partner_collections) == [
               "sykkelforeningen",
               "turlaget"
             ]
    end

    test "refuses what is not a collection handle" do
      changeset =
        Settings.changeset(%Settings{store: "default"}, %{partner_collections: ["Not A Handle"]})

      refute changeset.valid?
    end

    test "accepts only the three launch states" do
      assert Settings.changeset(%Settings{}, %{visibility: "preview"}).valid?
      refute Settings.changeset(%Settings{}, %{visibility: "open"}).valid?
    end
  end

  describe "reads" do
    test "an unsaved store uses the fallbacks" do
      prime("unsaved", nil)

      assert Settings.visibility("unsaved", :preview) == :preview
      assert Settings.partner_collections("unsaved", ["sykkelforeningen"]) == ["sykkelforeningen"]
    end

    test "a saved store uses what was saved, an empty list included" do
      prime("saved", %Settings{store: "saved", visibility: :live, partner_collections: []})

      assert Settings.visibility("saved", :off) == :live
      assert Settings.partner_collections("saved", ["sykkelforeningen"]) == []
    end

    test "a saved row without a launch state still falls back for it" do
      prime("half", %Settings{store: "half", visibility: nil, partner_collections: ["a"]})

      assert Settings.visibility("half", :preview) == :preview
    end
  end

  test "the installer's settings migration is valid Elixir" do
    path =
      Application.app_dir(
        :brando_shopify,
        "priv/templates/brando_shopify.install/settings_migration.exs"
      )

    source = File.read!(path)

    assert [{BrandoShopify.Repo.Migrations.CreateShopifySettings, _}] =
             Code.compile_string(source, path)

    assert source =~ "table(:shopify_settings"
  end
end
