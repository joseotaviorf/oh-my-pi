# Primary Market

## Ownership

**Data Owner:**
- vinicius.santanna@quintoandar.com.br

**Data Steward:**
- gustavo.rompe@quintoandar.com.br

## Overview

If TARS cannot access the `datalake_sale_primary_market` enrich schema because
the user lacks data-contract access, treat it as an access limitation. The team
is working on the data-contract permissions.

Until access is available, use the equivalent Primary Market enrich table in
the `sandbox` schema with the naming convention:

```text
sandbox.{schema}_{table_name}
```

Examples:

```text
sandbox.datalake_sale_primary_market_listing_sale_type
sandbox.datalake_sale_primary_market_house_development
sandbox.datalake_sale_primary_market_development_negotiation
```

Keep the same column names and filters, identify the sandbox source in the
answer, and do not apply this fallback to DW or other schemas.

### Overview context

- **Objective:** classify sale listings, visits, and ongoing-supply snapshots as **Primary** (new-build inventory sold by an incorporadora) or **Secondary** (resale between individuals), and route Ops/TARS questions to the current source of truth during the pilot rollout.
- **Asset status / lifecycle:** August 2026 São Paulo pilot, inventory supplied through Órulo. The engineering RFC introduced a **1:N** development model (one empreendimento → N typologies → N shell houses) that coexists with the legacy **1:1** secondary model (one listing ≈ one house ≈ one unit).
- **Source of truth:** use the source according to the grain. Listing/house classification is `datalake_sale_primary_market.listing_sale_type.sale_type` (`listing_sale_model.sale_type` enum; NULL maps to `SECONDARY`; old `is_primary_market = TRUE` test listings are excluded). Offer classification is `datalake_sales_flow_clean.offer.sale_type`, propagated through `datalake_sale_offer.core_sale_offer`, `datalake_sale_offer.sale_offer`, and the offer DW tables. Buyer activation classification is `datalake_buyer_prospect.buyer_prospect_type.sale_type`, with `bp_market_type` for market exclusivity.
- **Typical actions / events:** a typology is published as a shell listing → buyer visits the shell house → buyer offers on a **minted unit** Imovel (a new house_id, not the shell) → CCV is the de-facto closing signal for Primary (no post-CCV diligência step like Secondary).
- **Common metrics:** Primary listing count, Primary visit volume, Primary ongoing-supply stock, Primary offer volume, sale-flow volume, and buyer market exclusivity.
- **Related entities:** for house/listing grain fundamentals shared with Secondary, see [`house_and_listing.md`](house_and_listing.md). For offer/CCV mechanics, see [`fs-transact.md`](fs-transact.md).

### Service Architecture (why some cross-references don't exist yet)

The **Development** domain is a separate service/bounded-context from **Sales Flow** (the offer/CCV system) — this is a service boundary, not just a data-modeling choice, and it explains most of the "manual cross-reference" answers in the FAQ below.

- **`DevelopmentNegotiation`** captures pré-oferta intent (who, which unit, from which visit) entirely inside the Development domain — `development_id` and `visit_id` live on the same row, no cross-service call needed to answer "which development is this negotiation for?"
- **There is no `SaleOffer` / `Ccv` table inside the Development domain.** When a negotiation is ready to become an offer, the service publishes a `DevelopmentProposalRequested` event and calls `OfferPort.createOffer(negotiation)` — an outbound port that creates the offer in the external **sales-flow** service (which owns `SaleOffer`/`SalesFlow`/`Ccv`). This call is **asynchronous, with no FK persisted back into Development's own tables.**
- This is exactly why `dw_sale.fact_offers` / CCV joins still require crossing through `house_id` (via `DevelopmentTypologyUnit.imovel_id`) instead of a native foreign key: **there is no service-side join either** — house_id is the only key the two services share.
- **`DevelopmentNegotiationUnit.development_typology_unit_id` is unique** — enforced by the service, not just a query convention: one unit can have **at most one open negotiation** at a time. If a buyer wants two units, the service creates two separate negotiations with two separate unit house_ids.
- **Offer acceptance is also a service-side event**, not just a data write: on accept, the service atomically decrements `unitCount`, suspends the typology listing when sold out (and the whole development if all typologies are sold out), and only then mints the **real** unit Imovel used for the closing path. This is why the unit house_id is created at **offer accept**, not at offer send — a deliberate anti-ghost-inventory design, not a data gap.
- **`DevelopmentContact`** (active manager per empreendimento) is fully owned and queryable inside the Development domain — no external service call needed, which is why that FAQ answer below is native.

