defmodule Gladius.Transform do
  @moduledoc """
  Wraps any Gladius conformable with a post-validation transformation function.

  ## Semantics

  The pipeline is: `raw → conform(inner_spec) → fun.(shaped) → {:ok, result}`.

  - **Validation fails** → `{:error, errors}` is returned immediately; `fun` is
    never called. A transform never rescues invalid data.
  - **Validation passes** → `fun.(shaped_value)` is called. Its return value
    becomes the final `:ok` result.
  - **`fun` raises** → the exception is caught and surfaced as a
    `%Gladius.Error{predicate: :transform}`. The caller gets
    `{:error, [%Gladius.Error{message: "transform failed: ..."}]}`.

  ## Usage

      import Gladius

      email_spec = transform(string(:filled?, format: ~r/@/), &String.downcase/1)
      name_spec  = transform(string(:filled?), &String.trim/1)

      schema(%{
        required(:email) => email_spec,
        required(:name)  => name_spec
      })

  `transform/2` accepts any conformable as its inner spec:

      # Transform on a schema
      transform(schema(%{required(:x) => integer()}), fn m -> Map.put(m, :y, m.x * 2) end)

      # Chained — trim then downcase
      transform(transform(string(:filled?), &String.trim/1), &String.downcase/1)

  See `Gladius.transform/2` for construction.
  """

  @enforce_keys [:spec, :fun]
  defstruct [:spec, :fun]

  @type t :: %__MODULE__{
          spec: Gladius.conformable(),
          fun: (term() -> term())
        }
end
