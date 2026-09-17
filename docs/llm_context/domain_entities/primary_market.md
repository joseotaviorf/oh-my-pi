# Primary Market

## Ownership

**Data Owner:**
- vinicius.santanna@quintoandar.com.br

**Data Steward:**
- gustavo.rompe@quintoandar.com.br

## Overview

Primary Market **Development-domain** analytics are **DW-first**. Start from
`dw_sale_primary_market` whenever the column exists there; fall back to
`datalake_sale_primary_market` enrich only for columns not yet modeled in DW
(main gap today: `listing_sale_type`).

| Priority | Schema | Tables |
| --- | --- | --- |
| **1 — default** | `dw_sale_primary_market` | `dim_house_development`, `fact_development_negotiation` |
| **2 — enrich SSOT** | `datalake_sale_primary_market` | `listing_sale_type`, `house_development`, `development_negotiation` when DW is unavailable or a column is enrich-only |
| **3 — drill-down** | `datalake_ebdb_clean`, `datalake_company_clean` | `development*`, `company` — entity keys and attributes not yet on DW; not for analyst-facing cuts |

Do **not** use `sandbox.*` mirrors. If access to `dw_sale_primary_market` or
`datalake_sale_primary_market` fails because of data-contract permissions,
report the access limitation — do not substitute another schema.

## TARS routing guide (read this first)

Primary Market questions fail when TARS picks the wrong **entity** (empreendimento
vs tipologia vs unidade), the wrong **`id_house`** (shell vs unit), or the wrong
**`sale_type` channel** (listing vs offer). Follow this order:

1. **Classify the question** (table below).
2. **Pick the entity table** (Development catalog below).
3. **Pick the `id_house` path** (shell for visits/catalog; unit for offers/CCV).
4. **Pick `sale_type` source** (native column on the fact, or join
   `listing_sale_type` only when missing).
5. **Scope the population** — pilot vs general PRIMARY use **different join keys
   by grain** (table below); do not reuse one join for visits and offers.

### Question classifier

| User asks about… | Start here | Do **not** use |
| --- | --- | --- |
| Is this listing/visit/offer Primary or Secondary? | Native `sale_type` on the fact (see sale_type map) | `is_primary_market`, `is_sale_primary_market`, `listing_sale_model.is_primary_market` |
| Empreendimento name, address, construction status, Órulo provider | **`dim_house_development`** (DW default) | Counting houses as “anúncios”; enrich `house_development` only if DW unavailable |
| Incorporadora / builder company | **`dim_house_development.uuid_company`** + **`dim_house_development.company_name`** | Manual CASE mapping, `dim_company`, guessing from house owner |
| Tipologia (bedrooms, m², floor plan SKU) | **`dim_house_development`** or `development_typology` | Shell `id_house` count as physical apartments |
| Unidade / apartamento concreto / inventory de units | `development_typology_unit` | Shell listing `id_house` |
| Visitas em um empreendimento | `dw_visit.fact_visits` + join **`dim_house_development`** on **visit `sk_house`** (shell) | `id_visit` to find offers |
| Ofertas / CCV em um empreendimento | `dw_sale.fact_offers` + join on **unit `id_house`** via `development_typology_unit` or `fact_development_negotiation.id_house` | Visit shell `id_house` on offer facts |
| Pré-OS / proposta antes da OS | **`fact_development_negotiation`** (`actor = 'DEMAND'` for buyer-initiated) | Mixing AGENT and DEMAND rows; enrich `development_negotiation` only if DW unavailable |
| Gestor ativo do empreendimento | **`dim_house_development.active_contact_uuid_person`** | Random agent from visit |
| Piloto Órulo / estoque pilot SP | See **pilot scoping by grain** below | `sale_type = 'PRIMARY'` alone |

### Pilot scoping by grain (Órulo / Development domain)

The pilot is **not** one universal `id_house` list. Pick the membership join for
the **question's grain**:

| Question grain | Join on | Why |
| --- | --- | --- |
| Visits, shell listings, catalog, VB/VC | **`dim_house_development.id_house`** = visit/listing `sk_house` | Visits book on **shell** houses (`house.id_development_typology`) |
| Offers, CCV, pré-OS unit, unit inventory count | `development_typology_unit.id_house = offer sk_house` | Negotiation mints a **unit** Imovel |
| Empreendimento name on any linked house | **`dim_house_development`** (either path) | Unifies shell + unit link paths |
| Strict count of minted unit slots | `development_typology_unit` only | ~537 pilot units; excludes shell vitrine houses |

Optional Órulo filter: `dim_house_development.provider = 'ORULO'` (confirm enum in
`datalake_ebdb_clean.development` before relying on spelling).

### Entity hierarchy (Development domain)

```text
incorporadora (builder)
  └── dim_house_development.uuid_company + company_name (via datalake_company_clean.company)
empreendimento (development)
  └── datalake_ebdb_clean.development  |  id_development, name, address, provider, construction_status
tipologia (floor-plan SKU)
  └── datalake_ebdb_clean.development_typology  |  id_development_typology, bedrooms, total_area, …
        ├── shell Imovel (vitrine): published for search + visits
        │     └── house.id + house.id_development_typology  |  one shell per tipologia
        └── unidade (physical slot in the typology)
              └── development_typology_unit  |  id_house = unit Imovel (minted per negotiation/offer)
```

**UI rule:** one **anúncio** on the site groups many tipologias; each tipologia is
one **shell** `id_house`. Counting `id_house` as “number of anúncios” is wrong for
Primary — count `id_development` or distinct tipologies instead.

**Canonical analyst tables** (DW-first; one row per house or negotiation):

| Grain | **Use first (DW)** | Enrich fallback |
| --- | --- | --- |
| House + empreendimento + tipologia + incorporadora | `dw_sale_primary_market.dim_house_development` (`uuid_company`, `company_name`) | `datalake_sale_primary_market.house_development` |
| Pré-OS negotiation | `dw_sale_primary_market.fact_development_negotiation` | `datalake_sale_primary_market.development_negotiation` |
| Listing `sale_type` + price band | — (no DW table yet) | `datalake_sale_primary_market.listing_sale_type` |

