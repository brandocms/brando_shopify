defmodule BrandoShopifyE2EWeb do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: BrandoShopifyE2EWeb.Layouts]

      import Plug.Conn
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Phoenix.Controller
      import Plug.Conn
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
