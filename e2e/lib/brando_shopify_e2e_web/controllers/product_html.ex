defmodule BrandoShopifyE2EWeb.ProductHTML do
  # This deliberately compiles and renders through Brando's HTML surface. The
  # E2E app therefore catches integration drift on Brando's next branch.
  use BrandoWeb, :html

  embed_templates "product_html/*"
end
