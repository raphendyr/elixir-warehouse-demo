defmodule WarehouseWeb.PageController do
  use WarehouseWeb, :controller

  alias Warehouse.Products

  def index(conn, _params) do
    categories = Products.list_categories()
    render(conn, "index.html", categories: categories)
  end
end
