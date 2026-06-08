# Inspection

## Overview

An inspection is a technical assessment of a property's condition performed at key moments of the rental lifecycle. Inspections are critical for documenting the state of the property, preventing disputes, and identifying damages and responsibilities.

There are two types, determined by the `inspection_type` column in `dim_inspection`:

| Type | `inspection_type` | When it happens |
|------|-------------------|-----------------|
| Entry inspection | `onboarding` | At the start of a rental contract |
| Exit inspection | `offboarding` | At the end of a rental contract (linked to a termination) |

The lifecycle of an exit inspection typically follows these stages:
1. **Scheduling** — an appointment is created for the inspection (`fact_inspection.ts_booking_created`)
2. **Execution** — the inspector visits the property and documents its condition (`fact_inspection.ts_inspected`)
3. **Repair analysis (AR)** — damages are identified and repair requests are generated via the **Kirk AI system** (automatic laudo creation) or by a human editing team (manual). A separate, older **tag-based identification flow** also exists, tracked by `ts_automatic_repair_processing`: it drafts repairs from inspector tags, predates Kirk, and is **unrelated to Kirk** (and to automatic repair pricing). Manual editing is tracked by `ts_sent_to_inspection_editing`; these timestamps are **not mutually exclusive**. The AR stage start is `fact_report_inspections.ts_sent_to_repair_analysis`.
4. **Owner and tenant review (1st review)** — both parties see the report for the first time and may agree or contest items. Each party has separate access and approval tracking: `has_*_access_review` (opened the link) vs `has_*_approved_review` (clicked approve).
5. **Contestation analysis (AC)** — if the tenant contests, a dedicated team analyzes the dispute (`fact_report_inspections.ts_sent_to_contestation_analysis`)
6. **Budget approval (2nd review)** — after contestation (if any), a final budget is presented to both parties. Same access/approval pattern: `has_*_access_budget_approval` vs `has_*_approved_budget_approval`.
7. **Report closure** — the report is finalized. `has_agreement` is a composite flag: TRUE when early agreement, late agreement (both approved budget), or discount agreement occurred.

Not all inspections go through every stage. Entry inspections (onboarding) are simpler. Some exit inspections end with early agreements, skipping contestation and budget approval.

**Important distinction**: "Inspection" (vistoria) is a technical property assessment. "Visit" (visita) is when a prospective tenant views the property before renting. They are completely different entities.

## Glossary and Synonyms

- **Vistoria**, **inspeção** → `inspection`
- **Vistoria de entrada** → `inspection` with `inspection_type = 'onboarding'`
- **Vistoria de saída** → `inspection` with `inspection_type = 'offboarding'`
- **AR** (analise de reparos, analise automatica) → Automatic Repair Analysis stage. Columns with `_ar` suffix.
- **AC** (analise de contestacao) → Contestation Analysis stage. Columns with `_ac` suffix.
- **VT** (vistoria tecnica) → the technical inspection execution moment.
- **Laudo** (laudo de reparos, repair report) → the repair report. Table: `fact_report_inspections`.
- **Kirk** → QuintoAndar's AI project for automating the repair laudo. Today Kirk automatically identifies repair requests from inspection photos to **create the laudo**; automatic repair pricing is **not yet part of what Kirk does in production** — it is an upcoming capability of the same project, currently running as a separate test (see below). So, for now, treat "Kirk" as laudo creation only. Synonyms: IA de reparos, análise automática de reparos, fluxo automático do laudo, fluxo automático de criação do laudo.
- **Fluxo automático do laudo / laudo automático** → inspection where Kirk successfully generated repair requests.
- **Grupo controle (Kirk)** → inspection that was eligible for Kirk processing but deliberately excluded for A/B comparison.
- **Wave (Kirk)** → rollout phase of Kirk. Values: `'Shadow Mode'`, `'Wave 1'`, `'Wave 2'`, `'Wave 3'`, `'Wave 4'`.
- **Precificação automática de reparos / automatic repair pricing** → automatically prices the repairs in the laudo. Conceptually part of the **same Kirk project** — it is a test/pilot of what Kirk will eventually cover; for now Kirk only **creates** the laudo and pricing is not included in production. The two are separate **only in the data** (different sources): pricing is tracked via the `automatic-repair-pricing` annotation (rollout 2026-05-18; values `success` / `failed`), not exposed as its own column yet — it underlies `obt_offboarding.no_human_ar`.
- **AR sem intervenção humana / no human AR** → `obt_offboarding.no_human_ar`. Boolean: TRUE when the repair analysis required no human intervention.
- **Fluxo de identificação por tags (legado)** → older automatic flow that drafts repair requests from inspector tags (`ts_automatic_repair_processing`, `has_automatically_identified`). Predates Kirk and is unrelated to it and to automatic repair pricing.

