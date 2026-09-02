# Primary Market

## Ownership

**Data Owner:**
- vinicius.santanna@quintoandar.com.br

**Data Steward:**
- gustavo.rompe@quintoandar.com.br

## Overview

- **Objective:** classify sale listings, visits, and ongoing-supply snapshots as **Primary** (new-build inventory sold by an incorporadora) or **Secondary** (resale between individuals), and route Ops/TARS questions to the current source of truth during the pilot rollout.
- **Asset status / lifecycle:** August 2026 São Paulo pilot, inventory supplied through Órulo. The engineering RFC introduced a **1:N** development model (one empreendimento → N typologies → N shell houses) that coexists with the legacy **1:1** secondary model (one listing ≈ one house ≈ one unit).
- **Source of truth:** `ListingSaleModel.saleType`, exposed in the lake as `datalake_ebdb_clean.listing_sale_model.sale_type` (`PRIMARY` / `SECONDARY`, nullable). This supersedes the legacy `is_primary_market` boolean on the same source table — do not use the legacy boolean as a fallback once `sale_type` classification is live on a table (see per-table notes below).
- **Typical actions / events:** a typology is published as a shell listing → buyer visits the shell house → buyer offers on a **minted unit** Imovel (a new house_id, not the shell) → CCV is the de-facto closing signal for Primary (no post-CCV diligência step like Secondary).
- **Common metrics:** Primary listing count, Primary visit volume, Primary ongoing-supply stock, Primary offer volume (in progress — see Tables).
- **Related entities:** for house/listing grain fundamentals shared with Secondary, see [`house_and_listing.md`](house_and_listing.md). For offer/CCV mechanics, see [`fs-transact.md`](fs-transact.md).

## Service Architecture (why some cross-references don't exist yet)

The **Development** domain is a separate service/bounded-context from **Sales Flow** (the offer/CCV system) — this is a service boundary, not just a data-modeling choice, and it explains most of the "manual cross-reference" answers in the FAQ below.

- **`DevelopmentNegotiation`** captures pré-oferta intent (who, which unit, from which visit) entirely inside the Development domain — `development_id` and `visit_id` live on the same row, no cross-service call needed to answer "which development is this negotiation for?"
- **There is no `SaleOffer` / `Ccv` table inside the Development domain.** When a negotiation is ready to become an offer, the service publishes a `DevelopmentProposalRequested` event and calls `OfferPort.createOffer(negotiation)` — an outbound port that creates the offer in the external **sales-flow** service (which owns `SaleOffer`/`SalesFlow`/`Ccv`). This call is **asynchronous, with no FK persisted back into Development's own tables.**
- This is exactly why `dw_sale.fact_offers` / CCV joins still require crossing through `house_id` (via `DevelopmentTypologyUnit.imovel_id`) instead of a native foreign key: **there is no service-side join either** — house_id is the only key the two services share.
- **`DevelopmentNegotiationUnit.development_typology_unit_id` is unique** — enforced by the service, not just a query convention: one unit can have **at most one open negotiation** at a time. If a buyer wants two units, the service creates two separate negotiations with two separate unit house_ids.
- **Offer acceptance is also a service-side event**, not just a data write: on accept, the service atomically decrements `unitCount`, suspends the typology listing when sold out (and the whole development if all typologies are sold out), and only then mints the **real** unit Imovel used for the closing path. This is why the unit house_id is created at **offer accept**, not at offer send — a deliberate anti-ghost-inventory design, not a data gap.
- **`DevelopmentContact`** (active manager per empreendimento) is fully owned and queryable inside the Development domain — no external service call needed, which is why that FAQ answer below is native.

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Primary Market / Mercado Primário / MP** | New-build inventory sold by an incorporadora | `sale_type = 'PRIMARY'` is the strict SoT filter |
| **Secondary Market / Mercado Secundário** | Resale inventory between individuals (CPF sellers) | `sale_type = 'SECONDARY'`, or `NULL` when no listing_sale_model row exists |
| **Development / Empreendimento** | The real-estate project aggregate, containing multiple typologies | `datalake_ebdb_clean.development` |
| **Typology / Tipologia** | A floor-plan / SKU within a development; exposed as one **shell house** for search, visit, and offer | `datalake_ebdb_clean.development_typology` |
| **Shell house / Imóvel shell** | The house_id a typology is listed and visited on. **Not** a physical unit — one shell can represent many real apartments | Intent/visit key; kept unchanged per the funnel-attribution ADR (no visit rewrite) |
| **Unit Imovel** | The real physical apartment, minted as a **new** house_id only when a buyer makes an offer | `datalake_ebdb_clean.development_typology_unit.id_house`; distinct from the shell house on the same negotiation |
| **DevelopmentNegotiation / pré-OS** | Pre-offer negotiation event on a typology unit, created by an agent or the buyer | `datalake_ebdb_clean.development_negotiation`; `actor` (`AGENT`/`DEMAND`) must be filtered to avoid broker-inflation of pré-OS counts |
| **EN, Executivo de Negociação, Deal Maker** | Negotiation Executive assigned to an offer's sales flow — in Primary, a conversion accelerator / developer liaison, not a price closer like Secondary | `datalake_sale_offer_flows.offer_specialists.id_user_consultant` |
| **hub_bp** | The closing hub servicing an offer | `datalake_sales_flow_clean.offer.id_hub` — native Sales Flow field, same mechanism as Secondary |
| **city_group** | Region grouping of a house | Resolved from `datalake_ebdb_clean.house.id_region` → `datalake_region.region.city_group` |
| **DSP (`developers-supply-processor`)** | Product-side supply ledger for Primary inventory (Órulo sync) — **not** a DW/analytics source | See `datalake_ebdb_clean.development*` for the lake-side result of DSP → Main |
| **BSP (`brokers-supply-processor`)** | Unrelated 3P broker-lead pipeline — orthogonal axis (who supplies), not Primary/Secondary market type | Do not conflate with Primary Market classification |

