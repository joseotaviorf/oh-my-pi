# Supply Revamp

> **Status: WIP (work in progress).** This document covers only the first slice of the Rene Descartes Supply Revamp data model — `contact_info`, `intent`, and the application entities `contact_identifier` / `contact_info_identifier`. In the lake today, **only `lead_intent` is ingested**. `contact_info` lives in Rene Descartes PostgreSQL and is **not** loaded to `datalake_rene_descartes_clean`. This doc does **not** replace the production funnel model in [`supply.md`](supply.md) (`dw_growth.obt_supply`, `dw_growth.fact_supply_events`). Do not mix revamp clean tables with legacy funnel metrics until downstream DW/enrich layers exist.

## Ownership

**Data Owner:**
- gabriel.salla@quintoandar.com.br

**Data Steward:**
- gabriel.salla@quintoandar.com.br

## Overview

Supply Revamp is the new Rene Descartes entity model for first-party Supply acquisition. It recenters the funnel on **contacts** (owners who express intent) rather than the legacy `house_lead` grain. Canonical behavior is defined in [backend-services — Rene Descartes entities](https://github.com/quintoandar/backend-services/tree/forno/applications/rene-descartes/docs/business-rules/entities) and [OpenSpec specs](https://github.com/quintoandar/backend-services/tree/forno/applications/rene-descartes/openspec/specs) (`supply-schema-migration`, `supply-jpa-entities`, `shared-lead-contact-identifiers`).

**Canonical table names (application / logical model):**

| Entity | Canonical table | Role |
|--------|-----------------|------|
| Contact info | `contact_info` | Aggregate root — Supply client identity and channels |
| Intent | `intent` | Append-only — one row per capture-form submission |
| Contact identifier | `contact_identifier` | Internal IDR match index (engineering-owned) |
| Contact ↔ identifier link | `contact_info_identifier` | N:M link table (SAL-549 shared identifiers) |


| Canonical | Lake table (`datalake_rene_descartes_clean`) |
|-----------|-----------------------------------------------|
| `contact_info` | `contact_info` |
| `intent` | `lead_intent` |
| `contact_identifier` | not ingested yet |
| `contact_info_identifier` | not ingested yet |

**What is in production in the lake today (this doc only):**

1. **Contact info** — one row per Supply customer (`contact_info` in the lake).
2. **Intent** — one row per capture-form submission (`lead_intent` in the lake); append-only; links to contact via `id_contact`.
3. **Contact identifier** — internal IDR match index in Rene Descartes PostgreSQL (`contact_identifier`); **not yet ingested to the lake**. Since SAL-549, contacts attach via `contact_info_identifier` (N:M) — identifiers can be shared across contacts.

**Not documented here (planned revamp entities, not in prod lake):** `lead_attribution`, `opportunity`, `supply_activities`, `supply_rejection`, and any DW/obt built on the full revamp model. For end-to-end funnel, channel attribution, and conversions, continue using [`supply.md`](supply.md).

## Glossary and Synonyms

- **Supply Revamp**, **novo modelo de captação**, **modelo Rene revamp** → Rene Descartes entity model (contact-centric); canonical tables `contact_info`, `intent` (lake: `contact_info`, `lead_intent`)
- **Intent**, **intenção**, **demonstração de intenção** → owner submitted a capture form; row in `intent` (`id_intent`; lake: `lead_intent`)
- **Contact**, **cliente Supply**, **contato** → unified Supply customer in `contact_info` (`id_contact`; lake: `contact_info`)
- **Identity Resolution**, **IDR**, **resolução de identidade** → deterministic merge of incoming leads onto one `id_contact` via strong keys (`person_id`, phone, email, `meta_username`); match index is `contact_identifier` + `contact_info_identifier` in the app (not in lake)
- **Strong key** → `mobile_phone_number`, `email`, or `meta_username` — used for deduplication; normalized forms live in `contact_identifier.normalized_value` (app only)
- **Shared identifier (SAL-549)** → strong key already linked to another contact is **merged** into `contact_info` and linked via `contact_info_identifier` (not dropped); IDR resolves to the contact with the **strongest bond**
- **Supply source**, **fonte de captação** → `intent.supply_source`: `1P`, `3P`, or `CIQ`
- **Origin**, **origem do produto** → `intent.origin` — product surface (e.g. `OwnerPWA`, `Inbound`, `RENT Calculator`); constrains allowed `supply_source`
- **Detailed route**, **rota detalhada** → `intent.detailed_route` — sub-navigation (`header`, `is_owner_button`, `magic_carpet`; empty for `Inbound` / `Capta Ai`)
- **Legacy bridge**, **`house_lead_id`** → `intent.id_house_lead` — temporary link to legacy `house_lead` / `id_lead_ebdb`; `NULL` for new-flow intents
- **Contact channels (JSON column)** → `contact_info.channels` — canonical display list of channels (`type` + `value`); **not** scanned for IDR matching (matching uses `contact_identifier`)
- **Linked devices** → `contact_info.linked_devices` — flat JSON array of `device_id` strings for CDP event matching; not an IDR key

### `origin` → `supply_source` (allowed pairs)

| `origin` | `supply_source` |
|----------|-----------------|
| `OwnerPWA`, `Referral`, `Inbound`, `Capta Ai`, `RENT Calculator`, `SALE Calculator` | `1P` |
| `3P` | `3P` |
| `CIQ` | `CIQ` |

### `contact_info.channels` JSON — `type` values

| `type` | Role |
|--------|------|
| `mobile_phone_number` | Strong key (display format in JSON; normalized form in `contact_identifier`) |
| `landline_phone_number` | Stored in JSON; not a match key |
| `email` | Strong key |
| `meta_username` | Strong key (WhatsApp username) |
| `device_id` | Raw signal in JSON; never a match key |

## Tables

| You need... | Use this table |
|-------------|----------------|
| Supply customer identity, contact channels, Person link | `datalake_rene_descartes_clean.contact_info` (`ci`) — one row per customer (`id_contact`); partition on `year`/`month`/`day` from `ts_updated`; z-ordered by `id_contact` |
| Intent volume, product origin, supply source, A/B tags | `datalake_rene_descartes_clean.lead_intent` (`li`) — canonical `intent`; one row per intent (`id_intent`); append-only (`ts_created` only); partition on `year`/`month`/`day` from `ts_created`; z-ordered by `id_contact` |
| Join intents to their owning contact | `li.id_contact = ci.id_contact` |
| Bridge a revamp intent to legacy funnel (when populated) | `li.id_house_lead` ↔ legacy `id_lead_ebdb` / `obt_supply.sk_lead` — only when `id_house_lead IS NOT NULL` |
| Internal IDR match index (application only — **not in lake**) | `contact_identifier` in Rene Descartes PostgreSQL — one row per normalized strong key; contacts link via `contact_info_identifier` (N:M, SAL-549) |
| Internal contact ↔ identifier links (application only — **not in lake**) | `contact_info_identifier` — `UNIQUE (contact_id, identifier_id)` |

**Critical rules:**

- **Scope gate:** For funnel steps (lead → prospect → qualified → opportunity → first listing), channel reporting (`company_report_origin`), and Isaias metrics, use [`supply.md`](supply.md) and `dw_growth.obt_supply` — not this document.
- **Canonical vs lake names:** Application `contact_info` is `datalake_rene_descartes_clean.contact_info` in Trino. Application `intent` is still `lead_intent` in the lake — use that name in SQL.
- **Lake availability:** Only `contact_info` and `lead_intent` exist in `datalake_rene_descartes_clean` today. `contact_identifier` and `contact_info_identifier` are application-internal.
- **Partition filters:** `contact_info` — filter `year`, `month`, `day` on `ts_updated`. `lead_intent` — filter on `ts_created`.
- **PII:** `ci.channels` value fields contain personal data. Follow org PII policy.
- **`id_house_lead` semantics:** Non-null only for legacy `HouseLead` projection rows. New-flow intents have `id_house_lead IS NULL`.
- **Intent without contact:** If contact creation was skipped (no valid channels after phone validation, BR-LCI-013 / BR-LI-011), the app writes **no** `contact_info` and **no** `intent` for that event.
- **`person_id` / `id_person`:** Set when Person service resolves the contact; unique per contact when present; not cleared once set. `person_id` is matched on the `contact_info` row directly — not stored in `contact_identifier`.
- **SAL-549 IDR:** `contact_identifier` has no `contact_id` column; links live in `contact_info_identifier`. Shared identifiers resolve to the strongest bond (mobile > email; more links; latest link `ts_created`).
- **DataHub CI:** concrete `schema.table` names only in this section — no wildcards.

## Key Metrics

No official metric entity exists yet for this WIP slice. Use [`supply.md`](supply.md) for funnel, conversion, and Isaias numbers. Exploratory measures from the lake:

- **Intent volume:** `COUNT(*)` (or `COUNT(li.id_intent)`) on `datalake_rene_descartes_clean.lead_intent`, partitioned on `ts_created`.
- **Intent volume by origin and supply source:** same count grouped by `li.origin` and `li.supply_source` (allowed pairs in the glossary).
- **Intents per contact:** `COUNT(li.id_intent)` grouped by `li.id_contact` — contact profile is not in the lake.
- **Legacy-bridged intents:** count or list rows where `li.id_house_lead IS NOT NULL`.

## Relationships with Other Entities

### Supply (legacy funnel) — partial bridge only

- When `intent.id_house_lead` (`lead_intent.id_house_lead` in lake) is not null, bridge to legacy lead grain: `CAST(li.id_house_lead AS BIGINT) = obt.sk_lead`. See [`supply.md`](supply.md).
- New-flow intents (`id_house_lead IS NULL`) have **no** join to `obt_supply` today.

### Person (N:1 when resolved)

- `ci.id_person` → Person service UUID. Join Person clean/DW tables — do not rely on duplicated PII in `channels` JSON when `id_person` is set.

## Related Metric Entities

- None — WIP revamp slice (`contact_info`, `intent`) only; no official metric-entity golden queries yet. Use [`supply.md`](supply.md) for funnel and conversion metrics.

## Dos and Don'ts

**Do:**

- Use this document only for **contact** and **intent** questions on the revamp model (volume by `origin`/`supply_source`, contact enrichment, IDR-related contact grain).
- Refer to canonical names (`contact_info`, `intent`) in business language; in Trino use `contact_info` and `lead_intent`.
- Filter `contact_info` partitions on `ts_updated` and `lead_intent` partitions on `ts_created`.
- Filter `id_contact` when querying a known customer — both lake tables are z-ordered on that key.
- Use `intent.origin` and `intent.supply_source` together — each origin constrains allowed `supply_source` values.
- For funnel, conversion, and channel dashboards, use [`supply.md`](supply.md) and `dw_growth.obt_supply`.

**Don't:**

- Don't use revamp clean tables as a substitute for `obt_supply` or `fact_supply_events` — the revamp DW layer is not in production.
- Don't assume every legacy lead has an `intent` row — only leads projected through the new flow (or legacy bridge with `id_house_lead`) appear here.
- Don't scan `channels` JSON for IDR deduplication — matching uses `contact_identifier` + `contact_info_identifier` in the app.
- Don't query `contact_identifier` or `contact_info_identifier` in Trino — not in the lake yet.
- Don't count `id_house_lead IS NULL` intents as join failures to legacy supply — expected for new-flow intents.
- Don't assume `contact_identifier.contact_id` exists — removed in SAL-549; use the link table instead.

## Golden Queries

### Query 1 — Daily intent volume by origin and supply source

Counts distinct intents (capture-form submissions) by product origin and funnel class. Lake table `lead_intent` = canonical `intent`.

```sql
SELECT
    li.origin,
    li.supply_source,
    DATE(li.ts_created) AS dt_intent,
    COUNT(*) AS intent_count
FROM
    datalake_rene_descartes_clean.lead_intent AS li
WHERE
    li.year = 2026
    AND li.month >= 1
    AND li.ts_created >= DATE '2026-01-01'
GROUP BY
    1, 2, 3
ORDER BY
    3, 4 DESC
```

### Query 2 — Intent counts and latest origin/source per contact id

Contact grain (`datalake_rene_descartes_clean.contact_info`) with intent counts and latest origin/source.

```sql
SELECT
    li.id_contact,
    COUNT(li.id_intent) AS intent_count,
    MAX(li.ts_created) AS ts_last_intent,
    MAX_BY(li.origin, li.ts_created) AS last_origin,
    MAX_BY(li.supply_source, li.ts_created) AS last_supply_source
FROM
    datalake_rene_descartes_clean.contact_info AS ci
LEFT JOIN
    datalake_rene_descartes_clean.lead_intent AS li
        ON li.id_contact = ci.id_contact
WHERE
    ci.year = 2026
    AND ci.month >= 1
    AND ci.ts_created >= DATE '2026-01-01'
GROUP BY
    1
```

### Query 3 — Legacy bridge: intents linked to legacy lead id

Rows where the revamp intent carries a legacy `house_lead_id` for cross-check with `obt_supply`.

```sql
SELECT
    li.id_intent,
    li.id_contact,
    li.id_house_lead,
    li.origin,
    li.supply_source,
    li.ts_created
FROM
    datalake_rene_descartes_clean.lead_intent AS li
WHERE
    li.id_house_lead IS NOT NULL
    AND li.year = 2026
    AND li.month >= 1
    AND li.ts_created >= DATE '2026-01-01'
```

## DataHub catalog

> Added automatically by CI after publish — do not fill in manually.
