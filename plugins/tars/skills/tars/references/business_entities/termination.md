# Termination

## Overview

A termination represents the formal process of ending a rental contract at QuintoAndar. It is one of the most complex journeys in the platform, spanning multiple stages and involving several parties (tenant, landlord, and QuintoAndar operations).

The lifecycle typically includes:
1. **Termination request** — the tenant initiates the process (`fact_terminations.ts_termination_request`)
2. **Fee calculation** — early termination fees and discounts are determined (`fact_terminations.fee_final_amount`, `fact_terminations.fee_discount_percentage`)
3. **Exit inspection** — a technical inspection of the property to document its condition (linked via `fact_terminations.sk_exit_inspection`)
4. **Repair analysis** — damages found during inspection go through automatic or manual analysis across stages: AR (Automatic Repair), Review, AC (Analysis of Contestation)
5. **Report review and budget approval** — landlord and tenant review and approve the final report
6. **Mediation** (when needed) — a human mediator helps resolve disputes between parties (`dim_termination.has_mediation_ticket`)
7. **Vacancy and relisting** — the property is vacated and may be relisted for a new rental (`fact_terminations.is_relisting`)
8. **Termination closure** — the process is finalized (`fact_terminations.ts_termination_finished`)

Not all terminations follow every step. Some are canceled before completion, some skip the inspection (opt-out), and some are resolved quickly through early agreements.

## Glossary and Synonyms

- **Rescisão**, **distrato**, **cancelamento de contrato** → `termination`
- **Offboarding** → can be a synonym for `termination` depending on context. In quantitative questions ("how many offboardings happened?"), treat as equivalent to `termination`. In organizational contexts ("the offboarding team is handling this"), it refers to a broader journey that encompasses the termination itself, exit inspection, repair reports, relisting, and other processes — not just the termination.
- **Bandaid** (bandaid automatico, desconto automatico, desconto do bandaid) → The Bandaid product feature: an ML-driven discount system that automatically reduces the tenant's repair cost during offboarding to expedite resolution. ALL bandaids are automatic (product-driven) — there is no manual bandaid. Filter: `has_discount_agreement = TRUE` in `obt_offboarding` to identify terminations where a bandaid was applied. The column `model_discount_type` distinguishes the **application mode**, not whether the bandaid is automatic: `AUTOMATIC_BANDAID` = discount applied instantly without user interaction; `OFFERED_DISCOUNT` = discount offered to the tenant for approval before being applied. Do NOT filter by `model_discount_type` when the user asks about "bandaid" or "bandaid automatico" generically — both values represent the same product feature. For full discount details, use `datalake_inspections.automatic_discounts` (enrich) via `uuid_inspection`.
- **Laudo** (laudo de reparos, repair report) → the repair report produced after an exit inspection. Table: `fact_report_inspections`. See Inspection entity for details.

## Tables

| You need... | Use this table |
|-------------|----------------|
| Termination data (status, fees, dates, flags) | `dw_offboarding.fact_terminations` (`ft`) + `dim_termination` (`dt`) |
| Termination + inspection + repairs + report + mediation + discounts (cross-entity) | `dw_offboarding.obt_offboarding` (`obt`) — everything pre-joined, no manual JOINs needed. Already filters out canceled terminations. Covers: termination status/dates/fees, inspection execution, report access and approval flags by stage (review + budget approval) for both tenant and owner, repair counts by stage, repair costs, mediation, agreement, discounts/bandaid, leadtimes. When unsure about specific columns, search the repo for the SQL that builds this table. |
| Relisting / rerental after termination | `dw_offboarding.fact_house_listing_terminations` (`fhlt`) — **Relisting** (property relisted): `sk_next_house_listing_consolidated <> -1`. **Rerental** (new contract signed): `sk_next_contract <> -1`. Leadtime: `days_termination_to_contract_signed`. These are stages of the same funnel: relisting is the listing event, rerental is the conversion. |
| Enriched termination source data | `datalake_terminator.termination` (enrich — source for `fact_terminations`) |
| Mediation details (squad, resolution) | `datalake_offboarding.mediations` (enrich) |
| NPS score linked to termination | `dw_retention.fact_contract_termination` (`fct`) + `dw_retention.dim_nps_answer` (`dna`) — bridges termination to NPS via `sk_nps_answer_owner` / `sk_nps_answer_tenant`. Enrich alternative: `datalake_offboarding.nps_agg` with `nps_iq`, `nps_pp` per contract. |
| Discount data linked to inspections | `datalake_inspections.automatic_discounts` (enrich — JOIN via `uuid_inspection`) |

**Critical rules:**
- **Three key dates**: `ts_termination_request` (request), `dt_termination` (planned vacancy), `ts_termination_finished` (closure) — don't confuse them
- **Status filter**: `dim_termination.status <> 'CANCELED'` when measuring effective volume
- **Inspection JOINs**: CAST and Dedup rules apply — see Inspection entity for details

## Key Metrics

- Termination volume per month (filter by `ts_termination_request` or `ts_termination_finished`)
- Termination rate by reason (`termination_reason` in `dim_termination`)
- Mediation rate (`has_mediation_ticket` in `dim_termination`)
- Average time from request to vacancy (`leadtime_request_to_vacancy`)
- Terminations with tenant repairs (`has_repairs`)
- Relisting rate (`is_relisting`)
- End-to-end leadtime (`leadtime_total` in `obt_offboarding`)

## Relationships with Other Entities

### Contract (N:1 — many terminations to one contract)

JOIN via `ft.sk_contract` to `dw_rent.dim_contract` (`dc`) or `dw_rent.dim_contract_person`.

### Inspection (1:N — one termination may have multiple inspections)