## Tables

| You need... | Use this table |
|-------------|-----------------|
| Primary/Secondary classification at listing grain | `dw_sale.dim_listing` (`dl`) — `is_primary_market`, strict from `sale_type = 'PRIMARY'`; `NULL` and all other values are `FALSE`. Join `sk_house` for facts without their own flag. |
| Raw enum + unit-level attributes | `datalake_ebdb_clean.listing_sale_model` (`lsm`) — `sale_type`, `unit_count`, `min_price`, `max_price`. Prefer `dim_listing` for analyst queries; do not join this table directly from ad-hoc SQL. |
| House-grain Primary flag (pre-listing join) | `datalake_ebdb_listing.house` (enrich) — `is_sale_primary_market` = `BOOL_OR(sale_type = 'PRIMARY')` across that house's `listing_sale_model` rows. No legacy-boolean fallback. |
| House-grain canonical `sale_type` fill (preferred join target) | `datalake_sale_primary_market.listing_sale_type` (enrich) — one row per house, `sale_type` from the **most recently updated SALE** `listing_sale_model` row; prefers the enum, **falls back to the legacy boolean** when `sale_type` is null. Built so other enrich/DW tables join this instead of re-deriving the fallback logic themselves. **Different semantics from `house.is_sale_primary_market` above** — that one is strict (no fallback); this one has a fallback. Do not treat them as interchangeable. |
| Primary flag on visits — **just sale** | `dw_visit.fact_visits` and `dw_visit.fact_visit_schedules` (canonical — see [`visits.md`](visits.md)) — `sale_type` (STRING: `PRIMARY`/`SECONDARY`/`NULL`) at visit grain, derived from the latest SALE listing business context; RENT rows are `NULL`. `dw_sale.fact_visits` also got the column (same enrich source), but it is a **separate, legacy table not covered by `visits.md`** — prefer `dw_visit.fact_visits` unless you have a specific reason to use the older one. |
| Primary flag on daily supply snapshot | `dw_sale.fact_daily_ongoing_listing` — `sale_type` per snapshot day. |
| Development / typology context for a house | `datalake_sale_primary_market.house_development` (enrich; **no DW equivalent yet**) — denormalizes development name, construction status, address, and typology attributes onto the house grain. |
| Pré-OS negotiation events | `datalake_sale_primary_market.development_negotiation` (enrich; **no DW equivalent yet**) — one row per `DevelopmentNegotiation`; carries `id_offer`/`id_sales_flow` when the negotiation reached an offer. |
| Offer volume, EN, hub, city_group at negotiation grain | **In review** — `dw_sale_primary_market.fact_development_negotiation` (PR pending merge). Do not reference until merged; treat as not yet available. |

**`dw_sale.fact_offers` does not carry `sale_type` or `is_primary_market` today.** To identify Primary offers, join `dw_sale.dim_listing` on `sk_house` (interim pattern below). This is in-progress work — do not assume the column exists without checking the live schema first.

**`dw_sale.fact_sale_flows` does not carry `sale_type` yet.** Propagation hasn't reached this table — it may get the column in a future wave, same as `fact_offers` above. Until then, filter Primary at query time via the same `dim_listing` / `house` join. Check the live schema before assuming either way.

```sql
-- Interim Primary filter for facts without their own flag (e.g. fact_offers)
LEFT JOIN dw_sale.dim_listing AS dl
    ON fact_table.sk_house = dl.sk_house
WHERE dl.is_primary_market
```

## Key Metrics

### Component / exploratory metrics

