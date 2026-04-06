defmodule Gladius.Default do
  @moduledoc """
  Wraps any Gladius conformable with a fallback value used when an optional
  schema key is absent.

  ## Semantics

  - **Key absent**: the fallback `value` is injected directly — inner spec
    not run. The value is assumed correct.
  - **Key present**: the inner `spec` is run against the provided value
    normally. An invalid provided value returns an error; the default does
    not rescue it.
  - **Required key**: a `default/2` on a required key has no effect on
    absence behaviour.

  ## Usage

      schema(%{
        required(:name) => string(:filled?),
        optional(:role) => default(one_of([:admin, :user, :guest]), :user),
        optional(:retries) => default(integer(gte?: 0), 3)
      })

  See `Gladius.default/2` for construction.
  """

  @enforce_keys [:spec, :value]
  defstruct [:spec, :value, :message]

  @type t :: %__MODULE__{
          spec:    Gladius.conformable(),
          value:   term(),
          message: Gladius.Spec.message()
        }
end
