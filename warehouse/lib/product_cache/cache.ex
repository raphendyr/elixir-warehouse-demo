defmodule ProductCache.Cache do
  use GenServer

  alias Phoenix.PubSub
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
      # internal database (TODO: replace with ETS)
      products: %{}, # %{id => %Product{}, ...}
      # workers
      ready_downloaders: :queue.new,
      request_queue: :queue.new,
      # cache times
      categories: [], # [{category, next_update}, ...]
      availability: [], # [{manufacturer, next_update}, ...]
      # list of waiters, i.e., what messages to send when updates are received
      waiting: %{}, # %{request => [waiting call requests]}
      # automatic updates
      update_timers: %{}, # %{request => send_after_ref}
      monitors: %{}, # %{pid => monitor_ref}
      last_heartbeat: System.monotonic_time(),
    }
    {:ok, state}
  end

  # Calls from the application

  @impl true
  def handle_call(:categories, from, %{categories: categories} = state) do
    Logger.info(module: __MODULE__, call: :categories)
    state = heartbeat(state)
    case categories do
      [] -> {:noreply, reply_after_update({:reply, from}, :categories, state)}
      _ -> {:reply, {:ok, categories(state)}, state}
    end
  end

  @impl true
  def handle_call({:products, category}, from, %{categories: categories} = state) do
    Logger.info(module: __MODULE__, call: {:products, category})
    state = heartbeat(state)
    case cache_time_elapsed?(categories, category) do
      :ok ->
        {:reply, {:ok, products(category, state)}, state}

      :elapsed ->
        {:noreply, reply_after_update({:reply, from}, {:products, category}, state)}

      :missing ->
        {:reply, {:error, :unknown_category}, state}
    end
  end

  @impl true
  def handle_call({:product, id}, _from, %{products: products} = state) do
    Logger.info(module: __MODULE__, call: {:product, id})
    state = heartbeat(state)
    case Map.get(products, id) do
      %Product{} = product ->
        {:reply, {:ok, product}, state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_cast({:categories, pid}, %{categories: categories} = state) do
    Logger.info(module: __MODULE__, cast: :categories, pid: pid)
    state = monitor_client(pid, state)
    async_reply(pid, :categories, categories(state))
    if Enum.empty? categories do
      {:noreply, reply_after_update({:async, pid}, :categories, state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:products, category, pid}, %{categories: categories} = state) do
    request = {:products, category}
    Logger.info(module: __MODULE__, cast: request, pid: pid)
    state = monitor_client(pid, state)
    async_reply(pid, request, products(category, state))
    if cache_time_elapsed?(categories, category) == :elapsed do
      {:noreply, reply_after_update({:async, pid}, {:products, category}, state)}
    else
      {:noreply, state}
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

    # record the time of cache expiration
    update_delta = System.convert_time_unit(@cache_time, :millisecond, :native)
    next_update = System.monotonic_time() + update_delta
    categories = merge_cache_time(categories, category, next_update)
    state = %{state | categories: categories}

    # Generate changesets and validate
    updated_products =
      product_updates
      |> product_changesets(products)
      |> Enum.filter(fn
        {:changeset, _} -> true
        {:product, _} -> true
        {:error, errors} ->
          Logger.warn(module: __MODULE__, update: request, error: :invalid_data, errors: errors)
          false
      end)
      |> Enum.map(fn
        {:changeset, cs} -> {:changed, Changeset.apply_changes(cs)}
        {:product, product} -> {:existing, product}
      end)
    changed_products =
      updated_products
      |> Enum.filter(fn
        {:changed, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {_, product} -> product end)

    # remove products for this category, which are not part of the update
    ids =
      Enum.reduce(updated_products, MapSet.new, fn {_, product}, acc ->
        MapSet.put(acc, product.id)
      end)
    {removed_products, products} =
      products
      |> Enum.split_with(fn {id, p} -> p.type == category and not MapSet.member?(ids, id) end)
      |> (fn {removed, kept} ->
        {Enum.map(removed, &elem(&1, 1)), Map.new(kept)}
      end).()

    if not Enum.empty?(removed_products) do
      Logger.warn(module: __MODULE__, update: request, removed_count: Enum.count(removed_products))
    end

    # update products Map
    products = Enum.reduce(changed_products, products, &Map.put(&2, &1.id, &1))
    state = %{state | products: products}

    # check manufacturer updates
    manufacturers =
      updated_products
      |> Enum.reduce(MapSet.new, fn {_, product}, acc ->
        MapSet.put(acc, product.manufacturer)
      end)
      |> MapSet.to_list
    state = request_availability_updates(manufacturers, state)

    # reply to waiters
    data_func = fn -> products(category, state) end
    state = reply_to_waiters(request, data_func, state)

    # broadcast updated products
    changed_products
    |> Enum.group_by(& &1.type)
    |> Enum.each(fn {category, products} ->
      PubSub.broadcast(Warehouse.PubSub, "products:#{category}",
        {:updated_products, category, products})
    end)

    # broadcast removed products
    removed_products
    |> Enum.group_by(& &1.type)
    |> Enum.each(fn {category, products} ->
      PubSub.broadcast(Warehouse.PubSub, "products:#{category}",
        {:removed_products, category, products})
    end)

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

    # Generate changesets, validate and produce changed products
    changed_products =
      availability_updates
      |> Enum.map(&Map.put(&1, "manufacturer", manufacturer))
      |> product_changesets(products, &Product.availability_changeset/2)
      |> Enum.filter(fn
        {:changeset, _} -> true
        {:product, _} -> false
        {:error, errors} ->
          Logger.warn(module: __MODULE__, update: request, error: :invalid_data, errors: errors)
          false
      end)
      |> Enum.map(fn {:changeset, cs} -> Changeset.apply_changes(cs) end)

    # update products Map
    products = Enum.reduce(changed_products, products, &Map.put(&2, &1.id, &1))
    state = %{state | products: products}

    data_func = fn -> :availability_updated end
    state = reply_to_waiters(request, data_func, state)

    # broadcast updated products
    changed_products
    |> Enum.group_by(& &1.type)
    |> Enum.each(fn {category, products} ->
      PubSub.broadcast(Warehouse.PubSub, "products:#{category}",
        {:updated_products, category, products})
    end)

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
  def handle_info({:self_update, request}, %{update_timers: timers} = state) do
    state = %{state | update_timers: Map.delete(timers, request)}
    if has_listeners?(state) do
      Logger.info(module: __MODULE__, action: :self_update, request: request)
      state = reply_after_update(:self, request, state)
      {:noreply, state}
    else
      Logger.info(module: __MODULE__, action: :self_update, status: :stopping)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _}, %{monitors: monitors} = state) do
    monitors =
      case Map.pop(monitors, pid) do
        {^ref, monitors} ->
          monitors

        {monitor_ref, monitors} ->
          Logger.warn(module: __MODULE__, action: :demonitor, message: "Wrong monitor ref. DOWN event for #{pid} with #{ref}, but expected #{monitor_ref}")
          monitors

        nil ->
          Logger.warn(module: __MODULE__, action: :demonitor, message: "DOWN event for unknown pid #{pid} with #{ref}")
          monitors
      end
    {:noreply, %{state | monitors: monitors}}
  end


  ## Monitoring listeners/waiters to know when to suspend automatic updates

  defp has_listeners?(%{monitors: monitors, last_heartbeat: last_heartbeat}) do
    if not Enum.empty?(monitors) do
      true
    else
      last_heartbeat_ago =
        System.monotonic_time() - last_heartbeat
        |> System.convert_time_unit(:native, :millisecond)
      last_heartbeat_ago < @cache_time * 2
    end
  end

  defp monitor_client(pid, %{monitors: monitors} = state) do
    %{state | monitors:
      if Map.has_key?(monitors, pid) do
        monitors
      else
        ref = Process.monitor(pid)
        Map.put(monitors, pid, ref)
      end
    }
  end

  defp heartbeat(state) do
    %{state | last_heartbeat: System.monotonic_time()}
  end


  ## Private

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

  defp product_changesets(updates, products, new_changeset \\ &Product.changeset/2) do
    Enum.map(updates, fn update ->
      old_or_new = Map.get(products, update["id"], %Product{})
      changeset = new_changeset.(old_or_new, update)
      if changeset.valid? do
        if not Enum.empty?(changeset.changes) do
          {:changeset, changeset}
        else
          {:product, changeset.data}
        end
      else
        errors = Warehouse.ChangesetHelpers.changeset_errors(changeset)
        {:error, errors}
      end
    end)
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
        Enum.each(waiters, fn
          :self -> nil
          {:reply, from} -> GenServer.reply(from, {:ok, data})
          {:async, pid} -> async_reply(pid, request, data)
        end)
        %{state | waiting: waiting}
    end
  end

  defp async_reply(pid, :categories, categories) do
    send(pid, {:categories, categories})
  end

  defp async_reply(pid, {:products, category}, products) do
    send(pid, {:products, category, products})
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
