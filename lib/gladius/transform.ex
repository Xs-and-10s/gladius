defmodule Gladius.Transform do
  @moduledoc """
  Wraps any Gladius conformable with a post-validation transformation function.

  ## Semantics

  - **Validation fails** → `{:error, errors}` returned immediately; `fun`
    never called.
  - **Validation passes** → `fun.(shaped_value)` called. Its return value
    becomes the final `:ok` result.
  - **`fun` raises** → exception caught and surfaced as
    `%Gladius.Error{predicate: :transform}`.

  ## Usage

      import Gladius

      email_spec = transform(string(:filled?, format: ~r/@/), &String.downcase/1)
      name_spec  = transform(string(:filled?), &String.trim/1)

      # With custom message
      transform(string(:filled?), &String.trim/1, message: "name could not be normalised")

  See `Gladius.transform/2-3` for construction.
  """

  @enforce_keys [:spec, :fun]
  defstruct [:spec, :fun, :message]

  @type t :: %__MODULE__{
          spec:    Gladius.conformable(),
          fun:     (term() -> term()),
          message: Gladius.Spec.message()
        }
end
