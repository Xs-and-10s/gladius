defmodule Inspex.SignatureTest do
  use ExUnit.Case, async: true

  # ===========================================================================
  # Test subject modules
  #
  # We define helper modules inside the test file using Module.create or
  # inline module definitions. Each module uses `use Inspex.Signature` so the
  # def override is scoped only to that module — it does NOT affect the test
  # module itself.
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # Basic: args and ret
  # ---------------------------------------------------------------------------
  defmodule BasicSubject do
    use Inspex.Signature
    import Inspex

    signature args: [string(:filled?), integer(gte?: 0)],
              ret:  string(:filled?)
    def greet(name, count) do
      String.duplicate("Hello #{name}! ", count)
    end

    # Unsigned function — should not be affected by use Inspex.Signature
    def unsigned(x), do: x * 2
  end

  describe "basic args and ret" do
    test "valid call passes through unchanged" do
      assert BasicSubject.greet("Mark", 2) == "Hello Mark! Hello Mark! "
    end

    test "invalid arg raises SignatureError with :args kind" do
      assert_raise Inspex.SignatureError, fn ->
        BasicSubject.greet("", 2)   # empty string fails string(:filled?)
      end
    end

    test "error reports the correct argument index" do
      try do
        BasicSubject.greet("Mark", -1)   # -1 fails integer(gte?: 0)
      rescue
        e in Inspex.SignatureError ->
          assert e.kind == :args
          assert e.arg_index == 1
          assert e.value == -1
          assert e.function == :greet
          assert e.arity == 2
      end
    end

    test "wrong type for first arg" do
      try do
        BasicSubject.greet(42, 1)
      rescue
        e in Inspex.SignatureError ->
          assert e.kind == :args
          assert e.arg_index == 0
          assert e.value == 42
      end
    end

    test "invalid return value raises SignatureError with :ret kind" do
      # greet/2 returns "" when count is 0 (empty string fails :filled? on ret)
      assert_raise Inspex.SignatureError, fn ->
        BasicSubject.greet("Mark", 0)
      end
    end

    test "ret error reports the offending value" do
      try do
        BasicSubject.greet("Mark", 0)
      rescue
        e in Inspex.SignatureError ->
          assert e.kind == :ret
          assert e.value == ""
          assert e.function == :greet
      end
    end

    test "unsigned functions are unaffected" do
      assert BasicSubject.unsigned(21) == 42
    end
  end

  # ---------------------------------------------------------------------------
  # Multi-clause function
  # ---------------------------------------------------------------------------
  defmodule MultiClause do
    use Inspex.Signature
    import Inspex

    signature args: [integer()], ret: integer()
    def fact(0), do: 1
    def fact(n) when n > 0, do: n * fact(n - 1)
  end

  describe "multi-clause function" do
    test "first clause (base case) works" do
      assert MultiClause.fact(0) == 1
    end

    test "recursive clause works" do
      assert MultiClause.fact(5) == 120
    end

    test "arg violation raises SignatureError" do
      assert_raise Inspex.SignatureError, fn ->
        MultiClause.fact("not an integer")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Zero-arity function (ret only)
  # ---------------------------------------------------------------------------
  defmodule ZeroArity do
    use Inspex.Signature
    import Inspex

    signature ret: string(:filled?)
    def config_key, do: "my_key"

    signature ret: string(:filled?)
    def bad_key, do: ""    # always violates ret
  end

  describe "zero-arity function" do
    test "valid return passes through" do
      assert ZeroArity.config_key() == "my_key"
    end

    test "invalid return raises SignatureError" do
      assert_raise Inspex.SignatureError, fn ->
        ZeroArity.bad_key()
      end
    end
  end

  # ---------------------------------------------------------------------------
  # :fn relationship constraint
  # ---------------------------------------------------------------------------
  defmodule WithFnConstraint do
    use Inspex.Signature
    import Inspex

    # :fn spec receives a tuple {args_list, return_value} and must conform to it.
    # Here: the return value must be >= the first argument.
    signature args: [integer(), integer()],
              ret:  integer(),
              fn:   spec(fn {[a, _b], ret} -> ret >= a end)
    def add(a, b), do: a + b
  end

  describe ":fn relationship constraint" do
    test "valid relationship passes through" do
      assert WithFnConstraint.add(3, 4) == 7   # 7 >= 3 ✓
    end

    test ":fn violation raises SignatureError with :fn kind" do
      # We can't easily make add/2 violate the fn constraint legitimately,
      # so we test the constraint check directly via a module where the
      # implementation can be made to violate it.
      defmodule FnViolator do
        use Inspex.Signature
        import Inspex

        # Return must equal first arg (trivially checkable)
        signature args: [integer()],
                  ret:  integer(),
                  fn:   spec(fn {[a], ret} -> ret == a end)
        def identity(_n), do: 99   # always returns 99, violates fn unless arg is 99
      end

      assert_raise Inspex.SignatureError, fn ->
        FnViolator.identity(1)   # returns 99, but 99 != 1
      end

      try do
        FnViolator.identity(1)
      rescue
        e in Inspex.SignatureError -> assert e.kind == :fn
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ref/1 in signature specs (registry integration)
  # ---------------------------------------------------------------------------
  defmodule WithRef do
    use Inspex.Signature
    import Inspex

    # Registers a spec that this module's signature will reference.
    # We set it up in test setup rather than at module level to avoid
    # polluting the global registry.
    signature args: [ref(:sig_test_email)],
              ret:  boolean()
    def valid_email?(email), do: String.contains?(email, "@")
  end

  describe "ref/1 in signature" do
    setup do
      Inspex.Registry.register_local(:sig_test_email, Inspex.string(:filled?, format: ~r/@/))
      on_exit(&Inspex.Registry.clear_local/0)
    end

    test "valid email passes args check" do
      assert WithRef.valid_email?("user@example.com") == true
    end

    test "invalid arg raises SignatureError" do
      assert_raise Inspex.SignatureError, fn ->
        WithRef.valid_email?("notanemail")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Coercion in signature specs
  # ---------------------------------------------------------------------------
  defmodule WithCoercion do
    use Inspex.Signature
    import Inspex

    signature args: [coerce(integer(gte?: 0), from: :string)],
              ret:  string(:filled?)
    def times_two(n), do: Integer.to_string(n * 2)
  end

  describe "coercion in signature args" do
    test "string arg is coerced to integer before validation" do
      assert WithCoercion.times_two("5") == "10"
    end

    test "integer arg passes directly (idempotent coercion)" do
      assert WithCoercion.times_two(5) == "10"
    end

    test "invalid string raises SignatureError" do
      assert_raise Inspex.SignatureError, fn ->
        WithCoercion.times_two("bad")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # SignatureError message formatting
  # ---------------------------------------------------------------------------
  describe "SignatureError message" do
    test ":args error message is descriptive" do
      try do
        BasicSubject.greet(42, 1)
      rescue
        e in Inspex.SignatureError ->
          msg = Exception.message(e)
          assert msg =~ "Inspex.SignatureTest.BasicSubject"
          assert msg =~ "greet/2"
          assert msg =~ "argument[0]"
          assert msg =~ inspect(42)
      end
    end

    test ":ret error message is descriptive" do
      try do
        BasicSubject.greet("Mark", 0)
      rescue
        e in Inspex.SignatureError ->
          msg = Exception.message(e)
          assert msg =~ "greet/2"
          assert msg =~ "return value"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Signature does not affect defp or other macros
  # ---------------------------------------------------------------------------
  defmodule WithPrivate do
    use Inspex.Signature
    import Inspex

    signature args: [integer()], ret: integer()
    def double(n), do: helper(n)

    defp helper(n), do: n * 2
  end

  describe "private functions are not affected" do
    test "private helper is not wrapped or renamed" do
      assert WithPrivate.double(5) == 10
    end
  end
end