- **Primary listings:** `COUNT(DISTINCT sk_sale_listing)` where `dw_sale.dim_listing.is_primary_market = TRUE`.
- **Primary houses:** `COUNT(DISTINCT sk_house)` with the same filter.
- **Primary visit volume:** `SUM(num_visit_booked)` on `dw_visit.fact_visits` where `sale_type = 'PRIMARY'` — see [`visits.md`](visits.md) for booked vs completed metric conventions.
- **Primary ongoing supply (daily stock):** `COUNT(DISTINCT sk_snapshot)` (or house count) on `dw_sale.fact_daily_ongoing_listing` where `sale_type = 'PRIMARY'`.
- **Pré-OS volume (buyer-initiated only):** `COUNT(*)` on `datalake_sale_primary_market.development_negotiation` where `actor = 'DEMAND'` — filter `actor` to avoid broker-inflation from agent-created negotiations.

No official metric-entity file exists for Primary Market yet — all metrics above are component-level, not corporate/OKR definitions.

## Relationships with Other Entities

### House / Listing (shared grain, different meaning for the shell)

- Same `sk_house` / `id_house` mechanics as Secondary — see [`house_and_listing.md`](house_and_listing.md). The difference is semantic: a Primary shell house represents a **typology**, not one physical unit. Do not treat shell house counts as unit inventory; use `listing_sale_model.unit_count` for that.

### Development (N:1 — typology → development)

- `datalake_ebdb_clean.development_typology.id_development` → `datalake_ebdb_clean.development.id`.
- Ops needs empreendimento-grain cuts (region → incorporadora → empreendimento). The accepted rule: **keep the intent `house_id`** on visits/offers; join to `id_development` at consume time via `house → development_typology_unit`. Do **not** denormalize `id_development` onto facts.

### Offer / CCV (`fs-transact.md`)

- `SalesFlow.sale_type` is the offer-side discriminator, distinct from the listing-side `ListingSaleModel.saleType` — live on `datalake_sales_flow_clean.offer.sale_type`. As of this writing, only `SECONDARY` values have appeared in production (~1,161 rows); `PRIMARY` has 0 observed rows so far, and most rows are still `NULL` (pre-existing offers created before the column landed). Prefer the `dim_listing` join above for offers today since `fact_offers` doesn't yet expose this column — but the raw/clean data itself is available for anyone querying `datalake_sales_flow_clean.offer` directly.
- EN (Deal Maker) and hub assignment on an offer follow the **same raw sources** as Secondary (`offer_specialists`, `sales_flow.offer.id_hub`) — no separate Primary-specific mechanism.

### Visits (typology-shell caveat)

- Visits book on the **shell** house, same as the intent house_id above. A buyer can visit typology A and offer on typology C of the same development — this is expected, not a data error. Typology-level visit-completion rates across shells of the same development are **not meaningful**; aggregate at development grain instead.

## Frequently Asked Questions (example question → table, and why)

Source: SWE domain walkthrough. For each business question: how to answer it **today**, and why — ✓ native (no cross-reference needed) or ⚠ requires a manual cross-reference / has a gap.

### Q: How many visits were booked (VB) for a development?
**Stage:** VB · **Status:** ⚠ manual cross-reference

A visit is recorded in `dw_visit.fact_visit_schedules` by the house_id visited (the typology shell). To know whether that house belongs to a specific development, you have to manually cross-reference `datalake_ebdb_clean.development_typology_unit.id_house` (or the shell equivalent on `house.id_development_typology`) — there is no ready-made column that already says "this visit belongs to Primary Market development X."

### Q: Of those, how many were confirmed or completed (VC)?
**Stage:** VC, VB2VC · **Status:** ⚠ manual cross-reference

Confirmation/completion is already flagged on `dw_visit.fact_visits` (`visit_status`, `is_completed`). Same limitation as the question above: knowing it belongs to "development X" still requires repeating the manual `id_house` cross-reference — there's no shortcut specific to this stage.

### Q: How many visits generated a proposal request?
**Stage:** pré-OS · **Status:** ✓ native

Immediate answer: `datalake_ebdb_clean.development_negotiation` (exposed via `datalake_sale_primary_market.development_negotiation` in the lake) is born with `id_development` and `id_visit` on the same row. Unlike the questions above, no cross-reference is needed — that's the entire reason this table exists (see Service Architecture above).

### Q: How many proposals became a submitted offer (OS)?
**Stage:** OS · **Status:** ⚠ outside the domain

The offer itself is not stored in the Development domain. `DevelopmentNegotiationUnit` triggers `OfferPort`, which calls the external **sales-flow** system (see Service Architecture above). Counting "submitted offers" requires querying that system's own tables (`datalake_sales_flow_clean.offer` / `sales_flow`) or `dw_sale.fact_offers` once the Primary Market flag exists there.

