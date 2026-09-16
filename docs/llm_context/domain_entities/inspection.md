# Inspection

## Ownership

**Data Owner:**
- felipe.abreu@quintoandar.com.br
- carolina.espinoza@quintoandar.com.br

**Data Steward:**
- gustavo.silva@quintoandar.com.br

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
3. **Repair analysis (AR)** — damages are identified and repair requests are generated via the **Kirk AI system** (automatic laudo creation) or by a human editing team (manual). A separate, older **tag-based identification flow** also exists, tracked by `ts_automatic_repair_processing`: it drafts repairs from inspector tags, predates Kirk, and is **unrelated to Kirk** (and to automatic repair pricing). Manual editing is tracked by `ts_sent_to_inspection_editing`; these timestamps are **not mutually exclusive**. The AR stage start is `fact_report_inspections.ts_sent_to_repair_analysis` — but **this timestamp is only populated for manual flows, not for the automatic (Kirk) flow**, so treat it with care: a NULL value does not mean repair analysis was skipped, it may simply have gone through Kirk's automatic flow, which does not register this marking.
4. **Owner and tenant review (1st review)** — both parties see the report for the first time and may agree or contest items. Each party has separate access and approval tracking: `has_*_access_review` (opened the link) vs `has_*_approved_review` (clicked approve).
5. **Contestation analysis (AC)** — if the tenant contests, a dedicated team analyzes the dispute (`fact_report_inspections.ts_sent_to_contestation_analysis`)
6. **Budget approval (2nd review)** — after contestation (if any), a final budget is presented to both parties. Same access/approval pattern: `has_*_access_budget_approval` vs `has_*_approved_budget_approval`.
7. **Report closure** — the report is finalized. `has_agreement` is a composite flag: TRUE when early agreement, late agreement (both approved budget), or discount agreement occurred.

Not all inspections go through every stage. Entry inspections (onboarding) are simpler. Some exit inspections end with early agreements, skipping contestation and budget approval.

**Important distinction**: "Inspection" (vistoria) is a technical property assessment. "Visit" (visita) is when a prospective tenant views the property before renting. They are completely different entities.

## Related Metric Entities

