defmodule Inspex.UndefinedSpecError do
  @moduledoc "Raised when `ref/1` resolves against an unregistered spec name."
  defexception [:name]

  @impl true
  def message(%{name: name}) do
    """
    No spec registered under #{inspect(name)}.

    Register it with:

        Inspex.def(#{inspect(name)}, your_spec_here)

    (Step 1 registry uses the process dictionary — run Inspex.Registry.start/0
    or call register/2 directly before using ref/1.)
    """
  end
end

defmodule Inspex.Registry do
  @moduledoc """
  Named spec registry — **Step 1 implementation via the process dictionary**.

  The process dictionary keeps things self-contained with no supervision tree
  required. This means specs are registered *per-process* — perfect for tests
  and iex sessions. Step 2 replaces the body of `fetch!/1` and `register/2`
  with ETS + GenServer calls; the public API surface stays identical.

  ## Why not a module attribute / compile-time map?

  Lazy runtime resolution is what enables:
  - Circular schemas (a tree node whose children are also tree nodes)
  - Overriding specs in tests without touching production code
  - Hot-reloading specs in development

  ## Step 1 usage

      Inspex.Registry.register(:email, Inspex.string(:filled?, format: ~r/@/))
      Inspex.Registry.fetch!(:email)
      #=> %Inspex.Spec{type: :string, constraints: [filled?: true, format: ~r/@/]}
  """

  @pdict_prefix :__inspex_spec__

  @doc """
  Returns the spec registered under `name` in the current process.
  Raises `Inspex.UndefinedSpecError` if nothing is registered.
  """
  @spec fetch!(atom()) :: term()
  def fetch!(name) when is_atom(name) do
    case Process.get({@pdict_prefix, name}) do
      nil  -> raise Inspex.UndefinedSpecError, name: name
      spec -> spec
    end
  end

  @doc """
  Registers `spec` under `name` in the current process.
  Overwrites any previous registration for the same name.
  """
  @spec register(atom(), term()) :: :ok
  def register(name, spec) when is_atom(name) do
    Process.put({@pdict_prefix, name}, spec)
    :ok
  end

  @doc "Removes the registration for `name` from the current process."
  @spec unregister(atom()) :: :ok
  def unregister(name) when is_atom(name) do
    Process.delete({@pdict_prefix, name})
    :ok
  end

  @doc "Removes all inspex specs from the current process's dictionary."
  @spec clear() :: :ok
  def clear do
    Process.get_keys()
    |> Enum.filter(&match?({@pdict_prefix, _}, &1))
    |> Enum.each(&Process.delete/1)
    :ok
  end
end
