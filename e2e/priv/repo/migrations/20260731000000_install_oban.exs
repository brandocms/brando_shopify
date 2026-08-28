defmodule BrandoShopifyE2E.Repo.Migrations.InstallOban do
  use Ecto.Migration

  def up, do: Oban.Migration.up()
  def down, do: Oban.Migration.down()
end