- [Inspection SLA](../metric_entities/inspection_sla.md) — official onboarding/offboarding inspection SLA compliance rate.
- [Property Integrity Onboarding](../metric_entities/property_integrity_onboarding.md) — tenant engagement ratios on entry inspection report review (access, finish, comments); H2'2026 OKR = % Tenant Finished.
- [Property Integrity Offboarding](../metric_entities/property_integrity_offboarding.md) — offboarding-quality ratios (mediation, repairs, agreement, SPOC) from `obt_offboarding`.

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
- **AR sem intervenção humana / no human AR** → `obt_offboarding.no_human_ar`. Boolean: TRUE when the repair analysis required no human intervention. **NULL when no exit inspection was performed** (`ts_inspected IS NULL`): a non-performed inspection generates no repair analysis, so the flag is "not applicable" — treat NULL as no AR, never as FALSE.
- **Fluxo de identificação por tags (legado)** → older automatic flow that drafts repair requests from inspector tags (`ts_automatic_repair_processing`, `has_automatically_identified`). Predates Kirk and is unrelated to it and to automatic repair pricing.
- **Abastecimento**, **HOUSE_SUPPLY**, **house_supply** → inspector checklist for whether water, electricity, and gas are **on** at the property during the visit. Live data is the inspections-service item graph in `datalake_inspection_services_clean` (`item_group_type.type = 'house_supply'`; `item_type.type` in `water` / `gas` / `electricity`). The **answer** is one level deeper: `item_issue` → `issue_type.type` in `yes` / `no` / `it_was_not_possible_to_test`. An `item` row is the question, an `item_issue` row is the answer — measure fill on the answer, never on the `item` row alone. Room: `general_information`. Persisted via `POST inspections-service-api/assessments/sync`.
- **house_supplies** (column on `dim_assessment` / `assessment`) → **legacy only**. Old Details-screen widget (`consumeBills.*.workingStatus`). Stopped being populated around Apr 2025 when Flutter hid that widget for rooms with `general_information`. Do **not** use for current "% utilities on" metrics.
- **Contas de consumo** (conta inclusa no condomínio / concessionária) → also under `consumeBills`, typically **not** on entry inspections. Answers **who pays the bill**, not **whether the utility is on**. Do not mix with `house_supply`.

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
| Assessment data | `dw_inspections.dim_assessment` — JOIN via the `sk_assessment` key. Column `house_supplies` is **historical only** (legacy `consumeBills.*.workingStatus`); do not use it for current utilities-on metrics. |
| Whether water / electricity / gas were **on** at execution (abastecimento / HOUSE_SUPPLY) | Canonical clean graph: `datalake_inspection_services_clean.item`, `datalake_inspection_services_clean.item_group`, `datalake_inspection_services_clean.item_group_type` (`type = 'house_supply'`), `datalake_inspection_services_clean.item_type` (`water` / `gas` / `electricity`), `datalake_inspection_services_clean.item_issue`, `datalake_inspection_services_clean.issue_type` (`yes` / `no` / `it_was_not_possible_to_test`), `datalake_inspection_services_clean.room`, `datalake_inspection_services_clean.assessment`. Join executed inspection with `fi.sk_assessment = assessment.id_assessment` (UUID `sk_inspection = id_client_side` does not match). The answer is the `type` value in `issue_type`, reached through `item_issue` — an `item` row on its own only proves the question was rendered. Do **not** filter `is_active = TRUE`, and do **not** use the `is_present` flag on `item` (all three are `NULL` on house_supply rows, so any of those predicates returns zero rows). Do **not** use `dw_inspections.fact_item` for this metric (`item_type` / `item_group_type` are missing). See Golden Query 5. |
| Same metric with fewer joins (enrich shortcut) | `datalake_inspections.item_issue` (`ii`) + `datalake_inspections.item` (`i`) — the enrich layer is already denormalized: `ii` carries `id_assessment`, `item_group_type` and the answer `issue_type`, and `i` supplies `item_type` (`water` / `gas` / `electricity`). Two joins reproduce Golden Query 5 **exactly** (same 97.3% answered, 94.2% water on, 88.5% electricity on, 32.8% gas on — verified in Trino) versus seven on the clean graph: `ii.id_assessment = fi.sk_assessment` + `i.id_item = ii.id_item`, filtering `ii.item_group_type = 'house_supply'`. Trade-off: enrich is rebuilt from clean, so it lags the 30-minute clean fast lane. Use the clean graph when you need the freshest data or the full item graph. |
| Kirk AI flow flags (automatic laudo creation, control group, wave) — **preferred for exit inspections** | `dw_offboarding.obt_offboarding` — already pre-joined. Columns: `is_automated_ar` (boolean, already cast — Kirk succeeded), `automation_group` (varchar — `TRY_CAST AS BOOLEAN` to filter control group), `no_human_ar` (boolean — repair analysis required no human intervention). Use when the analysis is scoped to exit inspections tied to a termination (the most common case). |
| Kirk AI flow flags — **when obt is not appropriate** (all exit inspections, not just terminated ones) | `dw_inspections.dim_inspection` (DW) — JOIN already needed for `inspection_type` filter. Columns: `repair_request_ai_flow` (varchar bool), `ai_repair_analysis_control_group` (varchar bool), `ai_repair_analysis_wave_name`, `ai_processing_failure_reason`. Use `TRY_CAST(col AS BOOLEAN) = TRUE`. Lineage: `datalake_inspections.inspection_booking`. |

**Critical rules:**
- **CAST rule**: the `sk_inspection` column on `fact_inspection` is **VARCHAR** — always apply `CAST(... AS VARCHAR)` on the opposite side of JOINs: `fi.sk_inspection = CAST(other.sk_inspection AS VARCHAR)`
- **Dedup rule**: `fact_inspection` may have duplicates per contract — always apply `ROW_NUMBER() OVER(PARTITION BY fi.sk_contract ORDER BY fi.ts_updated DESC) AS rni` and filter `WHERE rni = 1`
- Always filter by the `inspection_type` column on `dim_inspection` (`onboarding` / `offboarding`) when the query starts from inspections
- **House supply join**: join the executed inspection on `sk_assessment = id_assessment`. Do not join HOUSE_SUPPLY items via `sk_inspection = id_client_side`. Do not filter the `is_active` flags on `item` / `item_issue`, nor the `is_present` flag on `item` — all three are `NULL` on every house_supply row.
- **House supply answer grain**: the answer is the `type` value in `issue_type`, reached through `item_issue` — not the `item` row. Reach it with an `INNER JOIN` (or require a non-NULL answer) before counting an item as answered, so a rendered-but-unanswered question never counts as filled.
- **Kirk boolean rule**: In `obt_offboarding`, `is_automated_ar` is already a proper `boolean` — use directly. When reading from `dim_inspection` directly, `repair_request_ai_flow` and `ai_repair_analysis_control_group` are stored as `varchar` in Trino — always use `TRY_CAST(col AS BOOLEAN) = TRUE`, never `col = TRUE`. The column `automation_group` in `obt_offboarding` is also varchar — apply `TRY_CAST` there too.