### ⚠️ Órulo-pilot scope vs listing-side PRIMARY — do not conflate

`listing_sale_type` no longer maps the legacy `is_primary_market` boolean to PRIMARY. It reads `listing_sale_model.sale_type` (NULL → `SECONDARY`) and **drops** `listing_sale_model` rows where `is_primary_market = TRUE` (old primary-market tests, unrelated to this pilot).

**Measured 2026-09-02 against the previous fallback-inclusive SSOT** (kept so TARS does not reuse those inflated numbers after the filter):

1. **The new Órulo pilot** (this doc's actual subject) — houses in `datalake_ebdb_clean.development_typology_unit` (**537** houses), almost all of which also have `sale_type = 'PRIMARY'` on the strict raw enum (**536** — 1 house not yet classified).
2. **Legacy pre-pilot `is_primary_market = TRUE` houses** — builder-sold / test listings flagged under the old system. There were roughly **4,767** of these (5,303 fallback-classified minus 536 strict). They are **excluded from `listing_sale_type` now**.

On that older snapshot, `dw_visit.fact_visits` with `sale_type = 'PRIMARY'` returned **37,407 visits booked** (90% VB2VC) across the mixed population, versus **23 visits booked** (5 completed, 17 distinct houses) when scoped to the 536/537-house pilot. After `listing_sale_type` and its downstream consumers re-run, listing-side `sale_type = 'PRIMARY'` should no longer include those ~4.7k test houses. **If a question is about the Órulo São Paulo pilot, still filter by `development_typology_unit.id_house` (or join `house_development`), not by `sale_type = 'PRIMARY'` alone** — that remains the native Development-domain population.

```sql
-- Correct pilot-scoped filter (any fact with a house-grain join key)
INNER JOIN datalake_ebdb_clean.development_typology_unit AS dtu
    ON dtu.id_house = fact_table.sk_house  -- or id_house, per the fact's own column name
```

`sale_type = 'PRIMARY'` on refreshed `listing_sale_type`-sourced tables is enum PRIMARY only. Tables natively scoped to the Development domain (`house_development`, `development_negotiation`) remain the safest pilot-only sources. Downstream DW facts may still show the old mix until they re-run after this enrich DAG.

## Related Metric Entities

- None — no metric entity doc owns Primary Market metrics yet.

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Primary Market / Mercado Primário / MP** | New-build inventory sold by an incorporadora | `sale_type = 'PRIMARY'` is the listing-side enum filter; use `development_typology_unit.id_house` for strict Órulo-pilot scope |
| **Secondary Market / Mercado Secundário** | Resale inventory between individuals (CPF sellers) | `listing_sale_type.sale_type = 'SECONDARY'` (NULL enum is filled as SECONDARY). A LEFT JOIN to `listing_sale_type` is NULL when the house has no remaining SALE listing_sale_model row after the old-test filter |
| **Development / Empreendimento** | The real-estate project aggregate, containing multiple typologies | `datalake_ebdb_clean.development` |
| **Typology / Tipologia** | A floor-plan / SKU within a development; exposed as one **shell house** for search, visit, and offer | `datalake_ebdb_clean.development_typology` |
| **Shell house / Imóvel shell** | The house_id a typology is listed and visited on. **Not** a physical unit — one shell can represent many real apartments | Intent/visit key; kept unchanged per the funnel-attribution ADR (no visit rewrite) |
| **Unit Imovel** | The real physical apartment, minted as a **new** house_id only when a buyer makes an offer | `datalake_ebdb_clean.development_typology_unit.id_house`; distinct from the shell house on the same negotiation |
| **DevelopmentNegotiation / pré-OS** | Pre-offer negotiation event on a typology unit, created by an agent or the buyer | `datalake_ebdb_clean.development_negotiation`; `actor` (`AGENT`/`DEMAND`) must be filtered to avoid broker-inflation of pré-OS counts |
| **EN, Executivo de Negociação, Deal Maker** | Negotiation Executive assigned to an offer's sales flow — in Primary, a conversion accelerator / developer liaison, not a price closer like Secondary | `datalake_sale_offer_flows.offer_specialists.id_user_consultant` |
| **hub_bp** | The closing hub servicing an offer | `datalake_sales_flow_clean.offer.id_hub` — native Sales Flow field, same mechanism as Secondary |
| **city_group** | Region grouping of a house | Resolved from `datalake_ebdb_clean.house.id_region` → `datalake_region.region.city_group` |
| **Buyer activation `sale_type`** | Market classification of the house that triggered the buyer-prospect activation | `datalake_buyer_prospect.buyer_prospect_type.sale_type`; strict Primary pilot membership through `house_development` |
| **`bp_market_type`** | Buyer market-exclusivity segment, independent of NBP/RBP | `PRIMARY_EXCLUSIVE`, `NON_EXCLUSIVE`, or `SECONDARY_EXCLUSIVE` in `buyer_prospect_type` |
| **DSP (`developers-supply-processor`)** | Product-side supply ledger for Primary inventory (Órulo sync) — **not** a DW/analytics source | See `datalake_ebdb_clean.development*` for the lake-side result of DSP → Main |
| **BSP (`brokers-supply-processor`)** | Unrelated 3P broker-lead pipeline — orthogonal axis (who supplies), not Primary/Secondary market type | Do not conflate with Primary Market classification |

## Tables

| You need... | Use this table |
|-------------|-----------------|
| Primary/Secondary classification at listing grain | `dw_sale.dim_listing` (`dl`) — prefer `sale_type`; retain `is_primary_market` for backward compatibility. |
| Raw enum + unit-level attributes | `datalake_ebdb_clean.listing_sale_model` (`lsm`) — `sale_type`, `unit_count`, `min_price`, `max_price`. Prefer the `listing_sale_type` SSOT for analyst queries; do not join this table directly from ad-hoc SQL. |
| House-grain Primary flag (pre-listing join) | `datalake_ebdb_listing.house` (enrich) — `is_sale_primary_market` = `BOOL_OR(sale_type = 'PRIMARY')` across that house's `listing_sale_model` rows. No legacy-boolean fallback. |
| House-grain canonical `sale_type` fill (preferred join target) | `datalake_sale_primary_market.listing_sale_type` (enrich) — one row per house from the SALE `listing_sale_model` (1:1 with SALE `listing_business_context`) that is **not** an old primary-market test (`is_primary_market != TRUE`). `sale_type` is the enum; NULL enum is filled as `SECONDARY`. It also carries `min_price` and `max_price`. Differs from `house.is_sale_primary_market` above (BOOL_OR of enum PRIMARY, no test-row exclusion). |
| Primary flag on visits — **just sale** | `dw_visit.fact_visits` and `dw_visit.fact_visit_schedules` (canonical — see [`visits.md`](visits.md)) — `sale_type` (STRING: `PRIMARY`/`SECONDARY`/`NULL`) at visit grain, derived from the house's SALE `listing_sale_type`; RENT rows are `NULL`. `dw_sale.fact_visits` also got the column (same enrich source), but it is a **separate, legacy table not covered by `visits.md`** — prefer `dw_visit.fact_visits` unless you have a specific reason to use the older one. |
| Primary flag on daily supply snapshot | `dw_sale.fact_daily_ongoing_listing` — `sale_type` per snapshot day. |
| Listing publication facts | `dw_sale.fact_listings` — `sale_type` per listing. |
| Listing price-change facts | `dw_sale.fact_listing_price_changes` — latest available house-level `sale_type`; not a historical as-of classification. |
| Offer volume and offer attributes | `dw_sale.fact_offers` and `dw_sale.dim_offer` — offer-side `sale_type` propagated from Sales Flow. |
| Sale agreement attributes | `dw_sale.dim_sale_agreement` — offer-side `sale_type` alongside CCV attributes. |
| Demand-funnel events | `dw_sale.fact_sale_demand_event` — visit events use `dw_sale.fact_visits.sale_type`; offer events use `dw_sale.fact_offers.sale_type`. |
| Buyer-house sale flows | `dw_sale.fact_sale_flows` — offer-side `sale_type`; booking/TTA-only flows remain NULL. |
| Buyer activation and market exclusivity | `datalake_buyer_prospect.buyer_prospect_type` — `sale_type` for the activation house and `bp_market_type` (`PRIMARY_EXCLUSIVE`, `NON_EXCLUSIVE`, `SECONDARY_EXCLUSIVE`). This is distinct from `bp_type` (`NBP`/`RBP`). |
| Development / typology context for a house | `datalake_sale_primary_market.house_development` (enrich) or `dw_sale_primary_market.dim_house_development` (DW) — house-grain development and typology attributes. |
| Pré-OS negotiation events | `datalake_sale_primary_market.development_negotiation` (enrich) or `dw_sale_primary_market.fact_development_negotiation` (DW) — visit house, unit house, offer, flow, and development keys. |
| Primary-market pilot scope | `datalake_ebdb_clean.development_typology_unit.id_house` or the development house tables — native Órulo-pilot population. `listing_sale_type.sale_type = 'PRIMARY'` is now enum-only (legacy boolean tests excluded), but still prefer the development tables when the question is about this pilot. |

`datalake_visit.visit_schedules` does not have a native `sale_type`. Visit
facts derive it from the house-level listing SSOT.

```sql
-- Use the native field when the target table exposes it
WHERE sale_type = 'PRIMARY'
```

## Key Metrics

### Component / exploratory metrics

- **Primary listings:** `COUNT(DISTINCT sk_sale_listing)` where `dw_sale.dim_listing.sale_type = 'PRIMARY'`.
- **Primary houses:** `COUNT(DISTINCT sk_house)` with the same filter.
- **Primary visit volume (pilot-scoped):** `SUM(num_visit_booked)` on `dw_visit.fact_visits`, joined to `development_typology_unit` on `id_house` (do **not** filter by `sale_type = 'PRIMARY'` alone — see the population warning above). As of 2026-09-02: 23 booked, 5 completed, 17 distinct houses. See [`visits.md`](visits.md) for booked vs completed metric conventions.
- **Primary ongoing supply (daily stock):** `COUNT(DISTINCT sk_snapshot)` (or house count) on `dw_sale.fact_daily_ongoing_listing` where `sale_type = 'PRIMARY'`.
- **Pré-OS volume (buyer-initiated only):** `COUNT(*)` on `datalake_sale_primary_market.development_negotiation` where `actor = 'DEMAND'` — filter `actor` to avoid broker-inflation from agent-created negotiations.
- **Visit → pré-OS conversion:** join `dw_visit.fact_visits.sk_visit` to `development_negotiation.id_visit` (same ID space — see Golden Query 4). As of 2026-09-02: 1 of 23 pilot visits (1 of 5 completed) led to a negotiation — directional only at this volume.
- **Buyer market exclusivity:** `COUNT(DISTINCT id_prospect)` on `datalake_buyer_prospect.buyer_prospect_type`, grouped by `bp_market_type` and filtered by `sale_type = 'PRIMARY'` for buyers activated by a Primary house.

No official metric-entity file exists for Primary Market yet — all metrics above are component-level, not corporate/OKR definitions.

## Relationships with other entities

### House / Listing (shared grain, different meaning for the shell)

- Same `sk_house` / `id_house` mechanics as Secondary — see [`house_and_listing.md`](house_and_listing.md). The difference is semantic: a Primary shell house represents a **typology**, not one physical unit. Do not treat shell house counts as unit inventory; use `listing_sale_model.unit_count` for that.

### Development (N:1 — typology → development)

- `datalake_ebdb_clean.development_typology.id_development` → `datalake_ebdb_clean.development.id`.
- Ops needs empreendimento-grain cuts (region → incorporadora → empreendimento). The accepted rule: **keep the intent `house_id`** on visits/offers; join to `id_development` at consume time via `house → development_typology_unit`. Do **not** denormalize `id_development` onto facts.

### Offer / CCV (`fs-transact.md`)

- `SalesFlow.sale_type` is the offer-side discriminator, distinct from the listing-side `ListingSaleModel.saleType`. It is available on `datalake_sales_flow_clean.offer`, then propagated to `datalake_sale_offer.core_sale_offer`, `datalake_sale_offer.sale_offer`, `dw_sale.fact_offers`, `dw_sale.dim_offer`, `dw_sale.dim_sale_agreement`, `dw_sale.fact_sale_demand_event`, and `dw_sale.fact_sale_flows`. NULL remains valid for historical or unclassified offers.
- EN (Deal Maker) and hub assignment on an offer follow the **same raw sources** as Secondary (`offer_specialists`, `sales_flow.offer.id_hub`) — no separate Primary-specific mechanism.

### Visits (typology-shell caveat)

- Visits book on the **shell** house, same as the intent house_id above. A buyer can visit typology A and offer on typology C of the same development — this is expected, not a data error. Typology-level visit-completion rates across shells of the same development are **not meaningful**; aggregate at development grain instead.

### Frequently Asked Questions (example question → table, and why)

Source: SWE domain walkthrough. For each business question: how to answer it **today**, and why — ✓ native (no cross-reference needed) or ⚠ requires a manual cross-reference / has a gap.

### Q: How many visits were booked (VB) for a development?
**Stage:** VB · **Status:** ⚠ manual cross-reference

A visit is recorded in `dw_visit.fact_visit_schedules` by the house_id visited (the typology shell). To know whether that house belongs to a specific development, you have to manually cross-reference `datalake_ebdb_clean.development_typology_unit.id_house` (or the shell equivalent on `house.id_development_typology`) — there is no ready-made column that already says "this visit belongs to Primary Market development X."

### Q: Of those, how many were confirmed or completed (VC)?
**Stage:** VC, VB2VC · **Status:** ⚠ manual cross-reference

Confirmation/completion is already flagged on `dw_visit.fact_visits` (`visit_status`, `is_completed`). Same limitation as the question above: knowing it belongs to "development X" still requires repeating the manual `id_house` cross-reference — there's no shortcut specific to this stage.

### Q: How many visits generated a proposal request?
**Stage:** pré-OS · **Status:** ✓ native

Immediate answer: `datalake_sale_primary_market.development_negotiation` is born with `id_development` and `id_visit` on the same row. Its DW evolution is `dw_sale_primary_market.fact_development_negotiation`. Unlike the questions above, no cross-reference is needed — that's the entire reason this table exists (see Service Architecture above).

### Q: How many proposals became a submitted offer (OS)?
**Stage:** OS · **Status:** ⚠ outside the domain

The offer itself is not stored in the Development domain. `DevelopmentNegotiationUnit` triggers `OfferPort`, which calls the external **sales-flow** system (see Service Architecture above). Count submitted offers with `dw_sale.fact_offers.sale_type = 'PRIMARY'`; use `dw_sale_primary_market.fact_development_negotiation` when the question also requires a development or negotiation key.

### Q: What's the offer-to-signed-contract conversion (OS2CCV) for a development's units?
**Stage:** OS2CCV · **Status:** ⚠ manual filter

`dw_sale.fact_offers` / `dw_sale.dim_sale_agreement` hold the CCV signature per offer. To restrict to one development, filter by the houses that appear in `development_typology_unit` — again a manual filter by `id_house`, not a ready-made column.

### Q: What's BP→CCV (Buyer Prospect → Contract) restricted to Primary Market?
**Stage:** BP2CCV · **Status:** ⚠ biggest gap

`datalake_buyer_prospect.buyer_prospect_type` now carries activation-level `sale_type` and buyer-level `bp_market_type`. The aggregated `dw_sale.fact_buyer_prospects` table still has no market classification or development key, so BP2CCV at the aggregate buyer-prospect grain remains a gap.

### Q: Who is the active manager (gestor) responsible for a development?
**Category:** operational · **Status:** ✓ native

This question never leaves the Development domain: `DevelopmentContact` (exposed via `datalake_sale_primary_market.house_development` and `dw_sale_primary_market.dim_house_development`) stores the development contact fields, with no external table or data-warehouse join needed.

## Dos and Don'ts

**Do:**
- Prefer `sale_type` on the target table. Keep `dw_sale.dim_listing.is_primary_market` only for backward-compatible listing filters.
- Prefer `sale_type` on the target table. At house/listing grain, use `listing_sale_type`: enum from the house's SALE `listing_sale_model` (1:1 with SALE LBC), NULL filled as `SECONDARY`, old `is_primary_market = TRUE` tests excluded. Do not substitute `house.is_sale_primary_market` without checking the difference (BOOL_OR of enum PRIMARY, no test-row exclusion).
- Treat the shell house_id as a **typology**, not a physical unit, when reasoning about Primary inventory counts.
- Use the native `sale_type` on facts and dimensions. If a table has no native field, join `datalake_sale_primary_market.listing_sale_type` at house grain.
- Filter `development_negotiation.actor = 'DEMAND'` when counting buyer-initiated pré-OS to avoid broker inflation.
- Scope any Órulo-pilot question via `development_typology_unit.id_house` (or `house_development`), not `sale_type = 'PRIMARY'` alone — see the population warning above.
- Check the live physical schema after each DAG rollout; merged SQL and deployed columns can temporarily differ until the affected DAG runs. If access fails because of missing Primary Market data-contract permissions, use the sandbox fallback documented above.

**Do not:**
- Do not use `is_3p_supply`, developer/company ownership, or price alone to infer Primary Market — these are orthogonal axes.
- Do not treat the shell house as one physical apartment; use `unit_count` on `listing_sale_model` or the unit Imovel (`development_typology_unit.id_house`) for inventory-level questions.
- Do not rewrite historical visit `house_id`s after an offer lands on a different typology, and do not expect synthetic "corrective" visits — neither exists by design.
- Do not denormalize `id_development` onto funnel facts — join it at consume time via `house → development_typology_unit → development_typology`.
- Do not treat `fact_offers.sale_type` as a listing classification; it is offer-side Sales Flow data.
- Do not treat `house.is_sale_primary_market` (BOOL_OR of enum PRIMARY, no test-row exclusion) and `listing_sale_type.sale_type` (SALE LBC 1:1, NULL → SECONDARY, old `is_primary_market = TRUE` tests dropped) as interchangeable — they can disagree on excluded test rows and on a NULL enum.
- Do not use `dw_sale.fact_buyer_prospects` as if it had `sale_type`; use `datalake_buyer_prospect.buyer_prospect_type` for activation-level market segmentation and `bp_market_type` for buyer exclusivity.
- Do not confuse `SalesFlow.sale_type` (offer-side, `datalake_sales_flow_clean.offer.sale_type`) with `ListingSaleModel.saleType` (listing-side, `datalake_ebdb_clean.listing_sale_model.sale_type`) — they are separate columns on separate tables, populated independently.

## Golden Queries

### Query 1 — Primary listing and house counts

Counts current Primary Market listings and shell houses in the DW.

```sql
SELECT
    COUNT(DISTINCT dl.sk_sale_listing) AS primary_listing_count,
    COUNT(DISTINCT dl.sk_house) AS primary_house_count
FROM dw_sale.dim_listing AS dl
WHERE dl.sale_type = 'PRIMARY'
  AND dl.status = 'PUBLISHED'
```

### Query 2 — Primary visit volume by month (pilot-scoped)

Counts Primary Market **pilot** visits booked and completed, monthly. **Deliberately does NOT filter `sale_type = 'PRIMARY'` alone** — see the population warning above. `listing_sale_type` now excludes the ~4.7k legacy test houses, but `development_typology_unit` remains the native Órulo-pilot membership key. Follows the same `SUM(num_visit_*)` convention as [`visits.md`](visits.md) — do not `COUNT(*)` rows for booked/completed totals.

```sql
SELECT
    DATE_TRUNC('month', CAST(fv.ts_visit_local_tz AS DATE)) AS visit_month,
    SUM(fv.num_visit_booked) AS primary_visits_booked,
    SUM(fv.num_visit_completed) AS primary_visits_completed
FROM dw_visit.fact_visits AS fv
INNER JOIN datalake_ebdb_clean.development_typology_unit AS dtu
    ON dtu.id_house = fv.sk_house
GROUP BY 1
ORDER BY 1 DESC
```

> See [`visits.md`](visits.md) for the full visit-fact column reference, VB2VC conventions, and the `fact_visits` ↔ `fact_visit_schedules` join.

### Query 3 — Pilot VB2VC rate vs. Secondary (comparison)

Compares visit-completion efficiency between the pilot and Secondary. Demonstrates why scoping matters: before `listing_sale_type` dropped old `is_primary_market = TRUE` tests, `sale_type = 'PRIMARY'` alone showed a misleading ~90% VB2VC (driven by the legacy population, not this pilot). The `development_typology_unit` join remains the strict Órulo-pilot segment.

```sql
SELECT
    CASE WHEN dtu.id_house IS NOT NULL THEN 'PRIMARY_PILOT' ELSE fv.sale_type END AS segment,
    SUM(fv.num_visit_booked) AS booked,
    SUM(fv.num_visit_completed) AS completed,
    CAST(SUM(fv.num_visit_completed) AS DOUBLE) / NULLIF(SUM(fv.num_visit_booked), 0) AS vb2vc_rate
FROM dw_visit.fact_visits AS fv
LEFT JOIN datalake_ebdb_clean.development_typology_unit AS dtu
    ON dtu.id_house = fv.sk_house
WHERE fv.sale_type IN ('PRIMARY', 'SECONDARY')
GROUP BY 1
ORDER BY 1
```

### Query 4 — Visit → pré-OS conversion (pilot)

How many pilot visits led to a negotiation (pré-OS)? `development_negotiation.id_visit` and `fact_visits.sk_visit` share the same ID space (both ultimately trace to `datalake_visit.visits.id_visit` / `datalake_ebdb_clean.visit.id`, which are kept in sync) — confirmed against the one known negotiation in production before relying on this join.

```sql
WITH pilot_visits AS (
    SELECT
        fv.sk_visit,
        fv.sk_house,
        fv.is_completed
    FROM dw_visit.fact_visits AS fv
    INNER JOIN datalake_ebdb_clean.development_typology_unit AS dtu
        ON dtu.id_house = fv.sk_house
)
SELECT
    COUNT(*) AS total_pilot_visits,
    SUM(CASE WHEN pv.is_completed THEN 1 ELSE 0 END) AS completed_pilot_visits,
    COUNT(DISTINCT dn.id_visit) AS visits_with_negotiation
FROM pilot_visits AS pv
LEFT JOIN datalake_sale_primary_market.development_negotiation AS dn
    ON dn.id_visit = pv.sk_visit
```

### Query 5 — Visits by development (top N)

Which developments are getting visit traffic. Useful for spotting cold-start developments the pilot hasn't yet demonstrated demand for.

```sql
SELECT
    hd.development_name,
    hd.id_development,
    SUM(fv.num_visit_booked) AS booked,
    SUM(fv.num_visit_completed) AS completed
FROM dw_visit.fact_visits AS fv
INNER JOIN datalake_sale_primary_market.house_development AS hd
    ON hd.id_house = fv.sk_house
GROUP BY 1, 2
ORDER BY booked DESC
LIMIT 10
```

### Query 6 — Pilot houses never visited (supply not yet demonstrated)

Supply-side gap check: how much of the pilot's published inventory has zero visit activity. Ops-relevant for identifying developments that may need marketing push or aren't ranking in search.

```sql
WITH visited_houses AS (
    SELECT DISTINCT sk_house
    FROM dw_visit.fact_visits
    WHERE num_visit_booked > 0
)
SELECT
    COUNT(*) AS n_pilot_houses,
    COUNT(vh.sk_house) AS n_visited,
    COUNT(*) - COUNT(vh.sk_house) AS n_never_visited
FROM datalake_sale_primary_market.house_development AS hd
LEFT JOIN visited_houses AS vh
    ON vh.sk_house = hd.id_house
```

## DataHub catalog

- **Data Product:** Published from this Markdown by the repository DataHub metadata workflow.
- **Datasets:** Tables in the Tables section are linked as DataHub assets. The same table may also appear on other Data Products.
- **Golden queries:** The six canonical queries above are published as DataHub Query entities.

<!-- Trigger republish: link Tables even when they already sit on another Data Product. -->
