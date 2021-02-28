defmodule Warehouse.Products do
  @moduledoc """
  The Products context.
  """

  alias Warehouse.Products.Category

  require Logger

  @doc false
  def list_categories() do
    {:ok, category_names} = ProductCache.categories()
    # NOTE: may die to timeout
    categories = Enum.map(category_names, fn name -> %Category{name: name} end)
    categories
  end

  @doc false
  def async_categories() do
    ProductCache.async_categories()
  end

  @doc """
  Returns the list of products.

  ## Examples

      iex> list_products("foo")
      [%Product{type: "foo"}, ...]

  """
  def list_products(category, retry \\ false) do
    try do
      case ProductCache.products(category, wait: false, timeout: 3_000) do
        {:ok, products} ->
          products

        {:error, :unknown_category} ->
          if retry or not Enum.any?(list_categories(), fn cat -> cat.name == category end) do
            []
          else
            list_products(category, true)
          end
      end
    catch
      :exit, {:timeout, {GenServer, :call, _}} ->
        Logger.warn(module: __MODULE__, action: {:list_products, category}, exit: :timeout)
        nil
    end
  end

  @doc false
  def async_products(category) do
    ProductCache.async_products(category)
  end

  @doc """
  Gets a single product.

  Raises `Warehouse.Products.NoResultsError` if the Product does not exist.

  ## Examples

      iex> get_product!(123)
      %Product{id: 123}

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
