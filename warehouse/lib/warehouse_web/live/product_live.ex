defmodule WarehouseWeb.ProductLive do
  use WarehouseWeb, :live_view

  require Logger

  alias Phoenix.PubSub
  alias Warehouse.Products

  @impl true
  def mount(_params, _session, socket) do
    Products.async_categories()
    {
      :ok,
      assign(socket, categories: [], category: nil, update_queue: :queue.new),
      temporary_assigns: [products: []]
    }
  end

  @impl true
  def handle_event("category", %{"value" => category}, socket) do
    Logger.info(module: __MODULE__, event: "category", category: category)

    # change update subscription to new category
    if not is_nil(socket.assigns.category) do
      PubSub.unsubscribe(Warehouse.PubSub, "products:#{socket.assigns.category}")
    end
    PubSub.subscribe(Warehouse.PubSub, "products:#{category}")

    # request initial products
    Products.async_products(category)

    # removed updates to old category from the update queue
    update_queue = :queue.filter(fn {_, cat, _} -> cat == category end, socket.assigns.update_queue)

    {:noreply, assign(socket, category: category, products: nil, update_queue: update_queue)}
  end

  @impl true
  def handle_info({:categories, categories}, socket) do
    {:noreply, assign(socket, categories: categories)}
  end

  @impl true
  def handle_info({:products, category, products}, socket) do
    Logger.info(module: __MODULE__, event: :products, count: Enum.count(products))
    {:noreply, schedule_product_push(:append, category, products, socket)}
  end

  @impl true
  def handle_info({:updated_products, category, products}, socket) do
    count = Enum.count(products)
    Logger.info(module: __MODULE__, event: :updated_products, count: count)
    {:noreply,
      schedule_product_push(:append, category, products, socket)
      |> put_flash(:info, "#{count} products updated")
    }
  end

  @impl true
  def handle_info({:removed_products, category, products}, socket) do
    count = Enum.count(products)
    Logger.info(module: __MODULE__, event: :removed_products, count: count)

    {:noreply,
      schedule_product_push(:remove, category, products, socket)
      |> put_flash(:error, "#{count} products removed from category")
    }
  end

  @impl true
  def handle_info(:push, %{assigns: %{category: category, update_queue: update_queue}} = socket) do
    # NOTE: This will push updates to the client faster than it can render them.
    # This design would require a back-pressure mechanic.
    # For example, the client could notify the server when it has handled an update.
    # I'm not sure if that can be build on top of LiveView or should a Channel be used for that instead.
    case :queue.out(update_queue) do
      {{:value, {action, cat, products}}, update_queue} ->
        socket =
          case {cat == category, action} do
            {true, :append} -> assign(socket, products: products)
            {true, :remove} ->
              products = Enum.map(products, &Map.put(&1, :deleted, true)) # mark product deleted
              assign(socket, products: products)
            {false, _} -> socket
          end
        if not :queue.is_empty(update_queue) do
          send(self(), :push)
        end
        {:noreply, assign(socket, update_queue: update_queue)}

      {:empty, _} ->
        {:noreply, socket}
    end
  end

  defp schedule_product_push(action, category, products, %{assigns: %{update_queue: update_queue}} = socket) do
    if :queue.is_empty(update_queue) do
      send(self(), :push)
    end
    update_queue =
      products
      |> (& [&1]).() # use single chunk for now, see NOTE in handle_info(:push
      #|> Enum.chunk_every(1000)
      |> Enum.reduce(update_queue, fn chunk, queue ->
        :queue.in({action, category, chunk}, queue)
      end)
    assign(socket, update_queue: update_queue)
  end
end
