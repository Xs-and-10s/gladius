defmodule Gladius.DefaultTest do
  use ExUnit.Case, async: true

  import Gladius

  # ---------------------------------------------------------------------------
  # default/2 construction
  # ---------------------------------------------------------------------------

  describe "default/2" do
    test "returns a %Gladius.Default{} struct" do
      spec = default(integer(gte?: 0), 0)
      assert %Gladius.Default{value: 0} = spec
      assert %Gladius.Spec{} = spec.spec
    end

    test "accepts any conformable as the inner spec" do
      assert %Gladius.Default{} = default(string(:filled?), "hello")
      assert %Gladius.Default{} = default(atom(in?: [:a, :b]), :a)
      assert %Gladius.Default{} = default(maybe(integer()), nil)
      assert %Gladius.Default{} = default(all_of([integer(), spec(&(&1 > 0))]), 1)
    end

    test "value can be nil" do
      spec = default(maybe(string(:filled?)), nil)
      assert %Gladius.Default{value: nil} = spec
    end

    test "value can be a complex term" do
      spec = default(list_of(integer()), [1, 2, 3])
      assert %Gladius.Default{value: [1, 2, 3]} = spec
    end
  end

  # ---------------------------------------------------------------------------
  # conform — standalone (outside a schema)
  # ---------------------------------------------------------------------------

  describe "conform/2 with %Default{} — value present" do
    test "validates and returns the provided value when it passes the inner spec" do
      spec = default(integer(gte?: 0), 0)
      assert {:ok, 42} = conform(spec, 42)
    end

    test "returns error when provided value fails the inner spec" do
      spec = default(integer(gte?: 0), 0)
      assert {:error, [%Gladius.Error{}]} = conform(spec, -1)
    end

    test "error path is preserved from inner spec" do
      spec = default(string(:filled?), "fallback")
      {:error, [error]} = conform(spec, "")
      assert error.path == []
    end

    test "inner spec coercions run when value is present" do
      spec = default(coerce(integer(), from: :string), 0)
      assert {:ok, 7} = conform(spec, "7")
    end
  end

  # ---------------------------------------------------------------------------
  # schema — optional key absent → inject default
  # ---------------------------------------------------------------------------

  describe "conform/2 with schema — absent optional key" do
    test "injects default value when optional key is absent" do
      s = schema(%{
        required(:name) => string(:filled?),
        optional(:role) => default(atom(in?: [:admin, :user, :guest]), :user)
      })

      assert {:ok, result} = conform(s, %{name: "Mark"})
      assert result.name == "Mark"
      assert result.role == :user
    end

    test "default value is NOT validated by inner spec" do
      # The default is assumed to be correct — we don't re-validate it
      # (this mirrors Peri behaviour and avoids needless runtime cost)
      s = schema(%{
        optional(:count) => default(integer(gte?: 0), 0)
      })

      assert {:ok, %{count: 0}} = conform(s, %{})
    end

    test "absent key without default is still omitted from output" do
      s = schema(%{
        required(:name) => string(:filled?),
        optional(:bio)  => string()
      })

      assert {:ok, result} = conform(s, %{name: "Mark"})
      refute Map.has_key?(result, :bio)
    end

    test "key present with default spec is validated by inner spec" do
      s = schema(%{
        optional(:role) => default(atom(in?: [:admin, :user, :guest]), :user)
      })

      assert {:ok, %{role: :admin}} = conform(s, %{role: :admin})
    end

    test "key present but invalid returns error — default does not rescue it" do
      s = schema(%{
        optional(:role) => default(atom(in?: [:admin, :user, :guest]), :user)
      })

      assert {:error, [error]} = conform(s, %{role: :superuser})
      assert error.path == [:role]
    end

    test "multiple optional fields with defaults — all injected when absent" do
      s = schema(%{
        required(:email)   => string(:filled?, format: ~r/@/),
        optional(:role)    => default(atom(in?: [:admin, :user]), :user),
        optional(:active)  => default(boolean(), true),
        optional(:retries) => default(integer(gte?: 0), 3)
      })

      assert {:ok, result} = conform(s, %{email: "a@b.com"})
      assert result.role    == :user
      assert result.active  == true
      assert result.retries == 3
    end

    test "mix of absent-with-default, absent-without-default, and present" do
      s = schema(%{
        required(:name)    => string(:filled?),
        optional(:role)    => default(atom(in?: [:admin, :user]), :user),
        optional(:bio)     => string()
      })

      assert {:ok, result} = conform(s, %{name: "Mark", role: :admin})
      assert result.name == "Mark"
      assert result.role == :admin
      refute Map.has_key?(result, :bio)
    end
  end

  # ---------------------------------------------------------------------------
  # schema — required key with default (unusual but legal)
  # ---------------------------------------------------------------------------

  describe "required key with default spec" do
    test "required key present passes normally" do
      s = schema(%{
        required(:count) => default(integer(gte?: 0), 0)
      })

      assert {:ok, %{count: 5}} = conform(s, %{count: 5})
    end

    test "required key absent returns missing-key error (default not injected)" do
      # A required key is required. The default only applies to *optional* keys.
      s = schema(%{
        required(:count) => default(integer(gte?: 0), 0)
      })

      assert {:error, [error]} = conform(s, %{})
      assert error.path == [:count]
    end
  end

  # ---------------------------------------------------------------------------
  # open_schema + default
  # ---------------------------------------------------------------------------

  describe "open_schema with defaults" do
    test "extra keys pass through and defaults are injected" do
      s = open_schema(%{
        optional(:role) => default(atom(in?: [:admin, :user]), :user)
      })

      assert {:ok, result} = conform(s, %{role: :admin, extra: "ok"})
      assert result.role  == :admin
      assert result.extra == "ok"
    end

    test "absent optional with default is injected in open_schema" do
      s = open_schema(%{
        optional(:role) => default(atom(in?: [:admin, :user]), :user)
      })

      assert {:ok, result} = conform(s, %{foo: "bar"})
      assert result.role == :user
      assert result.foo  == "bar"
    end
  end

  # ---------------------------------------------------------------------------
  # composability
  # ---------------------------------------------------------------------------

  describe "composability" do
    test "default wrapping a schema" do
      inner = schema(%{required(:x) => integer()})
      outer = schema(%{
        optional(:coords) => default(inner, %{x: 0})
      })

      assert {:ok, %{coords: %{x: 0}}} = conform(outer, %{})
      assert {:ok, %{coords: %{x: 9}}} = conform(outer, %{coords: %{x: 9}})
    end

    test "default wrapping a list_of" do
      s = schema(%{
        optional(:tags) => default(list_of(string(:filled?)), [])
      })

      assert {:ok, %{tags: []}}          = conform(s, %{})
      assert {:ok, %{tags: ["a", "b"]}}  = conform(s, %{tags: ["a", "b"]})
    end

    test "default wrapping a maybe — nil is a valid provided value" do
      s = schema(%{
        optional(:ref) => default(maybe(string(:filled?)), nil)
      })

      assert {:ok, %{ref: nil}}   = conform(s, %{})
      assert {:ok, %{ref: nil}}   = conform(s, %{ref: nil})
      assert {:ok, %{ref: "abc"}} = conform(s, %{ref: "abc"})
    end

    test "default inside ref resolves correctly" do
      Gladius.Registry.register(:defaulted_age, default(integer(gte?: 0), 18))

      s = schema(%{
        optional(:age) => ref(:defaulted_age)
      })

      assert {:ok, %{age: 18}} = conform(s, %{})
      assert {:ok, %{age: 25}} = conform(s, %{age: 25})
    end
  end

  # ---------------------------------------------------------------------------
  # generator inference
  # ---------------------------------------------------------------------------

  describe "gen/1" do
    test "delegates to inner spec's generator" do
      spec = default(integer(gte?: 0, lte?: 100), 0)
      generator = Gladius.gen(spec)
      assert %StreamData{} = generator
    end
  end

  # ---------------------------------------------------------------------------
  # to_typespec/1
  # ---------------------------------------------------------------------------

  describe "to_typespec/1" do
    test "delegates to inner spec's typespec" do
      spec = default(integer(), 0)
      assert Gladius.to_typespec(spec) == Gladius.to_typespec(integer())
    end
  end
end
