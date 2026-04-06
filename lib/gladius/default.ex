defmodule Gladius.Default do
  @moduledoc """
  Wraps any Gladius conformable with a fallback value used when an optional
  schema key is absent.

  ## Semantics

  - **Key absent** from the parent `schema/1` or `open_schema/1` map: the
    fallback `value` is injected directly into the output *without* running
    the inner spec. The value is assumed correct — validating it on every
    call would be redundant and would break the common pattern of using a
    compile-time literal that you know is valid.

  - **Key present**: the inner `spec` is run against the provided value
    normally. The fallback is ignored. An invalid provided value returns an
    error — the default does **not** rescue it.

  - **Required key**: a `default/2` on a required key has no effect on
    absence behaviour. Required keys that are absent always produce a
    missing-key error. The `default/2` wrapper is still meaningful for type
    documentation purposes.

  ## Usage

      import Gladius

      schema(%{
        required(:name) => string(:filled?),
        optional(:role) => default(one_of([:admin, :user, :guest]), :user),
        optional(:retries) => default(integer(gte?: 0), 3)
      })

  See `Gladius.default/2` for construction.
  """

  @enforce_keys [:spec, :value]
  defstruct [:spec, :value]

  @type t :: %__MODULE__{
          spec: Gladius.conformable(),
          value: term()
        }
end
