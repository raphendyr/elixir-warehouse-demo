defmodule Warehouse.ChangesetHelpers do
  import Ecto.Changeset

  require Logger

  def changeset_errors(changeset) do
    traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  def changeset_error_to_string(changeset) do
    changeset_errors(changeset)
    |> Enum.map(fn {field, errors} ->
      errors_str = Enum.join(errors, "; ")
      "  - #{field}: #{errors_str}\n"
    end)
    |> Enum.join("")
  end
end