Raw clean tables (`datalake_ebdb_clean.development*`, `datalake_company_clean.company`)
are for drill-down and keys not denormalized on `dim_house_development`.

### Two `id_house` paths (critical)

Every Primary funnel question must decide **which Imovel** the user means. Visits
and offers often use **different** `id_house` values for the same buyer journey.

| Path | Business meaning | When created | Typical status | Key columns |
| --- | --- | --- | --- | --- |
| **A — Shell / vitrine** | Tipologia exposed in catalog; visit books here | Tipologia published | **Published** (while typology active) | `visit.id_house`, `fact_development_negotiation.id_house_development`, `house.id_development_typology` |
| **B — Unit / oferta** | Concrete apartment minted for negotiation or offer | Negotiation / offer accept (anti-ghost inventory) | **Unpublished** (offer-only Imovel) | `development_typology_unit.id_house`, `fact_development_negotiation.id_house`, `fact_offers.sk_house` |

```text
Path A (visit):  visit.id_house  =  shell listing Imovel
Path B (offer):  offer house     =  development_typology_unit.id_house
                 =  sales_flow_clean.house.id_external   (NOT sales_flow.house.id)
```

**Join rules TARS must apply:**

- Visit metrics → join facts to **`dim_house_development`** / `development` on the
  **house id visited** (`sk_house` / `id_house` from visit).
- Offer / CCV metrics → join on **unit** `id_house` (`fact_development_negotiation.id_house`
  or `development_typology_unit.id_house`).
- `fact_development_negotiation` exposes **both** `id_house_development` (visit listing)
  and `id_house` (unit) on one row — use it to link visit context to offer context.
- **`id_visit` is not an offer key** — it is origin context only. Never match
  `id_visit` to `id_offer`.
- One visit can spawn **multiple** negotiations (buyer wants two units). One
  negotiation has **at most one** open unit (`DevelopmentNegotiationUnit` uniqueness).

`listing_sale_type` classifies **listing-side** houses. Unit houses created only
for offers may be **absent** from `listing_sale_type`; use **`dim_house_development`** for
empreendimento/tipologia on any `id_house`.

### `sale_type` map (three independent channels)

Do not assume one `sale_type` propagates everywhere. Pick the channel for the
**grain of the question**:

| Channel | Authoritative source | Propagated to | Filter |
| --- | --- | --- | --- |
| **Listing / house** | `datalake_sale_primary_market.listing_sale_type` (from `listing_sale_model.sale_type`; NULL → `SECONDARY`) | `dw_sale.dim_listing`, `dw_visit.fact_visits`, `dw_visit.fact_visit_schedules`, `dw_sale.fact_daily_ongoing_listing`, `dw_sale.fact_listings`, … | `sale_type = 'PRIMARY'` |
| **Offer / CCV** | `datalake_sales_flow_clean.offer.sale_type` | `datalake_sale_offer.core_sale_offer`, `datalake_sale_offer.sale_offer`, `dw_sale.fact_offers`, `dw_sale.dim_offer`, `dw_sale.dim_sale_agreement`, `dw_sale.fact_sale_demand_event` (offer events), `dw_sale.fact_sale_flows` | `sale_type = 'PRIMARY'` |
| **Buyer activation** | `datalake_buyer_prospect.buyer_prospect_type.sale_type` | (not on `dw_sale.fact_buyer_prospects` yet) | `sale_type = 'PRIMARY'` + `bp_market_type` for exclusivity |

**Compatibility booleans (do not use for new logic):**

- `dw_sale.dim_listing.is_primary_market` = `TRUE` only when `sale_type = 'PRIMARY'`.
- `datalake_ebdb_listing.house.is_sale_primary_market` = BOOL_OR of listing enum;
  can disagree with `listing_sale_type` on edge cases.

**When the fact has no `sale_type`:** join
`datalake_sale_primary_market.listing_sale_type` on `id_house` / `sk_house`. If
the house is a **unit** Imovel missing from that table, join **`dim_house_development`**
instead for Development attributes (not for market enum).

`NULL` in `sale_type` ≠ `SECONDARY`.

### Incorporadora name (`company_name` on DW)

Use **`dim_house_development.uuid_company`** and **`dim_house_development.company_name`**
— denormalized in DW from `datalake_ebdb_clean.development.company_uuid` joined to
`datalake_company_clean.company.uuid_company`. Do **not** use manual CASE mappings.

Example at development grain (DW-first):

```sql
SELECT
    id_development,
    development_name,
    uuid_company,
    company_name,
    COUNT(DISTINCT id_house) AS n_houses
FROM dw_sale_primary_market.dim_house_development
GROUP BY 1, 2, 3, 4
ORDER BY n_houses DESC
```

`company_name` is NULL when `company_uuid` is missing or has no row in
`datalake_company_clean.company` — report as unmapped; do not invent a name.

### Development entity catalog (where to find each thing)

