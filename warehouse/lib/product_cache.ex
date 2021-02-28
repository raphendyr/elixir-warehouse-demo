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

  def categories(opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout, 5_000)
    GenServer.call(ProductCache.Cache, {:categories, opts}, timeout)
  end

  def products(category, opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout, 5_000)
    GenServer.call(ProductCache.Cache, {:products, category, opts}, timeout)
  end

  def product(id, timeout \\ 5_000) do
    GenServer.call(ProductCache.Cache, {:product, id}, timeout)
  end

  def async_categories() do
    GenServer.cast(ProductCache.Cache, {:categories, self()})
  end

  def async_products(category) do
    GenServer.cast(ProductCache.Cache, {:products, category, self()})
  end
end
