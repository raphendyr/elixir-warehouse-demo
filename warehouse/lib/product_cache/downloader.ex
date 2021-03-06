defmodule ProductCache.Downloader do
  use GenServer

  require Logger

  alias ProductCache.ApiClient


  # API

  def start_link(args) do
    {name, args} = Keyword.pop(args, :name)
    name = to_string(__MODULE__) <> "." <> name |> String.to_atom
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init([queue: queue]) do
    {:ok, client} = ApiClient.new()
    :ok = GenServer.cast(queue, {:ready, self()})
    {:ok, %{
      client: client,
      queue: queue,
    }}
  end


  # Callbacks

  @impl true
  def handle_cast({:categories = request, cache}, %{client: client} = state) do
    Logger.info(module: __MODULE__, request: request, status: :started)
    result = ApiClient.categories(client)
    send_result(cache, request, result)
    {:noreply, state}
  end

  @impl true
  def handle_cast({{:products, category} = request, cache}, %{client: client} = state) do
    Logger.info(module: __MODULE__, request: request, status: :started)
    result = ApiClient.products(category, client)
    send_result(cache, request, result)
    {:noreply, state}
  end

  @impl true
  def handle_cast({{:availability, manufacturer} = request, cache}, %{client: client} = state) do
    Logger.info(module: __MODULE__, request: request, status: :started)
    result = ApiClient.availability(manufacturer, client)
    send_result(cache, request, result)
    {:noreply, state}
  end

  # ignore Gun events, when they arrive outside of get()

  @impl true
  def handle_info({:gun_down, _, _, _, _}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_up, _, _, _}, state) do
    {:noreply, state}
  end

  @doc false
  # reimplement hanle_info fallback function, which logs missed messages
  def handle_info(msg, state) do
    proc =
      case Process.info(self(), :registered_name) do
        {_, []} -> self()
        {_, name} -> name
      end

    :logger.error(
      %{label: {GenServer, :no_handle_info}, report: %{module: __MODULE__, message: msg, name: proc}},
      %{domain: [:otp, :elixir], error_logger: %{tag: :error_msg}, report_cb: &GenServer.format_report/1}
    )

    {:noreply, state}
  end

  defp send_result(cache, request, result) do
    case result do
      {:ok, data} ->
        if is_list(data) do
          Logger.info(module: __MODULE__, request: request, status: :ok, datasize: Enum.count(data))
        else
          Logger.info(module: __MODULE__, request: request, status: :ok, data: data)
        end
        GenServer.cast(cache, {:ready, self(), request, data})

      {:error, reason} ->
        Logger.info(module: __MODULE__, request: request, status: :error, reason: reason)
        GenServer.cast(cache, {:error, self(), request, reason})
    end
  end
end