| Concept | Grain | Best table | Key fields |
| --- | --- | --- | --- |
| Empreendimento | 1 row / development | `datalake_ebdb_clean.development` | `id`, `name`, `company_uuid`, `provider`, `construction_status`, address fields |
| Incorporadora | 1 row / builder company | **`dim_house_development`** (`uuid_company`, `company_name`) | Source join: `development.company_uuid` = `company.uuid_company` |
| Tipologia | 1 row / floor plan | `datalake_ebdb_clean.development_typology` | `id`, `id_development`, `bedrooms`, `bathrooms`, `total_area`, `type` |
| Shell house (vitrine) | 1 row / tipologia listing | `house` where `id_development_typology` set + published SALE listing | `house.id`, `listing_sale_type.sale_type`, `listing_sale_model.unit_count` for stock |
| Unidade (inventory slot) | 1 row / physical unit slot | `datalake_ebdb_clean.development_typology_unit` | `id`, `id_development_typology`, `id_house` (unit Imovel) |
| Unit published on catalog | optional | `datalake_ebdb_clean.development_listing_unit` | Links unit to `id_listing_business_context` when published |
| Gestor ativo | 1 contact / development | **`dim_house_development.active_contact_uuid_person`**, `active_contact_status` | Via `development.id_development_contact` |
| Amenities | N / development | **`dim_house_development.amenities`** (array) | Or `development_amenity` clean |
| Tipologia attributes | N / typology | **`dim_house_development.typology_attributes`** (array) | Or `development_typology_attribute` clean |
| Market enum + price band | 1 row / house (SALE listing) | `listing_sale_type` | `sale_type`, `min_price`, `max_price` |
| Pré-OS event | 1 row / negotiation | **`fact_development_negotiation`** | `id_development`, `id_visit`, `id_house_development`, `id_house`, `actor`, `id_offer` |

### Overview context

- **Objective:** classify sale listings, visits, and ongoing-supply snapshots as **Primary** (new-build inventory sold by an incorporadora) or **Secondary** (resale between individuals), and route Ops/TARS questions to the current source of truth during the pilot rollout.
- **Asset status / lifecycle:** August 2026 São Paulo pilot, inventory supplied through Órulo. The engineering RFC introduced a **1:N** development model (one empreendimento → N typologies → N shell houses) that coexists with the legacy **1:1** secondary model (one listing ≈ one house ≈ one unit).
- **Source of truth:** use the source according to the grain. Listing/house classification is `datalake_sale_primary_market.listing_sale_type.sale_type` (`listing_sale_model.sale_type` enum; NULL maps to `SECONDARY`; the legacy boolean is not authoritative). The compatibility boolean `dw_sale.dim_listing.is_primary_market` is derived from `sale_type` and is TRUE only for `PRIMARY`. Offer classification is `datalake_sales_flow_clean.offer.sale_type`, propagated through `datalake_sale_offer.core_sale_offer`, `datalake_sale_offer.sale_offer`, and the offer DW tables. Buyer activation classification is `datalake_buyer_prospect.buyer_prospect_type.sale_type`, with `bp_market_type` for market exclusivity.
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

`listing_sale_type` reads `listing_sale_model.sale_type` (NULL → `SECONDARY`).
The legacy `is_primary_market` source flag is not used for current
classification because it is stale.

**Measured 2026-09-02 against the previous fallback-inclusive SSOT** (kept so TARS does not reuse those inflated numbers after the filter):

