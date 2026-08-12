# Agents — Performance (Listing Deduplication & CIQ Listing Purchase)

## Ownership

**Data Owner:**
- anne.macedo@quintoandar.com.br

**Data Steward:**
- gustavo.rompe@quintoandar.com.br

---

## Overview

- **Objective:** Two related concepts that gate agent commissions on supply: **Valid First Listing** (property dedup, so a re-listed property doesn't count as a new first listing) and **CIQ Listing Purchase / Compra de Carteira** (pricing, payment, and portfolio-loss outcomes for CIQ_FULL rent listings).
- **Asset status / lifecycle:** listing published → deduplicated against similar/prior houses → validated first listing → (Compra de Carteira track) priced → paid → portfolio-loss evaluated on relist.
- **Typical actions / events:** address parsing/dedup, first-listing validation, CIQ pricing (initial → final), payment, portfolio-loss flagging.
- **Common metrics:** valid first listings per period, Compra de Carteira paid amount, portfolio loss rate.
- **Source systems:** EBDB house/listing data, Atlas (similar-property detection).
- **Related entities:** for the tiers-specific `ciq_first_listing` variant of first-listing validity, see [`agents_profile.md`](agents_profile.md). For `listing_category` / rent versioning semantics, see [`house_and_listing.md`](house_and_listing.md).

---

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Valid First Listing** | A first listing that survives property deduplication — a re-listed/duplicated property does NOT count again | `datalake_listing_deduplication.valid_first_listing`. Metric definition still evolving. |
| **Primeira listagem / first listing** | ⚠ "any first listing" vs "valid first listing" (dedup-gated) | Default to valid for CIQ/activation, confirm with the user. |
| **Compra de Carteira / CIQ listing purchase** | CIQ_FULL rent listing-purchase — eligibility, pricing, portfolio loss | `dw_ciq.fact_ciq_listing_purchase`. |
| **Perda de carteira / portfolio loss** | Relist still on market >90 days without a signed rent contract, or rent CS on/after 2026-07-01 with a later non-canceled CCV on the same house | `is_portfolio_loss` / `portfolio_loss_reason` on the DW fact only. |
| **Re-Listing** | New rent listing cycle after a prior rental ended | `listing_category = 'Re-Listing'`. See [`house_and_listing.md`](house_and_listing.md). |

---

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Deduplicated, validated first-listing record | `datalake_listing_deduplication.valid_first_listing` |
| Address-normalized dedup analysis | `datalake_listing_deduplication.listing_deduplication` |
| CIQ Compra de Carteira — dashboards, portfolio loss, final pricing, payment | `dw_ciq.fact_ciq_listing_purchase` |
| Similar-house / Atlas duplicity peer rows | `dw_ciq.fact_listing_purchase_duplicity` |
| Initial pricing speculation (pre-override) | `datalake_ciq.ciq_listing_purchase` |

**Critical rules:**
- **DW first:** analyst queries for Compra de Carteira must start at `dw_ciq.fact_ciq_listing_purchase`. Use `datalake_ciq.ciq_listing_purchase` only for `initial_pricing_type*` or pipeline debugging.
- `payment_status` and `is_eligible` live on `listing_purchase_pricing` / the DW fact — they are **not** on `ciq_listing_purchase` anymore.
- Grain of `fact_ciq_listing_purchase` is one row per **house listing version** in CIQ context, not one row per house.

---

## `datalake_listing_deduplication` (Valid First Listing)

Why it matters: the same physical property can be listed multiple times (re-listing, hybrid rent+sale, multiple agents). Counting each listing as a "first listing" would inflate activation and over-pay CIQ commissions.

**`valid_first_listing`** — one row per `id_house` (rent and sale side by side): `id_ciq_user_sale`, `id_ciq_user_rent`, `is_hybrid_house`, `house_listing_status`, `ts_first_listing_rent/sale`, `days_between_fl_to_cs`, `supply_source_rent/sale`.

**`listing_deduplication`** — one row per `id_house`, address-normalized dedup analysis over the full EBDB house universe: `id_address_parsed_short`, `is_duplicated`, `is_first_listing_in_duplicates`, `address_full`.

> ⚠ **`valid_first_listing` vs `ciq_first_listing` (tiers-specific, see [`agents_profile.md`](agents_profile.md)):** both validate a dedup-gated first listing, but this table is the broader dedup/activation source, while `ciq_first_listing` is the CIQ-consultant/tiers scope with a general compliance rule (published ≥2 days, or a signed contract within 60 days of first publication). For CIQ tier/commission questions, use `ciq_first_listing`.

## CIQ Listing Purchase (Compra de Carteira)

Pricing has two layers — do not conflate: **initial** (`initial_pricing_type` on base enrich — pre-override speculation) vs **final** (`pricing_type` on the fact/pricing enrich — after previous-paid and paid-similar-house overrides).

Anti-repurchase keys on the fact: `sk_previous_listing_paid` (same house already purchased), `sk_similar_house_paid` (similar-address house already **paid**), `sk_listing_duplicity` (join `fact_listing_purchase_duplicity` for peer detail).

**Portfolio loss** (`is_portfolio_loss` / `portfolio_loss_reason`, DW-only): exactly one of (1) `listing_category = 'Re-Listing'` AND `listing_status IN ('PUBLISHED','PUBLICADO')` AND no signed rent contract AND `total_days_since_publish > 90`, or (2) rent `ts_contract_signed >= 2026-07-01` AND a later non-canceled CCV on the same house. Rules are mutually exclusive per row (90d needs null CS; CCV needs CS).

## Dos and Don'ts

**Do:**

- For **CIQ portfolio loss**, use `dw_ciq.fact_ciq_listing_purchase.is_portfolio_loss` — do not re-derive from `has_republication` alone (that flag is on the **prior** cycle when a later version exists).
- For Compra de Carteira pricing, use `pricing_type` (final) — not `initial_pricing_type` (pre-override speculation).

**Don't:**

- Use `total_days_since_house_inactived` as "days available without rent" for Compra de Carteira — use `total_days_since_publish` / `is_portfolio_loss`.
- Treat `sk_similar_house_paid` as "any similar address" — it is specifically the **already-paid** similar house (anti-repurchase).
- Treat `datalake_big_agent.house_consultant_history.consultant_type` (`CIQ_FULL`, `CIQ_MANAGER`, `ASP`) as stable — active RFC pending.

---

## Golden Queries

### Query 1 — CIQ portfolio loss (Compra de Carteira)

Current-state rows flagged by either portfolio-loss rule on the DW fact. Use `portfolio_loss_reason` to see which rule fired.

```sql
SELECT
    f.sk_house,
    f.sk_house_listing,
    f.sk_partner,
    f.listing_category,
    f.listing_status,
    f.total_days_since_publish,
    f.ts_publicated,
    f.is_paid,
    f.ts_contract_signed,
    f.is_portfolio_loss,
    f.portfolio_loss_reason
FROM dw_ciq.fact_ciq_listing_purchase AS f
WHERE f.is_portfolio_loss = true;
```

> For ad-hoc checks on enrich inputs only, the 90-day rule is `listing_category = 'Re-Listing'` + `listing_status IN ('PUBLISHED', 'PUBLICADO')` + `ts_contract_signed IS NULL` + `total_days_since_publish > 90` on `datalake_ciq.ciq_listing_purchase` — prefer the DW fact.
