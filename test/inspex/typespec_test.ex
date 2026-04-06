defmodule Inspex.TypespecTest do
  use ExUnit.Case, async: true

  import Inspex
  alias Inspex.Typespec

  # Convenience: convert a spec to a typespec string for readable assertions.
  defp ts(spec), do: spec |> Inspex.to_typespec() |> Macro.to_string()

  # ===========================================================================
  # Primitives
  # ===========================================================================

  describe "primitive types" do
    test "string" do
      assert ts(string()) == "String.t()"
    end

    test "float" do
      assert ts(float()) == "float()"
    end

    test "number" do
      assert ts(number()) == "number()"
    end

    test "boolean" do
      assert ts(boolean()) == "boolean()"
    end

    test "atom" do
      assert ts(atom()) == "atom()"
    end

    test "map" do
      assert ts(map()) == "map()"
    end

    test "list" do
      assert ts(list()) == "list()"
    end

    test "any" do
      assert ts(any()) == "any()"
    end

    test "nil_spec" do
      # nil_spec() → nil as a typespec
      assert Inspex.to_typespec(nil_spec()) == nil
    end

    test "predicate-only spec falls back to term()" do
      assert ts(spec(&is_integer/1)) == "term()"
    end
  end

  # ===========================================================================
  # String constraints (all lossy)
  # ===========================================================================

  describe "string constraints" do
    test "filled? → String.t() (constraint elided)" do
      assert ts(string(:filled?)) == "String.t()"
    end

    test "format: → String.t() (constraint elided)" do
      assert ts(string(format: ~r/@/)) == "String.t()"
    end

    test "min_length: → String.t() (constraint elided)" do
      assert ts(string(min_length: 3)) == "String.t()"
    end

    test "all string constraints combined" do
      assert ts(string(:filled?, format: ~r/@/, min_length: 5)) == "String.t()"
    end
  end

  # ===========================================================================
  # Integer constraint specialisation
  # ===========================================================================

  describe "integer constraint specialisation" do
    test "bare integer()" do
      assert ts(integer()) == "integer()"
    end

    test "gte?: 0 → non_neg_integer()" do
      assert ts(integer(gte?: 0)) == "non_neg_integer()"
    end

    test "gt?: 0 → pos_integer()" do
      assert ts(integer(gt?: 0)) == "pos_integer()"
    end

    test "gte?: a, lte?: b → a..b (range)" do
      assert ts(integer(gte?: 1, lte?: 100)) == "1..100"
    end

    test "gte?: 0, lte?: 255 (byte range)" do
      assert ts(integer(gte?: 0, lte?: 255)) == "0..255"
    end

    test "in?: values → union of integer literals" do
      assert ts(integer(in?: [1, 2, 3])) == "1 | 2 | 3"
    end

    test "other constraints fall back to integer()" do
      assert ts(integer(lt?: 100)) == "integer()"
    end

    test "gte?: non-zero without lte → integer()" do
      assert ts(integer(gte?: 18)) == "integer()"
    end
  end

  # ===========================================================================
  # Atom with in?
  # ===========================================================================

  describe "atom with in? constraint" do
    test "in? with atom values → union of atom literals" do
      assert ts(atom(in?: [:admin, :user, :guest])) == ":admin | :user | :guest"
    end

    test "single value in? → single atom" do
      assert ts(atom(in?: [:ok])) == ":ok"
    end
  end

  # ===========================================================================
  # Combinators
  # ===========================================================================

  describe "maybe/1" do
    test "maybe(string()) → String.t() | nil" do
      assert ts(maybe(string())) == "String.t() | nil"
    end

    test "maybe(integer()) → integer() | nil" do
      assert ts(maybe(integer())) == "integer() | nil"
    end

    test "maybe(integer(gte?: 0)) → non_neg_integer() | nil" do
      assert ts(maybe(integer(gte?: 0))) == "non_neg_integer() | nil"
    end
  end

  describe "list_of/1" do
    test "list_of(string()) → [String.t()]" do
      assert ts(list_of(string())) == "[String.t()]"
    end

    test "list_of(integer()) → [integer()]" do
      assert ts(list_of(integer())) == "[integer()]"
    end

    test "list_of(maybe(string())) → [String.t() | nil]" do
      assert ts(list_of(maybe(string()))) == "[String.t() | nil]"
    end
  end

  describe "any_of/1" do
    test "any_of([string(), integer()]) → String.t() | integer()" do
      assert ts(any_of([string(), integer()])) == "String.t() | integer()"
    end

    test "any_of three types" do
      result = ts(any_of([string(), integer(), boolean()]))
      assert result == "String.t() | integer() | boolean()"
    end

    test "any_of with constraints preserved where possible" do
      assert ts(any_of([integer(gte?: 0), string()])) == "non_neg_integer() | String.t()"
    end
  end

  describe "all_of/1" do
    test "uses first typed spec's typespec" do
      assert ts(all_of([string(), string(:filled?)])) == "String.t()"
    end

    test "skips :any and finds first concrete type" do
      result = ts(all_of([any(), integer(gte?: 0)]))
      assert result == "non_neg_integer()"
    end

    test "all predicate-only → term()" do
      result = ts(all_of([spec(&is_integer/1), spec(&(&1 > 0))]))
      assert result == "term()"
    end
  end

  describe "not_spec/1" do
    test "not_spec → term()" do
      assert ts(not_spec(string())) == "term()"
    end
  end

  describe "ref/1" do
    test "ref(:email) → email() as named type reference" do
      # In typespec AST this is {name, [], []} — Macro.to_string renders it
      # as the name followed by ()
      assert ts(ref(:email)) == "email()"
    end

    test "ref(:user_profile) → user_profile()" do
      assert ts(ref(:user_profile)) == "user_profile()"
    end
  end

  describe "cond_spec/3" do
    test "union of both branches" do
      result = ts(cond_spec(&is_integer/1, integer(), string()))
      assert result == "integer() | String.t()"
    end

    test "cond_spec without else → integer() | any()" do
      result = ts(cond_spec(&is_integer/1, integer()))
      assert result == "integer() | any()"
    end
  end

  describe "coerce/2" do
    test "coerce uses the target type" do
      assert ts(coerce(integer(), from: :string)) == "integer()"
    end

    test "coerce with custom fn uses target type" do
      assert ts(coerce(string(), fn v -> {:ok, to_string(v)} end)) == "String.t()"
    end

    test "coerce wrapping an integer spec with constraints" do
      assert ts(coerce(integer(gte?: 0), from: :string)) == "non_neg_integer()"
    end
  end

  # ===========================================================================
  # Schema
  # ===========================================================================

  describe "schema/1 (closed)" do
    test "required keys only" do
      spec = schema(%{required(:name) => string(), required(:age) => integer()})
      result = ts(spec)
      assert result =~ "required(:name) => String.t()"
      assert result =~ "required(:age) => integer()"
      # Starts and ends with %{...}
      assert String.starts_with?(result, "%{")
    end

    test "optional key" do
      spec = schema(%{required(:name) => string(), optional(:role) => atom()})
      result = ts(spec)
      assert result =~ "required(:name) => String.t()"
      assert result =~ "optional(:role) => atom()"
    end

    test "nested types" do
      spec = schema(%{required(:ids) => list_of(integer(gte?: 0))})
      result = ts(spec)
      assert result =~ "required(:ids) => [non_neg_integer()]"
    end

    test "single key schema" do
      spec = schema(%{required(:email) => string()})
      assert ts(spec) == "%{required(:email) => String.t()}"
    end
  end

  describe "open_schema/1" do
    test "open schema adds optional(atom()) => any()" do
      spec = open_schema(%{required(:name) => string()})
      result = ts(spec)
      assert result =~ "required(:name) => String.t()"
      assert result =~ "optional(atom()) => any()"
    end
  end

  # ===========================================================================
  # lossiness/1
  # ===========================================================================

  describe "lossiness/1" do
    test "lossless specs return empty list" do
      assert Inspex.typespec_lossiness(string())              == []
      assert Inspex.typespec_lossiness(integer())             == []
      assert Inspex.typespec_lossiness(integer(gte?: 0))      == []
      assert Inspex.typespec_lossiness(integer(gte?: 0, lte?: 100)) == []
      assert Inspex.typespec_lossiness(maybe(string()))       == []
      assert Inspex.typespec_lossiness(list_of(integer()))    == []
      assert Inspex.typespec_lossiness(any_of([string(), integer()])) == []
      assert Inspex.typespec_lossiness(atom(in?: [:a, :b]))   == []
      assert Inspex.typespec_lossiness(ref(:email))           == []
    end

    test "string with filled? → constraint_not_expressible" do
      [notice | _] = Inspex.typespec_lossiness(string(:filled?))
      assert elem(notice, 0) == :constraint_not_expressible
    end

    test "string with format: → constraint_not_expressible" do
      [notice | _] = Inspex.typespec_lossiness(string(format: ~r/@/))
      assert elem(notice, 0) == :constraint_not_expressible
    end

    test "multiple string constraints → multiple notices" do
      notices = Inspex.typespec_lossiness(string(:filled?, format: ~r/@/, min_length: 3))
      kinds = Enum.map(notices, &elem(&1, 0))
      assert Enum.all?(kinds, &(&1 == :constraint_not_expressible))
      assert length(notices) == 3
    end

    test "not_spec → negation_not_expressible" do
      [notice | _] = Inspex.typespec_lossiness(not_spec(integer()))
      assert elem(notice, 0) == :negation_not_expressible
    end

    test "all_of → intersection_not_expressible" do
      [notice | _] = Inspex.typespec_lossiness(all_of([string(), string(:filled?)]))
      assert elem(notice, 0) == :intersection_not_expressible
    end

    test "cond_spec → predicate_not_expressible" do
      [notice | _] = Inspex.typespec_lossiness(cond_spec(&is_integer/1, integer(), string()))
      assert elem(notice, 0) == :predicate_not_expressible
    end

    test "coerce → coercion_not_expressible" do
      [notice | _] = Inspex.typespec_lossiness(coerce(integer(), from: :string))
      assert elem(notice, 0) == :coercion_not_expressible
    end

    test "nested lossiness is surfaced" do
      # maybe(not_spec(string())) should bubble up the not_spec notice
      notices = Inspex.typespec_lossiness(maybe(not_spec(string())))
      kinds = Enum.map(notices, &elem(&1, 0))
      assert :negation_not_expressible in kinds
    end

    test "schema lossiness from values is surfaced" do
      spec = schema(%{required(:name) => string(:filled?), required(:age) => integer()})
      [notice | _] = Inspex.typespec_lossiness(spec)
      assert elem(notice, 0) == :constraint_not_expressible
    end
  end

  # ===========================================================================
  # type_ast/2
  # ===========================================================================

  describe "type_ast/2" do
    test "generates @type declaration AST" do
      ast = Typespec.type_ast(:user_id, integer(gte?: 0))
      # Render it as a string — should look like @type user_id :: non_neg_integer()
      rendered = Macro.to_string(ast)
      assert rendered =~ "type"
      assert rendered =~ "user_id"
      assert rendered =~ "non_neg_integer()"
    end

    test "the generated AST is injectable into a module" do
      # Verify the AST is structurally valid by eval-ing it in a test module
      email_spec = string(:filled?, format: ~r/@/)
      ast = Typespec.type_ast(:email_address, email_spec)

      # Create a fresh module and inject the @type declaration
      {:module, mod, _, _} =
        Module.create(:"Inspex.TypespecTest.Dynamic#{:erlang.unique_integer([:positive])}",
          quote do
            unquote(ast)
          end,
          __ENV__
        )

      # The module should have compiled without error.
      # Check the @type attribute was set.
      types = mod.__info__(:attributes)[:type] || []
      assert Enum.any?(types, fn {name, _, _} -> name == :email_address end)
    end
  end
end