1. **The new Órulo pilot** (this doc's actual subject) — houses in `datalake_ebdb_clean.development_typology_unit` (**537** houses), almost all of which also have `sale_type = 'PRIMARY'` on the strict raw enum (**536** — 1 house not yet classified).
2. **Legacy pre-pilot houses previously identified by `is_primary_market = TRUE`** — builder-sold / test listings flagged under the old system. The flag is stale and is no longer a valid population filter.

On that older snapshot, `dw_visit.fact_visits` with `sale_type = 'PRIMARY'` returned **37,407 visits booked** (90% VB2VC) across the mixed population, versus **23 visits booked** (5 completed, 17 distinct houses) when scoped to the 536/537-house pilot. **If a question is about the Órulo São Paulo pilot, filter by `development_typology_unit.id_house` (or join `dim_house_development`), not by `sale_type = 'PRIMARY'` alone** — that remains the native Development-domain population.

```sql
-- Pilot visits / shell listing facts (visit sk_house = shell vitrine) — DW-first
INNER JOIN dw_sale_primary_market.dim_house_development AS dhd
    ON dhd.id_house = fact_table.sk_house

-- Pilot offers / unit facts (offer sk_house = minted unit Imovel)
INNER JOIN datalake_ebdb_clean.development_typology_unit AS dtu
    ON dtu.id_house = fact_table.sk_house
```

`sale_type = 'PRIMARY'` on refreshed `listing_sale_type`-sourced tables is enum PRIMARY only. Tables natively scoped to the Development domain (`dim_house_development`, `fact_development_negotiation`) remain the safest pilot-only sources.

## Related Metric Entities

- None — no metric entity doc owns Primary Market metrics yet.

## Glossary and Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Primary Market / Mercado Primário / MP** | New-build inventory sold by an incorporadora | `sale_type = 'PRIMARY'` is the listing-side enum filter; use `development_typology_unit.id_house` for strict Órulo-pilot scope |
| **Secondary Market / Mercado Secundário** | Resale inventory between individuals (CPF sellers) | `listing_sale_type.sale_type = 'SECONDARY'` (NULL enum is filled as SECONDARY). A LEFT JOIN to `listing_sale_type` is NULL when the house has no SALE listing_sale_model row |
| **Incorporadora / builder / developer company** | Legal entity behind the empreendimento | **`dim_house_development.uuid_company`** + **`dim_house_development.company_name`** (from `datalake_company_clean.company`) |
| **Development / Empreendimento** | The real-estate project aggregate, containing multiple typologies | **`dw_sale_primary_market.dim_house_development`** at house grain |
| **Typology / Tipologia** | A floor-plan / SKU within a development; exposed as one **shell house** for search and visit | `datalake_ebdb_clean.development_typology`; attributes denormalized on **`dim_house_development`** |
| **Shell house / Imóvel shell** | The house_id a typology is listed and visited on. **Not** a physical unit — one shell can represent many real apartments | Intent/visit key; kept unchanged per the funnel-attribution ADR (no visit rewrite) |
| **Unit Imovel / unidade** | The real physical apartment slot; `id_house` minted for negotiation/offer (usually unpublished) | `datalake_ebdb_clean.development_typology_unit.id_house`; offer path uses `fact_development_negotiation.id_house` and `fact_offers.sk_house` |
| **`id_house_development`** | Shell listing where the **visit** was booked | `fact_development_negotiation.id_house_development`, `visit.id_house` — not the offer house |
| **DevelopmentNegotiation / pré-OS** | Pre-offer negotiation event on a typology unit, created by an agent or the buyer | **`dw_sale_primary_market.fact_development_negotiation`**; `actor` (`AGENT`/`DEMAND`) must be filtered to avoid broker-inflation of pré-OS counts |
| **EN, Executivo de Negociação, Deal Maker** | Negotiation Executive assigned to an offer's sales flow — in Primary, a conversion accelerator / developer liaison, not a price closer like Secondary | `datalake_sale_offer_flows.offer_specialists.id_user_consultant` |
| **hub_bp** | The closing hub servicing an offer | `datalake_sales_flow_clean.offer.id_hub` — native Sales Flow field, same mechanism as Secondary |
| **city_group** | Region grouping of a house | Resolved from `datalake_ebdb_clean.house.id_region` → `datalake_region.region.city_group` |
| **Buyer activation `sale_type`** | Market classification of the house that triggered the buyer-prospect activation | `datalake_buyer_prospect.buyer_prospect_type.sale_type`; strict Primary pilot membership through **`dim_house_development`** |
| **`bp_market_type`** | Buyer market-exclusivity segment, independent of NBP/RBP | `PRIMARY_EXCLUSIVE`, `NON_EXCLUSIVE`, or `SECONDARY_EXCLUSIVE` in `buyer_prospect_type` |
| **DSP (`developers-supply-processor`)** | Product-side supply ledger for Primary inventory (Órulo sync) — **not** a DW/analytics source | See `datalake_ebdb_clean.development*` for the lake-side result of DSP → Main |
| **BSP (`brokers-supply-processor`)** | Unrelated 3P broker-lead pipeline — orthogonal axis (who supplies), not Primary/Secondary market type | Do not conflate with Primary Market classification |

## Tables

**DW-first for Development-domain cuts:** prefer `dw_sale_primary_market.dim_house_development`
and `fact_development_negotiation` before enrich mirrors. Do not use `sandbox.*`.

| You need... | Use this table |
|-------------|-----------------|
| Primary/Secondary classification at listing grain | `dw_sale.dim_listing` (`dl`) — use `sale_type`; `is_primary_market` is a derived compatibility boolean and must not be used for new analyses. |
| Raw enum + unit-level attributes | `datalake_ebdb_clean.listing_sale_model` (`lsm`) — `sale_type`, `unit_count`, `min_price`, `max_price`. Prefer the `listing_sale_type` SSOT for analyst queries; do not join this table directly from ad-hoc SQL. |
| House-grain Primary flag (pre-listing join) | `datalake_ebdb_listing.house` (enrich) — `is_sale_primary_market` = `BOOL_OR(sale_type = 'PRIMARY')` across that house's `listing_sale_model` rows. No legacy-boolean fallback. |
| House-grain canonical `sale_type` fill (preferred join target) | `datalake_sale_primary_market.listing_sale_type` (enrich) — one row per house from the SALE `listing_sale_model` (1:1 with SALE `listing_business_context`). `sale_type` is the enum; NULL enum is filled as `SECONDARY`. It also carries `min_price` and `max_price`. |
| Primary flag on visits — **just sale** | `dw_visit.fact_visits` and `dw_visit.fact_visit_schedules` (canonical — see [`visits.md`](visits.md)) — `sale_type` (STRING: `PRIMARY`/`SECONDARY`/`NULL`) at visit grain, derived from the house's SALE `listing_sale_type`; RENT rows are `NULL`. `dw_sale.fact_visits` also got the column (same enrich source), but it is a **separate, legacy table not covered by `visits.md`** — prefer `dw_visit.fact_visits` unless you have a specific reason to use the older one. |
| Primary flag on daily supply snapshot | `dw_sale.fact_daily_ongoing_listing` — `sale_type` per snapshot day. |
| Listing publication facts | `dw_sale.fact_listings` — `sale_type` per listing. |
| Listing price-change facts | `dw_sale.fact_listing_price_changes` — latest available house-level `sale_type`; not a historical as-of classification. |
| Offer volume and offer attributes | `dw_sale.fact_offers` and `dw_sale.dim_offer` — offer-side `sale_type` propagated from Sales Flow. |
| Sale agreement attributes | `dw_sale.dim_sale_agreement` — offer-side `sale_type` alongside CCV attributes. |
| Demand-funnel events | `dw_sale.fact_sale_demand_event` — visit events use `dw_sale.fact_visits.sale_type`; offer events use `dw_sale.fact_offers.sale_type`. |
| Buyer-house sale flows | `dw_sale.fact_sale_flows` — offer-side `sale_type`; booking/TTA-only flows remain NULL. |
| Buyer activation and market exclusivity | `datalake_buyer_prospect.buyer_prospect_type` — `sale_type` for the activation house and `bp_market_type` (`PRIMARY_EXCLUSIVE`, `NON_EXCLUSIVE`, `SECONDARY_EXCLUSIVE`). This is distinct from `bp_type` (`NBP`/`RBP`). |
| Development / typology context for a house | **`dw_sale_primary_market.dim_house_development`** (default) — house-grain development and typology attributes. Enrich fallback: `datalake_sale_primary_market.house_development`. |
| Pré-OS negotiation events | **`dw_sale_primary_market.fact_development_negotiation`** (default) — visit house, unit house, offer, flow, and development keys. Enrich fallback: `datalake_sale_primary_market.development_negotiation`. |
| Incorporadora name by development | **`dim_house_development.company_name`** (with `uuid_company`) — see **Incorporadora name** section. |
| Primary-market pilot scope | `datalake_ebdb_clean.development_typology_unit.id_house` or **`dim_house_development`** — native Órulo-pilot population. Prefer DW development tables for analyst cuts. |

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
- **Primary visit volume (pilot-scoped):** `SUM(num_visit_booked)` on `dw_visit.fact_visits`, joined to **`dim_house_development`** on **visit `sk_house`** (shell path — do **not** join `development_typology_unit` on visit `sk_house`). Do **not** filter by `sale_type = 'PRIMARY'` alone for strict pilot KPIs. See [`visits.md`](visits.md) for booked vs completed metric conventions.
- **Primary ongoing supply (daily stock):** `COUNT(DISTINCT sk_snapshot)` (or house count) on `dw_sale.fact_daily_ongoing_listing` where `sale_type = 'PRIMARY'`.
- **Pré-OS volume (buyer-initiated only):** `COUNT(*)` on **`dw_sale_primary_market.fact_development_negotiation`** where `actor = 'DEMAND'` — filter `actor` to avoid broker-inflation from agent-created negotiations.
- **Visit → pré-OS conversion:** join `dw_visit.fact_visits.sk_visit` to **`fact_development_negotiation.id_visit`** (same ID space — see Golden Query 13). As of 2026-09-02: 1 of 23 pilot visits (1 of 5 completed) led to a negotiation — directional only at this volume.
- **Buyer market exclusivity:** `COUNT(DISTINCT id_prospect)` on `datalake_buyer_prospect.buyer_prospect_type`, grouped by `bp_market_type` and filtered by `sale_type = 'PRIMARY'` for buyers activated by a Primary house.

No official metric-entity file exists for Primary Market yet — all metrics above are component-level, not corporate/OKR definitions.

## Relationships with other entities

### House / Listing (shared grain, different meaning for the shell)

- Same `sk_house` / `id_house` mechanics as Secondary — see [`house_and_listing.md`](house_and_listing.md). The difference is semantic: a Primary shell house represents a **typology**, not one physical unit. Do not treat shell house counts as unit inventory; use `listing_sale_model.unit_count` for that.

### Development (N:1 — typology → development)

- `datalake_ebdb_clean.development_typology.id_development` → `datalake_ebdb_clean.development.id`.
- Ops needs empreendimento-grain cuts (region → incorporadora → empreendimento). The accepted rule: **keep the intent `house_id`** on visits/offers; join to `id_development` at consume time via **`dim_house_development`** (unifies shell and unit paths; includes `company_name`). Do **not** denormalize `id_development` onto facts.

### Offer / CCV (`fs-transact.md`)

- `SalesFlow.sale_type` is the offer-side discriminator, distinct from the listing-side `ListingSaleModel.saleType`. It is available on `datalake_sales_flow_clean.offer`, then propagated to `datalake_sale_offer.core_sale_offer`, `datalake_sale_offer.sale_offer`, `dw_sale.fact_offers`, `dw_sale.dim_offer`, `dw_sale.dim_sale_agreement`, `dw_sale.fact_sale_demand_event`, and `dw_sale.fact_sale_flows`. NULL remains valid for historical or unclassified offers.
- EN (Deal Maker) and hub assignment on an offer follow the **same raw sources** as Secondary (`offer_specialists`, `sales_flow.offer.id_hub`) — no separate Primary-specific mechanism.

### Visits (typology-shell caveat)

- Visits book on the **shell** house, same as the intent house_id above. A buyer can visit typology A and offer on typology C of the same development — this is expected, not a data error. Typology-level visit-completion rates across shells of the same development are **not meaningful**; aggregate at development grain instead.

### Frequently Asked Questions (example question → table, and why)

Source: SWE domain walkthrough. For each business question: how to answer it **today**, and why — ✓ native (no cross-reference needed) or ⚠ requires a manual cross-reference / has a gap.

### Q: How many visits were booked (VB) for a development?
**Stage:** VB · **Status:** ⚠ manual cross-reference

A visit is recorded in `dw_visit.fact_visit_schedules` by the house_id visited (the typology **shell**). Join **`dw_sale_primary_market.dim_house_development`** on that `id_house` / `sk_house` to resolve empreendimento and tipologia — do **not** join `development_typology_unit` on the visit house (unit path is a different `id_house`).

### Q: Of those, how many were confirmed or completed (VC)?
**Stage:** VC, VB2VC · **Status:** ⚠ manual cross-reference

Confirmation/completion is already flagged on `dw_visit.fact_visits` (`visit_status`, `is_completed`). Same limitation as the question above: knowing it belongs to "development X" still requires repeating the manual `id_house` cross-reference — there's no shortcut specific to this stage.

### Q: How many visits generated a proposal request?
**Stage:** pré-OS · **Status:** ✓ native

Immediate answer: **`dw_sale_primary_market.fact_development_negotiation`** is born with `id_development` and `id_visit` on the same row. Unlike the questions above, no cross-reference is needed — that's the entire reason this table exists (see Service Architecture above). Enrich fallback: `datalake_sale_primary_market.development_negotiation`.

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

This question never leaves the Development domain: `DevelopmentContact` (exposed via **`dw_sale_primary_market.dim_house_development`**) stores the development contact fields, with no external table or data-warehouse join needed.

## Dos and Don'ts

**Do:**
- Read **TARS routing guide** above before picking tables — especially shell vs unit `id_house`.
- **Start from `dw_sale_primary_market`** (`dim_house_development`, `fact_development_negotiation`) for Development-domain analyst cuts; use enrich tables only when a column is enrich-only (e.g. `listing_sale_type`) or DW access fails.
- Prefer native `sale_type` on the fact/dimension being queried. At house/listing grain without a native column, join `listing_sale_type` (enum; NULL → `SECONDARY`). For unit Imovel missing from `listing_sale_type`, use **`dim_house_development`** for Development attributes.
- Read incorporadora **name** from **`dim_house_development.company_name`** — see **Incorporadora name** section.
- Keep `dw_sale.dim_listing.is_primary_market` only for backward-compatible dashboards — it is derived from `sale_type`.
- Treat the shell house_id as a **typology**, not a physical unit, when reasoning about Primary inventory counts.
- Scope pilot **visits** via **`dim_house_development`**; scope pilot **offers/units** via `development_typology_unit`.
- Filter **`fact_development_negotiation.actor = 'DEMAND'`** when counting buyer-initiated pré-OS to avoid broker inflation.
- Scope any Órulo-pilot question via `development_typology_unit.id_house` (or **`dim_house_development`**), not `sale_type = 'PRIMARY'` alone — see the population warning above.
- Check the live physical schema after each DAG rollout; merged SQL and deployed columns can temporarily differ until the affected DAG runs. If access fails because of missing Primary Market data-contract permissions, report the limitation — do **not** substitute `sandbox.*` or other schemas.

**Do not:**
- Do not use `is_3p_supply`, developer/company ownership, or price alone to infer Primary Market — these are orthogonal axes.
- Do not treat the shell house as one physical apartment; use `unit_count` on `listing_sale_model` or the unit Imovel (`development_typology_unit.id_house`) for inventory-level questions.
- Do not rewrite historical visit `house_id`s after an offer lands on a different typology, and do not expect synthetic "corrective" visits — neither exists by design.
- Do not denormalize `id_development` onto funnel facts — join at consume time via **`dim_house_development`** or the correct shell/unit path above.
- Do not treat `fact_offers.sale_type` as a listing classification; it is offer-side Sales Flow data.
- Do not treat `house.is_sale_primary_market` and `listing_sale_type.sale_type` as interchangeable — BOOL_OR vs SSOT can disagree.
- Do not join visit `id_house` to `fact_offers` expecting a match on Primary — visit is shell, offer is unit.
- Do not use manual incorporadora CASE mappings — use **`dim_house_development.company_name`** (resolved via `datalake_company_clean.company`).
- Do not use `sandbox.*` mirrors for Primary Market analysis.
- Do not use `dw_sale.fact_buyer_prospects` as if it had `sale_type`; use `datalake_buyer_prospect.buyer_prospect_type` for activation-level market segmentation and `bp_market_type` for buyer exclusivity.
- Do not confuse `SalesFlow.sale_type` (offer-side, `datalake_sales_flow_clean.offer.sale_type`) with `ListingSaleModel.saleType` (listing-side, `datalake_ebdb_clean.listing_sale_model.sale_type`) — they are separate columns on separate tables, populated independently.

## Golden Queries

Queries **1–10** mirror the Primary Market Hub examples. Queries **11–17** add
pilot scoping, pré-OS, incorporadora mapping, and shell-vs-unit patterns from
the TARS routing guide above. Prefer `sale_type = 'PRIMARY'` over
`is_primary_market` in new analyses. Default Development joins to
`dim_house_development` / `fact_development_negotiation` (DW).

### Query 1 — Published Primary houses and listings (Hub Q1)

```sql
SELECT
    COUNT(DISTINCT sk_house) AS n_primary_houses_published,
    COUNT(DISTINCT sk_sale_listing) AS n_primary_listings_published
FROM dw_sale.dim_listing
WHERE sale_type = 'PRIMARY'
  AND status = 'PUBLISHED'
```

> `is_primary_market = TRUE` is equivalent here (derived from `sale_type`). Use
> `sale_type` in new SQL. `COUNT(DISTINCT sk_sale_listing)` is safer than
> `COUNT(*)` if the dimension ever fans out.

### Query 2 — Average, highest, and lowest price (Hub Q2)

**Preferred (SSOT):**

```sql
SELECT
    COUNT(*) AS n_houses,
    COUNT(min_price) AS n_with_price,
    AVG(min_price) AS avg_min_price,
    AVG(max_price) AS avg_max_price,
    MAX(max_price) AS highest_price,
    MIN(min_price) AS lowest_price
FROM datalake_sale_primary_market.listing_sale_type
WHERE sale_type = 'PRIMARY'
```

**Origin (avoid in new analyses — join clean tables manually):**

```sql
WITH latest_lsm AS (
    SELECT
        lbc.id_house,
        lsm.sale_type,
        lsm.min_price,
        lsm.max_price,
        ROW_NUMBER() OVER (PARTITION BY lbc.id_house ORDER BY lbc.ts_updated DESC) AS _w
    FROM datalake_ebdb_clean.listing_business_context AS lbc
    INNER JOIN datalake_ebdb_clean.listing_sale_model AS lsm
        ON lbc.id = lsm.id_listing_business_context
    WHERE lbc.business_context = 'SALE'
)
SELECT
    COUNT(*) AS n_houses,
    COUNT(min_price) AS n_with_price,
    AVG(min_price) AS avg_min_price,
    AVG(max_price) AS avg_max_price,
    MAX(max_price) AS highest_price,
    MIN(min_price) AS lowest_price
FROM latest_lsm
WHERE _w = 1
  AND sale_type = 'PRIMARY'
```

### Query 3 — Distinct developments (Hub Q3)

**Origin:**

```sql
SELECT COUNT(DISTINCT id) AS n_developments
FROM datalake_ebdb_clean.development
```

**Preferred (DW / enrich):**

```sql
SELECT COUNT(DISTINCT id_development) AS n_developments
FROM dw_sale_primary_market.dim_house_development
-- enrich equivalent: datalake_sale_primary_market.house_development
```

### Query 4 — Typologies per development (Hub Q4)

**Origin:**

```sql
WITH per_dev AS (
    SELECT
        id_development,
        COUNT(*) AS n_typologies
    FROM datalake_ebdb_clean.development_typology
    GROUP BY id_development
)
SELECT
    COUNT(*) AS n_developments_with_typology,
    AVG(n_typologies) AS avg_typologies_per_development,
    MAX(n_typologies) AS max_typologies_per_development
FROM per_dev
```

**Preferred (DW / enrich):**

```sql
WITH per_development AS (
    SELECT
        id_development,
        COUNT(DISTINCT id_development_typology) AS n_typologies
    FROM dw_sale_primary_market.dim_house_development
    GROUP BY id_development
)
SELECT
    COUNT(*) AS n_developments_with_typology,
    AVG(n_typologies) AS avg_typologies_per_development,
    MAX(n_typologies) AS max_typologies_per_development
FROM per_development
```

### Query 5 — Typology area and bedrooms (Hub Q5)

**Origin:**

```sql
SELECT
    COUNT(*) AS n_typologies,
    COUNT(total_area) AS n_with_area,
    AVG(total_area) AS avg_total_area_m2,
    AVG(bedrooms) AS avg_bedrooms
FROM datalake_ebdb_clean.development_typology
```

**Preferred (DW / enrich):**

```sql
WITH unique_typologies AS (
    SELECT DISTINCT
        id_development_typology,
        total_area,
        bedrooms
    FROM dw_sale_primary_market.dim_house_development
)
SELECT
    COUNT(*) AS n_typologies,
    COUNT(total_area) AS n_with_area,
    AVG(total_area) AS avg_total_area_m2,
    AVG(bedrooms) AS avg_bedrooms
FROM unique_typologies
```

### Query 6 — Primary visit booked and completed (Hub Q6)

General Primary Market visits (`sale_type` on the visit fact). For **Órulo pilot**
scope, join **`dim_house_development`** on `sk_house` instead — see Query 11.

```sql
SELECT
    COUNT(DISTINCT CASE WHEN is_booking = 1 THEN sk_schedule END) AS n_primary_visit_booked,
    COUNT(DISTINCT CASE WHEN is_completed = 1 THEN sk_schedule END) AS n_primary_visit_completed,
    1.0 * COUNT(DISTINCT CASE WHEN is_completed = 1 THEN sk_schedule END)
        / NULLIF(COUNT(DISTINCT CASE WHEN is_booking = 1 THEN sk_schedule END), 0) AS visit_completion_rate
FROM dw_visit.fact_visit_schedules
WHERE sale_type = 'PRIMARY'
```

### Query 7 — Demand funnel conversion (Hub Q7)

```sql
WITH primary_event_counts AS (
    SELECT
        COUNT(DISTINCT CASE WHEN sk_event_type = 1 THEN sk_sale_demand_event END) AS vb,
        COUNT(DISTINCT CASE WHEN sk_event_type = 2 THEN sk_sale_demand_event END) AS vc,
        COUNT(DISTINCT CASE WHEN sk_event_type = 3 THEN sk_sale_demand_event END) AS os,
        COUNT(DISTINCT CASE WHEN sk_event_type = 4 THEN sk_sale_demand_event END) AS oa,
        COUNT(DISTINCT CASE WHEN sk_event_type = 6 THEN sk_sale_demand_event END) AS ccv
    FROM dw_sale.fact_sale_demand_event
    WHERE sale_type = 'PRIMARY'
)
SELECT
    vb,
    vc,
    os,
    oa,
    ccv,
    1.0 * vc / NULLIF(vb, 0) AS vb_to_vc_rate,
    1.0 * oa / NULLIF(os, 0) AS os_to_oa_rate,
    1.0 * ccv / NULLIF(os, 0) AS os_to_ccv_rate
FROM primary_event_counts
```

### Query 8 — Primary offer conversion (Hub Q8)

```sql
SELECT
    COUNT(DISTINCT sk_offer) AS n_primary_offers,
    COUNT(DISTINCT CASE WHEN sk_offer_accepted_date <> -1 THEN sk_offer END) AS n_primary_offers_accepted,
    COUNT(DISTINCT CASE WHEN sk_sale_agreement_signed_date <> -1 THEN sk_offer END) AS n_primary_ccvs_signed,
    1.0 * COUNT(DISTINCT CASE WHEN sk_offer_accepted_date <> -1 THEN sk_offer END)
        / NULLIF(COUNT(DISTINCT sk_offer), 0) AS offer_acceptance_rate,
    1.0 * COUNT(DISTINCT CASE WHEN sk_sale_agreement_signed_date <> -1 THEN sk_offer END)
        / NULLIF(COUNT(DISTINCT sk_offer), 0) AS offer_to_ccv_rate
FROM dw_sale.fact_offers
WHERE sale_type = 'PRIMARY'
```

### Query 9 — Buyers with a Primary offer (Hub Q9)

```sql
SELECT
    COUNT(DISTINCT sk_buyer) AS n_buyers_with_primary_offer,
    COUNT(DISTINCT sk_house) AS n_houses_with_primary_offer,
    COUNT(DISTINCT sk_offer) AS n_primary_offers
FROM dw_sale.fact_offers
WHERE sale_type = 'PRIMARY'
```

> Offer `sk_house` is the **unit** Imovel path, not the visit shell house.

### Query 10 — Primary buyers by market exclusivity (Hub Q10)

`bp_market_type` (`PRIMARY_EXCLUSIVE`, `NON_EXCLUSIVE`, `SECONDARY_EXCLUSIVE`) is
independent of `bp_type` (`NBP` / `RBP` = new vs returning buyer).

```sql
SELECT
    bp_market_type,
    bp_type,
    COUNT(DISTINCT id_prospect) AS n_buyers,
    COUNT(*) AS n_activation_events,
    COUNT(DISTINCT id_house) AS n_houses,
    COUNT(DISTINCT id_offer) AS n_offers
FROM datalake_buyer_prospect.buyer_prospect_type
WHERE sale_type = 'PRIMARY'
GROUP BY bp_market_type, bp_type
ORDER BY bp_market_type, bp_type
```

### Query 11 — Primary visit volume by month (pilot-scoped)

Counts Primary Market **pilot** visits booked and completed, monthly. Joins
**`dim_house_development`** because visits book on **shell** houses, not unit Imovels.
**Deliberately does NOT filter `sale_type = 'PRIMARY'` alone** for strict pilot
KPIs. Follows the same `SUM(num_visit_*)` convention as [`visits.md`](visits.md)
— do not `COUNT(*)` rows for booked/completed totals.

```sql
SELECT
    DATE_TRUNC('month', CAST(fv.ts_visit_local_tz AS DATE)) AS visit_month,
    SUM(fv.num_visit_booked) AS primary_visits_booked,
    SUM(fv.num_visit_completed) AS primary_visits_completed
FROM dw_visit.fact_visits AS fv
INNER JOIN dw_sale_primary_market.dim_house_development AS dhd
    ON dhd.id_house = fv.sk_house
GROUP BY 1
ORDER BY 1 DESC
```

> See [`visits.md`](visits.md) for the full visit-fact column reference, VB2VC conventions, and the `fact_visits` ↔ `fact_visit_schedules` join.

### Query 12 — Pilot VB2VC rate vs. Secondary (comparison)

Compares visit-completion efficiency between the pilot and Secondary. Pilot
segment uses **`dim_house_development`** on visit `sk_house` (shell path).

```sql
SELECT
    CASE WHEN dhd.id_house IS NOT NULL THEN 'PRIMARY_PILOT' ELSE fv.sale_type END AS segment,
    SUM(fv.num_visit_booked) AS booked,
    SUM(fv.num_visit_completed) AS completed,
    CAST(SUM(fv.num_visit_completed) AS DOUBLE) / NULLIF(SUM(fv.num_visit_booked), 0) AS vb2vc_rate
FROM dw_visit.fact_visits AS fv
LEFT JOIN dw_sale_primary_market.dim_house_development AS dhd
    ON dhd.id_house = fv.sk_house
WHERE fv.sale_type IN ('PRIMARY', 'SECONDARY')
GROUP BY 1
ORDER BY 1
```

### Query 13 — Visit → pré-OS conversion (pilot)

How many pilot visits led to a negotiation (pré-OS)? `fact_development_negotiation.id_visit` and `fact_visits.sk_visit` share the same ID space (both ultimately trace to `datalake_visit.visits.id_visit` / `datalake_ebdb_clean.visit.id`, which are kept in sync) — confirmed against the one known negotiation in production before relying on this join.

```sql
WITH pilot_visits AS (
    SELECT
        fv.sk_visit,
        fv.sk_house,
        fv.is_completed
    FROM dw_visit.fact_visits AS fv
    INNER JOIN dw_sale_primary_market.dim_house_development AS dhd
        ON dhd.id_house = fv.sk_house
)
SELECT
    COUNT(*) AS total_pilot_visits,
    SUM(CASE WHEN pv.is_completed THEN 1 ELSE 0 END) AS completed_pilot_visits,
    COUNT(DISTINCT fdn.id_visit) AS visits_with_negotiation
FROM pilot_visits AS pv
LEFT JOIN dw_sale_primary_market.fact_development_negotiation AS fdn
    ON fdn.id_visit = pv.sk_visit
```

### Query 14 — Visits by development (top N)

Which developments are getting visit traffic. Useful for spotting cold-start developments the pilot hasn't yet demonstrated demand for.

```sql
SELECT
    dhd.development_name,
    dhd.id_development,
    SUM(fv.num_visit_booked) AS booked,
    SUM(fv.num_visit_completed) AS completed
FROM dw_visit.fact_visits AS fv
INNER JOIN dw_sale_primary_market.dim_house_development AS dhd
    ON dhd.id_house = fv.sk_house
GROUP BY 1, 2
ORDER BY booked DESC
LIMIT 10
```

### Query 15 — Classify an `id_house` as shell vs unit (TARS sanity check)

Given a house id, determine whether it is a typology shell (visit/catalog) or a
minted unit (offer path), and resolve empreendimento + tipologia without
reimplementing the two link paths.

```sql
SELECT
    h.id AS id_house,
    CASE
        WHEN shell.id_development_typology IS NOT NULL THEN 'SHELL_TYPOLOGY_LISTING'
        WHEN dtu.id_house IS NOT NULL THEN 'UNIT_IMOVEL'
        ELSE 'NOT_IN_DEVELOPMENT_DOMAIN'
    END AS house_role,
    dhd.id_development,
    dhd.development_name,
    dhd.id_development_typology,
    dhd.bedrooms,
    dhd.total_area,
    lst.sale_type AS listing_sale_type
FROM datalake_ebdb_clean.house AS h
LEFT JOIN dw_sale_primary_market.dim_house_development AS dhd
    ON dhd.id_house = h.id
LEFT JOIN datalake_sale_primary_market.listing_sale_type AS lst
    ON lst.id_house = h.id
LEFT JOIN datalake_ebdb_clean.development_typology_unit AS dtu
    ON dtu.id_house = h.id
LEFT JOIN datalake_ebdb_clean.house AS shell
    ON shell.id = h.id
    AND shell.id_development_typology IS NOT NULL
WHERE h.id = 895686210  -- replace with the id_house in question
```

Prefer **`dim_house_development`** alone when you only need empreendimento/tipologia on
any linked house. Use this query when TARS must explain shell vs unit explicitly.

### Query 16 — Pilot houses never visited (supply not yet demonstrated)

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
FROM dw_sale_primary_market.dim_house_development AS dhd
LEFT JOIN visited_houses AS vh
    ON vh.sk_house = dhd.id_house
```

### Query 17 — Incorporadora name by development

DW-first cut at development grain using denormalized `company_name`.

```sql
SELECT
    id_development,
    development_name,
    uuid_company,
    company_name,
    COUNT(DISTINCT id_house) AS n_houses
FROM dw_sale_primary_market.dim_house_development
GROUP BY 1, 2, 3, 4
ORDER BY n_houses DESC
```

## DataHub catalog

- **Data Product:** Published from this Markdown by the repository DataHub metadata workflow.
- **Datasets:** Tables in the Tables section are linked as DataHub assets. The same table may also appear on other Data Products.
- **Golden queries:** The seventeen queries above (Hub Q1–Q10 plus pilot/TARS supplements) are published as DataHub Query entities.
