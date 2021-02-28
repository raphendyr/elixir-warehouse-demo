defmodule WarehouseWeb.ProductController do
  use WarehouseWeb, :controller

  alias Warehouse.Products

  def index(conn, %{}) do
    categories = Products.list_categories()
    render(conn, "index.html", categories: categories)
  end

  def list(conn, %{"category" => category}) do
    categories = Products.list_categories()
    products = Products.list_products(category)
    render(conn, "list.html",
      categories: categories,
      category: category,
      products: products,
    )
  end

  def show(conn, %{"id" => id}) do
    product = Products.get_product!(id)
    render(conn, "show.html", product: product)
  end
end
