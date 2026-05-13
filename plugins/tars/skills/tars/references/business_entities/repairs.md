# Repairs

## Overview

A repair is a request to fix, clean, remove, or replace an item in a rental property. Repairs happen in two distinct contexts: **offboarding repairs** arise from the exit inspection (vistoria de saída) when damages or differences are found, and **ongoing repairs** are maintenance issues reported by the tenant during the active rental contract. Entry inspections (vistoria de entrada) do not generate repairs — they only document item conditions as a baseline for future comparison.

**Offboarding repairs** follow this lifecycle:
1. **Identification** — during the exit inspection, the inspector (or an automated system) identifies damages and creates repair requests (`fact_repair_request.ts_created`)
2. **Repair Analysis (AR)** — repairs are assessed, costs estimated, and responsibility assigned (`dim_repair_request.cost`, `dim_repair_request.responsibility`)
3. **Review (1st review)** — tenant and owner review the repair list; either party may contest items (`fact_repair_request.has_tenant_contestation`)
4. **Contestation Analysis (AC)** — if contested, a team analyzes the dispute (`fact_contestation`)
5. **Budget Approval (2nd review)** — final budget presented to both parties (`fact_repair_request.has_tenant_budget_approval_contestation`, `has_owner_budget_approval_contestation`)
6. **Exemption / Resolution** — some repairs may be exempted by the owner or an analyst (`dim_repair_exempted.is_exempted`); the report is finalized

**Ongoing repairs** follow a Zendesk-ticket-based flow:
1. **Opening** — tenant reports a maintenance issue via app or web (`fact_ongoing_repairs.ts_created_local`)
2. **Triage** — ticket is classified by criticality and repair type (`dim_ongoing_repairs.criticality`, `repair_class`)
3. **Service provider assignment** — a provider is chosen (tenant's choice, owner's choice, or compulsory) (`fact_ongoing_repairs.ts_ps_iq`, `ts_ps_pp`, `ts_compulsory`)
4. **Execution** — repair is performed; owner approval may be required (`dim_ongoing_repairs.owner_approval`)
5. **Resolution** — ticket is solved (`fact_ongoing_repairs.ts_solved_local`)

Not all repairs follow every step. Offboarding repairs may be exempted early, agreed upon without contestation, or absorbed by QuintoAndar. Ongoing repairs may be resolved via self-service, closed by merge, or ended without tenant contact.

## Glossary and Synonyms

- **Reparo**, **solicitação de reparo** → `repair request`. Two distinct universes: offboarding (from inspection) vs ongoing (from Zendesk ticket)
- **Reparo de saída**, **reparo de offboarding** → offboarding repair. Tables: `dw_inspections.fact_repair_request` + `dim_repair_request`
- **Reparo ongoing**, **reparo de manutenção** → ongoing repair during active contract. Tables: `dw_repairs.fact_ongoing_repairs` + `dim_ongoing_repairs`
- **AR** (análise de reparos) → Automatic Repair Analysis stage of the offboarding inspection report
- **AC** (análise de contestação) → Contestation Analysis stage, when tenant disputes repair items
- **Contestação** → formal dispute of a repair item by tenant or owner. Table: `dw_inspections.fact_contestation`
- **Isenção** (exemption) → owner or analyst exempts a repair, removing it from the tenant's responsibility. Table: `dw_inspections.dim_repair_exempted`
- **Benfeitoria** → improvement made by the tenant; not a defect. In ongoing repairs: `dim_ongoing_repairs.criticality = 'Benfeitoria'`
- **PS IQ** (prestador do inquilino) → service provider chosen by the tenant (`fact_ongoing_repairs.ts_ps_iq`)
- **PS PP** (prestador do proprietário) → service provider chosen by the owner (`fact_ongoing_repairs.ts_ps_pp`)
- **Compulsória** → compulsory repair execution ordered by QuintoAndar (`fact_ongoing_repairs.ts_compulsory`)
- **FUP** (follow-up) → tenant negotiation follow-up in ongoing repairs (`dim_ongoing_repairs.status_fup_iq`)
- **FRT** (Full Repair Time) → days from ticket creation to resolution (`fact_ongoing_repairs.frt`)

