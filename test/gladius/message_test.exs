defmodule Gladius.MessageTest do
  use ExUnit.Case, async: false

  import Gladius

  defmodule TestTranslator do
    @behaviour Gladius.Translator
    def translate(domain, msgid, bindings) do
      suffix = if bindings == [], do: "", else: " (#{inspect(bindings)})"
      "[#{domain || "default"}] #{String.upcase(msgid)}#{suffix}"
    end
  end

  describe "message: string on %Spec{}" do
    test "overrides constraint error message" do
      spec = string(:filled?, message: "can't be blank")
      assert {:error, [error]} = conform(spec, "")
      assert error.message == "can't be blank"
    end

    test "overrides type error message" do
      spec = integer(message: "must be a whole number")
      assert {:error, [error]} = conform(spec, "oops")
      assert error.message == "must be a whole number"
    end

    test "overrides gte? constraint message" do
      spec = integer(gte?: 18, message: "you must be at least 18")
      assert {:error, [error]} = conform(spec, 15)
      assert error.message == "you must be at least 18"
    end

    test "does not affect successful conformance" do
      spec = string(:filled?, message: "can't be blank")
      assert {:ok, "hello"} = conform(spec, "hello")
    end

    test "overrides ALL errors when multiple constraints fail" do
      spec = string(min_length: 5, max_length: 3, message: "invalid string")
      {:error, errors} = conform(spec, "abcd")
      assert Enum.all?(errors, &(&1.message == "invalid string"))
    end

    test "message: on atom/1" do
      spec = atom(in?: [:a, :b], message: "must be :a or :b")
      assert {:error, [error]} = conform(spec, :c)
      assert error.message == "must be :a or :b"
    end

    test "message: on float/1" do
      spec = float(gte?: 0.0, message: "must be non-negative")
      assert {:error, [error]} = conform(spec, -1.0)
      assert error.message == "must be non-negative"
    end

    test "message: on list/1" do
      spec = list(:filled?, message: "list can't be empty")
      assert {:error, [error]} = conform(spec, [])
      assert error.message == "list can't be empty"
    end
  end

  describe "message: string on combinators" do
    test "maybe/2 overrides inner spec error" do
      spec = maybe(string(:filled?), message: "must be a non-empty string or nil")
      assert {:error, [error]} = conform(spec, "")
      assert error.message == "must be a non-empty string or nil"
    end

    test "maybe/2 does not affect nil pass-through" do
      spec = maybe(string(:filled?), message: "must be non-empty or nil")
      assert {:ok, nil} = conform(spec, nil)
    end

    test "transform/3 overrides transform failure message" do
      spec = transform(string(:filled?), fn _ -> raise "boom" end, message: "normalization failed")
      assert {:error, [error]} = conform(spec, "hello")
      assert error.message == "normalization failed"
    end

    test "transform/3 overrides validation failure message too" do
      spec = transform(string(:filled?), &String.trim/1, message: "transform msg")
      {:error, [error]} = conform(spec, "")
      assert error.message == "transform msg"
    end

    test "any_of with message: overrides union failure" do
      spec = %Gladius.Any{specs: [integer(), float()], message: "must be numeric"}
      assert {:error, [error]} = conform(spec, "string")
      assert error.message == "must be numeric"
    end

    test "not_spec with message: overrides negation failure" do
      spec = %Gladius.Not{spec: integer(), message: "must not be an integer"}
      assert {:error, [error]} = conform(spec, 42)
      assert error.message == "must not be an integer"
    end
  end

  describe "message: with coerce/2" do
    test "overrides coercion error" do
      spec = coerce(integer(), from: :string, message: "must be a valid number")
      assert {:error, [error]} = conform(spec, "abc")
      assert error.message == "must be a valid number"
    end

    test "overrides constraint error after successful coercion" do
      spec = coerce(integer(gte?: 0), from: :string, message: "must be a non-negative number")
      assert {:error, [error]} = conform(spec, "-5")
      assert error.message == "must be a non-negative number"
    end

    test "does not affect successful coercion + validation" do
      spec = coerce(integer(gte?: 0), from: :string, message: "must be a non-negative number")
      assert {:ok, 42} = conform(spec, "42")
    end
  end

  describe "tuple message without translator" do
    test "uses msgid as fallback when no translator configured" do
      spec = string(:filled?, message: {"errors", "can't be blank", []})
      assert {:error, [error]} = conform(spec, "")
      assert error.message == "can't be blank"
    end

    test "msgid used even when bindings are present" do
      spec = integer(gte?: 18, message: {"errors", "must be at least %{min}", [min: 18]})
      assert {:error, [error]} = conform(spec, 15)
      assert error.message == "must be at least %{min}"
    end
  end

  describe "tuple message with translator configured" do
    setup do
      Application.put_env(:gladius, :translator, Gladius.MessageTest.TestTranslator)
      on_exit(fn -> Application.delete_env(:gladius, :translator) end)
      :ok
    end

    test "tuple message is passed to translator" do
      spec = string(:filled?, message: {"errors", "can't be blank", []})
      assert {:error, [error]} = conform(spec, "")
      assert error.message == "[errors] CAN'T BE BLANK"
    end

    test "tuple message bindings are passed to translator" do
      spec = integer(gte?: 18, message: {"errors", "must be at least %{min}", [min: 18]})
      assert {:error, [error]} = conform(spec, 15)
      assert error.message =~ "MUST BE AT LEAST"
      assert error.message =~ "min: 18"
    end

    test "plain string message bypasses translator" do
      spec = string(:filled?, message: "already localised string")
      assert {:error, [error]} = conform(spec, "")
      assert error.message == "already localised string"
    end

    test "built-in errors go through translator when no custom message" do
      spec = string(:filled?)
      assert {:error, [error]} = conform(spec, "")
      assert error.message == "[default] MUST BE FILLED"
    end
  end

  describe "message_key and message_bindings on %Gladius.Error{}" do
    test "gte? failure populates message_key and message_bindings" do
      {:error, [error]} = conform(integer(gte?: 18), 15)
      assert error.message_key == :gte?
      assert error.message_bindings == [min: 18]
    end

    test "gt? failure populates bindings" do
      {:error, [error]} = conform(integer(gt?: 0), 0)
      assert error.message_key == :gt?
      assert error.message_bindings == [min: 0]
    end

    test "lte? failure populates bindings" do
      {:error, [error]} = conform(integer(lte?: 10), 15)
      assert error.message_key == :lte?
      assert error.message_bindings == [max: 10]
    end

    test "filled? failure populates message_key with empty bindings" do
      {:error, [error]} = conform(string(:filled?), "")
      assert error.message_key == :filled?
      assert error.message_bindings == []
    end

    test "format failure populates message_key and regex binding" do
      {:error, [error]} = conform(string(format: ~r/@/), "notanemail")
      assert error.message_key == :format
      # Compare source strings — %Regex{} internal references differ between compilations
      assert Regex.source(error.message_bindings[:format]) == "@"
    end

    test "in? failure populates message_key and values binding" do
      {:error, [error]} = conform(atom(in?: [:a, :b]), :c)
      assert error.message_key == :in?
      assert error.message_bindings[:values] == [:a, :b]
    end

    test "type? failure populates message_key with expected/actual bindings" do
      {:error, [error]} = conform(integer(), "string")
      assert error.message_key == :type?
      assert error.message_bindings[:expected] == :integer
      assert error.message_bindings[:actual] == :string
    end

    test "coerce failure populates message_key" do
      {:error, [error]} = conform(coerce(integer(), from: :string), "abc")
      assert error.message_key == :coerce
      assert error.message_bindings[:original] == "abc"
    end

    test "transform failure populates message_key and reason binding" do
      {:error, [error]} = conform(transform(string(), fn _ -> raise "boom" end), "hi")
      assert error.message_key == :transform
      assert error.message_bindings[:reason] =~ "boom"
    end

    test "min_length failure populates bindings" do
      {:error, [error]} = conform(string(min_length: 5), "hi")
      assert error.message_key == :min_length
      assert error.message_bindings == [min: 5]
    end

    test "size? failure populates bindings" do
      {:error, [error]} = conform(string(size?: 5), "hi")
      assert error.message_key == :size?
      assert error.message_bindings == [size: 5]
    end

    test "custom message: does not change message_key/bindings" do
      {:error, [error]} = conform(integer(gte?: 18, message: "too young"), 15)
      assert error.message == "too young"
      assert error.message_key == :gte?
      assert error.message_bindings == [min: 18]
    end
  end

  describe "custom message inside schema" do
    test "error path is still correct when message is overridden" do
      s = schema(%{required(:age) => integer(gte?: 18, message: "must be adult")})
      assert {:error, [error]} = conform(s, %{age: 15})
      assert error.path == [:age]
      assert error.message == "must be adult"
    end

    test "multiple fields with different custom messages" do
      s = schema(%{
        required(:name) => string(:filled?, message: "name required"),
        required(:age)  => integer(gte?: 18, message: "must be adult")
      })
      {:error, errors} = conform(s, %{name: "", age: 15})
      name_err = Enum.find(errors, &(&1.path == [:name]))
      age_err  = Enum.find(errors, &(&1.path == [:age]))
      assert name_err.message == "name required"
      assert age_err.message  == "must be adult"
    end

    test "fields without custom messages still get default messages" do
      s = schema(%{
        required(:name) => string(:filled?, message: "name required"),
        required(:age)  => integer(gte?: 18)
      })
      {:error, errors} = conform(s, %{name: "", age: 15})
      age_err = Enum.find(errors, &(&1.path == [:age]))
      assert age_err.message =~ "18"
    end
  end

  describe "spec/2 macro with message:" do
    test "message: in opts is stored on the spec struct" do
      s = spec(is_integer(), message: "must be int")
      assert s.message == "must be int"
    end

    test "message overrides predicate failure" do
      s = spec(is_integer() and &(&1 > 0), message: "must be positive int")
      assert {:error, [error]} = conform(s, -1)
      assert error.message == "must be positive int"
    end
  end
end
