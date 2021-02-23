defmodule Warehouse.Products.Category do
  @derive {Phoenix.Param, key: :name}
  defstruct [:name]
end