## Tables

| You need... | Use this table |
|-------------|----------------|
| Offboarding repair status, contestation flags, cost absorption, media | `dw_inspections.fact_repair_request` (`rr`) — one row per repair request from exit inspections |
| Offboarding repair descriptive attributes (type, cost, item, room, responsibility) | `dw_inspections.dim_repair_request` (`drr`) — deduped, one row per repair request |
| Contestation details (who contested, at which stage, cost) | `dw_inspections.fact_contestation` (`fc`) — one row per contestation event |
| Exemption history (who exempted, responsibility reassignment) | `dw_inspections.dim_repair_exempted` (`dre`) — latest exemption per repair request |
| Ongoing repair ticket facts (SLAs, timestamps, operational flags) | `dw_repairs.fact_ongoing_repairs` (`for`) — one row per Zendesk ticket |
| Ongoing repair descriptive attributes (classification, criticality, execution flow) | `dw_repairs.dim_ongoing_repairs` (`dor`) — one row per Zendesk ticket |
| Full offboarding picture (termination + inspection + repairs + report) | `dw_offboarding.obt_offboarding` (`obt`) — pre-joined, no manual JOINs. See Termination entity |
| Per-stage repair cost over time (temporal) | `datalake_inspection_services_clean.repair_request_history` (clean) — tracks `cost` per repair with `origin` indicating the stage. Only source for per-stage monetary values |
| Detailed offboarding repair data at finer granularity | `datalake_inspections.repair_request` (enrich) — upstream of DW tables |

**Critical rules:**
- **Two separate universes**: offboarding repairs (`dw_inspections`) and ongoing repairs (`dw_repairs`) have **different schemas, ID spaces, and data models**. Never mix them in the same query without explicitly labeling the context.
- **CAST rule** (offboarding): `fact_repair_request.sk_inspection` JOINs with `fact_inspection.sk_inspection` — since `sk_inspection` in `fact_inspection` is VARCHAR, apply `CAST` on the other side: `fi.sk_inspection = CAST(rr.sk_inspection AS VARCHAR)`
- **Dedup rule** (offboarding): `dim_repair_request` is already deduped by `ROW_NUMBER() OVER (PARTITION BY id_repair_request ORDER BY ts_updated DESC)`. No additional dedup needed.
- **Dedup rule** (ongoing): `fact_ongoing_repairs` and `dim_ongoing_repairs` are deduped by `ROW_NUMBER() OVER (PARTITION BY id_ticket ORDER BY ts_updated DESC)`. No additional dedup needed.
- **Grain change**: joining `fact_inspection` → `fact_repair_request` fans out from inspection grain to repair grain (1:N). Always aggregate back when the desired output grain is per inspection.

## Key Metrics

- Repair volume per inspection — count of `fact_repair_request` rows per `sk_inspection`
- Repair volume per termination — use `fact_terminations.total_tentant_repair_ar` / `_review` / `_ac` for pre-aggregated counts by stage
- Total repair cost per inspection — `SUM(drr.cost)` from `dim_repair_request` joined to `fact_repair_request`
- Final tenant repair cost per termination — `obt_offboarding.final_tenant_inspection_cost`
- Contestation rate — percentage of repairs with `has_tenant_contestation = TRUE` in `fact_repair_request`
- Exemption rate — percentage of repairs with `is_exempted = TRUE` in `fact_repair_request` or `dim_repair_exempted`
- Cost absorption distribution — `is_cost_absorbed_by_tenant` / `_owner` / `_company` in `fact_repair_request`
- Agreement rate — `obt_offboarding.has_agreement` (combines early, late, and discount agreements)
- Ongoing repair FRT (Full Repair Time) — `fact_ongoing_repairs.frt` (days from creation to solved)
- Ongoing repair first reply time — `fact_ongoing_repairs.days_to_first_reply` or `ldt_fr_minutes`
- Ongoing repair CSAT — `fact_ongoing_repairs.csat_score`
- Ongoing repair contestation rate — `fact_ongoing_repairs.is_contestation`