### Q: What's the offer-to-signed-contract conversion (OS2CCV) for a development's units?
**Stage:** OS2CCV · **Status:** ⚠ manual filter

`dw_sale.fact_offers` / `dw_sale.dim_sale_agreement` hold the CCV signature per offer. To restrict to one development, filter by the houses that appear in `development_typology_unit` — again a manual filter by `id_house`, not a ready-made column.

### Q: What's BP→CCV (Buyer Prospect → Contract) restricted to Primary Market?
**Stage:** BP2CCV · **Status:** ⚠ biggest gap

BP comes from `dw_buyer_prospect`, which today carries **no** reference to the development — not direct, not even via house_id. Unlike the questions above, not even the manual cross-reference is possible yet: this is the most serious gap for segmenting this funnel stage by Primary Market. (Also documented in the wiki's `metrics.md` as the "confirmed biggest gap.")

### Q: Who is the active manager (gestor) responsible for a development?
**Category:** operational · **Status:** ✓ native

This question never leaves the Development domain: `DevelopmentContact` (exposed via `datalake_sale_primary_market.house_development.active_contact_uuid_person` / `active_contact_status`) already stores the active manager (`status = 'ACTIVE'`) per development, with no external table or data-warehouse join needed.

## Dos and Don'ts

**Do:**
- Use `dw_sale.dim_listing.is_primary_market` for current, strict Primary/Secondary classification.
- Prefer `sale_type` (the enum) over the legacy `is_primary_market` boolean on `listing_sale_model` wherever both exist — the enum wins, the legacy value is only used as history for pre-existing rows on `house.sql`'s own rollup, not queried directly by analysts.
- Treat the shell house_id as a **typology**, not a physical unit, when reasoning about Primary inventory counts.
- Join `dim_listing` on `sk_house` for any Primary/Secondary question on a fact that doesn't carry its own flag yet (e.g. `fact_offers`).
- Filter `development_negotiation.actor = 'DEMAND'` when counting buyer-initiated pré-OS to avoid broker inflation.
- Check the live SQL/metadata before assuming a table has `sale_type` — this domain is mid-rollout and columns are landing incrementally.

**Do not:**
- Do not use `is_3p_supply`, developer/company ownership, or price alone to infer Primary Market — these are orthogonal axes.
- Do not treat the shell house as one physical apartment; use `unit_count` on `listing_sale_model` or the unit Imovel (`development_typology_unit.id_house`) for inventory-level questions.
- Do not rewrite historical visit `house_id`s after an offer lands on a different typology, and do not expect synthetic "corrective" visits — neither exists by design.
- Do not denormalize `id_development` onto funnel facts — join it at consume time via `house → development_typology_unit → development_typology`.
- Do not assume `fact_offers` has a Primary flag — verify against the live schema; as of this doc, it does not.
- Do not treat `house.is_sale_primary_market` (strict, no fallback) and `listing_sale_type.sale_type` (has a legacy-boolean fallback) as interchangeable — they can disagree on rows where `sale_type` is still null.
- Do not assume `dw_sale.fact_sale_flows` will never get `sale_type` — propagation just hasn't reached it yet. Join `dim_listing` / `house` as the interim alternative, but re-check the live schema; it may land there in a future wave.
- Do not confuse `SalesFlow.sale_type` (offer-side, `datalake_sales_flow_clean.offer.sale_type`) with `ListingSaleModel.saleType` (listing-side, `datalake_ebdb_clean.listing_sale_model.sale_type`) — they are separate columns on separate tables, populated independently.

## Golden Queries

### Query 1 — Primary listing and house counts

Counts current Primary Market listings and shell houses in the DW.

```sql
SELECT
    COUNT(DISTINCT dl.sk_sale_listing) AS primary_listing_count,
    COUNT(DISTINCT dl.sk_house) AS primary_house_count
FROM dw_sale.dim_listing AS dl
WHERE dl.is_primary_market
```

### Query 2 — Primary visit volume by month

Counts Primary Market visits booked and completed, monthly, using the visit-grain `sale_type` column (not a `dim_listing` join). Follows the same `SUM(num_visit_*)` convention as [`visits.md`](visits.md) — do not `COUNT(*)` rows for booked/completed totals.

```sql
SELECT
    DATE_TRUNC('month', CAST(ts_visit_local_tz AS DATE)) AS visit_month,
    SUM(num_visit_booked) AS primary_visits_booked,
    SUM(num_visit_completed) AS primary_visits_completed
FROM dw_visit.fact_visits
WHERE sale_type = 'PRIMARY'
GROUP BY 1
ORDER BY 1 DESC
```

> See [`visits.md`](visits.md) for the full visit-fact column reference, VB2VC conventions, and the `fact_visits` ↔ `fact_visit_schedules` join.
