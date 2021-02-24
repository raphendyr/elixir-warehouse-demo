defmodule ProductCache do
  @moduledoc """
  Caches data from the backend.

  Backend
    https://bad-api-assignment.reaktor.com/

  GET /v2/products/:category
    Return a listing of products in a given category.

  GET /v2/availability/:manufacturer
    Return a list of availability info.
  """

  def categories() do
    GenServer.call(ProductCache.Cache, :categories)
  end

  def products(category) do
    GenServer.call(ProductCache.Cache, {:products, category})
  end

  def product(id) do
    GenServer.call(ProductCache.Cache, {:product, id})
  end

  def async_categories() do
    GenServer.cast(ProductCache.Cache, {:categories, self()})
  end

  def async_products(category) do
    GenServer.cast(ProductCache.Cache, {:products, category, self()})
  end
end
