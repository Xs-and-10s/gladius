defmodule Inspex.SignatureError do
  @moduledoc """
  Raised by `Inspex.Signature` when a function call violates its declared
  signature in `:dev` or `:test` environments.

  Never raised in `:prod` — signatures compile away to zero overhead.

  ## Fields

  - `:module`    — the module containing the violating function
  - `:function`  — function name (atom)
  - `:arity`     — function arity (integer)
  - `:kind`      — `:args`, `:ret`, or `:fn`
  - `:arg_index` — 0-based index of the failing argument (`:args` violations only)
  - `:value`     — the value that failed conformance
  - `:errors`    — `[%Inspex.Error{}]` from `Inspex.conform/2`
  """

  defexception [:module, :function, :arity, :kind, :arg_index, :value, errors: []]

  @impl true
  def message(%{kind: :args} = e) do
    formatted = format_errors(e.errors)
    "#{mfa(e)} argument[#{e.arg_index}] #{inspect(e.value)} failed:\n  #{formatted}"
  end

  def message(%{kind: :ret} = e) do
    formatted = format_errors(e.errors)
    "#{mfa(e)} return value #{inspect(e.value)} failed:\n  #{formatted}"
  end

  def message(%{kind: :fn} = e) do
    formatted = format_errors(e.errors)
    "#{mfa(e)} :fn relationship constraint failed:\n  #{formatted}"
  end

  defp mfa(%{module: m, function: f, arity: a}), do: "#{inspect(m)}.#{f}/#{a}"

  defp format_errors(errors) do
    Enum.map_join(errors, "\n  ", &to_string/1)
  end
end