## Relationships with Other Entities

### Inspection (N:1 — many repairs belong to one inspection)

- `rr.sk_inspection`: links offboarding repairs to the inspection
- `fi.sk_inspection = CAST(rr.sk_inspection AS VARCHAR)` (CAST rule applies)
- One inspection can have zero to many repairs; aggregate when output grain is per inspection
- See the Inspection entity for the full inspection lifecycle and report data

### Termination (N:1 — offboarding repairs belong to one termination via inspection)

- Indirect link: `fact_repair_request` → `fact_inspection` → `fact_terminations` (via `fi.sk_main_inspection = ft.sk_exit_inspection`)
- Direct at repair-request level: `rr.sk_contract = ft.sk_contract`
- Pre-aggregated repair counts on `fact_terminations`: `total_tentant_repair_ar`, `total_tentant_repair_review`, `total_tentant_repair_ac`
- For the full pre-joined view: use `obt_offboarding`

### Contract (N:1 — many repairs to one contract)

- Offboarding: `rr.sk_contract` → `dw_rent.dim_contract.sk_contract`
- Ongoing: `for.sk_contract` → `dw_rent.dim_contract.sk_contract`

### Contestation (1:N — one repair may have multiple contestations)

- `fc.sk_repair_request = rr.sk_repair_request` (from `fact_contestation`)
- Or via `rr.sk_contestation = fc.sk_contestation` for the primary contestation
- `fact_contestation` distinguishes tenant vs owner and review vs budget approval stages

### House (N:1 — via inspection or contract)

- Offboarding: through `fact_inspection.sk_house`
- Ongoing: through `dw_rent.dim_contract.sk_house` via `sk_contract`

## Dos and Don'ts

**Do:**
- Always identify which repair universe you're querying: offboarding (`dw_inspections`) or ongoing (`dw_repairs`) — they are separate data models
- Apply the CAST rule when joining `fact_repair_request.sk_inspection` to `fact_inspection.sk_inspection`: `fi.sk_inspection = CAST(rr.sk_inspection AS VARCHAR)`
- Use `dim_repair_request.cost` for the estimated cost of individual offboarding repairs
- Use `obt_offboarding.final_tenant_inspection_cost` for the final aggregated cost per termination
- Use `datalake_inspection_services_clean.repair_request_history` when you need cost at a specific stage (e.g., AR, review) — it's the only source with temporal per-stage monetary values
- Use `fact_terminations.total_tentant_repair_ar` / `_review` / `_ac` for pre-aggregated repair counts by stage at termination level
- Aggregate `fact_repair_request` results when the desired output grain is per inspection or per termination (the JOIN fans out to repair grain)
- For ongoing repairs, use `dim_ongoing_repairs.criticality` for urgency classification and `repair_class` / `repair_type` / `repair_detailed` for the three-level repair categorization

**Don't:**
- Don't mix offboarding and ongoing repair tables in the same query without clearly labeling the context — they have different schemas, ID spaces, and semantics
- Don't confuse repair **counts** per stage (`total_tentant_repair_ar`, `_review`, `_ac` on `fact_terminations`) with monetary **costs** — these are counts, not currency values
- Don't assume `dim_repair_request.cost` is the final cost — it's the estimated cost at the time of analysis; the final cost after exemptions and contestations may differ
- Don't JOIN `fact_repair_request` to `fact_inspection` without applying the CAST rule — `sk_inspection` types differ
- Don't forget that ongoing repair timestamps in `fact_ongoing_repairs` are adjusted by `-3 hours` from UTC to local São Paulo time — columns like `ts_created_local`, `ts_solved_local` are already localized
- Don't confuse `is_contestation` in ongoing repairs (tag-derived boolean on Zendesk ticket) with `fact_contestation` in offboarding repairs (formal contestation table with cost and stage data)

## Golden Queries

### Query 1 — Offboarding repairs with descriptive attributes

