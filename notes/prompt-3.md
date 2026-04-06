I'm continuing development of Gladius, an Elixir validation library I built in a previous session. The full session is here — read it before proceeding: https://claude.ai/chat/1c077786-39f8-4700-9b86-3388a352e4f3
The session contains the complete library: spec algebra, registry, coercion pipeline, generator inference, signature function contracts, typespec bridge (to_typespec/1), and defspec/defschema with type: true. All 190+ tests pass. It was published to Hex.pm as gladius.
At the end of that session we did a retrospective comparing Gladius to norm, drops, and peri. We identified four concrete gaps that prevent Gladius from being the library Elixir developers reach for by default. I want to close all four in this session, in priority order.

The four gaps to close
1. No Ecto integration (highest priority)
Gladius has no to_changeset/1. Peri has it. Most Phoenix/Ecto projects need to validate data through Ecto changesets for error formatting, HTML form integration, and database-layer validation. A Gladius schema should be convertible to an Ecto schemaless changeset. This should be an optional integration — Code.ensure_loaded?(Ecto.Changeset) guarded — so Gladius stays a zero-Ecto-dependency library by default.
2. No default values
When schema/1 conforms a map with an absent optional key, that key is simply absent in the output. Peri supports {:default, value}. We need a default/2 combinator or an optional(:key, default: value) syntax so callers can declare fallbacks without post-processing the conformed output.
3. No field transformations (post-validation)
Gladius has coercion before validation but no transformation after. A common need: trim strings, downcase emails, normalize phone numbers. We need a transform/2 combinator — something like transform(string(:filled?), &String.trim/1) — that runs after validation succeeds and shapes the output value.
4. No struct validation
Gladius only validates maps. %User{} can't be passed to conform/2 without Map.from_struct/1 first. We need conform/2 to accept structs, and ideally a defschema variant that generates a struct-aware validator.

What I want from this session
Before writing any code, read the previous session carefully and understand:

The exact struct definitions in types.ex
How conform/2 dispatches on struct type
How defschema generates functions
How the coercion pipeline works (the coerce field on %Spec{}, the Gladius.conform clause ordering)
How the registry and ref/1 lazy resolution work

Then propose a concrete implementation plan for all four gaps, with the interfaces you're proposing for each (API, struct changes, new modules). Get my sign-off on the plan before writing any code. Build one gap at a time, tests first, and confirm green before moving to the next.
The library module is Gladius (renamed from Inspex after publishing). The app name in mix.exs is :gladius. All module names should be Gladius.*.
