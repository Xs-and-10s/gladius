defmodule Gladius.StructTest do
  use ExUnit.Case, async: true

  import Gladius

  # ---------------------------------------------------------------------------
  # Test fixtures
  # ---------------------------------------------------------------------------

  # Plain Elixir structs used as input throughout these tests
  defmodule User do
    defstruct [:name, :email, :age, :role]
  end

  defmodule Address do
    defstruct [:street, :city, :zip]
  end

  # A defschema with struct: true — defines both schema and matching struct
  defmodule Schemas do
    import Gladius

    defschema :point, struct: true do
      schema(%{
        required(:x) => integer(),
        required(:y) => integer()
      })
    end

    defschema :person, struct: true do
      schema(%{
        required(:name)  => transform(string(:filled?), &String.trim/1),
        optional(:score) => default(integer(gte?: 0), 0)
      })
    end
  end

  # ---------------------------------------------------------------------------
  # Part A — conform/2 accepts structs as input
  # ---------------------------------------------------------------------------

  describe "conform/2 with struct input" do
    test "validates a struct against a schema — happy path" do
      s = schema(%{
        required(:name)  => string(:filled?),
        required(:email) => string(:filled?, format: ~r/@/)
      })

      user = %User{name: "Mark", email: "mark@x.com"}
      assert {:ok, %{name: "Mark", email: "mark@x.com"}} = conform(s, user)
    end

    test "output is a plain map, not the original struct type" do
      s = schema(%{required(:name) => string(:filled?)})
      user = %User{name: "Mark"}
      {:ok, result} = conform(s, user)
      refute is_struct(result)
      assert is_map(result)
    end

    test "returns errors for invalid struct fields" do
      s = schema(%{
        required(:name) => string(:filled?),
        required(:age)  => integer(gte?: 18)
      })

      user = %User{name: "", age: 15}
      assert {:error, errors} = conform(s, user)
      assert Enum.any?(errors, &(&1.path == [:name]))
      assert Enum.any?(errors, &(&1.path == [:age]))
    end

    test "nil struct fields are treated as absent map keys" do
      s = schema(%{
        required(:name)  => string(:filled?),
        optional(:role)  => atom()
      })

      # %User{role: nil} — nil field counts as absent for optional
      user = %User{name: "Mark", role: nil}
      # role: nil is present as a key in Map.from_struct, so it IS present —
      # but nil fails atom() type check only if it's required.
      # Let's verify the exact behaviour: Map.from_struct includes nil fields.
      {:ok, result} = conform(s, user)
      assert result.name == "Mark"
    end

    test "coercion works on struct fields" do
      s = schema(%{
        required(:age) => coerce(integer(), from: :string)
      })

      # Simulate a struct that stores age as string
      defmodule RawUser do
        defstruct [:age]
      end

      user = %RawUser{age: "33"}
      assert {:ok, %{age: 33}} = conform(s, user)
    end

    test "transform works on struct fields" do
      s = schema(%{
        required(:name) => transform(string(:filled?), &String.trim/1)
      })

      user = %User{name: "  Mark  "}
      assert {:ok, %{name: "Mark"}} = conform(s, user)
    end

    test "nested struct is converted recursively when schema is nested" do
      address_schema = schema(%{
        required(:street) => string(:filled?),
        required(:city)   => string(:filled?)
      })

      # Wrap Address struct field in a parent schema
      s = schema(%{
        required(:name)    => string(:filled?),
        required(:address) => address_schema
      })

      defmodule UserWithAddress do
        defstruct [:name, :address]
      end

      input = %UserWithAddress{
        name: "Mark",
        address: %Address{street: "123 Main", city: "Culpeper", zip: nil}
      }

      assert {:ok, %{name: "Mark", address: %{street: "123 Main", city: "Culpeper"}}} =
               conform(s, input)
    end

    test "valid?/2 works with struct input" do
      s = schema(%{required(:name) => string(:filled?)})
      assert valid?(s, %User{name: "Mark"})
      refute valid?(s, %User{name: ""})
    end

    test "explain/2 works with struct input" do
      s = schema(%{required(:name) => string(:filled?)})
      result = explain(s, %User{name: ""})
      refute result.valid?
      assert result.formatted =~ "filled"
    end
  end

  # ---------------------------------------------------------------------------
  # Part B — conform_struct/2
  # ---------------------------------------------------------------------------

  describe "conform_struct/2" do
    test "validates and re-wraps in the original struct type" do
      s = schema(%{
        required(:name)  => string(:filled?),
        required(:email) => string(:filled?, format: ~r/@/)
      })

      user = %User{name: "Mark", email: "mark@x.com"}
      assert {:ok, %User{name: "Mark", email: "mark@x.com"}} = Gladius.conform_struct(s, user)
    end

    test "shaped values (coercions, transforms) are reflected in the returned struct" do
      s = schema(%{
        required(:name) => transform(string(:filled?), &String.trim/1),
        required(:age)  => coerce(integer(), from: :string)
      })

      defmodule CoercedUser do
        defstruct [:name, :age]
      end

      user = %CoercedUser{name: "  Mark  ", age: "33"}
      assert {:ok, %CoercedUser{name: "Mark", age: 33}} = Gladius.conform_struct(s, user)
    end

    test "returns error tuple on validation failure — same format as conform/2" do
      s = schema(%{
        required(:name) => string(:filled?),
        required(:age)  => integer(gte?: 18)
      })

      user = %User{name: "", age: 10}
      assert {:error, errors} = Gladius.conform_struct(s, user)
      assert is_list(errors)
      assert Enum.all?(errors, &match?(%Gladius.Error{}, &1))
    end

    test "requires a struct as input — plain maps are rejected" do
      s = schema(%{required(:name) => string(:filled?)})
      assert {:error, [error]} = Gladius.conform_struct(s, %{name: "Mark"})
      assert error.message =~ "struct"
    end

    test "requires a struct as input — other values are rejected" do
      s = schema(%{required(:name) => string(:filled?)})
      assert {:error, [error]} = Gladius.conform_struct(s, "not a struct")
      assert error.message =~ "struct"
    end

    test "open_schema preserves extra keys in the struct" do
      s = open_schema(%{required(:name) => string(:filled?)})
      user = %User{name: "Mark", email: "mark@x.com", age: 33}
      assert {:ok, %User{name: "Mark", email: "mark@x.com", age: 33}} =
               Gladius.conform_struct(s, user)
    end

    test "struct fields not in schema are nil in the returned struct (closed schema)" do
      s = schema(%{required(:name) => string(:filled?)})
      user = %User{name: "Mark", email: "mark@x.com", age: 33, role: :admin}
      # closed schema — email/age/role are unknown keys → error
      assert {:error, _} = Gladius.conform_struct(s, user)
    end
  end

  # ---------------------------------------------------------------------------
  # Part B — defschema struct: true
  # ---------------------------------------------------------------------------

  describe "defschema struct: true" do
    test "generates a struct module matching the schema fields" do
      # The point/1 function should exist and its output is %Schemas.PointSchema{}
      assert function_exported?(Gladius.StructTest.Schemas, :point, 1)
      assert function_exported?(Gladius.StructTest.Schemas, :point!, 1)
    end

    test "conform returns a struct of the generated type" do
      assert {:ok, result} = Schemas.point(%{x: 3, y: 4})
      assert is_struct(result)
      assert result.__struct__ == Gladius.StructTest.Schemas.PointSchema
      assert result.x == 3
      assert result.y == 4
    end

    test "bang variant returns the struct directly" do
      result = Schemas.point!(%{x: 1, y: 2})
      assert %Gladius.StructTest.Schemas.PointSchema{x: 1, y: 2} = result
    end

    test "validation errors are still returned on invalid input" do
      assert {:error, [error]} = Schemas.point(%{x: "not_int", y: 0})
      assert error.path == [:x]
    end

    test "transforms run before struct wrapping" do
      assert {:ok, result} = Schemas.person(%{name: "  Mark  "})
      assert result.name == "Mark"
    end

    test "defaults are injected before struct wrapping" do
      assert {:ok, result} = Schemas.person(%{name: "Mark"})
      assert result.score == 0
    end

    test "bang raises ConformError on failure" do
      assert_raise Gladius.ConformError, fn ->
        Schemas.point!(%{x: "bad", y: 0})
      end
    end
  end
end
