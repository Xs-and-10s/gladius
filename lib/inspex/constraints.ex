defmodule Inspex.Constraints do
  @moduledoc """
  Evaluates a keyword list of named constraints against a value that has
  already passed its type check.

  Named constraints are the key difference between `string(:filled?)` and
  `spec(fn s -> s != "" end)`: the named form is introspectable by the
  generator in Step 4, enabling automatic test data production.

  ## Constraint catalogue

  ### Universal
  - `:filled?` — value must be non-empty (string, list, or map) and non-nil

  ### Numeric (`integer`, `float`, `number`)
  - `gt?: n`  — value > n
  - `gte?: n` — value >= n
  - `lt?: n`  — value < n
  - `lte?: n` — value <= n

  ### Strings
  - `min_length: n` — byte_size >= n
  - `max_length: n` — byte_size <= n
  - `format: ~r/regex/` — must match regex

  ### Collections (strings and lists)
  - `size?: n` — exactly n characters / elements

  ### Enumerations
  - `in?: [values]` — value must be a member of the list

  ## Extensibility

  Unknown constraints are silently ignored so user-defined constraint
  *names* can be layered on top without forking the library. In Step 4,
  custom constraint → generator mappings will be registerable via
  `Inspex.Constraints.register_generator/2`.
  """

  alias Inspex.Error

  @type constraint :: {atom(), term()}

  @spec check(term(), keyword()) :: [Error.t()]
  def check(value, constraints) when is_list(constraints) do
    Enum.flat_map(constraints, &check_one(value, &1))
  end

  # ---------------------------------------------------------------------------
  # Individual constraint checkers
  # ---------------------------------------------------------------------------

  defp check_one(value, {:filled?, true}), do: check_filled(value)
  defp check_one(_value, {:filled?, false}), do: []                  # filled?: false is a no-op

  defp check_one(value, {:gt?, n}),        do: check_gt(value, n)
  defp check_one(value, {:gte?, n}),       do: check_gte(value, n)
  defp check_one(value, {:lt?, n}),        do: check_lt(value, n)
  defp check_one(value, {:lte?, n}),       do: check_lte(value, n)

  defp check_one(value, {:min_length, n}), do: check_min_length(value, n)
  defp check_one(value, {:max_length, n}), do: check_max_length(value, n)
  defp check_one(value, {:size?, n}),      do: check_size(value, n)

  defp check_one(value, {:format, regex}), do: check_format(value, regex)
  defp check_one(value, {:in?, values}),   do: check_in(value, values)

  # Unknown constraint — ignored for extensibility
  defp check_one(_value, _unknown), do: []

  # ---------------------------------------------------------------------------

  defp check_filled(""),                                  do: [err(:filled?, "",  "must be filled")]
  defp check_filled([]),                                  do: [err(:filled?, [],  "must be filled")]
  defp check_filled(%{} = m) when map_size(m) == 0,       do: [err(:filled?, %{}, "must be filled")]
  defp check_filled(nil),                                 do: [err(:filled?, nil, "must be filled")]
  defp check_filled(_),                                   do: []

  defp check_gt(v, n) when is_number(v) and v > n,        do: []
  defp check_gt(v, n) when is_number(v),                  do: [err(:gt?,  v, "must be greater than #{n}")]
  defp check_gt(v, _),                                    do: [err(:gt?,  v, "must be a number")]

  defp check_gte(v, n) when is_number(v) and v >= n,      do: []
  defp check_gte(v, n) when is_number(v),                 do: [err(:gte?, v, "must be >= #{n}")]
  defp check_gte(v, _),                                   do: [err(:gte?, v, "must be a number")]

  defp check_lt(v, n) when is_number(v) and v < n,        do: []
  defp check_lt(v, n) when is_number(v),                  do: [err(:lt?,  v, "must be less than #{n}")]
  defp check_lt(v, _),                                    do: [err(:lt?,  v, "must be a number")]

  defp check_lte(v, n) when is_number(v) and v <= n,      do: []
  defp check_lte(v, n) when is_number(v),                 do: [err(:lte?, v, "must be <= #{n}")]
  defp check_lte(v, _),                                   do: [err(:lte?, v, "must be a number")]

  defp check_min_length(v, n) when is_binary(v) do
    if byte_size(v) >= n, do: [], else: [err(:min_length, v, "must be at least #{n} characters")]
  end
  defp check_min_length(v, n) when is_list(v) do
    if length(v) >= n, do: [], else: [err(:min_length, v, "must have at least #{n} items")]
  end
  defp check_min_length(v, _), do: [err(:min_length, v, "must be a string or list")]

  defp check_max_length(v, n) when is_binary(v) do
    if byte_size(v) <= n, do: [], else: [err(:max_length, v, "must be at most #{n} characters")]
  end
  defp check_max_length(v, n) when is_list(v) do
    if length(v) <= n, do: [], else: [err(:max_length, v, "must have at most #{n} items")]
  end
  defp check_max_length(v, _), do: [err(:max_length, v, "must be a string or list")]

  defp check_size(v, n) when is_binary(v) do
    if byte_size(v) == n, do: [], else: [err(:size?, v, "must be exactly #{n} characters")]
  end
  defp check_size(v, n) when is_list(v) do
    if length(v) == n, do: [], else: [err(:size?, v, "must have exactly #{n} items")]
  end
  defp check_size(v, _), do: [err(:size?, v, "must be a string or list")]

  defp check_format(v, %Regex{} = r) when is_binary(v) do
    if Regex.match?(r, v), do: [], else: [err(:format, v, "must match format #{inspect(r)}")]
  end
  defp check_format(v, _), do: [err(:format, v, "must be a string")]

  defp check_in(v, values) when is_list(values) do
    if v in values,
      do: [],
      else: [err(:in?, v, "must be one of #{inspect(values)}")]
  end

  # ---------------------------------------------------------------------------

  defp err(pred, value, message) do
    %Inspex.Error{predicate: pred, value: value, message: message}
  end
end
