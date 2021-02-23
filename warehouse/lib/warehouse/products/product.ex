defmodule Warehouse.Products.Product do
  use Ecto.Schema

  import Ecto.Changeset

  require Logger

  # {
  #   "id": "88f4509301855f214f",
  #   "type": "beanies",
  #   "name": "REVNYDAL BANG",
  #   "color": [
  #     "green"
  #   ],
  #   "price": 16,
  #   "manufacturer": "niksleh"
  # }

  @primary_key false

  embedded_schema do
    field :id, :string
    field :type, :string
    field :name, :string
    field :color, {:array, :string}
    field :price, :integer
    field :manufacturer, :string
    field :availability, :string, default: ""
  end

  def changeset(product, params \\ %{}) do
    product
    |> cast(params, [:id, :type, :name, :color, :price, :manufacturer])
    |> validate_required([:id, :type, :name, :price, :manufacturer])
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_not_changed(:id)
  end

  def availability_changeset(product, params \\ %{}) do
    product
    |> cast(params, [:id, :availability, :manufacturer])
    |> validate_required([:id, :manufacturer])
    |> validate_not_changed(:id)
    |> validate_not_changed(:manufacturer)
  end

  defp validate_not_changed(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      old = Map.get(changeset.data, field)
      if is_bitstring(old) and is_bitstring(value) and old != value do
        [{field, "can't be changed"}]
      else
        []
      end
    end)
  end
end
