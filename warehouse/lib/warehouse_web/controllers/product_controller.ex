defmodule WarehouseWeb.ProductController do
  use WarehouseWeb, :controller

  alias Warehouse.Products

  def index(conn, %{"category" => category}) do
    products = Products.list_products(category)
    render(conn, "index.html", category: category, products: products)
  end

  def show(conn, %{"id" => id}) do
    product = Products.get_product!(id)
    render(conn, "show.html", product: product)
  end
end