## Tables

| You need... | Use this table |
|-------------|----------------|
| Inspection data with report and basic attributes | `dw_inspections.fact_inspection` (`fi`) + `dim_inspection` (`di`) + `fact_report_inspections` (`fri`) |
| Individual repair requests per inspection | `dw_inspections.fact_repair_request` (`rr`) — changes grain to repair level, aggregate when needed |
| Descriptive attributes for repairs (type, category) | `dw_inspections.dim_repair_request` (`drr`) |
| Contestation details when tenant disputes repair items | `dw_inspections.fact_contestation` |
| Scheduling data and appointment history | `dw_inspections.fact_appointments` |
| Full offboarding picture (termination + inspection + repairs + report + mediation) | `dw_offboarding.obt_offboarding` (`obt`) — pre-joined, no manual JOINs. Includes report access and approval flags by stage for both tenant and owner. See Termination entity for full domain coverage. When unsure about specific columns, search the repo for the SQL that builds this table. |
| Deep dive into repair details, contestations, media | `datalake_inspections.repair_request` (enrich — finer granularity than DW) |
| Reviewer approval data per party | `datalake_inspections.reviewer` (enrich) |
| Automatic discount details | `datalake_inspections.automatic_discounts` (enrich) — JOIN via `fi.sk_client_side = ad.uuid_inspection` |
| Repair cost at a specific stage (temporal) | `datalake_inspection_services_clean.repair_request_history` (clean) — tracks `cost` per repair over time with `origin` indicating the stage. Only source for per-stage monetary values. |
| Assessment data | `dw_inspections.dim_assessment` — JOIN via `fi.sk_assessment` |
| Kirk AI flow flags (automatic laudo creation, control group, wave) — **preferred for exit inspections** | `dw_offboarding.obt_offboarding` — already pre-joined. Columns: `is_automated_ar` (boolean, already cast — Kirk succeeded), `automation_group` (varchar — `TRY_CAST AS BOOLEAN` to filter control group), `no_human_ar` (boolean — repair analysis required no human intervention). Use when the analysis is scoped to exit inspections tied to a termination (the most common case). |
| Kirk AI flow flags — **when obt is not appropriate** (all exit inspections, not just terminated ones) | `dw_inspections.dim_inspection` (DW) — JOIN already needed for `inspection_type` filter. Columns: `repair_request_ai_flow` (varchar bool), `ai_repair_analysis_control_group` (varchar bool), `ai_repair_analysis_wave_name`, `ai_processing_failure_reason`. Use `TRY_CAST(col AS BOOLEAN) = TRUE`. Lineage: `datalake_inspections.inspection_booking`. |

**Critical rules:**
- **CAST rule**: `fact_inspection.sk_inspection` is **VARCHAR** — always apply `CAST(... AS VARCHAR)` on the opposite side of JOINs: `fi.sk_inspection = CAST(other.sk_inspection AS VARCHAR)`
- **Dedup rule**: `fact_inspection` may have duplicates per contract — always apply `ROW_NUMBER() OVER(PARTITION BY fi.sk_contract ORDER BY fi.ts_updated DESC) AS rni` and filter `WHERE rni = 1`
- Always filter by `dim_inspection.inspection_type` (`onboarding` / `offboarding`) when the query starts from inspections
- **Kirk boolean rule**: In `obt_offboarding`, `is_automated_ar` is already a proper `boolean` — use directly. When reading from `dim_inspection` directly, `repair_request_ai_flow` and `ai_repair_analysis_control_group` are stored as `varchar` in Trino — always use `TRY_CAST(col AS BOOLEAN) = TRUE`, never `col = TRUE`. The column `automation_group` in `obt_offboarding` is also varchar — apply `TRY_CAST` there too.


## Key Metrics

Most inspection-related metrics are anchored to the **Termination** entity, not to the inspection itself. This is because stakeholders typically ask "what happened during the offboarding journey?" rather than "what happened in the inspection?". As a result, the main metrics use `fact_terminations` or `obt_offboarding` as the starting point and bring inspection data via JOINs:

**Termination-anchored metrics (most common):**
- Rate of terminations with tenant repairs (`fact_terminations.has_repairs`)
- Rate of terminations with repairs and agreement between parties (`obt_offboarding.has_agreement`)
- Rate of terminations with exit inspection opt-out / exempt (`fact_terminations.is_exit_inspection_opt_out`)
- Rate of terminations with repairs requiring mediation (`dim_termination.has_mediation_ticket`)
- Average repair cost per termination (`obt_offboarding.final_tenant_inspection_cost`)
- Leadtime from termination request to inspection execution (`obt_offboarding.leadtime_vt`)
- Leadtime for repair analysis (`obt_offboarding.leadtime_ar`)

**Inspection-only metrics (not tied to termination):**
- Report access rate — percentage of inspections where landlord and/or tenant accessed the report (`fact_report_inspections.has_tenant_access_review`, `fact_report_inspections.has_owner_access_review`)
- Inspection volume per month (filter by `inspection_type` and `status`)
- SLA compliance: time between scheduling and execution (`fact_inspection.ldt_hours_execution`, `fact_inspection.is_sla_execution`)

**Kirk / automatic laudo metrics:**
- Kirk adoption rate — `COUNT_IF(is_automated_ar) / COUNT(*)` from `dw_offboarding.obt_offboarding` 
- Agreement rate by laudo flow type — `COUNT_IF(has_agreement) / COUNT(*)` per `fluxo_laudo` group from `obt_offboarding`. Use `has_agreement` as the primary signal (combines early, late, and discount agreements). See Golden Query 4 for the full breakdown.
- No-human AR rate — `COUNT_IF(no_human_ar) / COUNT(*)` from `dw_offboarding.obt_offboarding`. Share of terminations whose repair analysis required no human intervention (no tenant AR repairs, or Kirk repairs with successful automatic pricing).

## Relationships with Other Entities

### Contract (N:1 — many inspections to one contract)

JOIN via `fi.sk_contract` to `dw_rent.dim_contract` (`dc`) or `dw_rent.dim_contract_person`.

### Termination (N:1 — an exit inspection belongs to one termination)

- `fi.sk_main_inspection = ft.sk_exit_inspection` (from `dw_offboarding.fact_terminations`)
- See the Termination entity for the reverse JOIN perspective

### Repair Request (1:N — one inspection may have multiple repairs)

- `fi.sk_inspection = CAST(rr.sk_inspection AS VARCHAR)` (CAST rule applies)
- This JOIN fans out to repair grain — aggregate back when needed
- For descriptive attributes: `rr.sk_repair_request = drr.sk_repair_request`
- See the Repairs entity for the full repair lifecycle, contestation details, and ongoing repairs

### Report (1:1 — one inspection has one report)

- `fi.sk_inspection = CAST(fri.sk_inspection AS VARCHAR)` (CAST rule applies)
- Contains timestamps for each review stage (AR, Review, Budget Approval) and party approval flags

### House (N:1 — many inspections to one house)

An inspection is linked to one house: `fi.sk_house`.

## Dos and Don'ts

**Do:**
- Start from `dw_inspections.fact_inspection` for inspection-centric queries
- Apply the Dedup rule and CAST rule (see Critical rules in Tables) on every query involving `fact_inspection`
- Always filter by `di.inspection_type` (`onboarding` or `offboarding`) when the query starts from inspections
- Use `fi.sk_client_side = an.uuid_inspection` for JOINs with annotation tables
- Aggregate `fact_repair_request` when the desired grain is per inspection — the JOIN fans out to repair level
- Use `has_agreement` in `fact_report_inspections` for the final agreement status (combines early, late, and discount agreements)
- Consider `obt_offboarding` when you need exit inspection data already joined with terminations, reports, and repairs
- When analyzing Kirk impact on approvals, use `obt_offboarding` with `has_agreement` as the primary metric — it consolidates early, late, and discount agreements into a single boolean. For the A/B split: `is_automated_ar = TRUE` (Kirk group) vs `TRY_CAST(automation_group AS BOOLEAN) = TRUE` (eligible control group) — same eligibility pool, cleanest comparison. See Golden Query 4.
- When using `dim_inspection` directly (not obt), use `TRY_CAST(repair_request_ai_flow AS BOOLEAN)` and `TRY_CAST(ai_repair_analysis_control_group AS BOOLEAN)` — both are `varchar` in Trino

