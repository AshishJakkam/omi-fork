# Taking payments on your own deployment

You asked for payments to land in your bank account. This is the honest scope: it is **not** a
config flag, because upstream billing is wired to Omi's own Stripe account. It is a day of work,
and here is exactly what is involved.

## What already exists

The backend has a complete Stripe integration, so you are pointing it at *your* account rather
than building billing from scratch:

```
routers/payment.py          checkout, customer portal, webhooks, Connect onboarding
utils/subscription.py       plan resolution, quota enforcement
config/plan_catalog*.py     plan → price → entitlement mapping
utils/stripe_webhook_ledger.py   idempotent webhook dispatch
```

## What you must supply

Three secrets:

| Env var | What it is |
|---|---|
| `STRIPE_API_KEY` | Your Stripe secret key (`sk_live_…` / `sk_test_…`) |
| `STRIPE_WEBHOOK_SECRET` | Signing secret for your subscription webhook endpoint |
| `STRIPE_CONNECT_WEBHOOK_SECRET` | Signing secret for the Connect webhook, if you pay out to others |

And one price id per plan interval. From `PRIMARY_BILLING_ENV_VARS`:

```
STRIPE_UNLIMITED_MONTHLY_PRICE_ID      STRIPE_UNLIMITED_ANNUAL_PRICE_ID
STRIPE_ARCHITECT_MONTHLY_PRICE_ID      STRIPE_ARCHITECT_ANNUAL_PRICE_ID
STRIPE_OPERATOR_MONTHLY_PRICE_ID       STRIPE_OPERATOR_ANNUAL_PRICE_ID
STRIPE_UNLIMITED_V2_MONTHLY_PRICE_ID   STRIPE_UNLIMITED_V2_ANNUAL_PRICE_ID
```

## The trap that will cost you an afternoon

Setting the env vars **is** sufficient for plan resolution — `resolve_stripe_price_plan` consults
`configured_billing_price_plans()`, which reads `BILLING_ENV_VAR_PLAN_TYPES` straight from the
environment, so your own price ids map to plans without touching the catalog.

The trap is the *silent* failure when a price is **not** configured. `resolve_stripe_price_plan`
resolves in this order:

```
configured ladder prices (env)  →  retained Omi prices (generated map)  →  configured billing env
                                →  else: raise ValueError('Price ID … does not correspond to a known plan.')
```

So if a checkout completes at Stripe for a price the backend does not know, **the payment succeeds
and no entitlement is granted.** The customer is charged and gets nothing. Set all price ids your
checkout can emit, and confirm one end-to-end test purchase before taking real money.

Two ambiguity checks also fail loudly, by design:

- one price id assigned to two plans → `configured for both …`
- a retained Omi price reclassified as a different plan → `retained as … but configured as …`

### When you do need to regenerate

Only if you want the **storefront display** to list your plans (the app's pricing sheet reads
`PLAN_STOREFRONTS` / `PLAN_DISPLAY_NAMES`), or if you edit `scripts/generate_plan_catalog.py`'s
source data. Then:

```bash
python backend/scripts/generate_plan_catalog.py
```

Review the diff — a catalog change alters entitlements, so it should be committed deliberately, not
regenerated on every deploy.

## Store rules, which decide your margin

| Distribution | Who processes payment | Your cut |
|---|---|---|
| Sideload / TestFlight / direct install | **You** (Stripe) | ~97 % after Stripe fees |
| App Store | Apple | 70–85 %, and Apple requires IAP for digital goods |
| Play Store | Google | 70–85 %, same rule |

You are sideloading, so Stripe direct is legitimate today. The moment this ships through the App
Store as a paid product, Apple's IAP rules apply and you cannot route around them.

## What is *not* built

- **Payouts to schools as sub-merchants** would need Stripe Connect onboarding (`routers/payment.py`
  already imports Connect, but you would own the account link flow).
- **Invoicing / GST** for Indian customers is yours to handle; there is no tax engine here.
- The app's storefront copy (`PLAN_STOREFRONTS`, `PLAN_DISPLAY_NAMES`) still reads "Omi Pro".
  Rebrand it before anyone sees a payment page with someone else's product name.

## Cheapest correct order of operations

1. Ship the unlock: `OMI_SELFHOST_UNLIMITED=true`, no payments at all.
2. Add Stripe only when you have a customer who wants to pay — until then billing is pure overhead.
3. Regenerate the plan catalog **last**, as one reviewed commit.