## Key Metrics

Use [Related Metric Entities](#related-metric-entities) for **official** inspection SLA and property-integrity metrics. Most offboarding inspection metrics are termination-anchored — see also [Termination](termination.md) and [Property Integrity Offboarding](../metric_entities/property_integrity_offboarding.md).

### Official metrics (metric entities)

| When you need… | Metric entity |
|----------------|---------------|
| Inspection SLA compliance (onboarding/offboarding) | [Inspection SLA](../metric_entities/inspection_sla.md) |
| % tenant finished / access / comments (onboarding report review) | [Property Integrity Onboarding](../metric_entities/property_integrity_onboarding.md) |
| % offboarding w/o mediation, w/o repairs, both agree, compulsory/band-aid, SPOC roll out | [Property Integrity Offboarding](../metric_entities/property_integrity_offboarding.md) |

### Component / exploratory metrics

Most inspection-related metrics are anchored to the **Termination** entity, not to the inspection itself. This is because stakeholders typically ask "what happened during the offboarding journey?" rather than "what happened in the inspection?". As a result, the main metrics use `fact_terminations` or `obt_offboarding` as the starting point and bring inspection data via JOINs:

**Termination-anchored metrics (most common):**
- Rate of terminations with tenant repairs (`fact_terminations.has_repairs`)
- Rate of terminations with repairs and agreement between parties (`obt_offboarding.has_agreement`)
- Rate of terminations with exit inspection opt-out / exempt (`fact_terminations.is_exit_inspection_opt_out`)
- Rate of terminations with repairs requiring mediation (`dim_termination.has_mediation_ticket`) — flag only populated for terminations that already reached `DONE`; scope the denominator to finished terminations (see Termination entity)
- Average repair cost per termination (`obt_offboarding.final_tenant_inspection_cost`)
- Leadtime from termination request to inspection execution (`obt_offboarding.leadtime_vt`)
- Leadtime for repair analysis (`obt_offboarding.leadtime_ar`)

**Inspection-only metrics (not tied to termination):**
- Report access rate — percentage of inspections where landlord and/or tenant accessed the report (`fact_report_inspections.has_tenant_access_review`, `fact_report_inspections.has_owner_access_review`)
- Inspection volume per month (filter by `inspection_type` and `status`)
- SLA compliance: time between scheduling and execution (`fact_inspection.ldt_hours_execution`, `fact_inspection.is_sla_execution`) — generic SLA signal only; official SLA in [Inspection SLA](../metric_entities/inspection_sla.md)
- Share of **executed onboarding** inspections where the inspector **answered** water / electricity / gas (coverage), and — among those — the share answered `yes` (abastecimento) — Golden Query 5. "Answered" means an `item_issue` / `issue_type` answer exists, not that the `item` row exists. Mind the denominators: coverage is over all executed onboarding inspections, while the on-rates are conditional on having answered, since a missing house_supply block means *unknown*, not *off*. Gas `yes` is much lower than water/electricity because of `it_was_not_possible_to_test`; do not read "% all three on" as "the property has no utilities".

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
- **Don't read `final_tenant_inspection_cost` / `total_cost` as the net amount the tenant actually pays** — it is a **gross** value, before any automatic discount applied along the termination flow. If the IQ (tenant) receives discounts, this column still shows the gross repair value prior to any discount. When there is mediation, the value may also change after the negotiation between the parties during mediation.
- **Don't use `ts_automatic_repair_processing` for Kirk-related analyses** — this field tracks a separate tag-based identification process unrelated to Kirk (and unrelated to automatic repair pricing). It is not a proxy for the automatic laudo flow. Use `is_automated_ar` (in `obt_offboarding`) or `repair_request_ai_flow` (in `dim_inspection`) instead.
- **Don't read `no_human_ar = TRUE` as "Kirk priced it automatically"** — TRUE also includes terminations with **no tenant AR repairs at all** (nothing to review). `FALSE` means repairs still required human handling: repairs outside the Kirk flow, or Kirk repairs without a successful automatic pricing. It is not a Kirk-vs-control flag — for the A/B split use `is_automated_ar` vs `automation_group`. **`NULL` means no exit inspection was performed** (`ts_inspected IS NULL`) so there was no repair analysis at all — filter `no_human_ar IS NOT NULL` when computing no-human AR rates, and never treat NULL as FALSE.
- Don't compare `repair_request_ai_flow = TRUE` against `sem_dados_kirk` (inspections with no Kirk data) as the primary comparison — the `sem_dados_kirk` group contains older inspections that predate Kirk rollout, creating a confounding time effect. Prefer comparing against `ai_repair_analysis_control_group = TRUE` (same eligibility, A/B controlled).
- **Don't use `dim_assessment.house_supplies` (or `assessment.house_supplies`) for current "% utilities on"** — the column is historical; empty recent months do not mean the inspector app stopped asking. Use the `house_supply` item graph in `datalake_inspection_services_clean` (Golden Query 5).
- **Don't measure HOUSE_SUPPLY from `datalake_inspections.item` alone** — the enrich `item` table is fine and does reflect inspections-service / Flutter (it is built from the IS clean tables and carries fresh `item_group_type = 'house_supply'` rows), but it holds only the **question**. Without joining `datalake_inspections.item_issue` for the answer you get the same overstated fill rate as counting `item` rows on the clean graph.
- **Don't use `dw_inspections.fact_item` for this metric** — it lacks `item_type` / `item_group_type`.
- **Don't filter `is_active = TRUE`** on `item` / `item_issue` when measuring house supply — the column is `NULL` on every house_supply row, so the filter returns zero rows.
- **Don't count an `item` row as a filled answer** — the `item` row is the question the app rendered; the answer is the `item_issue` → `issue_type.type` row. Counting `item_type.type = 'water'` alone would report a rendered-but-unanswered question as filled and overstate the fill rate. Require the `issue_type` answer (see Golden Query 5).
- **Don't use `item.is_present` as the "inspector answered" flag** for house supply — it is `NULL` on all house_supply rows (it is meaningful for damage-checklist items, not for these chips).
- **Don't treat "% water + electricity + gas all `yes`" as "the listing has no abastecimento"** — water and electricity are on in the large majority; gas pulls the "all three on" rate down (often `it_was_not_possible_to_test`).
- **Don't mix HOUSE_SUPPLY (is it on?) with consumeBills "contas de consumo"** (who pays the bill / condo vs concessionaire).

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

### Query 5 — Onboarding utilities on (HOUSE_SUPPLY / abastecimento)

Share of **executed entry inspections** where the inspector **answered** water, electricity, and gas, and the share answered `yes` (on). Canonical path is the inspections-service clean graph (`item_group_type.type = 'house_supply'`), joined to the executed visit on `sk_assessment = id_assessment`. Do not use `dim_assessment.house_supplies`. Do not filter `is_active` / `is_present`. One row per contract.

Reading the result — **the two metrics use different denominators on purpose**:

- `pct_answered` is **coverage**, over every executed onboarding inspection. It measures the answer, not the question: `item_issue` / `issue_type` are `INNER JOIN`ed on purpose, because an `item` row only proves the app rendered the chip. The remainder (`100 - pct_answered`) is inspections whose assessment has **no house_supply block at all** — a different app/template version, not an inspector who skipped the question.
- `pct_water_on` and the other on-rates are **conditional on having answered**. An inspection with no house_supply block is *unknown*, not *utility off*, so it must not sit in the denominator. Dividing the on-rates by the full executed base instead would understate each of them by roughly 2-3 points and silently mix a coverage gap into a supply metric.
- Gas `yes` is much lower than water/electricity because of `it_was_not_possible_to_test` — do not read "% all three on" as "no utilities".

```sql
WITH executed_onboarding AS (
    SELECT
        fi.sk_contract,
        fi.sk_assessment,
        ROW_NUMBER() OVER (
            PARTITION BY fi.sk_contract
            ORDER BY fi.ts_updated DESC
        ) AS rni
    FROM dw_inspections.fact_inspection AS fi
    INNER JOIN dw_inspections.dim_inspection AS di
        ON fi.sk_inspection = di.sk_inspection
    WHERE di.inspection_type = 'onboarding'
        AND fi.ts_inspected IS NOT NULL
        AND fi.ts_inspected >= TIMESTAMP '2026-06-01 00:00:00'
),
base AS (
    SELECT
        sk_contract,
        sk_assessment
    FROM executed_onboarding
    WHERE rni = 1
),
house_supply AS (
    -- One row per contract. answered_* = the inspector gave an answer (item_issue ->
    -- issue_type), not merely that the app rendered the item.
    SELECT
        base.sk_contract,
        MAX(CASE WHEN it."type" = 'water' THEN 1 ELSE 0 END) AS answered_water,
        MAX(CASE WHEN it."type" = 'electricity' THEN 1 ELSE 0 END) AS answered_electricity,
        MAX(CASE WHEN it."type" = 'gas' THEN 1 ELSE 0 END) AS answered_gas,
        MAX(CASE WHEN it."type" = 'water' AND ist."type" = 'yes' THEN 1 ELSE 0 END) AS water_on,
        MAX(CASE WHEN it."type" = 'electricity' AND ist."type" = 'yes' THEN 1 ELSE 0 END) AS electricity_on,
        MAX(CASE WHEN it."type" = 'gas' AND ist."type" = 'yes' THEN 1 ELSE 0 END) AS gas_on,
        MAX(CASE WHEN it."type" = 'gas' AND ist."type" = 'it_was_not_possible_to_test' THEN 1 ELSE 0 END) AS gas_not_tested
    FROM base
    INNER JOIN datalake_inspection_services_clean.assessment AS assessment
        ON CAST(base.sk_assessment AS VARCHAR) = CAST(assessment.id_assessment AS VARCHAR)
    INNER JOIN datalake_inspection_services_clean.room AS room
        ON room.id_assessment = assessment.id_assessment
    INNER JOIN datalake_inspection_services_clean.item_group AS item_group
        ON item_group.id_room = room.id_room
    INNER JOIN datalake_inspection_services_clean.item_group_type AS item_group_type
        ON item_group_type.id_item_group_type = item_group.id_type
        AND item_group_type."type" = 'house_supply'
    INNER JOIN datalake_inspection_services_clean.item AS item
        ON item.id_item_group = item_group.id_item_group
    INNER JOIN datalake_inspection_services_clean.item_type AS it
        ON it.id_item_type = item.id_type
    -- INNER JOIN: the answer is mandatory. An item row without an item_issue is a
    -- rendered-but-unanswered question and must not count as filled.
    INNER JOIN datalake_inspection_services_clean.item_issue AS item_issue
        ON item_issue.id_item = item.id_item
    INNER JOIN datalake_inspection_services_clean.issue_type AS ist
        ON ist.id_issue_type = item_issue.id_type
    GROUP BY base.sk_contract
),
flags AS (
    SELECT
        COALESCE(
            hs.answered_water = 1
            AND hs.answered_electricity = 1
            AND hs.answered_gas = 1,
            FALSE
        ) AS answered_all,
        COALESCE(hs.water_on = 1, FALSE) AS water_on,
        COALESCE(hs.electricity_on = 1, FALSE) AS electricity_on,
        COALESCE(hs.gas_on = 1, FALSE) AS gas_on,
        COALESCE(hs.gas_not_tested = 1, FALSE) AS gas_not_tested
    FROM base
    LEFT JOIN house_supply AS hs
        ON hs.sk_contract = base.sk_contract
)
SELECT
    -- Coverage: denominator is every executed onboarding inspection.
    COUNT(*) AS executed_onboarding_inspections,
    COUNT_IF(answered_all) AS answered_water_gas_electricity,
    ROUND(100.0 * COUNT_IF(answered_all) / COUNT(*), 1) AS pct_answered,
    -- On-rates: denominator is only the inspections that answered. An inspection with no
    -- house_supply block is "unknown", not "utility off", so it must stay out of the
    -- denominator — leaving it in silently understates every on-rate.
    ROUND(100.0 * COUNT_IF(water_on) / NULLIF(COUNT_IF(answered_all), 0), 1) AS pct_water_on,
    ROUND(100.0 * COUNT_IF(electricity_on) / NULLIF(COUNT_IF(answered_all), 0), 1) AS pct_electricity_on,
    ROUND(100.0 * COUNT_IF(gas_on) / NULLIF(COUNT_IF(answered_all), 0), 1) AS pct_gas_on,
    ROUND(100.0 * COUNT_IF(gas_not_tested) / NULLIF(COUNT_IF(answered_all), 0), 1) AS pct_gas_not_tested,
    ROUND(
        100.0 * COUNT_IF(water_on AND electricity_on AND gas_on)
        / NULLIF(COUNT_IF(answered_all), 0),
        1
    ) AS pct_all_three_on
FROM flags
```
