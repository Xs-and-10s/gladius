# Changelog

All notable changes to Gladius are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Gladius adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.0] — Unreleased

### Added

#### Default values — `default/2`

New combinator that injects a fallback when an optional schema key is absent.
The fallback is injected as-is — the inner spec only runs when the key is present.

```elixir
schema(%{
  required(:name)    => string(:filled?),
  optional(:role)    => default(atom(in?: [:admin, :user]), :user),
  optional(:retries) => default(integer(gte?: 0), 3)
})
```

- Absent key → fallback injected; inner spec not run
- Present key → inner spec validates the provided value normally
- Invalid provided value → error returned; fallback does not rescue it
- Required key → `default/2` has no effect on absence
- Composes with `ref/1` — a ref pointing to a `%Default{}` resolves correctly

#### Post-validation transforms — `transform/2`

New combinator that applies a function to the shaped value after validation
succeeds. Never runs on invalid data. Exceptions from the transform function
are caught and surfaced as `%Gladius.Error{predicate: :transform}`.

```elixir
schema(%{
  required(:name)  => transform(string(:filled?), &String.trim/1),
  required(:email) => transform(string(:filled?, format: ~r/@/), &String.downcase/1)
})

# Chainable via pipe — transform/2 is spec-first:
string(:filled?)
|> transform(&String.trim/1)
|> transform(&String.downcase/1)
```

- Runs after coercion and validation: `raw → coerce → validate → transform → {:ok, result}`
- Absent optional keys with `default(transform(...), val)` bypass the transform
- `gen/1` and `to_typespec/1` delegate to the inner spec

#### Struct validation

`conform/2` now accepts any Elixir struct as input. The struct is converted
to a plain map via `Map.from_struct/1` before dispatch. Output is a plain map.

```elixir
Gladius.conform(schema, %User{name: "Mark", email: "mark@x.com"})
#=> {:ok, %{name: "Mark", email: "mark@x.com"}}
```

`conform_struct/2` validates a struct and re-wraps the shaped output in the
original struct type on success.

```elixir
Gladius.conform_struct(schema, %User{name: "  Mark  ", age: "33"})
#=> {:ok, %User{name: "Mark", age: 33}}
```

`defschema` now accepts a `struct: true` option that defines both the
validator functions and a matching output struct in a single declaration.
The struct module is named `<CallerModule>.<PascalName>Schema`.

```elixir
defmodule MyApp.Schemas do
  import Gladius

  defschema :point, struct: true do
    schema(%{required(:x) => integer(), required(:y) => integer()})
  end
end

MyApp.Schemas.point(%{x: 3, y: 4})
#=> {:ok, %MyApp.Schemas.PointSchema{x: 3, y: 4}}
```

#### Ecto integration — `Gladius.Ecto`

New optional module `Gladius.Ecto` (guarded by
`Code.ensure_loaded?(Ecto.Changeset)`) that converts a Gladius schema into an
`Ecto.Changeset`. Requires `{:ecto, "~> 3.0"}` in the consuming application's
dependencies — Gladius does not pull it in transitively.

```elixir
# Schemaless (create workflows)
Gladius.Ecto.changeset(gladius_schema, params)

# Schema-aware (update workflows)
Gladius.Ecto.changeset(gladius_schema, params, %User{})
```

- String-keyed params (the Phoenix default) are normalised to atom keys
  before conforming — no manual atomisation step needed
- On `{:ok, shaped}` — changeset is valid; `changes` contains the fully
  shaped output with coercions, transforms, and defaults applied
- On `{:error, errors}` — changeset is invalid; each `%Gladius.Error{}` is
  mapped to `add_error/3` keyed on the last path segment
  (`%Error{path: [:address, :zip]}` → `add_error(cs, :zip, ...)`)
- Returns a plain `%Ecto.Changeset{}` — pipe Ecto validators after as normal

### Changed

- `conformable()` type union extended with `Gladius.Default` and
  `Gladius.Transform`
- `Gladius.Gen.gen/1` and `Gladius.Typespec.to_typespec/1` now handle
  `%Default{}` and `%Transform{}` by delegating to their inner spec

---

## [0.1.0] — unreleased

First public release.

### Spec algebra

- **Primitive builders** — `string/0-2`, `integer/0-2`, `float/0-2`,
  `number/0`, `boolean/0`, `atom/0-1`, `map/0`, `list/0-2`, `any/0`,
  `nil_spec/0`
- **Named constraints** — `filled?`, `gt?`, `gte?`, `lt?`, `lte?`,
  `min_length:`, `max_length:`, `size?:`, `format:`, `in?` — introspectable
  and generator-aware
- **Arbitrary predicates** — `spec/1` for cases named constraints can't cover
- **Combinators** — `all_of/1` (intersection), `any_of/1` (union),
  `not_spec/1` (complement), `maybe/1` (nullable), `list_of/1` (typed list),
  `cond_spec/2-3` (conditional branching)
- **Coercion** — `coerce/2` wraps any spec with a pre-processing step;
  runs before type-checking and constraints
- **Schemas** — `schema/1` (closed) and `open_schema/1`; errors accumulated
  across all keys in one pass, no short-circuiting

### Registry

- `defspec/2-3` — registers a named spec globally in ETS; accessible from
  any process via `ref/1`
- `defschema/2-3` — generates `name/1` and `name!/1` validator functions in
  the calling module
- `ref/1` — lazy registry reference; resolved at conform-time, enabling
  circular schemas
- Process-local overlay (`register_local/2`) for async-safe test isolation

### Coercion pipeline

- **Built-in source types** — `:string`, `:integer`, `:atom`, `:float`
- **Built-in pairs** — 11 source→target coercions: string→integer/float/
  boolean/atom/number, integer→float/string/boolean, atom→string,
  float→integer/string
- **User-extensible registry** — `Gladius.Coercions.register/2` backed by
  `:persistent_term`; user coercions take precedence over built-ins

### Generator inference

- `gen/1` — infers a `StreamData` generator from any spec
- Supports all primitives, combinators, and schemas
- Bounds-over-filters strategy for constrained numeric/string specs
  (avoids `FilterTooNarrowError`)
- Custom generators via `spec(pred, gen: my_generator)`

### Function signature checking

- `use Gladius.Signature` — opt-in per module
- `signature args: [...], ret: ..., fn: ...` — declares arg specs, return
  spec, and optional relationship constraint
- Validates and coerces all args before the impl runs; coerced values are
  forwarded (not the originals)
- Multi-clause functions: declare `signature` once before the first clause
- **Path errors** — all failing args reported in one raise; each error path
  prefixed with `{:arg, N}` so nested schema field failures render as
  `argument[0][:email]: must be filled`
- Zero overhead in `:prod` — signatures compile away entirely

### Typespec bridge

- `to_typespec/1` — converts any Gladius spec to quoted Elixir typespec AST
- `typespec_lossiness/1` — reports constraints that have no typespec
  equivalent (string format, negation, intersection, etc.)
- `type_ast/2` — generates `@type name :: type` declaration AST for macro
  injection
- `defspec :name, spec, type: true` — auto-generates `@type` with
  compile-time lossiness warnings
- `defschema :name, type: true do ... end` — same for schemas
- Integer constraint specialisation: `gte?: 0` → `non_neg_integer()`,
  `gt?: 0` → `pos_integer()`, `gte?: a, lte?: b` → `a..b`

---

[0.2.0]: https://github.com/Xs-and-10s/gladius/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Xs-and-10s/gladius/releases/tag/v0.1.0
