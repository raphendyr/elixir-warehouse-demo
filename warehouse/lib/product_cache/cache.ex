defmodule ProductCache.Cache do
  use GenServer

  alias Ecto.Changeset
  alias ProductCache.Downloader
  alias Warehouse.Products.Product

  require Logger

  #@cache_time 5 * 60 * 1_000 # 5 minutes in milliseconds
  @cache_time 20 * 1_000 # 20 seconds in milliseconds


  # API

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end


  # Callbacks

  @impl true
  def init(_args) do
    # TODO: use supervisor and allocate downloader dynamically
    for i <- 0..10 do
      {:ok, _pid} = Downloader.start_link(name: "Worker#{i}", queue: self())
    end

    state = %{
      # workers
      ready_downloaders: :queue.new,
      request_queue: :queue.new,
      # cache times
      categories: [], # [{category, next_update}, ...]
      availability: [], # [{manufacturer, next_update}, ...]
      products: %{}, # %{id => %Product{}, ...}
      # other
      waiting: %{}, # %{request => [waiting call requests]}
      update_timers: %{}, # %{request => send_after_ref}
    }
    {:ok, state}
  end

  # Calls from the application

  @impl true
  def handle_call(:categories, from, %{categories: categories} = state) do
    Logger.info(module: __MODULE__, request: :categories)
    case categories do
      [] -> {:noreply, reply_after_update(from, :categories, state)}
      _ -> {:reply, {:ok, categories(state)}, state}
    end
  end

  @impl true
  def handle_call({:products, category}, from, %{categories: categories} = state) do
    Logger.info(module: __MODULE__, request: {:products, category})
    case cache_time_elapsed?(categories, category) do
      :ok ->
        {:reply, {:ok, products(category, state)}, state}

      :elapsed ->
        {:noreply, reply_after_update(from, {:products, category}, state)}

      :missing ->
        {:reply, {:error, :unknown_category}, state}
    end
  end

  @impl true
  def handle_call({:product, id}, _from, %{products: products} = state) do
    Logger.info(module: __MODULE__, request: {:product, id})
    case Map.get(products, id) do
      %Product{} = product ->
        {:reply, {:ok, product}, state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # Replies from downloaders

  @impl true
  def handle_cast({:ready, downloader}, state) do
    {:noreply, downloader_ready(downloader, state)}
  end

  @impl true
  def handle_cast({:ready, downloader, :categories = request, categories},
                  %{categories: existing_categories} = state)
  do
    state = downloader_ready(downloader, state)

    now = System.monotonic_time()
    category_times =
      categories
      |> Enum.map(fn category ->
        case List.keyfind(existing_categories, category, 0) do
          {^category, next_update} -> {category, next_update}
          _ -> {category, now}
        end
      end)

    data_func = fn -> Enum.sort(categories) end
    state = reply_to_waiters(request, data_func, state)
    state = schedule_updater(request, @cache_time, state)
    {:noreply, %{state | categories: category_times}}
  end

  @impl true
  def handle_cast({:ready, downloader, {:products, category} = request, product_updates},
                  %{categories: categories, products: products} = state)
  do
    state = downloader_ready(downloader, state)

    update_delta = System.convert_time_unit(@cache_time, :millisecond, :native)
    next_update = System.monotonic_time() + update_delta
    categories = merge_cache_time(categories, category, next_update)
    state = %{state | categories: categories}

    # construct %Product{} structs from the update and merge with existing data
    # validates the update data
    updated =
      product_updates
      |> Enum.map(fn update ->
        old_or_new =
          case Map.get(products, update["id"]) do
            %Product{} = product -> product
            _ -> %Product{}
          end
        changeset = Product.changeset(old_or_new, update)
        if changeset.valid? do
          # NOTE: changeset.changes is empty if data is the same
          Changeset.apply_changes(changeset)
        else
          errors = Warehouse.ChangesetHelpers.changeset_errors(changeset)
          Logger.warn(module: __MODULE__, update: request, error: :invalid_data, errors: errors)
          nil
        end
      end)
      |> Enum.filter(& not is_nil(&1))

    # remove products for this category, which are not part of the update
    ids = updated |> Enum.map(& &1.id) |> MapSet.new
    products =
      products
      |> Enum.filter(fn {id, product} ->
        product.type != category || MapSet.member?(ids, id)
      end)
      |> Map.new

    # update products map
    products =
      Enum.reduce(updated, products, fn product, products ->
        Map.put(products, product.id, product)
      end)

    state = %{state | products: products}

    # check manufacturer updates
    manufacturers =
      updated
      |> Enum.reduce(MapSet.new, fn product, manufacturers ->
        MapSet.put(manufacturers, product.manufacturer)
      end)

    state = request_availability_updates(manufacturers, state)

    data_func = fn -> products(category, state) end
    state = reply_to_waiters(request, data_func, state)
    state = schedule_updater(request, @cache_time, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:ready, downloader, {:availability, manufacturer} = request, availability_updates},
                  %{availability: availability, products: products} = state)
  do
    state = downloader_ready(downloader, state)

    update_delta = System.convert_time_unit(trunc(@cache_time * 0.9), :millisecond, :native)
    next_update = System.monotonic_time() + update_delta
    availability = merge_cache_time(availability, manufacturer, next_update)
    state = %{state | availability: availability}

    updates =
      Enum.map(availability_updates, fn update ->
        old_or_new =
          case Map.get(products, update["id"]) do
            %Product{} = product -> product
            _ -> %Product{}
          end
        update = Map.put(update, "manufacturer", manufacturer)
        changeset = Product.availability_changeset(old_or_new, update)
        if changeset.valid? do
          if changeset.changes, do: changeset, else: nil
        else
          errors = Warehouse.ChangesetHelpers.changeset_errors(changeset)
          Logger.warn(module: __MODULE__, update: request, error: :invalid_data, errors: errors)
          nil
        end
      end)

    products =
      Enum.reduce(updates, products, fn changeset, products ->
        product = Changeset.apply_changes(changeset)
        Map.put(products, product.id, product)
      end)

    state = %{state | products: products}

    data_func = fn -> :availability_updated end
    state = reply_to_waiters(request, data_func, state)
    # TODO: emit updates to subscribers

    {:noreply, state}
  end

  @impl true
  def handle_cast({:error, downloader, request, reason}, state) do
    state = downloader_ready(downloader, state)
    Logger.warn(module: __MODULE__, message: "request update failed", request: request)
    state = reply_to_waiters(request, (fn -> {:error, reason} end), state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:self_update, request}, state) do
    # TODO: only if still relevant...
    {:noreply, reply_after_update(:self, request, state)}
  end


  # Private

  defp categories(%{categories: categories}) do
    categories
    |> Enum.map(fn {name, _} -> name end)
    |> Enum.sort()
  end

  defp products(category, %{products: products}) do
    Map.values(products)
    |> Enum.filter(fn product -> product.type == category end)
    |> Enum.sort_by(&(&1.name))
  end

  defp request_availability_updates(manufacturers, %{availability: availability} = state) do
    Enum.reduce(manufacturers, state, fn manufacturer, state ->
      case cache_time_elapsed?(availability, manufacturer) do
        res when res in [:elapsed, :missing] ->
          reply_after_update(:self, {:availability, manufacturer}, state)
        _ ->
          state
      end
    end)
  end


  ## Cache time management

  defp schedule_updater(request, after_ms, %{update_timers: timers} = state) do
    case timers do
      %{^request => _ref} ->
        state

      _ ->
        ref = Process.send_after(self(), {:self_update, request}, after_ms)
        timers = Map.put(timers, request, ref)
        %{state | update_timers: timers}
    end
  end

  defp cache_time_elapsed?(times, key) do
    case List.keyfind(times, key, 0) do
      nil -> :missing
      {^key, next_update} ->
        if next_update > System.monotonic_time(), do: :ok, else: :elapsed
    end
  end

  defp merge_cache_time(times, key, time) do
    times = List.keydelete(times, key, 0)
    keylist_insert(times, key, time)
  end

  # Inserts a key to a list, so that the list is kept sorted by the value.
  # In other words, the list is a min heap.
  # Because the list is always sorted, the insertion cost is O(n).
  defp keylist_insert([], key, value) do
    [{key, value}]
  end

  defp keylist_insert([{_, top} | _] = list, key, value) when value < top do
    [{key, value} | list]
  end

  defp keylist_insert([head | tail], key, value) do
    [head | keylist_insert(tail, key, value)]
  end


  ## Management for active GenServer.call requests
  # this is between the cache and the application

  defp reply_after_update(from, request, %{waiting: waiting} = state) do
    case waiting do
      %{^request => waiters} ->
        # update underway
        %{state | waiting: %{waiting | request => [from | waiters]}}

      %{} ->
        # no active update
        state = queue_or_handle_request(request, state)
        %{state | waiting: Map.put(waiting, request, [from])}
    end
  end

  defp reply_to_waiters(request, data_func, %{waiting: waiting} = state) do
    case Map.pop(waiting, request) do
      {nil, _} ->
        state

      {waiters, waiting} ->
        data = data_func.()
        for from <- waiters do
          if from != :self do
            GenServer.reply(from, {:ok, data})
          end
        end
        %{state | waiting: waiting}
    end
  end


  ## Request queue management, i.e., task queue for downloaders
  # this is between the cache and downloaders

  defp queue_or_handle_request(request, %{ready_downloaders: downloaders, request_queue: requests} = state) do
    if :queue.is_empty(requests) and not :queue.is_empty(downloaders) do
      {{:value, downloader}, downloaders} = :queue.out(downloaders)
      :ok = GenServer.cast(downloader, {request, self()})
      %{state | ready_downloaders: downloaders}
    else
      %{state | request_queue: :queue.in(request, requests)}
    end
  end

  defp downloader_ready(downloader, %{ready_downloaders: downloaders, request_queue: requests} = state) do
    downloaders = :queue.in(downloader, downloaders)
    {downloaders, requests} = feed_downloaders(downloaders, requests)
    %{state | ready_downloaders: downloaders, request_queue: requests}
  end

  #defp feed_downloaders(%{ready_downloaders: downloaders, request_queue: requests} = state) do
  #  {downloaders, requests} = feed_downloaders(downloaders, requests)
  #  %{state | ready_downloaders: downloaders, request_queue: requests}
  #end

  defp feed_downloaders(downloaders, requests) do
    if not :queue.is_empty(downloaders) and not :queue.is_empty(requests) do
      {{:value, downloader}, downloaders} = :queue.out(downloaders)
      {{:value, request}, requests} = :queue.out(requests)
      :ok = GenServer.cast(downloader, {request, self()})
      feed_downloaders(downloaders, requests)
    else
      {downloaders, requests}
    end
  end
end
