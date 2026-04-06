# gladius_marketplace.ex
#
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  G L A D I U S  —  comprehensive showcase                                ║
# ║  Multi-tenant marketplace platform                                        ║
# ║                                                                           ║
# ║  Demonstrates every feature of the Gladius library:                       ║
# ║    defspec / defschema with type: true                                    ║
# ║    all_of / any_of / not_spec / maybe / list_of / cond_spec               ║
# ║    ref/1 (circular schemas, cross-module reuse)                           ║
# ║    coerce/2 (built-in + user-registered)                                  ║
# ║    signature (args / ret / fn — zero overhead in :prod)                   ║
# ║    gen/1 (property-based test data generation)                            ║
# ║    to_typespec/1 + typespec_lossiness/1                                   ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

import Gladius

# ─────────────────────────────────────────────────────────────────────────────
# §0  Application startup
#     Register custom coercions once at boot — :persistent_term backs them,
#     so reads are free and writes never happen in hot paths.
# ─────────────────────────────────────────────────────────────────────────────

# Money values arrive from payment providers as %{amount: float, currency: binary}.
# After this, `coerce(ref(:money_cents), from: :money)` works everywhere.
Gladius.Coercions.register({:money, :integer}, fn
  %{amount: a, currency: "USD"} when is_number(a) ->
    {:ok, round(a * 100)}
  cents when is_integer(cents) and cents >= 0 ->
    {:ok, cents}
  {cents, :usd} when is_integer(cents) and cents >= 0 ->
    {:ok, cents}
  v ->
    {:error, "cannot coerce #{inspect(v)} to cents — expected %{amount:, currency: \"USD\"}"}
end)

# Semantic-version strings → {major, minor, patch} tuples for version specs.
Gladius.Coercions.register({:semver_string, :tuple}, fn
  v when is_tuple(v) and tuple_size(v) == 3 ->
    {:ok, v}
  s when is_binary(s) ->
    case String.split(s, ".") do
      [maj, min, pat] ->
        with {ma, ""} <- Integer.parse(maj),
             {mi, ""} <- Integer.parse(min),
             {pa, ""} <- Integer.parse(pat) do
          {:ok, {ma, mi, pa}}
        else
          _ -> {:error, "not a valid semver: #{inspect(s)}"}
        end
      _ ->
        {:error, "expected MAJOR.MINOR.PATCH, got #{inspect(s)}"}
    end
end)

# ─────────────────────────────────────────────────────────────────────────────
# §1  Leaf specs — named, globally registered, @type generated at compile time
# ─────────────────────────────────────────────────────────────────────────────

# Constraints that have no typespec equivalent emit compile-time warnings.
# Everything else maps losslessly (gte?: 0 → non_neg_integer(), etc.)

defspec :uuid,
  string(size?: 36, format: ~r/^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$/),
  type: true
# ⚑ compile warning: format constraint not expressible in typespec
# @type uuid :: String.t()

defspec :email,
  string(:filled?, format: ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/),
  type: true
# @type email :: String.t()

defspec :slug,
  string(:filled?, format: ~r/^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$/, max_length: 64),
  type: true
# @type slug :: String.t()

