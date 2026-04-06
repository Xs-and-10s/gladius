defmodule Gladius.Translator do
  @moduledoc """
  Behaviour for plugging a custom message translator into Gladius.

  When a translator is configured, every built-in error message produced by
  Gladius is passed through it. Custom `message:` tuples
  (`{domain, msgid, bindings}`) are also dispatched through the translator.
  Plain string `message:` overrides bypass the translator entirely — they are
  assumed to be already-localised.

  ## Configuration

      # config/config.exs
      config :gladius, translator: MyApp.GladiusTranslator

  ## Implementing a translator

      defmodule MyApp.GladiusTranslator do
        @behaviour Gladius.Translator
        use Gettext, backend: MyAppWeb.Gettext

        @impl Gladius.Translator
        def translate(domain, msgid, bindings) do
          dgettext(domain || "errors", msgid, bindings)
        end
      end

  ## LLM-based translation

  The structured `{domain, msgid, bindings}` form is intentionally compatible
  with approaches beyond Gettext. An LLM translator, for example, can use
  `msgid` as a template and `bindings` for interpolation context without any
  pre-compiled catalogue:

      defmodule MyApp.LLMTranslator do
        @behaviour Gladius.Translator

        @impl Gladius.Translator
        def translate(_domain, msgid, bindings) do
          MyApp.LLM.translate_to_locale(msgid, bindings, locale: Gettext.get_locale())
        end
      end

  ## Built-in message keys

  Gladius populates `message_key` and `message_bindings` on every
  `%Gladius.Error{}` so translators can look up catalogue entries by key
  rather than matching on the English default string:

      :filled?      — []
      :gt?          — [min: n]
      :gte?         — [min: n]
      :lt?          — [max: n]
      :lte?         — [max: n]
      :min_length   — [min: n]
      :max_length   — [max: n]
      :size?        — [size: n]
      :format       — [format: regex]
      :in?          — [values: list]
      :type?        — [expected: type, actual: type]
      :coerce       — [original: value]
      :transform    — [reason: message]
  """

  @doc """
  Translates a validation message.

  - `domain` — the Gettext domain string (e.g. `"errors"`), or `nil` for the
    default domain. Supplied when the caller uses the
    `{domain, msgid, bindings}` tuple form.
  - `msgid`  — the untranslated English message string or message ID.
  - `bindings` — keyword list of interpolation values. Built-in errors always
    include the dynamic values that appear in the default message.
  """
  @callback translate(
              domain :: String.t() | nil,
              msgid :: String.t(),
              bindings :: keyword()
            ) :: String.t()
end
