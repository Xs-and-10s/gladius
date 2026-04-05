defmodule Inspex.Coercions do
  @moduledoc """
  Built-in coercion functions for use with `Inspex.coerce/2`.

  All coercion functions have the signature:

      (term()) :: {:ok, term()} | {:error, String.t()}

  Coercions are idempotent by convention — if the value is already the target
  type, they return `{:ok, value}` unchanged. This means you don't need to
  special-case values that are already correct:

      Inspex.Coercions.string_to_integer(42)   #=> {:ok, 42}
      Inspex.Coercions.string_to_integer("42") #=> {:ok, 42}
      Inspex.Coercions.string_to_integer("x")  #=> {:error, "cannot coerce ..."}

  ## Using built-in coercions

      import Inspex

      coerce(integer(), from: :string)   # "42"     → 42
      coerce(float(),   from: :string)   # "3.14"   → 3.14
      coerce(boolean(), from: :string)   # "true"   → true
      coerce(atom(),    from: :string)   # "ok"     → :ok  (existing atoms only)

  ## Providing custom coercions

      coerce(integer(), fn
        v when is_binary(v) ->
          case Integer.parse(String.trim(v)) do
            {n, ""} -> {:ok, n}
            _       -> {:error, "not an integer string: \#{inspect(v)}"}
          end
        v when is_integer(v) -> {:ok, v}
        v -> {:error, "cannot coerce \#{inspect(v)} to integer"}
      end)
  """

  # ---------------------------------------------------------------------------
  # String → other types (the common case: HTTP params, form data, CSV)
  # ---------------------------------------------------------------------------

  @doc "Coerces a string to an integer. Passes integers through unchanged."
  @spec string_to_integer(term()) :: {:ok, integer()} | {:error, String.t()}
  def string_to_integer(v) when is_integer(v), do: {:ok, v}

  def string_to_integer(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> {:ok, n}
      _       -> {:error, ~s(cannot coerce #{inspect(v)} to integer)}
    end
  end

  def string_to_integer(v), do: {:error, "cannot coerce #{inspect(v)} to integer"}

  @doc "Coerces a string to a float. Passes floats and integers through unchanged."
  @spec string_to_float(term()) :: {:ok, float()} | {:error, String.t()}
  def string_to_float(v) when is_float(v),   do: {:ok, v}
  def string_to_float(v) when is_integer(v), do: {:ok, v * 1.0}

  def string_to_float(v) when is_binary(v) do
    case Float.parse(String.trim(v)) do
      {f, ""} -> {:ok, f}
      _       -> {:error, ~s(cannot coerce #{inspect(v)} to float)}
    end
  end

  def string_to_float(v), do: {:error, "cannot coerce #{inspect(v)} to float"}

  @doc """
  Coerces a string to a boolean. Passes booleans through unchanged.

  Truthy strings:  `"true"`, `"1"`, `"yes"`, `"on"`  (case-insensitive)
  Falsy strings:   `"false"`, `"0"`, `"no"`, `"off"` (case-insensitive)
  """
  @spec string_to_boolean(term()) :: {:ok, boolean()} | {:error, String.t()}
  def string_to_boolean(v) when is_boolean(v), do: {:ok, v}

  def string_to_boolean(v) when is_binary(v) do
    case String.downcase(String.trim(v)) do
      t when t in ~w(true 1 yes on)    -> {:ok, true}
      f when f in ~w(false 0 no off)   -> {:ok, false}
      _ -> {:error, ~s(cannot coerce #{inspect(v)} to boolean — expected true/false/yes/no/1/0/on/off)}
    end
  end

  def string_to_boolean(v), do: {:error, "cannot coerce #{inspect(v)} to boolean"}

  @doc """
  Coerces a string to an existing atom. Passes atoms through unchanged.

  Uses `String.to_existing_atom/1` — safe against atom table exhaustion.
  Fails if the atom has never been loaded into the VM (e.g., an atom that only
  exists in code not yet compiled or loaded).

  For enum-style fields, prefer `atom(in?: [...])` which ensures the atoms are
  always already loaded.
  """
  @spec string_to_atom(term()) :: {:ok, atom()} | {:error, String.t()}
  def string_to_atom(v) when is_atom(v), do: {:ok, v}

  def string_to_atom(v) when is_binary(v) do
    {:ok, String.to_existing_atom(v)}
  rescue
    ArgumentError -> {:error, ~s(#{inspect(v)} is not an existing atom)}
  end

  def string_to_atom(v), do: {:error, "cannot coerce #{inspect(v)} to atom"}

  # ---------------------------------------------------------------------------
  # Lookup — maps (source_type, target_type) → coercion function
  # ---------------------------------------------------------------------------

  @doc """
  Returns the built-in coercion function for the given source → target type pair.
  Raises `ArgumentError` if no built-in coercion exists for that combination.

  Called by `Inspex.coerce(spec, from: source_type)`.
  """
  @spec lookup(atom(), atom()) :: (term() -> {:ok, term()} | {:error, String.t()})
  def lookup(:string, :integer), do: &string_to_integer/1
  def lookup(:string, :float),   do: &string_to_float/1
  def lookup(:string, :boolean), do: &string_to_boolean/1
  def lookup(:string, :atom),    do: &string_to_atom/1
  def lookup(:string, :number),  do: &string_to_float/1

  def lookup(source, target) do
    raise ArgumentError, """
    No built-in coercion from #{inspect(source)} to #{inspect(target)}.

    Provide a custom function:

        coerce(#{target}(), fn value ->
          # return {:ok, coerced} or {:error, "reason"}
        end)

    Available built-in coercions (from: :string):
      :integer, :float, :number, :boolean, :atom
    """
  end
end
