defmodule ProductCache.ApiClient do
  use Tesla, only: [:get], docs: false

  require Logger

  alias Tesla.Adapter.Gun

  adapter Gun,
    timeout: 8_000,
    connection_timeout: 5_000

  plug Tesla.Middleware.Telemetry
  plug Tesla.Middleware.FollowRedirects
  plug Tesla.Middleware.Headers, [
    {"user-agent", "raphendyr-warehouse/0.1.0"},
    {"accept", "application/json"},
  ]

  plug Tesla.Middleware.Retry,
    delay: 500,
    max_retries: 10,
    max_delay: 5_000,
    should_retry: fn
      {:ok, %{status: status}} when status != 200 -> true
      {:ok, %{body: body}} when is_bitstring(body) -> true
      {:ok, _} -> false
      {:error, _} -> true
    end

  #plug Tesla.Middleware.BaseUrl, "https://bad-api-assignment.reaktor.com"
  plug Tesla.Middleware.BaseUrl, "http://127.0.0.1:5000/"
  plug Tesla.Middleware.JSON

  def new() do
    {:ok, %{}}
  end

  def categories(_client) do
    {:ok, [
      "gloves",
      "facemasks",
      "beanies",
    ]}
  end

  def manufacturers(_client) do
    {:ok, [
      "abiplos",
      "hennex",
      "juuran",
      "laion",
      "niksleh",
      "okkau"
    ]}
  end

  def products(category, _client) do
    with {:ok, products} <- get_json("/v2/products/" <> category),
         products <- downcase_id(products)
    do
      {:ok, products}
    end
  end

  def availability(manufacturer, _client) do
    with {:ok, response} <- get_json("/v2/availability/" <> manufacturer),
         {:ok, availability} <- availability_from_api_response(response),
         availability <- resolve_instock_values(availability),
         availability <- downcase_id(availability)
    do
      {:ok, availability}
    end
  end

  defp availability_from_api_response(response) do
    case response do
      %{"code" => code, "response" => availability}
      when code == 200 and is_list(availability) ->
        {:ok, availability}

      _ ->
        {:error, :invalid_response}
    end
  end

  defp resolve_instock_values(availability) do
    for item <- availability do
      case Map.get(item, "id") do
        nil -> nil
        "" -> nil
        id ->
          case parse_instock(item) do
            {:ok, instock} ->
              %{"id" => id, "availability" => instock}

            {:error, reason} ->
              Logger.warn(module: __MODULE__, func: :availability, id: id, error: reason)
              nil
          end
      end
    end
    |> Enum.filter(& not is_nil(&1))
  end

  defp parse_instock(item) do
    # <AVAILABILITY>
    #   <CODE>200</CODE>
    #   <INSTOCKVALUE>INSTOCK</INSTOCKVALUE>
    # </AVAILABILITY>
    with {:ok, payload} <- parse_instock_payload(item),
         {:ok, root, _tail} <- :erlsom.simple_form(payload),
         {:ok, children} <- parse_instock_children(root),
         :ok <- parse_instock_code(children),
         {:ok, instock} <- parse_instock_value(children)
    do
      {:ok, instock}
    end
  end

  defp parse_instock_payload(item) do
    case item do
      %{"DATAPAYLOAD" => payload} -> {:ok, payload}
      _ -> {:error, {:invalid_data, :payload_missing}}
    end
  end

  defp parse_instock_children(root) do
    case root do
      {'AVAILABILITY', _attrs, children} -> {:ok, children}
      _ -> {:error, {:invalid_data, :root_not_found, root}}
    end
  end

  defp parse_instock_code(children) do
    case List.keyfind(children, 'CODE', 0) do
      {_name, _atrrs, [code]} when code == '200' -> :ok
      nil -> {:error, {:invalid_data, :code_not_ok}}
    end
  end

  defp parse_instock_value(children) do
    case List.keyfind(children, 'INSTOCKVALUE', 0) do
      {_name, _atrrs, [value]} -> {:ok, to_string(value)}
      nil -> {:error, {:invalid_data, :code_not_ok}}
    end
  end

  defp get_json(path) do
    case get(path) do
      {:ok, %{status: status, body: body}} when status == 200 and not is_bitstring(body) ->
        {:ok, body}

      {:ok, _} ->
        {:error, :invalid_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp downcase_id(list) do
    for item <- list do
      %{item | "id" => String.downcase(item["id"])}
    end
  end
end