Individual repair requests from exit inspections with type, cost, item, and responsibility. Joins fact and dimension tables.

```sql
SELECT
    rr.sk_repair_request,
    rr.sk_inspection,
    rr.sk_contract,
    drr.type,
    drr.cost,
    drr.item_name,
    drr.room_name,
    drr.responsibility,
    rr.has_tenant_contestation,
    rr.is_exempted,
    rr.is_cost_absorbed_by_tenant,
    rr.is_cost_absorbed_by_owner,
    rr.is_cost_absorbed_by_company,
    rr.ts_created
FROM dw_inspections.fact_repair_request AS rr
LEFT JOIN dw_inspections.dim_repair_request AS drr
    ON rr.sk_repair_request = drr.id_repair_request
```

### Query 2 — Offboarding repairs linked to inspection and termination

Repairs in the context of exit inspections and terminations. Applies CAST and Dedup rules for `fact_inspection`.

```sql
SELECT sub.*
FROM (
    SELECT
        ft.sk_termination,
        fi.sk_inspection,
        rr.sk_repair_request,
        drr.type,
        drr.cost,
        drr.item_name,
        drr.responsibility,
        rr.has_tenant_contestation,
        rr.is_exempted,
        ROW_NUMBER() OVER (PARTITION BY fi.sk_contract ORDER BY fi.ts_updated DESC) AS rni
    FROM dw_offboarding.fact_terminations AS ft
    LEFT JOIN dw_inspections.fact_inspection AS fi
        ON ft.sk_exit_inspection = fi.sk_main_inspection
    LEFT JOIN dw_inspections.dim_inspection AS di
        ON fi.sk_inspection = di.sk_inspection
    LEFT JOIN dw_inspections.fact_repair_request AS rr
        ON fi.sk_inspection = CAST(rr.sk_inspection AS VARCHAR)
    LEFT JOIN dw_inspections.dim_repair_request AS drr
        ON rr.sk_repair_request = drr.id_repair_request
    WHERE di.inspection_type = 'offboarding'
) AS sub
WHERE sub.rni = 1
```

### Query 3 — Ongoing repair tickets with classification

Ongoing repair tickets with their three-level classification, criticality, and key SLA metrics.

```sql
SELECT
    f.sk_ticket,
    f.sk_request,
    f.sk_contract,
    d.repair_class,
    d.repair_type,
    d.repair_detailed,
    d.criticality,
    d.execution_flow,
    d.owner_approval,
    f.frt,
    f.days_to_first_reply,
    f.csat_score,
    f.is_contestation,
    f.is_reflux,
    f.is_ongoing,
    f.ts_created_local,
    f.ts_solved_local
FROM dw_repairs.fact_ongoing_repairs AS f
LEFT JOIN dw_repairs.dim_ongoing_repairs AS d
    ON f.sk_ticket = d.sk_ticket
```

### Query 4 — Monthly repair cost and agreement summary using OBT

Monthly evolution of repair volume, average cost, and agreement rate using `obt_offboarding` — no manual JOINs needed.

```sql
SELECT
    DATE_TRUNC('month', obt.ts_termination_finished) AS month_finished,
    COUNT(*) AS total_terminations,
    SUM(CASE WHEN obt.has_repairs THEN 1 ELSE 0 END) AS with_repairs,
    AVG(obt.final_tenant_inspection_cost) AS avg_repair_cost,
    SUM(CASE WHEN obt.has_agreement THEN 1 ELSE 0 END) AS with_agreement,
    CAST(SUM(CASE WHEN obt.has_agreement THEN 1 ELSE 0 END) AS DOUBLE)
        / NULLIF(SUM(CASE WHEN obt.has_repairs THEN 1 ELSE 0 END), 0) AS agreement_rate
FROM dw_offboarding.obt_offboarding AS obt
WHERE obt.ts_termination_finished >= DATE '2025-01-01'
    AND obt.sk_inspection IS NOT NULL
GROUP BY DATE_TRUNC('month', obt.ts_termination_finished)
ORDER BY month_finished DESC
```
