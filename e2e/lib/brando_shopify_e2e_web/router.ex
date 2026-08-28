defmodule BrandoShopifyE2EWeb.Router do
  use BrandoShopifyE2EWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :cart_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/__shopify", BrandoShopifyE2EWeb do
    post "/reset", FixtureController, :reset
    patch "/product", FixtureController, :update_product
    get "/state", FixtureController, :state
    post "/live/sync", FixtureController, :live_sync
    get "/checkout", FixtureController, :checkout
  end

  scope "/test-assets", BrandoShopifyE2EWeb do
    get "/cart.js", AssetController, :cart_js
    get "/cart.css", AssetController, :cart_css
  end

  scope "/shopify" do
    pipe_through :cart_api
    forward "/cart", BrandoShopify.Plug.Cart, store: :default
  end

  scope "/", BrandoShopifyE2EWeb do
    pipe_through :browser
    get "/shopify-e2e/products/:handle", ProductController, :show
  end
end
