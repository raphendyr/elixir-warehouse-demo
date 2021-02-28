defmodule ProductCache do
  @moduledoc ~S"""
  An active in-memory cache application.

  The cache is conceptually the same as Redis or Memcached.
  However, actors can subscribe to product updates with
  `PubSub.subscribe(Warehouse.PubSub, "products:#{category}")`,
  which is useful for LiveViews for example.

  This module includes the public API of the cache.
  """

  @doc ~S"""
  Returns a list of category names
  """
  def categories(opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout, 5_000)
    GenServer.call(ProductCache.Cache, {:categories, opts}, timeout)
  end

  @doc ~S"""
  Returns a list of products for a category
  """
  def products(category, opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout, 5_000)
    GenServer.call(ProductCache.Cache, {:products, category, opts}, timeout)
  end

  @doc ~S"""
  Returns a product by it's id, if it exists.
  """
  def product(id, timeout \\ 5_000) do
    GenServer.call(ProductCache.Cache, {:product, id}, timeout)
  end

  @doc ~S"""
  Makes async request for categories.
  Categories are send back as a message {:categories, categories}.
  """
  def async_categories() do
    GenServer.cast(ProductCache.Cache, {:categories, self()})
  end

  @doc ~S"""
  Makes async request for products.
  Products are send back as a message {:products, category, products}.
  """
  def async_products(category) do
    GenServer.cast(ProductCache.Cache, {:products, category, self()})
  end
end
