defmodule Warehouse.Products.NoResultsError do
  defexception [:message, plug_status: 404]

  def exception(id: id) do
    msg = "Product with id='#{id}' was not found"
    %__MODULE__{message: msg}
  end
end
