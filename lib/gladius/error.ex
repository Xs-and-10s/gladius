defmodule Gladius.Error do
  @moduledoc """
  A single validation failure, with a dot-traversable path to the offending
  value.

  ## Fields

  - `:path` — list of atom keys and integer indices tracing from the root of
    the validated value to the failure site. Empty for root-level failures.
  - `:predicate` — the name of the named constraint or check that failed.
    `nil` for arbitrary-predicate specs.
  - `:value` — the actual value that failed (after any coercions).
  - `:message` — a human-readable description, already translated if a
    `Gladius.Translator` is configured.
  - `:message_key` — the untranslated predicate key, useful for custom
    renderers and i18n. `nil` for user-supplied messages.
  - `:message_bindings` — keyword list of dynamic values used in the message,
    e.g. `[min: 18]` for a `gte?` failure. Empty for opaque errors.
  - `:meta` — open map for extra context.

  ## String representation

      iex> to_string(%Gladius.Error{path: [:user, :age], message: "must be >= 18"})
      ":user.:age: must be >= 18"

      iex> to_string(%Gladius.Error{path: [], message: "must be a map"})
      "must be a map"
  """

  @type t :: %__MODULE__{
          path:             [atom() | non_neg_integer()],
          predicate:        atom() | nil,
          value:            term(),
          message:          String.t(),
          message_key:      atom() | nil,
          message_bindings: keyword(),
          meta:             map()
        }

  defstruct [
    path:             [],
    predicate:        nil,
    value:            nil,
    message:          "",
    message_key:      nil,
    message_bindings: [],
    meta:             %{}
  ]

  defimpl String.Chars do
    def to_string(%Gladius.Error{path: [], message: msg}), do: msg

    def to_string(%Gladius.Error{path: path, message: msg}) do
      formatted =
        path
        |> Enum.map(fn
          key when is_atom(key)    -> inspect(key)
          idx when is_integer(idx) -> "[#{idx}]"
          other                    -> inspect(other)
        end)
        |> Enum.join(".")

      "#{formatted}: #{msg}"
    end
  end
end

# ---------------------------------------------------------------------------

defmodule Gladius.ExplainResult do
  @moduledoc """
  The structured result of `Gladius.explain/2`.

  ## Fields

  - `:valid?` — `true` if the value conformed to the spec.
  - `:value` — the shaped value on success, the original value on failure.
  - `:errors` — list of `Gladius.Error.t()`. Empty on success.
  - `:formatted` — a pre-rendered newline-delimited string. `"ok"` on success.
  """

  @type t :: %__MODULE__{
          valid?:    boolean(),
          value:     term(),
          errors:    [Gladius.Error.t()],
          formatted: String.t()
        }

  defstruct [:valid?, :value, errors: [], formatted: ""]
end