- Primary exit inspection: `ft.sk_exit_inspection = fi.sk_main_inspection`
- All contract inspections: JOIN via `sk_contract` and filter `inspection_type = 'offboarding'` — apply the Dedup rule (see Inspection entity)
- CAST and Dedup rules apply to `fact_inspection` — see the Inspection entity for details

### NPS (1:N — one termination may have NPS answers from owner and tenant)

- `ft.sk_termination = fct.sk_termination` (from `dw_retention.fact_contract_termination`)
- Then `fct.sk_nps_answer_tenant = dna.sk_nps_answer` or `fct.sk_nps_answer_owner = dna.sk_nps_answer` (from `dw_retention.dim_nps_answer`)
- Filter offboarding NPS: `dna.nps_campaign LIKE '%offboarding%'`

### Repair Request (1:N — one termination may have multiple repairs)

- `ft.sk_contract = rr.sk_contract` (from `dw_inspections.fact_repair_request`) — fans out to repair grain
- `fact_terminations` carries aggregated repair columns per stage: `total_tentant_repair_ar`, `total_tentant_repair_review`, `total_tentant_repair_ac` — prefer these for termination-level analysis
- See the Repairs entity for individual repair details, contestation data, exemptions, and cost analysis

## Dos and Don'ts

**Do:**
- Start from `dw_offboarding.fact_terminations` for termination-centric queries, or `obt_offboarding` for cross-entity data without manual JOINs
- Use `sk_termination` to join `fact_terminations` with `dim_termination`
- Use `sk_contract` for JOINs with contract, repair, and inspection tables
- Filter by `dt.status <> 'CANCELED'` when measuring effective termination volume
- Apply date filters on the termination entity (`ts_termination_request` or `ts_termination_finished`), not on secondary entities
- Filter `has_discount_agreement = TRUE` in `obt_offboarding` for bandaid analysis — this covers all bandaid types. Do NOT add `model_discount_type` filters unless the user explicitly asks to compare instant application (`AUTOMATIC_BANDAID`) vs offered-then-accepted (`OFFERED_DISCOUNT`). For discount details beyond OBT, use `datalake_inspections.automatic_discounts` (enrich) via `uuid_inspection`
- Check `fact_house_listing_terminations` when the analysis involves relisting or rerental

**Don't:**
- Don't confuse `ts_termination_request` (request), `dt_termination` (planned vacancy), and `ts_termination_finished` (closure) — each answers a different question
- Don't treat every recorded termination as effective — always consider the status
- Don't confuse repair columns by stage: `total_tentant_repair_ar` (AR), `total_tentant_repair_review` (Review), `total_tentant_repair_ac` (AC)
- Don't JOIN with `fact_inspection` without applying CAST and Dedup rules — see Inspection entity

## Golden Queries

### Query 1 — Base pattern with descriptive attributes

Terminations with their descriptive attributes (status, category, reason).

```sql
SELECT
    ft.*,
    dt.*
FROM dw_offboarding.fact_terminations AS ft
LEFT JOIN dw_offboarding.dim_termination AS dt
    ON ft.sk_termination = dt.sk_termination
```

### Query 2 — Termination with exit inspection (cross-domain)

Terminations joined with their exit inspections. Dedup and CAST rules applied (see Inspection entity).

```sql
SELECT
    ft.*,
    fi.*,
    ROW_NUMBER() OVER (PARTITION BY fi.sk_contract ORDER BY fi.ts_updated DESC) AS rni
FROM dw_offboarding.fact_terminations AS ft
LEFT JOIN dw_inspections.fact_inspection AS fi
    ON ft.sk_exit_inspection = fi.sk_main_inspection
```

### Query 3 — Using obt_offboarding with contract details

The `obt_offboarding` table already joins terminations with inspections, reports, repairs, mediations, and discounts. It is the best starting point when you need a wide view. Here it is enriched with contract person data to identify the tenant:

```sql
SELECT
    obt.sk_contract,
    obt.sk_termination,
    obt.termination_status,
    obt.termination_reason,
    obt.rent_value,
    obt.fee_final_amount,
    obt.has_repairs,
    obt.has_agreement,
    obt.model_discount_type,
    obt.has_applied_discount,
    obt.inspection_status,
    obt.leadtime_total,
    obt.leadtime_vt,
    obt.leadtime_ar,
    obt.ts_termination_request,
    obt.dt_termination,
    obt.ts_termination_finished,
    dcp.person_name AS tenant_name
FROM dw_offboarding.obt_offboarding AS obt
LEFT JOIN dw_rent.dim_contract_person AS dcp
    ON obt.sk_contract = dcp.sk_contract
    AND dcp.person_type = 'TENANT'
WHERE obt.ts_termination_finished >= DATE '2025-01-01'
```

### Query 4 — Termination with NPS (cross-domain)

Terminations joined with NPS answers. Uses `fact_contract_termination` as a bridge to `dim_nps_answer`.

```sql
SELECT
    ft.sk_termination,
    ft.sk_contract,
    dna_tenant.score AS nps_score_tenant,
    dna_owner.score AS nps_score_owner,
    dna_tenant.nps_campaign
FROM dw_offboarding.fact_terminations AS ft
LEFT JOIN dw_retention.fact_contract_termination AS fct
    ON ft.sk_termination = fct.sk_termination
LEFT JOIN dw_retention.dim_nps_answer AS dna_tenant
    ON fct.sk_nps_answer_tenant = dna_tenant.sk_nps_answer
LEFT JOIN dw_retention.dim_nps_answer AS dna_owner
    ON fct.sk_nps_answer_owner = dna_owner.sk_nps_answer
```
