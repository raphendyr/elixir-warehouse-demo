defmodule WarehouseWeb.PageController do
  use WarehouseWeb, :controller

  alias Warehouse.Products

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
