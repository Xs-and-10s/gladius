defmodule Gladius.Ecto do
  @moduledoc """
  Optional Ecto integration for Gladius.

  Converts a Gladius schema into an `Ecto.Changeset`, running full Gladius
  validation and mapping errors to changeset errors. Requires `ecto` to be
  present in your application's dependencies — Gladius does not pull it in
  by default.

  ## Usage

      # In your mix.exs — add alongside gladius:
      {:ecto, "~> 3.0"}           # most Phoenix apps already have this

  ## Schemaless changeset (create workflows)

      params = %{"name" => "Mark", "email" => "MARK@X.COM", "age" => "33"}

      schema = schema(%{
        required(:name)  => string(:filled?),
        required(:email) => transform(string(:filled?, format: ~r/@/), &String.downcase/1),
        required(:age)   => coerce(integer(gte?: 18), from: :string),
        optional(:role)  => default(atom(in?: [:admin, :user]), :user)
      })

      Gladius.Ecto.changeset(schema, params)
      #=> %Ecto.Changeset{valid?: true,
      #=>   changes: %{name: "Mark", email: "mark@x.com", age: 33, role: :user}}

  ## Schema-aware changeset (update workflows)

  Pass an existing struct as the third argument. Ecto will only mark fields
  that differ from the struct's current values as changes.

      user = %User{name: "Mark", email: "mark@x.com", age: 33, role: :admin}
      Gladius.Ecto.changeset(schema, %{"name" => "Mark", "age" => "40"}, user)
      #=> %Ecto.Changeset{valid?: true, changes: %{age: 40}}

  ## Errors

  On validation failure, Gladius errors are mapped to changeset errors keyed
  on the **last path segment**. Nested path errors such as
  `%Error{path: [:address, :zip]}` are surfaced as `add_error(cs, :zip, ...)`.

      Gladius.Ecto.changeset(schema, %{"name" => "", "age" => "15"})
      #=> %Ecto.Changeset{valid?: false,
      #=>   errors: [name: {"must be filled", []}, age: {"must be >= 18", []}]}

  ## Composing with Ecto validators

  The returned changeset is a plain `%Ecto.Changeset{}` — pipe Ecto validators
  after as normal. Gladius handles shape/type/constraint validation;
  database-level uniqueness and association constraints still go through Ecto.

      params
      |> Gladius.Ecto.changeset(schema)
      |> Ecto.Changeset.unique_constraint(:email)
      |> Repo.insert()

  ## Availability guard

  This module only exists when `Ecto.Changeset` is compiled into the project.
  Calling `Gladius.Ecto.changeset/2` when Ecto is absent raises
  `UndefinedFunctionError`. Guard with `Code.ensure_loaded?(Ecto.Changeset)`
  if you need to branch at runtime.
  """

  if Code.ensure_loaded?(Ecto.Changeset) do
    alias Gladius.{Schema, SchemaKey, Spec, Default, Transform, Maybe, All, Any, Ref, Error}

    @doc """
    Builds an `Ecto.Changeset` from a Gladius schema and params map.

    Runs full Gladius validation including coercions, transforms, and defaults.
    On success the changeset is valid and its `changes` contain the shaped
    output. On failure the changeset is invalid and its `errors` contain one
    entry per `%Gladius.Error{}`.

    ## Arguments

    - `gladius_schema` — a `%Gladius.Schema{}` built with `schema/1` or
      `open_schema/1`.
    - `params` — the raw input map (string or atom keys).
    - `base` — the base data for the changeset. Defaults to `%{}` for
      schemaless changesets (create workflows). Pass an existing struct for
      update workflows.
    """
    @spec changeset(Schema.t(), map(), map() | struct()) :: Ecto.Changeset.t()
    def changeset(gladius_schema, params, base \\ %{})

    def changeset(%Schema{} = gladius_schema, params, base) when is_map(params) do
      types  = infer_types(gladius_schema)
      fields = Map.keys(types)
      data   = {base, types}

      # Normalise string keys → atoms before conforming.
      # Phoenix sends all form/JSON params as string-keyed maps.
      # Gladius schemas are atom-keyed — without this step every field
      # would appear "missing" and coercions would never run.
      atom_params = atomize_keys(params)

      case Gladius.conform(gladius_schema, atom_params) do
        {:ok, shaped} ->
          # Pass already-shaped output — types are correct, no double-coercion.
          # Changeset is naturally valid since Ecto cast won't add errors for
          # well-typed values.
          Ecto.Changeset.cast(data, shaped, fields)

        {:error, errors} ->
          # Best-effort cast of raw params so Phoenix can render what the user
          # typed, then force invalid and map Gladius errors.
          data
          |> Ecto.Changeset.cast(atom_params, fields)
          |> Map.put(:valid?, false)
          |> apply_errors(errors)
      end
    end

    # -------------------------------------------------------------------------
    # Type inference
    # -------------------------------------------------------------------------

    # Builds a %{field_name => ecto_type} map from the schema's key list.
    # Ecto needs this to know how to cast and track changes per field.
    defp infer_types(%Schema{keys: keys}) do
      Map.new(keys, fn %SchemaKey{name: name, spec: spec} ->
        {name, infer_ecto_type(spec)}
      end)
    end

    # Primitive specs — direct mapping
    defp infer_ecto_type(%Spec{type: :string}),  do: :string
    defp infer_ecto_type(%Spec{type: :integer}), do: :integer
    defp infer_ecto_type(%Spec{type: :float}),   do: :float
    defp infer_ecto_type(%Spec{type: :number}),  do: :float
    defp infer_ecto_type(%Spec{type: :boolean}), do: :boolean
    defp infer_ecto_type(%Spec{type: :map}),     do: :map

    # Ecto has no :atom type — use :any so the shaped atom passes through
    defp infer_ecto_type(%Spec{type: :atom}),    do: :any
    defp infer_ecto_type(%Spec{type: :any}),     do: :any
    defp infer_ecto_type(%Spec{type: :null}),    do: :any
    defp infer_ecto_type(%Spec{type: :list}),    do: {:array, :any}
    defp infer_ecto_type(%Spec{type: nil}),      do: :any

    # Transparent wrappers — unwrap and delegate
    defp infer_ecto_type(%Default{spec: inner}),   do: infer_ecto_type(inner)
    defp infer_ecto_type(%Transform{spec: inner}), do: infer_ecto_type(inner)
    defp infer_ecto_type(%Maybe{spec: inner}),     do: infer_ecto_type(inner)

    # all_of — use the first typed spec (same as typespec bridge)
    defp infer_ecto_type(%All{specs: [first | _]}), do: infer_ecto_type(first)
    defp infer_ecto_type(%All{specs: []}),           do: :any

    # any_of — use :any (union type; Ecto can't express this)
    defp infer_ecto_type(%Any{}), do: :any

    # Ref — resolve one level; fall back to :any if registry miss
    defp infer_ecto_type(%Ref{name: name}) do
      infer_ecto_type(Gladius.Registry.fetch!(name))
    rescue
      _ -> :any
    end

    # ListOf — typed array
    defp infer_ecto_type(%Gladius.ListOf{element_spec: el}) do
      {:array, infer_ecto_type(el)}
    end

    # Nested schema — :map (Ecto embeds_one is out of scope for schemaless)
    defp infer_ecto_type(%Schema{}), do: :map

    # Fallback for any unknown conformable
    defp infer_ecto_type(_), do: :any

    # -------------------------------------------------------------------------
    # Error mapping
    # -------------------------------------------------------------------------

    defp apply_errors(changeset, errors) do
      Enum.reduce(errors, changeset, fn %Error{path: path, message: message}, cs ->
        field = last_segment(path)
        Ecto.Changeset.add_error(cs, field, message)
      end)
    end

    # ---------------------------------------------------------------------------
    # Key normalisation
    # ---------------------------------------------------------------------------

    # Converts top-level string keys to existing atoms.
    # Nested values are left as-is — Gladius handles nested map conforming.
    # Keys that have no corresponding atom (truly unknown fields) are kept as
    # strings; the schema's unknown-key check will produce an error for them.
    defp atomize_keys(params) when is_map(params) do
      Map.new(params, fn
        {k, v} when is_binary(k) ->
          atom =
            try do
              String.to_existing_atom(k)
            rescue
              ArgumentError -> k
            end
          {atom, v}
        {k, v} ->
          {k, v}
      end)
    end

    defp atomize_keys(other), do: other

    # Root-level error (path: []) → :base — Ecto's conventional field for
    # non-field errors (e.g. "must be a map").
    defp last_segment([]), do: :base

    defp last_segment(path) do
      case List.last(path) do
        segment when is_atom(segment) ->
          segment

        segment when is_binary(segment) ->
          # String key — happens when params were string-keyed.
          # Convert to atom; fall back to :base for truly unknown keys.
          try do
            String.to_existing_atom(segment)
          rescue
            ArgumentError -> :base
          end

        # List index at the tail means an element-level error.
        # Surface under :base — callers can inspect the full Error for detail.
        segment when is_integer(segment) ->
          :base
      end
    end
  end
end
