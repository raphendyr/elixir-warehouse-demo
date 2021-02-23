defmodule Warehouse.Products do
  @moduledoc """
  The Products context.
  """

  alias Warehouse.Products.Category

  require Logger

  @doc false
  def list_categories() do
    {:ok, category_names} = ProductCache.categories()
    categories = Enum.map(category_names, fn name -> %Category{name: name} end)
    categories
  end

  @doc """
  Returns the list of products.

  ## Examples

      iex> list_products("foo")
      [%Product{}, ...]

  """
  def list_products(category, retry \\ false) do
    case ProductCache.products(category) do
      {:ok, products} ->
        products

      {:error, :unknown_category} ->
        if retry or not Enum.any?(list_categories(), fn cat -> cat.name == category end) do
          []
        else
          list_products(category, true)
        end
    end
  end

  @doc """
  Gets a single product.

  Raises `Warehouse.Products.NoResultsError` if the Product does not exist.

  ## Examples

      iex> get_product!(123)
      %Product{}

      iex> get_product!(456)
      ** (Warehouse.Products.NoResultsError)

  """
  def get_product!(id) do
    case ProductCache.product(id) do
      {:ok, product} -> product
      {:error, :not_found} -> raise Warehouse.Products.NoResultsError, id: id
    end
  end
end