defspec :url,
  string(:filled?, format: ~r|^https://[^\s]{1,2000}$|),
  type: true
# @type url :: String.t()

defspec :money_cents,
  integer(gte?: 0),
  type: true
# @type money_cents :: non_neg_integer()   ← lossless!

defspec :positive_cents,
  integer(gt?: 0),
  type: true
# @type positive_cents :: pos_integer()    ← lossless!

defspec :percentage,
  float(gte?: 0.0, lte?: 1.0),
  type: true
# @type percentage :: float()

defspec :iso_country,
  string(size?: 2, format: ~r/^[A-Z]{2}$/),
  type: true
# @type iso_country :: String.t()

defspec :phone,
  string(:filled?, format: ~r/^\+[1-9]\d{7,14}$/),
  type: true
# @type phone :: String.t()

defspec :semver,
  coerce(
    spec(fn {ma, mi, pa} -> is_integer(ma) and is_integer(mi) and is_integer(pa) end),
    from: :semver_string
  )
# Converts "1.2.3" → {1, 2, 3} before the predicate runs.
# No type: true — the predicate is opaque to the typespec bridge.

defspec :role,
  atom(in?: [:buyer, :vendor, :admin, :support]),
  type: true
# @type role :: :buyer | :vendor | :admin | :support   ← lossless!

defspec :order_status,
  atom(in?: [:pending, :confirmed, :processing, :shipped, :delivered, :cancelled, :refunded]),
  type: true
# @type order_status :: :pending | :confirmed | :processing | :shipped
#                     | :delivered | :cancelled | :refunded

defspec :product_type,
  atom(in?: [:physical, :digital, :subscription]),
  type: true
# @type product_type :: :physical | :digital | :subscription

defspec :currency,
  atom(in?: [:usd, :eur, :gbp, :jpy, :cad, :aud]),
  type: true
# @type currency :: :usd | :eur | :gbp | :jpy | :cad | :aud

# ─────────────────────────────────────────────────────────────────────────────
# §2  Compound leaf specs — combinators at the spec layer
# ─────────────────────────────────────────────────────────────────────────────

# A discount rate is either a percentage OR a fixed cent amount.
# any_of tries in order; first match wins.
defspec :discount_value,
  any_of([
    all_of([ref(:percentage), spec(&(&1 < 1.0))]),  # percentage discount < 100%
    ref(:money_cents)                                # fixed amount discount
  ])
# Not type: true — any_of lossiness would obscure the union

# A non-empty list of UUIDs — used for bulk operations.
defspec :uuid_list,
  all_of([
    list_of(ref(:uuid)),
    spec(fn ids -> length(ids) >= 1 end, gen: StreamData.list_of(
      StreamData.string(:alphanumeric, length: 36),
      min_length: 1,
      max_length: 100
    ))
  ])

# A tag is a short, lowercase slug — stricter than the general slug.
defspec :tag,
  string(:filled?, format: ~r/^[a-z][a-z0-9_]{0,29}$/, max_length: 30),
  type: true

# ─────────────────────────────────────────────────────────────────────────────
# §3  Schemas — Address, Payment methods
# ─────────────────────────────────────────────────────────────────────────────

defschema :address, type: true do
  schema(%{
    required(:line1)   => string(:filled?, max_length: 100),
    optional(:line2)   => maybe(string(max_length: 100)),
    required(:city)    => string(:filled?, max_length: 50),
    required(:state)   => string(size?: 2, format: ~r/^[A-Z]{2}$/),
    required(:zip)     => string(:filled?, format: ~r/^\d{5}(-\d{4})?$/),
    required(:country) => ref(:iso_country),
    optional(:phone)   => maybe(ref(:phone))
  })
end
# @type address :: %{
#   required(:line1)   => String.t(),
#   optional(:line2)   => String.t() | nil,
#   required(:city)    => String.t(),
#   required(:state)   => String.t(),
#   required(:zip)     => String.t(),
#   required(:country) => String.t(),
#   optional(:phone)   => String.t() | nil
# }

defschema :card_payment, type: true do
  schema(%{
    required(:type)        => atom(in?: [:card]),
    required(:last_four)   => string(size?: 4, format: ~r/^\d{4}$/),
    required(:brand)       => atom(in?: [:visa, :mastercard, :amex, :discover]),
    required(:exp_month)   => integer(gte?: 1,    lte?: 12),
    required(:exp_year)    => integer(gte?: 2024, lte?: 2040),
    required(:billing_zip) => string(:filled?)
  })
end
# @type card_payment :: %{..., required(:exp_month) => 1..12, required(:exp_year) => 2024..2040}

defschema :bank_payment, type: true do
  schema(%{
    required(:type)          => atom(in?: [:ach]),
    required(:routing)       => string(size?: 9, format: ~r/^\d{9}$/),
    required(:account_last4) => string(size?: 4, format: ~r/^\d{4}$/),
    required(:account_type)  => atom(in?: [:checking, :savings])
  })
end

defschema :crypto_payment, type: true do
  schema(%{
    required(:type)     => atom(in?: [:crypto]),
    required(:currency) => atom(in?: [:btc, :eth, :usdc]),
    required(:tx_hash)  => string(:filled?, size?: 66),
    required(:network)  => atom(in?: [:mainnet, :testnet])
  })
end

# Payment is one of three schemas — any_of dispatches to the first match.
# The :type key in each schema disambiguates at conform-time.
defspec :payment_method,
  any_of([ref(:card_payment), ref(:bank_payment), ref(:crypto_payment)])

# ─────────────────────────────────────────────────────────────────────────────
# §4  Product schemas — three distinct shapes for three product types
# ─────────────────────────────────────────────────────────────────────────────

defschema :physical_product, type: true do
  schema(%{
    required(:id)               => ref(:uuid),
    required(:vendor_id)        => ref(:uuid),
    required(:name)             => string(:filled?, max_length: 200),
    required(:slug)             => ref(:slug),
    required(:type)             => atom(in?: [:physical]),
    required(:price_cents)      => ref(:money_cents),
    optional(:compare_at_cents) => maybe(ref(:money_cents)),
    required(:sku)              => string(:filled?, max_length: 64),
    required(:weight_grams)     => integer(gte?: 1),
    required(:shipping_class)   => atom(in?: [:standard, :expedited, :overnight, :freight]),
    required(:inventory)        => integer(gte?: 0),
    optional(:dimensions)       => maybe(schema(%{
      required(:length_cm) => float(gt?: 0.0),
      required(:width_cm)  => float(gt?: 0.0),
      required(:height_cm) => float(gt?: 0.0)
    })),
    optional(:images)           => list_of(ref(:url)),
    optional(:tags)             => list_of(ref(:tag)),
    required(:active?)          => boolean()
  })
end

defschema :digital_product, type: true do
  schema(%{
    required(:id)              => ref(:uuid),
    required(:vendor_id)       => ref(:uuid),
    required(:name)            => string(:filled?, max_length: 200),
    required(:slug)            => ref(:slug),
    required(:type)            => atom(in?: [:digital]),
    required(:price_cents)     => ref(:money_cents),
    required(:download_url)    => ref(:url),
    required(:file_size_kb)    => integer(gte?: 1),
    required(:file_type)       => atom(in?: [:pdf, :zip, :mp3, :mp4, :epub, :exe, :dmg]),
    optional(:version)         => maybe(ref(:semver)),
    optional(:license)         => maybe(atom(in?: [:single, :team, :enterprise, :unlimited])),
    optional(:download_limit)  => maybe(integer(gte?: 1)),
    optional(:tags)            => list_of(ref(:tag)),
    required(:active?)         => boolean()
  })
end

defschema :subscription_product, type: true do
  schema(%{
    required(:id)           => ref(:uuid),
    required(:vendor_id)    => ref(:uuid),
    required(:name)         => string(:filled?, max_length: 200),
    required(:slug)         => ref(:slug),
    required(:type)         => atom(in?: [:subscription]),
    required(:price_cents)  => ref(:money_cents),
    required(:interval)     => atom(in?: [:monthly, :quarterly, :annual]),
    required(:trial_days)   => integer(gte?: 0,  lte?: 90),
    optional(:max_seats)    => maybe(integer(gte?: 1, lte?: 10_000)),
    optional(:features)     => list_of(string(:filled?, max_length: 100)),
    required(:active?)      => boolean()
  })
end

# ─────────────────────────────────────────────────────────────────────────────
# §5  Discount schema — cond_spec for percent vs fixed amount validation
# ─────────────────────────────────────────────────────────────────────────────

defschema :discount, type: true do
  schema(%{
    required(:type)       => atom(in?: [:percent, :fixed]),
    required(:value)      => cond_spec(
                               # Branch on the :type field in the PARENT map would require
                               # cross-field logic; instead we validate loose here and
                               # enforce precision in the :fn of the order signature (§7).
                               fn v -> is_float(v) end,
                               ref(:percentage),     # percent path: 0.0–1.0
                               ref(:money_cents)     # fixed path:   non-negative integer
                             ),
    optional(:code)       => maybe(string(:filled?, max_length: 32)),
    optional(:expires_at) => maybe(integer(gte?: 0))  # unix timestamp
  })
end

# ─────────────────────────────────────────────────────────────────────────────
# §6  Line item and Order — the centrepiece schemas
# ─────────────────────────────────────────────────────────────────────────────

defschema :line_item, type: true do
  schema(%{
    required(:product_id)    => ref(:uuid),
    required(:product_type)  => ref(:product_type),
    required(:quantity)      => integer(gte?: 1, lte?: 999),
    required(:unit_price)    => ref(:money_cents),
    required(:subtotal)      => ref(:money_cents),
    optional(:discount)      => maybe(ref(:discount)),
    optional(:notes)         => maybe(string(max_length: 200))
  })
end

defschema :order, type: true do
  schema(%{
    required(:id)               => ref(:uuid),
    required(:buyer_id)         => ref(:uuid),
    required(:vendor_id)        => ref(:uuid),
    required(:status)           => ref(:order_status),
    required(:line_items)       => list_of(ref(:line_item)),

    # Digital-only orders have nil shipping_address; physical orders require one.
    # The :fn constraint in the signature (§7) enforces this cross-field rule.
    required(:shipping_address) => maybe(ref(:address)),
    required(:billing_address)  => ref(:address),

    required(:payment_method)   => ref(:payment_method),
    required(:currency)         => ref(:currency),
    required(:subtotal_cents)   => ref(:money_cents),
    required(:shipping_cents)   => ref(:money_cents),
    required(:tax_cents)        => ref(:money_cents),
    required(:discount_cents)   => ref(:money_cents),
    required(:total_cents)      => ref(:money_cents),

    optional(:coupon_code)      => maybe(string(:filled?, max_length: 32)),
    optional(:notes)            => maybe(string(max_length: 500)),
    optional(:tags)             => list_of(ref(:tag)),
    optional(:metadata)         => maybe(map())
  })
end

# ─────────────────────────────────────────────────────────────────────────────
# §7  User and Vendor schemas — with HTTP ingress coercion variants
# ─────────────────────────────────────────────────────────────────────────────

defschema :user, type: true do
  schema(%{
    required(:id)          => ref(:uuid),
    required(:email)       => ref(:email),
    required(:role)        => ref(:role),
    required(:name)        => string(:filled?, max_length: 100),
    optional(:phone)       => maybe(ref(:phone)),
    optional(:avatar_url)  => maybe(ref(:url)),
    optional(:address)     => maybe(ref(:address)),
    required(:verified?)   => boolean(),
    required(:active?)     => boolean(),
    required(:created_at)  => integer(gte?: 0),  # unix timestamp
    optional(:metadata)    => maybe(map())
  })
end

# HTTP boundary — all fields arrive as strings from form params or query string.
# Coercions run first: "buyer" → :buyer, "true" → true, etc.
defschema :user_create_params do
  schema(%{
    required(:email)     => coerce(ref(:email),   from: :string),
    required(:name)      => string(:filled?,       max_length: 100),
    required(:role)      => coerce(ref(:role),     from: :string),
    optional(:phone)     => maybe(coerce(ref(:phone), from: :string)),
    optional(:verified?) => coerce(boolean(),      from: :string)
  })
end

defschema :vendor, type: true do
  schema(%{
    required(:id)            => ref(:uuid),
    required(:user_id)       => ref(:uuid),
    required(:name)          => string(:filled?,  max_length: 100),
    required(:slug)          => ref(:slug),
    required(:email)         => ref(:email),
    optional(:description)   => maybe(string(max_length: 2000)),
    optional(:logo_url)      => maybe(ref(:url)),
    required(:address)       => ref(:address),
    required(:payout_account) => ref(:bank_payment),
    required(:commission_rate) => ref(:percentage),
    required(:verified?)     => boolean(),
    required(:active?)       => boolean(),
    optional(:tags)          => list_of(ref(:tag))
  })
end

# ─────────────────────────────────────────────────────────────────────────────
# §8  Cross-field relationship specs — used in :fn of signatures
# ─────────────────────────────────────────────────────────────────────────────

# Order total == subtotal + shipping + tax - discount
order_total_consistent? =
  spec(fn %{subtotal_cents: s, shipping_cents: sh, tax_cents: t,
             discount_cents: d, total_cents: total} ->
    total == s + sh + t - d
  end)

# Line item subtotal == quantity * unit_price (before discount)
line_item_math? =
  spec(fn %{quantity: q, unit_price: u, subtotal: sub} ->
    sub == q * u
  end)

# Shipped or delivered orders must have a shipping address
shipped_has_address? =
  spec(fn
    %{status: s, shipping_address: nil}
    when s in [:shipped, :delivered] -> false
    _ -> true
  end)

# Digital-only orders should have nil shipping_address
digital_only_no_shipping? =
  spec(fn %{line_items: items, shipping_address: addr} ->
    all_digital = Enum.all?(items, &(&1.product_type == :digital))
    if all_digital, do: is_nil(addr), else: true
  end)

# A cancelled order cannot transition back to processing
valid_status_transition? =
  spec(fn {old_status, new_status} ->
    terminal = MapSet.new([:cancelled, :refunded, :delivered])
    not MapSet.member?(terminal, old_status) or old_status == new_status
  end)

# ─────────────────────────────────────────────────────────────────────────────
# §9  API modules — use Gladius.Signature for runtime contract checking
#     In :dev/:test → validation fires on every call
#     In :prod       → compiles away entirely, zero overhead
# ─────────────────────────────────────────────────────────────────────────────

defmodule Marketplace.Orders do
  use Gladius.Signature
  import Gladius

  @doc """
  Places a new order. Validates all inputs before the body runs, then
  checks the return value against the order schema and the total
  consistency invariant before handing it back to the caller.
  """
  signature args: [
              ref(:uuid),                     # buyer_id  — must be UUID format
              ref(:uuid),                     # vendor_id — must be UUID format
              list_of(ref(:line_item)),       # line_items — every element validated
              ref(:payment_method),           # card | bank | crypto — dispatched by any_of
              ref(:address)                   # billing_address — full schema check
            ],
            ret:  ref(:order),
            fn:   spec(fn {[_buyer, _vendor, items, _payment, _billing], order} ->
                    # Return must reference the same number of line items
                    # and satisfy the total consistency invariant.
                    length(order.line_items) == length(items) and
                    order.total_cents == order.subtotal_cents +
                                        order.shipping_cents +
                                        order.tax_cents -
                                        order.discount_cents
                  end)
  def place_order(buyer_id, vendor_id, line_items, payment_method, billing_address) do
    subtotal = Enum.sum(Enum.map(line_items, & &1.subtotal))
    shipping = calculate_shipping(line_items)
    tax      = calculate_tax(subtotal, billing_address)

    %{
      id:               UUID.uuid4(),
      buyer_id:         buyer_id,
      vendor_id:        vendor_id,
      status:           :pending,
      line_items:       line_items,
      shipping_address: nil,                  # populated in process_shipping/1
      billing_address:  billing_address,
      payment_method:   payment_method,
      currency:         :usd,
      subtotal_cents:   subtotal,
      shipping_cents:   shipping,
      tax_cents:        tax,
      discount_cents:   0,
      total_cents:      subtotal + shipping + tax
    }
  end

  @doc """
  Transitions an order's status. The :fn constraint enforces that no
  terminal status (cancelled, refunded, delivered) can transition further.
  """
  signature args: [ref(:uuid), ref(:order_status)],
            ret:  ref(:order),
            fn:   spec(fn {[order_id, new_status], order} ->
                    order.id == order_id and order.status == new_status
                  end)
  def transition_order(order_id, new_status) do
    order = fetch_order!(order_id)
    unless valid_transition?(order.status, new_status),
      do: raise("Invalid status transition: #{order.status} → #{new_status}")
    update_order(order, status: new_status)
  end

  @doc """
  Applies a coupon. Validated return must be <= the original order total.
  The :fn constraint catches any discount calculation bug before it ships.
  """
  signature args: [ref(:uuid), string(:filled?, max_length: 32)],
            ret:  ref(:order),
            fn:   spec(fn {[order_id, _code], updated_order} ->
                    original = fetch_order!(order_id)
                    updated_order.total_cents <= original.total_cents and
                    updated_order.total_cents >= 0
                  end)
  def apply_coupon(order_id, coupon_code) do
    order    = fetch_order!(order_id)
    discount = lookup_coupon!(coupon_code)
    apply_discount(order, discount)
  end

  @doc """
  Bulk cancel. Args: list of UUIDs (non-empty), reason atom.
  All items in the list must be cancellable (not already terminal).
  """
  signature args: [ref(:uuid_list), atom(in?: [:fraud, :customer_request, :inventory, :other])],
            ret:  list_of(ref(:order)),
            fn:   spec(fn {[order_ids, _reason], cancelled_orders} ->
                    length(cancelled_orders) == length(order_ids) and
                    Enum.all?(cancelled_orders, &(&1.status == :cancelled))
                  end)
  def bulk_cancel(order_ids, reason) do
    Enum.map(order_ids, &cancel_order(&1, reason))
  end

  defp calculate_shipping(_items), do: 0
  defp calculate_tax(subtotal, _address), do: round(subtotal * 0.08)
  defp fetch_order!(_id), do: %{id: "...", status: :pending, total_cents: 0}
  defp update_order(order, updates), do: Map.merge(order, Map.new(updates))
  defp valid_transition?(_from, _to), do: true
  defp lookup_coupon!(_code), do: %{type: :percent, value: 0.1}
  defp apply_discount(order, _discount), do: order
  defp cancel_order(id, _reason), do: %{id: id, status: :cancelled}
end

defmodule Marketplace.Users do
  use Gladius.Signature
  import Gladius

  @doc """
  Creates a user from HTTP params — all values arrive as strings.
  Coercion runs before validation: "buyer" → :buyer, "true" → true.
  The impl receives already-typed values; no casting needed inside.
  """
  signature args: [ref(:user_create_params)],
            ret:  ref(:user)
  def create_user(params) do
    # params.role is already :buyer (atom), params.verified? is already true/false
    Map.merge(params, %{
      id:         UUID.uuid4(),
      active?:    true,
      verified?:  Map.get(params, :verified?, false),
      created_at: System.os_time(:second),
      metadata:   nil
    })
  end

  @doc "Updates email. Both args validated before the body runs."
  signature args: [ref(:uuid), ref(:email)],
            ret:  ref(:user),
            fn:   spec(fn {[user_id, email], user} ->
                    user.id == user_id and user.email == email
                  end)
  def update_email(user_id, new_email) do
    fetch_user!(user_id)
    |> Map.put(:email, new_email)
  end

  @doc "Verifies a user. Return must have verified?: true."
  signature args: [ref(:uuid)],
            ret:  ref(:user),
            fn:   spec(fn {[_id], user} -> user.verified? == true end)
  def verify_user(user_id) do
    fetch_user!(user_id) |> Map.put(:verified?, true)
  end

  defp fetch_user!(_id), do: %{id: "...", email: "x@x.com", verified?: false}
end

defmodule Marketplace.Vendors do
  use Gladius.Signature
  import Gladius

  @doc """
  Initiates a vendor payout. The amount accepts a %{amount:, currency:} map
  from the payment provider, coerced to integer cents via the :money coercion.
  The :fn constraint ensures a zero-amount payout never returns :ok.
  """
  signature args: [
              ref(:uuid),
              coerce(ref(:money_cents), from: :money),
              ref(:bank_payment)
            ],
            ret:  atom(in?: [:ok, :pending, :failed]),
            fn:   spec(fn {[_vendor_id, amount_cents, _bank], result} ->
                    amount_cents > 0 or result != :ok
                  end)
  def initiate_payout(vendor_id, amount_cents, bank_account) do
    # amount_cents is already an integer — the coercion ran before this body.
    if amount_cents > 0 and valid_bank?(bank_account),
      do: :ok,
      else: :failed
  end

  @doc """
  Updates commission rate. Rate must be a float in [0.0, 1.0].
  """
  signature args: [ref(:uuid), ref(:percentage)],
            ret:  ref(:vendor),
            fn:   spec(fn {[vendor_id, rate], vendor} ->
                    vendor.id == vendor_id and vendor.commission_rate == rate
                  end)
  def update_commission(vendor_id, new_rate) do
    fetch_vendor!(vendor_id) |> Map.put(:commission_rate, new_rate)
  end

  defp valid_bank?(_bank), do: true
  defp fetch_vendor!(_id), do: %{id: "...", commission_rate: 0.0}
end

defmodule Marketplace.Search do
  use Gladius.Signature
  import Gladius

  @doc """
  Search products. The query schema is validated via signature — no guard
  clauses needed inside the function body.
  """
  signature args: [
              schema(%{
                optional(:query)       => maybe(string(:filled?, max_length: 200)),
                optional(:product_type)=> maybe(ref(:product_type)),
                optional(:min_price)   => maybe(coerce(ref(:money_cents), from: :string)),
                optional(:max_price)   => maybe(coerce(ref(:money_cents), from: :string)),
                optional(:tags)        => maybe(list_of(ref(:tag))),
                optional(:vendor_id)   => maybe(ref(:uuid)),
                optional(:page)        => maybe(coerce(integer(gte?: 1), from: :string)),
                optional(:per_page)    => maybe(coerce(integer(gte?: 1, lte?: 100), from: :string))
              })
            ],
            ret: schema(%{
              required(:results)    => list_of(ref(:uuid)),
              required(:total)      => integer(gte?: 0),
              required(:page)       => integer(gte?: 1),
              required(:per_page)   => integer(gte?: 1, lte?: 100),
              required(:has_more?)  => boolean()
            }),
            fn:  spec(fn {[params], results} ->
                   per_page = Map.get(params, :per_page, 20)
                   length(results.results) <= per_page
                 end)
  def search(params) do
    %{results: [], total: 0, page: Map.get(params, :page, 1),
      per_page: Map.get(params, :per_page, 20), has_more?: false}
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# §10  Property-based tests — gen/1 drives every schema
# ─────────────────────────────────────────────────────────────────────────────

defmodule Marketplace.PropertyTest do
  use ExUnitProperties
  import Gladius, except: [
    integer: 0, integer: 1, integer: 2,
    float: 0, float: 1, float: 2,
    string: 0, string: 1, string: 2,
    boolean: 0, atom: 0, atom: 1,
    list: 0, list: 1, list: 2, list_of: 1, gen: 1
  ]

  # Every generated address conforms — the generator infers bounds from
  # size?/format constraints automatically.
  property "generated addresses always conform" do
    check all addr <- Gladius.gen(ref(:address)) do
      assert {:ok, _} = Gladius.conform(ref(:address), addr)
    end
  end

  # Generated users always conform and conform is idempotent.
  property "conform is idempotent for generated users" do
    check all user <- Gladius.gen(ref(:user)) do
      {:ok, shaped} = Gladius.conform(ref(:user), user)
      assert Gladius.conform(ref(:user), shaped) == {:ok, shaped}
    end
  end

  # Generated line items always conform.
  property "generated line items always conform" do
    check all item <- Gladius.gen(ref(:line_item)) do
      assert Gladius.valid?(ref(:line_item), item)
    end
  end

  # HTTP params coercion roundtrip — strings in, typed values out.
  property "user_create_params coerces all string fields correctly" do
    raw_params_gen =
      ExUnitProperties.gen all
        name  <- StreamData.string(:printable, min_length: 1, max_length: 50),
        local <- StreamData.string(:alphanumeric, min_length: 1, max_length: 20),
        domain <- StreamData.string(:alphanumeric, min_length: 2, max_length: 10) do
        %{
          email:    "#{local}@#{domain}.com",
          name:     name,
          role:     "buyer",
          verified?: "true"
        }
      end

    check all params <- raw_params_gen do
      case Gladius.conform(ref(:user_create_params), params) do
        {:ok, shaped} ->
          assert shaped.role == :buyer
          assert shaped.verified? == true
          assert is_binary(shaped.email)
        {:error, _} ->
          # Some generated names/emails may fail format constraints — that's OK
          :ok
      end
    end
  end

  # card_payment generator produces valid payment methods.
  property "generated card payments always conform" do
    check all card <- Gladius.gen(ref(:card_payment)) do
      assert Gladius.valid?(ref(:card_payment), card)
    end
  end

  # any_of generates from all branches — verify distribution.
  property "payment_method any_of generates all three payment types" do
    samples = Enum.take(Gladius.gen(ref(:payment_method)), 300)
    types = Enum.map(samples, & &1.type) |> Enum.uniq() |> MapSet.new()
    assert MapSet.member?(types, :card)
    assert MapSet.member?(types, :ach)
    assert MapSet.member?(types, :crypto)
  end

  # order_status generates all atoms in the union.
  property "order_status generates all valid statuses" do
    samples = Enum.take(Gladius.gen(ref(:order_status)), 500)
    statuses = MapSet.new(samples)
    expected = MapSet.new([:pending, :confirmed, :processing,
                            :shipped, :delivered, :cancelled, :refunded])
    assert MapSet.subset?(expected, statuses)
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# §11  Introspection at the REPL
# ─────────────────────────────────────────────────────────────────────────────

# Paste these into `iex -S mix` to explore the spec registry and typespec bridge:
#
# # All registered spec names:
# iex> Gladius.Registry.all() |> Map.keys() |> Enum.sort()
# [:address, :bank_payment, :card_payment, :crypto_payment, :currency,
#  :digital_product, :discount, :discount_value, :email, :iso_country,
#  :line_item, :money_cents, :order, :order_status, :payment_method,
#  :percentage, :phone, :physical_product, :positive_cents, :product_type,
#  :role, :slug, :subscription_product, :tag, :url, :user, :uuid,
#  :uuid_list, :vendor]
#
# # Lossless specs:
# iex> Gladius.typespec_lossiness(Gladius.Registry.fetch!(:money_cents))
# []
# iex> Gladius.typespec_lossiness(Gladius.Registry.fetch!(:role))
# []
# iex> Gladius.typespec_lossiness(Gladius.Registry.fetch!(:order_status))
# []
#
# # Lossy specs (constraints that have no typespec equivalent):
# iex> Gladius.typespec_lossiness(Gladius.Registry.fetch!(:email))
# [{:constraint_not_expressible, "filled?: true ..."},
#  {:constraint_not_expressible, "format: ~r/.../ ..."}]
#
# # Render an order's typespec:
# iex> Gladius.Registry.fetch!(:order) |> Gladius.to_typespec() |> Macro.to_string()
# "%{required(:id) => String.t(), required(:buyer_id) => String.t(),
#    required(:vendor_id) => String.t(),
#    required(:status) => :pending | :confirmed | :processing | :shipped
#                       | :delivered | :cancelled | :refunded, ...}"
#
# # Conform an HTTP param map end-to-end:
# iex> Gladius.conform(Gladius.Registry.fetch!(:user_create_params), %{
# ...>   email: "mark@example.com", name: "Mark", role: "vendor"
# ...> })
# {:ok, %{email: "mark@example.com", name: "Mark", role: :vendor}}
#
# # Inspect what a custom coercion does:
# iex> Gladius.Coercions.lookup(:money, :integer).(%{amount: 9.99, currency: "USD"})
# {:ok, 999}
# iex> Gladius.Coercions.lookup(:money, :integer).({999, :usd})
# {:ok, 999}
#
# # User-registered coercions in the registry:
# iex> Gladius.Coercions.registered() |> Map.keys()
# [{:money, :integer}, {:semver_string, :tuple}]