**Don't:**
- Don't confuse `onboarding` (entry) with `offboarding` (exit) — always filter by `inspection_type`
- Don't omit the Dedup rule on `fact_inspection` — its absence causes silent duplications
- Don't JOIN with `fact_repair_request` without aggregating back (grain change: 1 inspection → N repairs)
- Don't assume REVIEW approval ends the process — the report goes through REVIEW and then BUDGET_APPROVAL
- Don't treat "owner contestation" as a formal contestation — it refers to additional repairs requested by the landlord; owner contestation is disabled
- Don't confuse inspection (vistoria — technical assessment) with visit (visita — prospective tenant viewing)
- Don't confuse repair **counts** per stage (`total_tentant_repair_ar`, `_review`, `_ac`) with monetary values — these are counts, not costs. `fact_report_inspections.total_cost` and `obt_offboarding.final_tenant_inspection_cost` are the **final** report cost, not per-stage. For monetary value at a specific stage (e.g., AR exit), use `datalake_inspection_services_clean.repair_request_history` — it tracks `cost` per repair over time with an `origin` column indicating the stage
- **Don't use `ts_automatic_repair_processing` for Kirk-related analyses** — this field tracks a separate tag-based identification process unrelated to Kirk (and unrelated to automatic repair pricing). It is not a proxy for the automatic laudo flow. Use `is_automated_ar` (in `obt_offboarding`) or `repair_request_ai_flow` (in `dim_inspection`) instead.
- **Don't read `no_human_ar = TRUE` as "Kirk priced it automatically"** — TRUE also includes terminations with **no tenant AR repairs at all** (nothing to review). `FALSE` means repairs still required human handling: repairs outside the Kirk flow, or Kirk repairs without a successful automatic pricing. It is not a Kirk-vs-control flag — for the A/B split use `is_automated_ar` vs `automation_group`.
- Don't compare `repair_request_ai_flow = TRUE` against `sem_dados_kirk` (inspections with no Kirk data) as the primary comparison — the `sem_dados_kirk` group contains older inspections that predate Kirk rollout, creating a confounding time effect. Prefer comparing against `ai_repair_analysis_control_group = TRUE` (same eligibility, A/B controlled).

## Golden Queries

### Query 1 — Base pattern with report data (offboarding)

Exit inspections with descriptive attributes and report data. Dedup and CAST rules applied. Wrap in subquery and filter `WHERE rni = 1` to deduplicate.

```sql
SELECT sub.*
FROM (
    SELECT
        fi.*,
        di.*,
        fri.*,
        ROW_NUMBER() OVER (PARTITION BY fi.sk_contract ORDER BY fi.ts_updated DESC) AS rni
    FROM dw_inspections.fact_inspection AS fi
    LEFT JOIN dw_inspections.dim_inspection AS di
        ON fi.sk_inspection = di.sk_inspection
    LEFT JOIN dw_inspections.fact_report_inspections AS fri
        ON fi.sk_inspection = CAST(fri.sk_inspection AS VARCHAR)
    WHERE di.inspection_type = 'offboarding'
) AS sub
WHERE sub.rni = 1
```

### Query 2 — With repairs (grain changes to repair level)

Exit inspections with individual repair requests. The JOIN fans out to repair grain — aggregate when needed.

```sql
SELECT
    fi.*,
    di.*,
    rr.*,
    ROW_NUMBER() OVER (PARTITION BY fi.sk_contract ORDER BY fi.ts_updated DESC) AS rni
FROM dw_inspections.fact_inspection AS fi
LEFT JOIN dw_inspections.dim_inspection AS di
    ON fi.sk_inspection = di.sk_inspection
LEFT JOIN dw_inspections.fact_repair_request AS rr
    ON fi.sk_inspection = CAST(rr.sk_inspection AS VARCHAR)
WHERE di.inspection_type = 'offboarding'
```

### Query 3 — Using obt_offboarding for the full picture

When you need exit inspection data in the context of the entire offboarding journey (termination + inspection + report + repairs + mediation), `obt_offboarding` provides everything pre-joined. Here it's used to analyze inspection leadtimes by termination reason:

```sql
SELECT
    obt.termination_reason,
    COUNT(*) AS total_inspections,
    AVG(obt.leadtime_vt) AS avg_days_to_inspection,
    AVG(obt.leadtime_ar) AS avg_days_repair_analysis,
    AVG(obt.leadtime_owner_tenant_review) AS avg_days_review,
    SUM(CASE WHEN obt.has_agreement THEN 1 ELSE 0 END) AS total_with_agreement
FROM dw_offboarding.obt_offboarding AS obt
WHERE obt.ts_termination_finished >= DATE '2025-01-01'
    AND obt.sk_inspection IS NOT NULL
GROUP BY obt.termination_reason
ORDER BY total_inspections DESC
```

### Query 4 — Kirk automatic laudo flow vs IQ/PP approval rates

Compare approval and agreement rates between inspections processed by Kirk (automatic) and the eligible control group (manual). Uses `obt_offboarding` — the simplest and most correct path because Kirk flags and all approval columns are already pre-joined.

- `is_automated_ar` is already a proper `boolean` in the OBT — no casting needed.
- `automation_group` is `varchar` — use `TRY_CAST(automation_group AS BOOLEAN) = TRUE` to filter the control group.
- The cleanest A/B comparison is `is_automated_ar = TRUE` vs `TRY_CAST(automation_group AS BOOLEAN) = TRUE` (same eligibility pool).
- Denominator for approval rates = inspections that **accessed** the stage (not total), to isolate behavioral propensity from access rate differences.

```sql
SELECT
    CASE
        WHEN obt.is_automated_ar = TRUE                                    THEN 'kirk_automatico'
        WHEN TRY_CAST(obt.automation_group AS BOOLEAN) = TRUE              THEN 'controle_elegivel'
        WHEN obt.is_automated_ar IS NOT NULL
          OR obt.automation_group IS NOT NULL                              THEN 'kirk_nao_elegivel'
        ELSE 'sem_dados_kirk'
    END AS fluxo_laudo,
    COUNT(*) AS total,
    -- IQ (Inquilino/Tenant) — 1ª revisão
    COUNT_IF(obt.has_tenant_access_review)    AS iq_acessou_revisao,
    COUNT_IF(obt.has_tenant_approved_review)  AS iq_aprovou_revisao,
    ROUND(100.0 * COUNT_IF(obt.has_tenant_approved_review)
          / NULLIF(COUNT_IF(obt.has_tenant_access_review), 0), 1)              AS pct_iq_aprovacao_revisao,
    -- IQ — aprovação de orçamento (2ª revisão)
    COUNT_IF(obt.has_tenant_access_budget_approval)       AS iq_acessou_orcamento,
    COUNT_IF(obt.has_tenant_approved_budget_approval)     AS iq_aprovou_orcamento,
    ROUND(100.0 * COUNT_IF(obt.has_tenant_approved_budget_approval)
          / NULLIF(COUNT_IF(obt.has_tenant_access_budget_approval), 0), 1)     AS pct_iq_aprovacao_orcamento,
    -- PP (Proprietário/Owner) — 1ª revisão
    COUNT_IF(obt.has_owner_access_review)    AS pp_acessou_revisao,
    COUNT_IF(obt.has_owner_approved_review)  AS pp_aprovou_revisao,
    ROUND(100.0 * COUNT_IF(obt.has_owner_approved_review)
          / NULLIF(COUNT_IF(obt.has_owner_access_review), 0), 1)               AS pct_pp_aprovacao_revisao,
    -- PP — aprovação de orçamento (2ª revisão)
    COUNT_IF(obt.has_owner_access_budget_approval)        AS pp_acessou_orcamento,
    COUNT_IF(obt.has_owner_approved_budget_approval)      AS pp_aprovou_orcamento,
    ROUND(100.0 * COUNT_IF(obt.has_owner_approved_budget_approval)
          / NULLIF(COUNT_IF(obt.has_owner_access_budget_approval), 0), 1)      AS pct_pp_aprovacao_orcamento,
    -- Acordo final
    COUNT_IF(obt.has_early_agreement) AS total_early_agreement,
    COUNT_IF(obt.has_late_agreement)  AS total_late_agreement,
    COUNT_IF(obt.has_agreement)       AS total_agreement,
    ROUND(100.0 * COUNT_IF(obt.has_agreement) / COUNT(*), 1)                   AS pct_agreement
FROM dw_offboarding.obt_offboarding AS obt
WHERE obt.ts_termination_finished >= DATE '2025-01-01'
    AND obt.sk_inspection IS NOT NULL
GROUP BY 1
ORDER BY total DESC
```
