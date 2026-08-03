# Backlog Out of SLA (BPO Performance — Back Office)

## Ownership

**Data Owner:**

- [joao.mariani@quintoandar.com.br](mailto:joao.mariani@quintoandar.com.br)

**Data Steward:**

- [victor.sakai@quintoandar.com.br](mailto:victor.sakai@quintoandar.com.br)

## Overview

**Metric name:** % Fora Prazo Back
**English name:** Backlog Out of SLA Rate
**Domain:** Customer Support / BPO Performance
**Scope:** Back Office, Post-Contract, email channel
**Operational sources:** Zendesk and Salesforce
**Main consumption:** monthly BPO Performance view by operation

The metric measures the share of the open backlog that has exceeded the applicable SLA target as of a reference date.

**Exists exclusively for the Back Office, Post-Contract, email channel.**

Backlog is a **stock** metric. Each date represents a snapshot of the tickets and cases still open at that moment. Because of this, the monthly value must always come from a single snapshot — never the sum or the average of the days in the month.

**Known active limitations**: the Zendesk zero-contribution issue from 2026-06-25 onward (see [Data Sources — Zendesk](#zendesk)) and the "Out of SLA" residual in Onboarding/Offboarding (see [Confirmed field limitations](#confirmed-field-limitations-2026-07-23--known-out-of-sla-residual)) — see [Validation](#validation) for the full evidence.

## Related Business Entities

- Ticket
- Department

## Catalog

| Metric | Type |
| :---- | :---- |
| Backlog Out of SLA Rate | Health Metric |

## MBR

**Name** Post Contract
**Category** CS Quality

## Glossary and Synonyms

- **% Fora Prazo Back**, **Backlog Out of SLA Rate**, **Backlog Out of SLA (BPO Performance — Back Office)**, **backlog out-of-SLA rate**, **taxa de backlog fora do prazo** → this metric

Minimum terms used in the metric definition:

- **Backlog**: tickets or cases still open at a reference date.
- **Backlog No Prazo (Backlog Within SLA)**: backlog within the SLA target.
- **Backlog Fora do Prazo (Backlog Out of SLA)**: backlog above the SLA target.
- **Saldo (Balance)**: Salesforce total after excluding cases resolved on the same day.
- **sk_ticket**: Zendesk ticket identifier.
- **case_number**: Salesforce case identifier.
- **reference_date**: standardized snapshot date.
- **unified_ticket_id**: identifier composed of platform + source identifier.

## Scope

**Included**: the metric considers only Back Office, Post-Contract, email channel.

**Excluded**:

- Pre-Contract operations;
- Front Office;
- categories classified as `others`;
- CSI, Escalated, Inspection, and PP Multi queues that are not explicitly mapped to one of the seven official rows;
- canceled or deleted records;
- tickets and cases resolved on or before the reference date.

## Calculation

The naive-path error is treating backlog as a flow metric — summing or averaging several dates within the month. Backlog is a stock: the monthly value must come from a single snapshot (the last `reference_date` available in the month).

The correct calculation is:

```
% Fora Prazo Back = Backlog Fora do Prazo / Backlog Total
```

where:

- **Backlog Total**: distinct count of tickets or cases still open at the end of the reference date.
- **Backlog Fora do Prazo**: distinct count of open tickets or cases whose backlog time exceeded the applicable SLA.
- Cases resolved or closed on the reference date itself are excluded from both the numerator and the denominator.
- On Salesforce, the official denominator is **Saldo**, defined as raw Backlog Total − cases resolved on the same day.

### Granularity

The canonical grain prior to aggregation is:

- **Zendesk**: one row per `sk_ticket` and `dt_metric_reference`, after deduplication by `aux_number = 1`.
- **Salesforce**: one row per `case_number` and `date_reference`, using only the most recent version of the case.
- **Unified base**: one row per `unified_ticket_id` and `reference_date`.

The unified identifier must carry the platform to avoid collisions:

```sql
CONCAT(source_platform, '-', CAST(raw_ticket_id AS VARCHAR))
```

### Temporal rule and monthly cutoff

Standardized temporal field: `reference_date`.

- Zendesk: `dt_metric_reference`.
- Salesforce: `date_reference`.

Rules:

- For each month, use the last `reference_date` available within the month.
- For a month still open, the value is a moving figure and must be revalidated once the month closes.
- Do not sum daily backlog and do not average daily percentages.

### Canonical Filter

Apply on the Zendesk side (`dw_customer_support.fact_backlog_metrics_tasks` joined to `dim_ticket` / `fact_tickets` / `dim_department`):

```sql
bmt.origin = 'email'
AND dit.tags NOT LIKE '%closed_by_merge%'
AND dd.department IN (
    'Entrada no imóvel [ONB] [POS] [BACK]',
    'Aditivos [REP] [POS] [BACK]',
    'CX Pagamentos Ativo [POS] [BACK] [PAY]',
    'Alteração de dados bancários [BACK]',
    'Atendimento Escalado [OFF] [POS] [BACK]'
)
AND (resolution_date IS NULL OR resolution_date > reference_date)
```

**Warning**: filter the channel via `fact_backlog_metrics_tasks.origin = 'email'` — **do not** use `fact_tickets.channel`. Confirmed in the field (2026-07-23): `fact_tickets.channel = 'email'` drops from ~1,641 records (May/26) to ~54 (Jun/Jul/26), an abrupt and implausible break — evidence of a fill-rate issue on that column for recent tickets. `bmt.origin` is stable across the same dates and is the correct column for this filter.

Apply on the Salesforce side (curated daily backlog base reconstructed from `events_case` — see [Data Sources → Salesforce](#salesforce)):

```sql
channel = 'email'
AND last_department IN (
    'Onboarding ForRent',
    'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos',
    'Payment FR - Reembolso de Condomínio', 'Payment FR - Condomínio Geral',
    'Payment FR - Aluguel', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
    'Payment FR - Dados Bancários', 'Payment FR - Dados Bancários Front',
    'Offboarding - CNX', 'Offboarding - AEC', 'Offboarding - Atento'
)
AND (resolution_date IS NULL OR resolution_date > reference_date)
```

**Warning**: use only the most recent version of each `case_number` (`ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY last_modified_date DESC)`, `rn = 1`). Skipping this dedup keeps stale, superseded versions of the same case in the base — the same case is counted more than once, double-counting cases and inflating both Backlog Total and Backlog Out of SLA. Also exclude deleted cases (`event_type = 'DELETE'`) and cases with status `CANCELED` — see the full mandatory rules below.

### Nuances

#### Data Sources

##### Zendesk

Main source: `dw_customer_support.fact_backlog_metrics_tasks`.

Relevant supporting tables:

- `dw_customer_support.dim_ticket`
- `dw_customer_support.fact_tickets`
- `dw_customer_support.dim_taxonomy`
- `dw_customer_support.dim_department`
- `dw_customer_support.dim_analyst`

Mandatory rules:

- Deduplicate via `ROW_NUMBER() OVER (PARTITION BY sk_task, dt_metric_reference ORDER BY sla_target DESC)` and keep `aux_number = 1`.
- Exclude tickets flagged as `closed_by_merge` (via `dim_ticket.tags NOT LIKE '%closed_by_merge%'`).
- Filter the channel via `fact_backlog_metrics_tasks.origin = 'email'` — do not use `fact_tickets.channel` (see the warning in Canonical Filter above).
- Do not use the raw `is_backlog_within_sla`/`is_backlog_with_exceed_sla` flags from the fact table — recompute `is_backlog_in_time`/`is_backlog_not_in_time` from `LEAST(bmt.days_worked, fact_tickets.days_elapsed_business)` compared against `bmt.sla_target` (see Golden Query).
- Consider only open-backlog status (derived, not the raw `status` column — see the fallback rule below).
- Exclude tickets resolved on or before the reference date.
- Fix the fixed resolution-date fallback before productive use — see the confirmed limitation below, still active in production.

**Confirmed production limitation (2026-07-23) — not a query discrepancy, this is the real state of the source:** the official status formula uses `COALESCE(DATE(ts_solved), DATE(ft.ts_solved), DATE '2026-06-25')`. For any `dt_metric_reference` from 2026-06-25 onward, every ticket still open (with no `ts_solved`) falls into the fallback and is classified as `'solved'`, removing it from the backlog. This was confirmed two independent ways: (1) running the full Golden Query on Trino, which returned zero Zendesk backlog rows for 2026-06-30 and 2026-07-22 across every tested operation; (2) the official dashboard extract (real RunSQL, exported by the metric owner on 2026-07-23) also returned no Zendesk rows for those two dates. Therefore, from 2026-06-25 onward Zendesk contributes zero to the official backlog — this must not be treated as a discrepancy to resolve in this metric's Golden Query; it is a confirmed source bug, already logged for the data engineering team responsible for the Zendesk pipeline. Reconciliations performed from that date onward must treat Zendesk as a zero contribution until the fix is published and the Golden Query is re-run.

##### Salesforce

The daily base is rebuilt from case events plus a calendar spine.

Main components:

- `datalake_salesforce_clean.events_case`
- `datalake_salesforce_clean.record_types`
- `datalake_salesforce_clean.case_milestones`
- `sandbox.sla_target_salesforce`
- business-day and holiday calendar

Mandatory rules:

- Rebuild via the full official RunSQL — do not query the materialized table `dw_bpo_performance.backlog_metrics_salesforce` in isolation. Confirmed in the field (2026-07-23): this materialized table has up to 22 rows per `case_number` × `date_reference`, each with a distinct `ts_load` (repeated ETL loads, not deduplicated). Using it directly without deduplicating by `ts_load` inflates the backlog by up to ~2.6x. The official RunSQL avoids this problem because it rebuilds history directly from `datalake_salesforce_clean.events_case`, not from this materialized table.
- Rebuild `ts_solved` via the `status_historico`/`solved_date` logic (status change history in `events_case`), not from an already-materialized `ts_solved` field.
- Use only the most recent version of each `case_number`, via `ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY last_modified_date DESC)`, `rn = 1`.
- Use the case's current/most recent queue; do not accept any historical queue.
- Exclude deleted cases (`events_case` with `event_type = 'DELETE'`) and cases with status `CANCELED`.
- Exclude cases resolved or closed on the reference date itself.
- Compute business days via the non-working-days calendar (`datalake_quintoandar.aux_date` + `datalake_gsheets_clean.service_city_holidays`, National category), not a calendar-day calculation.
- SLA target: `sandbox.sla_target_salesforce`, falling back to `datalake_salesforce_clean.case_milestones.target_response_in_days` when absent.
- Use **Saldo** as the official denominator (`COUNT DISTINCT case_number` − cases resolved on the reference date itself).
- Explicitly handle `NULL` in resolution and closing dates.
- Deduplicate the SLA reference before the join. The current rule provisionally uses `MIN(sla_tgt)` when conflicting values exist.

**Field validation (2026-07-23)** — official RunSQL reproduced at the `case_number` grain, compared against the dashboard: Total (Saldo) matched exactly or within ≤0.3% in 8 of 9 tested points (3 operations × 3 months); the only relevant deviation was Offboarding in May/2026 (Salesforce Saldo = 1,069 vs. official combined Zendesk+Salesforce = 2,642), explained by the migration still in progress that month (see [Composition Rule](#composition-rule-zendesk--salesforce-field-validated-2026-07-23) below), not by a reconstruction error. "Out of SLA" matched exactly for Dados Bancários across all 3 months; for Onboarding and Offboarding in Jun/Jul/26 there is a small, known residual (see [Confirmed field limitations](#confirmed-field-limitations-2026-07-23--known-out-of-sla-residual) below).

#### Composition Rule (Zendesk + Salesforce, field-validated 2026-07-23)

The composition is not a direct sum of the raw tables — each source must first go through the rules described in [Data Sources](#data-sources) before being summed. After that, the composition by operation and reference date is a simple sum of Backlog Total (Zendesk) + Saldo (Salesforce), and of Backlog Out of SLA from each side.

Validation performed: reproduction of the Zendesk Golden Query + the official Salesforce RunSQL, compared against 9 official reference values (Dados Bancários, Offboarding, Onboarding × May/Jun/Jul 2026) and against an official dashboard extract at the `case_number`/`sk_ticket` grain (2026-07-23):

| Operation | May/26 | Jun/26 | Jul/26 |
| :---- | :---- | :---- | :---- |
| Onboarding (Total) | ZD 29 + SF Saldo 647 = 676 vs. official 675 (+0.15%) | SF 673 vs. official 672 (+0.15%) — ZD contributes 0 | SF 662 vs. official 664 (-0.30%) — ZD contributes 0 |
| Dados Bancários (Total) | ZD 11 + SF Saldo 142 = 153 vs. official 153 (exact) | SF 226 vs. official 226 (exact) — ZD contributes 0 | SF 349 vs. official 350 (-0.29%) — ZD contributes 0 |
| Offboarding (Total) | ZD 1,573 + SF Saldo 1,069 = 2,642 vs. official 2,642 (exact) | SF 2,816 vs. official 2,814 (+0.07%) — ZD contributes 0 | SF 2,884 vs. official 2,888 (-0.14%) — ZD contributes 0 |

May closed exact or near-exact across all 3 operations by summing both sources. From June onward, Zendesk contributes zero (see the [confirmed limitation](#zendesk) in the Zendesk section above) and Salesforce alone already reproduces the official Total with ≤0.3% deviation — consistent with the Zendesk→Salesforce migration of these queues being essentially complete from June/2026 onward.

#### Confirmed field limitations (2026-07-23) — known Out-of-SLA residual

Even with Total practically reconciled, "Backlog Out of SLA" shows a small, systematic residual in two spots, which must remain documented and must not be confused with a reconstruction error:

- **Onboarding, Jun/Jul 2026**: Salesforce reproduced 26 and 29 out-of-SLA cases vs. official 28 and 32 (a -7.1% and -9.4% difference). Consistent with the already-documented reopened-case handling issue for this operation (the weakest case-by-case match in the group, ~82% in the evaluated extracts).
- **Offboarding, Jun/Jul 2026**: Salesforce reproduced 409 and 458 out-of-SLA cases vs. official 394 and 431 (a +3.8% and +6.3% difference). Consistent with the small false-positive rate already documented for this operation (~97-99% case-by-case match).
- **Dados Bancários and May/2026 (all operations)**: no relevant residual — Out of SLA matched exactly or within rounding.

These two residuals are known, small in absolute terms, and do not block using Total/Saldo as a reliable metric; they remain logged as a future investigation item, not a publication blocker.

#### Operation Mapping

**Onboarding**
- Zendesk: `Entrada no imóvel [ONB] [POS] [BACK]`
- Salesforce: `Onboarding ForRent`

**Ongoing**
- Zendesk: `Aditivos [REP] [POS] [BACK]`
- Salesforce: `Ongoing FR - Geral` and `Ongoing FR - Informe de Rendimentos`

**Payments Ativo Back**
- Zendesk: `CX Pagamentos Ativo [POS] [BACK] [PAY]`
- Salesforce: `Payment FR - Reembolso de Condomínio`, `Payment FR - Condomínio Geral`, `Payment FR - Aluguel`, `Payment_FR_GeneralCondominium`, and `Payment FR - PP Multi`

**Dados Bancários**
- Zendesk: `Alteração de dados bancários [BACK]`
- Salesforce: `Payment FR - Dados Bancários` and `Payment FR - Dados Bancários Front`

**Payments** (rollup computed by summing the numerators and denominators of Payments Ativo Back + Dados Bancários — never compute as an average of the child percentages)

**Offboarding**
- Zendesk: `Atendimento Escalado [OFF] [POS] [BACK]`
- Salesforce: `Offboarding - CNX`, `Offboarding - AEC`, and `Offboarding - Atento`

**Pós-Contrato (Post-Contract)** (rollup computed by summing the numerators and denominators of Onboarding + Ongoing + Payments + Offboarding — never compute as an average of the child percentages)

#### Rules Incorporated After Validation

- **Current Salesforce queue**: the operation scope must be defined by the most recent version of the case. Using any historical value of `omni_channel_queue__c` keeps transferred cases under old operations and inflates the backlog.
- **Cases resolved on the same day**: tickets and cases resolved or closed on the reference date do not belong to that day's backlog. The exclusion must be applied to both the numerator and the denominator.
- **Salesforce denominator**: the official denominator is Saldo, not the raw Backlog Total. This rule was confirmed by the operational formula used in the reference spreadsheet.
- **NULL handling**: exclusion conditions must preserve cases still open. Use, for example, `resolution_date IS NULL OR reference_date <> resolution_date`. Do not use only the second condition, since comparison with `NULL` never returns `TRUE`.
- **SLA deduplication**: the `sandbox.sla_target_salesforce` table can contain more than one row per `theme_type`, including conflicting values. The Golden Query must deduplicate this reference before the join.

#### Supported Breakdowns

The metric can be analyzed by:

- month or reference date;
- operation;
- platform;
- department or queue;
- agent organization;
- ticket or case, in a detailed view.

When breaking down by ticket or `case_number`, the metric must keep the same aggregate total, as long as the filters and the classification rule are identical.

**Join key**: none between the sources — Zendesk and Salesforce are reconstructed independently (see [Data Sources](#data-sources)) and then combined via `UNION ALL` in the unified base, keyed by `unified_ticket_id`/`reference_date`.

**Fallback**: the Salesforce SLA target falls back to `datalake_salesforce_clean.case_milestones.target_response_in_days` when `sandbox.sla_target_salesforce` has no value.

## Dos and Don'ts

**Do:**

- Use a single monthly snapshot (the last `reference_date` of the month) — never sum or average days.
- Deduplicate Zendesk by `sk_task`/`dt_metric_reference` keeping `aux_number = 1`.
- Filter the Zendesk channel via `fact_backlog_metrics_tasks.origin = 'email'`.
- Exclude `closed_by_merge` tickets.
- Recompute `is_backlog_in_time`/`is_backlog_not_in_time` from `LEAST(days_worked, days_elapsed_business)` vs. `sla_target`.
- Rebuild the Salesforce backlog via the full official RunSQL (from `events_case`), not via the isolated materialized table.
- Use only the most recent version of each `case_number` (`rn = 1` by `last_modified_date DESC`) and the case's current queue.
- Exclude deleted Salesforce cases (`event_type = 'DELETE'`) and cases with status `CANCELED`.
- Use **Saldo** (raw Backlog Total − resolved on the same day) as the official Salesforce denominator.
- Exclude tickets/cases resolved on the reference date itself from both the numerator and the denominator, on both sources.
- Deduplicate `sandbox.sla_target_salesforce` before the join, and apply the fallback to `case_milestones.target_response_in_days` when absent.
- Handle `NULL` in resolution dates with `resolution_date IS NULL OR reference_date <> resolution_date` (never just the second condition).
- Compose Zendesk + Salesforce by summing numerators and denominators already filtered by operation and `reference_date` — never before applying each source's rules.
- Sum Payments (Payments Ativo Back + Dados Bancários) and Pós-Contrato (Onboarding + Ongoing + Payments + Offboarding) by summing numerators/denominators.
- Treat Zendesk as a zero contribution from 2026-06-25 onward in any reconciliation, until the `ts_solved` fallback bug is fixed at the source.
- Return the SQL used whenever the user requests validation or auditing.

**Don't:**

- Don't use `fact_tickets.channel` to filter the Zendesk channel — use `fact_backlog_metrics_tasks.origin`.
- Don't use the raw `is_backlog_within_sla`/`is_backlog_with_exceed_sla` flags from the Zendesk fact table.
- Don't query `dw_bpo_performance.backlog_metrics_salesforce` in isolation without deduplicating by `ts_load` — it inflates the backlog by up to ~2.6x.
- Don't accept any historical Salesforce queue (`omni_channel_queue__c`) — only the case's most recent version.
- Don't include deleted or `CANCELED` Salesforce cases.
- Don't use the raw Salesforce Backlog Total as the denominator — use Saldo.
- Don't treat the Zendesk zero contribution from 2026-06-25 onward as a Golden Query bug — it is a confirmed source bug (fixed `ts_solved` fallback), already logged for the responsible engineering team.
- Don't confuse `Payments` (maps to Dados Bancários) with `Payments Ativo Back` (its own operation).
- Don't compute Payments or Pós-Contrato as an average of the child percentages — always sum numerators and denominators.
- Don't sum daily backlog or average daily percentages.
- Don't include Pre-Contract operations, Front Office, `others` categories, or CSI/Escalated/Inspection/PP Multi queues outside the official seven-row mapping.

## Golden Queries

All queries are written for the July 2026 window — change the two `DATE(...)` bounds to move it. They contain no `LIMIT` and are reduced to the minimal logic needed to reproduce % Fora Prazo Back — they are not full copies of the dashboard queries. Trino dialect.

### Zendesk Canonical Base

```sql
WITH zendesk_raw AS (
  SELECT
    bmt.sk_task                                   AS raw_ticket_id,
    CAST(bmt.dt_metric_reference AS DATE)         AS reference_date,
    dd.department                                 AS department,
    dd.team                                       AS last_team,
    bmt.origin                                    AS channel,
    bmt.sla_target                                AS sla_target,
    bmt.days_worked                               AS days_worked,
    bmt.days_worked_with_days_offs                AS days_worked_with_days_offs,
    tickets.days_elapsed_business                 AS days_elapsed_business,
    CASE
      WHEN da_last.agent_organization IN ('atn', 'atento')              THEN 'atento'
      WHEN da_last.agent_organization IN ('webhelp', 'webhelpbr', 'contractors') THEN 'webhelp'
      WHEN da_last.agent_organization IN ('quintoandar.com', 'quintoandar')      THEN 'quintoandar'
      WHEN da_last.agent_organization IS NULL                            THEN 'unassigned'
      ELSE da_last.agent_organization
    END                                            AS agent_organization,
    COALESCE(DATE(bmt.ts_solved), DATE(ft.ts_solved)) AS resolution_date,
    ROW_NUMBER() OVER (
      PARTITION BY bmt.sk_task, bmt.dt_metric_reference
      ORDER BY bmt.sla_target DESC
    )                                              AS aux_number
  FROM dw_customer_support.fact_backlog_metrics_tasks AS bmt
  LEFT JOIN dw_customer_support.dim_ticket      AS dit     ON CAST(dit.sk_ticket AS VARCHAR) = bmt.sk_task
  LEFT JOIN dw_customer_support.fact_tickets    AS ft      ON dit.sk_ticket = ft.sk_ticket
  LEFT JOIN dw_customer_support.dim_department  AS dd      ON bmt.sk_main_department = dd.sk_department
  LEFT JOIN dw_customer_support.fact_tickets    AS tickets ON bmt.sk_task = CAST(tickets.sk_ticket AS VARCHAR(99))
  LEFT JOIN dw_customer_support.dim_analyst     AS da_last ON da_last.sk_analyst = tickets.sk_last_analyst
  -- Change both bounds to the analysis window you want.
  WHERE bmt.dt_metric_reference BETWEEN DATE('2026-07-01') AND DATE('2026-07-31')
    AND dit.tags NOT LIKE '%closed_by_merge%'
    AND NOT (
      (dit.tags LIKE '%form_faq%' OR dit.tags LIKE '%email_orientacao_do_processo%'
       OR dit.tags LIKE '%tarefacx_cognito%' OR dit.tags LIKE '%for%' OR dit.tags LIKE '%cognito%')
      AND (
        (dd.department = 'Entrada no imóvel [ONB] [POS] [BACK]' AND bmt.ts_started >= DATE('2026-04-14'))
        OR (dd.department = 'Aditivos [REP] [POS] [BACK]' AND bmt.ts_started >= DATE('2026-04-23'))
      )
    )
    AND dd.department IN (
      'Entrada no imóvel [ONB] [POS] [BACK]', 'Aditivos [REP] [POS] [BACK]',
      'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
      'Atendimento Escalado [OFF] [POS] [BACK]'
    )
    AND bmt.origin = 'email'
)
SELECT
  'zendesk'                                                             AS source_platform,
  raw_ticket_id,
  CONCAT('zendesk-', CAST(raw_ticket_id AS VARCHAR))                     AS unified_ticket_id,
  reference_date,
  department,
  last_team,
  agent_organization,
  sla_target,
  days_worked,
  days_worked_with_days_offs,
  -- Confirmed against production data (see Field Validation): 'Payments' is NOT
  -- a fourth leaf here -- it is Payments Ativo Back + Dados Bancarios summed.
  -- This CASE produces only the LEAF operations; the 'Payments' and
  -- 'Pos-Contrato' rollups are computed at aggregation time (see the Out of SLA Rate queries below).
  CASE
    WHEN department = 'Entrada no imóvel [ONB] [POS] [BACK]'       THEN 'Onboarding'
    WHEN department = 'Aditivos [REP] [POS] [BACK]'                THEN 'Ongoing'
    WHEN department = 'CX Pagamentos Ativo [POS] [BACK] [PAY]'     THEN 'Payments Ativo Back'
    WHEN department = 'Alteração de dados bancários [BACK]'        THEN 'Dados Bancários'
    WHEN department = 'Atendimento Escalado [OFF] [POS] [BACK]'    THEN 'Offboarding'
    ELSE NULL
  END                                                                    AS backlog_operation_leaf,
  CASE
    WHEN LEAST(days_worked, days_elapsed_business) <= sla_target THEN 1
    WHEN LEAST(days_worked, days_elapsed_business) > sla_target  THEN 0
    ELSE NULL
  END                                                                    AS is_backlog_in_time,
  CASE
    WHEN LEAST(days_worked, days_elapsed_business) > sla_target  THEN 1
    WHEN LEAST(days_worked, days_elapsed_business) <= sla_target THEN 0
    ELSE NULL
  END                                                                    AS is_backlog_not_in_time,
  CASE WHEN days_worked_with_days_offs >= 60 THEN 1 ELSE 0 END           AS is_backlog_over_60d
FROM zendesk_raw
WHERE aux_number = 1
  -- exclude tickets resolved on or before the reference date (see Business Definition)
  AND (resolution_date IS NULL OR resolution_date > reference_date)
```

### Salesforce Canonical Base

Note: the Salesforce dashboard query rebuilds the daily backlog from raw case events, inline (status history, milestones, SPOC classification, days-off calendar). Reproducing that full reconstruction inside this metric's Golden Query would violate the instruction to keep Golden Queries minimal. This query assumes that reconstruction already exists as a stable upstream table/view (`curated_salesforce_daily_backlog_base`) exposing `date_reference`, `case_number`, `last_department`, `last_agent_organization`, `sla_target`, `days_worked`, `days_worked_with_days_offs`, `is_backlog_in_time`, `is_backlog_not_in_time`, `ts_solved`, `ts_closed`, `channel`. Confirming the exact name/location of that upstream object is an **Open Decision** — if it does not yet exist, the full `cases_perspective` → calendar → `exploded_backlog`/`days_off` chain from the dashboard query needs to be materialized first.

```sql
WITH salesforce_raw AS (
  -- Assumes access to an existing, curated daily backlog view/table, built with
  -- the same cases_perspective + calendar + days_off logic documented in
  -- "Data Sources > Salesforce". This Golden Query intentionally does not repeat
  -- the full case-event reconstruction (status history, milestones, SPOC, etc.)
  -- since those concerns belong to the upstream cases-perspective model, not
  -- to the Golden Query of this metric.
  SELECT
    case_number                                    AS raw_ticket_id,
    CAST(date_reference AS DATE)                   AS reference_date,
    last_department                                AS last_department,   -- raw omni_channel_queue
    last_agent_organization                         AS agent_organization,
    sla_target,
    days_worked,
    days_worked_with_days_offs,
    is_backlog_in_time,
    is_backlog_not_in_time,
    COALESCE(DATE(ts_solved), DATE(ts_closed))     AS resolution_date
  -- Replace with the real schema.table once the Open Decision below is settled.
  FROM curated_salesforce_daily_backlog_base
  -- Change both bounds to the analysis window you want.
  WHERE date_reference BETWEEN DATE('2026-07-01') AND DATE('2026-07-31')
    AND channel = 'email'
    AND last_department IN (
      'Onboarding ForRent',
      'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos',
      'Payment FR - Reembolso de Condomínio', 'Payment FR - Condomínio Geral',
      'Payment FR - Aluguel', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
      'Payment FR - Dados Bancários', 'Payment FR - Dados Bancários Front',
      'Offboarding - CNX', 'Offboarding - AEC', 'Offboarding - Atento'
    )
)
SELECT
  'salesforce'                                                          AS source_platform,
  raw_ticket_id,
  CONCAT('salesforce-', CAST(raw_ticket_id AS VARCHAR))                  AS unified_ticket_id,
  reference_date,
  last_department                                                        AS department,
  agent_organization,
  sla_target,
  days_worked,
  days_worked_with_days_offs,
  CASE
    WHEN last_department = 'Onboarding ForRent'                                                                    THEN 'Onboarding'
    WHEN last_department IN ('Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos')                          THEN 'Ongoing'
    WHEN last_department IN ('Payment FR - Reembolso de Condomínio', 'Payment FR - Condomínio Geral',
                              'Payment FR - Aluguel', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi')     THEN 'Payments Ativo Back'
    WHEN last_department IN ('Payment FR - Dados Bancários', 'Payment FR - Dados Bancários Front')                 THEN 'Dados Bancários'
    WHEN last_department IN ('Offboarding - CNX', 'Offboarding - AEC', 'Offboarding - Atento')                     THEN 'Offboarding'
    ELSE NULL
  END                                                                    AS backlog_operation_leaf,
  is_backlog_in_time,
  is_backlog_not_in_time,
  CASE WHEN days_worked_with_days_offs >= 60 THEN 1 ELSE 0 END           AS is_backlog_over_60d
FROM salesforce_raw
-- exclude cases resolved on or before the reference date (see Business Definition)
WHERE (resolution_date IS NULL OR resolution_date > reference_date)
```

### Unified Backlog Base

```sql
WITH unified_backlog AS (
  SELECT * FROM zendesk_canonical_base
  UNION ALL
  SELECT * FROM salesforce_canonical_base
),
month_bounds AS (
  SELECT
    d.month_start,
    LEAST(date_add('day', -1, date_add('month', 1, d.month_start)), CURRENT_DATE) AS snapshot_ceiling
  FROM UNNEST(
    -- Change both bounds to the analysis window you want.
    sequence(date_trunc('month', DATE('2026-07-01')), date_trunc('month', DATE('2026-07-31')), interval '1' month)
  ) AS d(month_start)
),
snapshot_dates AS (
  SELECT
    mb.month_start,
    MAX(ub.reference_date) AS snapshot_date
  FROM month_bounds mb
  JOIN unified_backlog ub
    ON ub.reference_date <= mb.snapshot_ceiling
   AND ub.reference_date >= mb.month_start
  GROUP BY mb.month_start
)
SELECT
  sd.month_start,
  ub.*
FROM unified_backlog ub
JOIN snapshot_dates sd
  ON ub.reference_date = sd.snapshot_date
```

### Out of SLA Rate — Post-Contract

Post-Contract is the rollup of the 4 leaf operations (Onboarding, Ongoing, Payments [itself a rollup], Offboarding) — confirmed empirically, see [Operation Mapping](#operation-mapping).

```sql
SELECT
  month_start,
  COUNT(DISTINCT unified_ticket_id)                                                      AS backlog_total,
  COUNT(DISTINCT CASE WHEN is_backlog_in_time = 1 THEN unified_ticket_id END)             AS backlog_in_sla,
  COUNT(DISTINCT CASE WHEN is_backlog_not_in_time = 1 THEN unified_ticket_id END)         AS backlog_out_of_sla,
  CAST(COUNT(DISTINCT CASE WHEN is_backlog_not_in_time = 1 THEN unified_ticket_id END) AS DOUBLE)
    / NULLIF(COUNT(DISTINCT unified_ticket_id), 0)                                       AS out_of_sla_rate
FROM unified_backlog_base
WHERE backlog_operation_leaf IS NOT NULL   -- the 5 leaf operations only (Payments Ativo Back + Dados Bancarios each count once here)
GROUP BY month_start
ORDER BY month_start
```

### Out of SLA Rate by Operation

Produces the 7 official rows in a single pass: the 5 leaves as-is, plus Payments (rollup of Payments Ativo Back + Dados Bancários) and Pós-Contrato (rollup of all 5 leaves) via `GROUPING SETS`.

```sql
WITH leaf_rates AS (
  SELECT
    month_start,
    backlog_operation_leaf                                                                AS backlog_operation_adjusted,
    unified_ticket_id,
    is_backlog_in_time,
    is_backlog_not_in_time
  FROM unified_backlog_base
  WHERE backlog_operation_leaf IS NOT NULL
),
with_rollup_labels AS (
  -- tags each ticket with every operation it should be counted under,
  -- including the 'Payments' and 'Pos-Contrato' rollups
  SELECT month_start, backlog_operation_adjusted, unified_ticket_id, is_backlog_in_time, is_backlog_not_in_time FROM leaf_rates
  UNION ALL
  SELECT month_start, 'Payments', unified_ticket_id, is_backlog_in_time, is_backlog_not_in_time
  FROM leaf_rates WHERE backlog_operation_adjusted IN ('Payments Ativo Back', 'Dados Bancários')
  UNION ALL
  SELECT month_start, 'Pós-Contrato', unified_ticket_id, is_backlog_in_time, is_backlog_not_in_time
  FROM leaf_rates WHERE backlog_operation_adjusted IN ('Onboarding', 'Ongoing', 'Payments Ativo Back', 'Dados Bancários', 'Offboarding')
)
SELECT
  month_start,
  backlog_operation_adjusted,
  COUNT(DISTINCT unified_ticket_id)                                                      AS backlog_total,
  COUNT(DISTINCT CASE WHEN is_backlog_in_time = 1 THEN unified_ticket_id END)             AS backlog_in_sla,
  COUNT(DISTINCT CASE WHEN is_backlog_not_in_time = 1 THEN unified_ticket_id END)         AS backlog_out_of_sla,
  CAST(COUNT(DISTINCT CASE WHEN is_backlog_not_in_time = 1 THEN unified_ticket_id END) AS DOUBLE)
    / NULLIF(COUNT(DISTINCT unified_ticket_id), 0)                                       AS out_of_sla_rate
FROM with_rollup_labels
GROUP BY month_start, backlog_operation_adjusted
ORDER BY month_start, backlog_operation_adjusted
```

### Detailed Out-of-SLA Cases

```sql
SELECT
  unified_ticket_id,
  source_platform,
  raw_ticket_id,
  reference_date,
  month_start,
  department,
  backlog_operation_leaf,
  agent_organization,
  sla_target,
  days_worked,
  days_worked_with_days_offs,
  is_backlog_over_60d
FROM unified_backlog_base
WHERE is_backlog_not_in_time = 1
  AND backlog_operation_leaf IS NOT NULL
ORDER BY reference_date, backlog_operation_leaf, unified_ticket_id
```

### Validation

Validated period: Aug/2025 to Jul/2026.

Main evidence:

- Aug/2025 to Mar/2026: 56 of 56 operation/month combinations reproduced within 0.05 p.p.
- May/2026: seven official rows at CRAVOU or CRAVOU-tier level; largest difference 0.15 p.p.
- June and July/2026: adherence confirmed for most operations.
- Payments Ativo Back and Dados Bancários reached 100% case-by-case match in the evaluated extracts.
- Ongoing and Offboarding showed a match above 97% in the evaluated extracts.
- Onboarding remains the main exception, especially in Jul/2026, due to reopened-case handling.

**Conclusion**: the business rule and the formula are sufficiently evidenced. Two known limitations remain active and should be factored into any reconciliation:

- Zendesk contributes zero from 2026-06-25 onward due to the fixed `ts_solved` fallback (see [Data Sources → Zendesk](#zendesk)) — a confirmed source bug, not a Golden Query issue.
- Known "Out of SLA" residual in Onboarding and Offboarding in Jun/Jul 2026 (see [Confirmed field limitations](#confirmed-field-limitations-2026-07-23--known-out-of-sla-residual)).

#### Open decision — name/location of `curated_salesforce_daily_backlog_base`

The Salesforce Golden Query depends on a stable upstream table/view that rebuilds the daily backlog from `events_case` + calendar + days-off (see the note above in the Salesforce Canonical Base). The exact name and location of that object have not yet been confirmed. Until that decision is made:

- do not assume a specific schema/table name beyond the `curated_salesforce_daily_backlog_base` placeholder;
- if the object does not yet exist, materialize the `cases_perspective` → calendar → `exploded_backlog`/`days_off` chain from the dashboard query first;
- confirm with the Data Steward before assuming the final location.
