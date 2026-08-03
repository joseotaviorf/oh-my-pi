# Offboard Human vs Digital Metrics

## Ownership

**Data Owner:**
- samia.lauar@quintoandar.com.br
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- lucas.polak@quintoandar.com.br

## Overview

**Offboard Human vs Digital Metrics** is the official metric family that measures how For Rent
offboarding terminations (TFs) are served — **digital** (no human ticket, no mediation, not SPOC),
**human support** (ticket or mediation, excluding SPOC), or **SPOC** — and how NPS varies across
the **digital** and **human-support** segments only. Metrics 1–3 count finished TFs by channel
share; metrics 4–5 report classic NPS (`(% promoters − % detractors) × 100`) on the
corresponding NPS-answer subsets; metrics 6–7 count the NPS response volumes that serve as
denominators.

These TF shares are the **population counterpart** to the offboarding NPS digital / human-support
cuts in this file — they measure how **big** each segment is, while the NPS metrics measure how
**satisfied** each segment is. (They are computed on different bases and grains, so the two will
not tie out one-to-one.)

**NPS geral (offboarding), NPS SPOC, and NPS não-SPOC / AS IS** are defined exclusively in
[`nps_fr.md`](nps_fr.md) (`sandbox.nps_fr`) — do not redefine or duplicate them here.

A naive approach — e.g. counting any Zendesk ticket on the contract, or pooling NPS answers
without the offboarding campaign filter and ticket/mediation classification — produces numbers
that do not match the Superset MBR dashboards.

**This metric family exists exclusively for For Rent offboarding (U&J / Seamless scope).**

## Changelog

- **2026-07-28** — Delegated NPS geral, SPOC, and não-SPOC to
  [`nps_fr.md`](nps_fr.md) (`sandbox.nps_fr`). Reduced metric set from 13 to 7 (TF shares 1–3;
  NPS digital / human support 4–5; response volumes 6–7). NPS golden queries now read answers
  from `sandbox.nps_fr` with `score_category`, aligned with NPS FR.
- **2026-07-22 (b)** — Replaced fixed `2025-04-01` lookback in golden queries with
  `lookback_start_date = DATE_ADD('month', -6, report_start_date)`, where `report_start_date` is
  the earliest date in the user's requested period. Added `params` / `bounds` CTEs; final SELECT
  filters on `[report_start_date, report_end_date)`.
- **2026-07-22 (a)** — Aligned Query 1 with Ops's current Superset SQL:
  removed `ROW_NUMBER` dedup on `fact_services` (join is 1:1 on `sk_support_session` with
  `is_current = TRUE`); dropped `'Reanálise de reparos [OFF] [POS] [BACK]'` from Salesforce
  queues (Ops comment: no human contact). Closed the `2025-10-01` scope open question — live
  query uses `2025-04-01`. Documented the 2026-06-25 front/back entity split and noted
  `encarteiramento_inteligente_model` as an Ops-only breakdown, outside metrics 1–7.
- **2026-07-21** — Fixed Query 1 (metrics 1–3): `fact_customer_contacts` has no `theme` or
  `dt_created` column. Both now come from `dw_support_journey.fact_services` (join key
  `sk_support_session`), matching Ops's live Superset query, plus the UTC→BRT (`-3h`) adjustment
  on `dt_created`. Verified against the reference dashboard for May–Jul 2026 (within ~0.02 p.p.).
  Also fixed Query 2: `dim_nps_answer` has no `score` column — the raw 0–10 score is
  `nps_answer`. See Nuances for details.

## Related Business Entities

- Termination
- NPS
- Ticket

## Related Metric Entities

- NPS FR (NPS geral offboarding, SPOC, não-SPOC / AS IS — source of truth for all offboarding NPS except digital / human-support cuts)

## Catalog

| Metric | Type |
| :---- | :---- |
| % de TFs digitais | OKR |
| % de TFs com suporte humano | Health Metric |
| % de TFs atendidas por SPOC | Health Metric |
| NPS human support (offboarding) | OKR |
| NPS digital (offboarding) | OKR |
| Qtd. respostas NPS human support | Health Metric |
| Qtd. respostas NPS digital | Health Metric |

## MBR

**Name** Post Contract
**Category** New Offboarding

## Glossary and Synonyms

- **% TFs digitais**, **% digital offboarding**, **TF digital share** → metric 1
- **% TFs com suporte humano**, **% human support offboarding**, **TF human support share** → metric 2
- **% TFs atendidas por SPOC**, **% SPOC offboarding**, **SPOC TF share** → metric 3
- **NPS human support (offboarding)**, **NPS suporte humano off** → metric 4
- **NPS digital (offboarding)**, **NPS digital off**, **NPS self-service off** → metric 5
- **Qtd. respostas NPS human support (offboarding)** → metric 6
- **Qtd. respostas NPS digital (offboarding)** → metric 7
- **TF**, **rescisão**, **termination** → one finished offboarding contract (`sk_contract`)
- **NPS geral (offboarding)**, **NPS SPOC**, **NPS não-SPOC / AS IS** → see [`nps_fr.md`](nps_fr.md) (not defined in this file)

## Scope

**Included**: finished For Rent offboarding terminations with `ts_termination_finished IS NOT NULL`
and `dim_contract.status = 'Finalizado'` (TF volume metrics 1–3); offboarding NPS responses
from **`sandbox.nps_fr`** (`campanha_nps = 'offboarding'`), matched to the termination timeline
(NPS metrics 4–7). Support classification uses tickets matched within the offboarding window
(`ts_termination_request` → `ts_termination_finished + 15 days`), by contract or by tenant/owner
when the contract key is unavailable. Ticket sources: legacy Zendesk contacts
(`dw_customer_support.fact_customer_contacts`, themed via `dw_support_journey.fact_services`
— see Nuances), `dw_bpo_performance.segments_perspective` (front), and Salesforce
`dw_bpo_performance.cases_perspective` offboarding queues.

**Excluded**: non-finished terminations (`ts_termination_finished IS NULL` or status ≠
`Finalizado`), terminations whose offboarding window falls entirely before the rolling lookback
(see Nuances → Rolling lookback window), and NPS campaigns outside the offboarding For Rent scope.

## Calculation

### Shared classification flags

On the **TF grain** (one row per `sk_contract` / `sk_termination`):

```
is_spoc              = COALESCE(fact_terminations.is_spoc_contract, FALSE)
is_mediacao          = COALESCE(obt_offboarding.has_mediation_ticket, FALSE)
has_ticket           = (tipo_ticket IS NOT NULL) OR is_mediacao
human_support_no_spoc = has_ticket AND NOT is_spoc
```

On the **NPS grain** (one row per `sk_nps_answer`), ticket/mediation flags are inherited from
the linked termination; SPOC exclusion uses `is_spoc_test` from `sandbox.nps_fr`. NPS is
computed from `score_category` (`promoter` / `passive` / `detractor`) — same engine as
[`nps_fr.md`](nps_fr.md).

### Metric 1 — % de TFs digitais

Pivot date: `ts_termination_finished`.

```
% TFs digitais = COUNT(DISTINCT CASE WHEN human_support_no_spoc = FALSE AND is_spoc = FALSE
                                      THEN sk_contract END)
               / COUNT(DISTINCT sk_contract)
```

### Metric 2 — % de TFs com suporte humano

Pivot date: `ts_termination_finished`.

```
% TFs human support = COUNT(DISTINCT CASE WHEN human_support_no_spoc = TRUE
                                           THEN sk_contract END)
                    / COUNT(DISTINCT sk_contract)
```

### Metric 3 — % de TFs atendidas por SPOC

Pivot date: `ts_termination_finished`.

```
% TFs SPOC = COUNT(DISTINCT CASE WHEN is_spoc = TRUE THEN sk_contract END)
           / COUNT(DISTINCT sk_contract)
```

### Metric 4 — NPS human support (offboarding)

Pivot date: `ts_response_nps` (= `sandbox.nps_fr.ts_answered`). Restricted to
`((tipo_ticket IS NOT NULL) OR (is_mediacao = TRUE)) AND is_spoc_test = FALSE`.

```
NPS human support = (
    COUNT(DISTINCT CASE WHEN score_category = 'promoter'
         AND ((tipo_ticket IS NOT NULL) OR (is_mediacao = TRUE)) AND is_spoc_test = FALSE
         THEN sk_nps_answer END)
  - COUNT(DISTINCT CASE WHEN score_category = 'detractor'
         AND ((tipo_ticket IS NOT NULL) OR (is_mediacao = TRUE)) AND is_spoc_test = FALSE
         THEN sk_nps_answer END)
) / CAST(COUNT(DISTINCT CASE WHEN ((tipo_ticket IS NOT NULL) OR (is_mediacao = TRUE))
                              AND is_spoc_test = FALSE THEN sk_nps_answer END) AS DOUBLE) * 100
```

### Metric 5 — NPS digital (offboarding)

Pivot date: `ts_response_nps`. Restricted to
`(tipo_ticket IS NULL) AND (is_mediacao = FALSE) AND (is_spoc_test = FALSE)`.

```
NPS digital = (
    COUNT(DISTINCT CASE WHEN score_category = 'promoter'
         AND (tipo_ticket IS NULL) AND (is_mediacao = FALSE) AND (is_spoc_test = FALSE)
         THEN sk_nps_answer END)
  - COUNT(DISTINCT CASE WHEN score_category = 'detractor'
         AND (tipo_ticket IS NULL) AND (is_mediacao = FALSE) AND (is_spoc_test = FALSE)
         THEN sk_nps_answer END)
) / CAST(COUNT(DISTINCT CASE WHEN (tipo_ticket IS NULL) AND (is_mediacao = FALSE)
                              AND (is_spoc_test = FALSE) THEN sk_nps_answer END) AS DOUBLE) * 100
```

### Metrics 6–7 — NPS response counts (offboarding)

Pivot date: `ts_response_nps`. Each metric is the denominator of the corresponding NPS metric:

| # | Metric | Formula |
|---|--------|---------|
| 6 | Qtd. respostas NPS human support | `COUNT(DISTINCT CASE WHEN ((tipo_ticket IS NOT NULL) OR (is_mediacao = TRUE)) AND is_spoc_test = FALSE THEN sk_nps_answer END)` |
| 7 | Qtd. respostas NPS digital | `COUNT(DISTINCT CASE WHEN (tipo_ticket IS NULL) AND (is_mediacao = FALSE) AND (is_spoc_test = FALSE) THEN sk_nps_answer END)` |

### Common time aggregations

- **Month**: `date_trunc('month', DATE(ts_termination_finished))` (metrics 1–3) or
  `date_trunc('month', DATE(ts_response_nps))` (metrics 4–7)
- **Week**: `date_trunc('week', DATE(...))` on the same pivot column
- **Day / quarter**: same pattern with `date_trunc('day', ...)` or `date_trunc('quarter', ...)`

### Canonical Filter

**Reporting period (user request)** — set `report_start_date` to the **earliest date** in the
analysis window the user asked for (on the pivot column: `ts_termination_finished` for metrics
1–3, `ts_response_nps` for metrics 4–7). Optionally set `report_end_date` for the upper bound.

**Rolling lookback (component CTEs)** — never hardcode a fixed historical cutoff. Derive the
lower bound for all upstream scans as **six months before** `report_start_date`:

```sql
lookback_start_date = DATE_ADD('month', -6, report_start_date)
```

Use `lookback_start_date` on `ts_termination_request`, ticket/contact timestamps, and
`ts_answered` when building the component CTEs. Filter the **final** result to
`[report_start_date, report_end_date)` on the pivot column.

**TF base** (`dw_offboarding.fact_terminations` + joins):

```sql
CAST(ft.ts_termination_request AS DATE) >= lookback_start_date
AND ft.ts_termination_finished IS NOT NULL
AND dc.status = 'Finalizado'
-- final output: DATE(ts_termination_finished) >= report_start_date
```

**NPS base** (`sandbox.nps_fr` — same source as [`nps_fr.md`](nps_fr.md)):

```sql
campanha_nps = 'offboarding'
AND CAST(ts_answered AS TIMESTAMP) >= lookback_start_date
-- final output: DATE(ts_response_nps) >= report_start_date
```

Use `COUNT(DISTINCT sk_nps_answer)` for all NPS counts — `sandbox.nps_fr` may fan out on wide
joins (see `nps_fr.md` → Golden Queries).

**Warning**: for NPS geral, SPOC, and não-SPOC / AS IS, use [`nps_fr.md`](nps_fr.md) — not this
file. Counting tickets without the offboarding time window or department filters inflates
human-support share.

### Nuances

**Rolling lookback window** — component CTEs (terminations, tickets, NPS answers) must scan from
`lookback_start_date = DATE_ADD('month', -6, report_start_date)`, where `report_start_date` is
the **minimum date** in the user's requested period. The six-month buffer covers offboarding
windows and ticket matching for terminations whose `ts_termination_finished` falls inside the
reporting range but whose `ts_termination_request` started earlier. Do **not** substitute a fixed
date such as `2025-04-01`.

**Offboarding window for ticket matching** — a ticket counts only when
`ts_ticket_started BETWEEN ts_termination_request AND ts_termination_finished + 15 days`.
Match by `sk_contract` when available; otherwise match by tenant or owner `sk_user`.

**SPOC flag** — `is_spoc = COALESCE(fact_terminations.is_spoc_contract, FALSE)`. SPOC
terminations are a separate bucket: they do not count as digital or human support, even if they
had support tickets.

**Human support ticket sources** — three unioned sources within the offboarding window:

| Source | Table | Key filter |
|--------|-------|------------|
| Legacy Zendesk contacts | `dw_customer_support.fact_customer_contacts`, themed via `dw_support_journey.fact_services` (join key `sk_support_session`; `fact_tickets`/`dim_taxonomy` as fallback theme when a `sk_ticket` is matched) | `department IN ('CX Rescisão [FRONT] [POS]', '[AeC] CX Rescisão [FRONT] [POS]')`, `is_last_interaction = TRUE`, channel `chat`/`call` |
| Front segments | `dw_bpo_performance.segments_perspective` | Offboarding front/back departments; `is_last_interaction = TRUE`, `is_answered = TRUE`, inbound or collections queues |
| Salesforce cases | `dw_bpo_performance.cases_perspective` | Offboarding `last_department` values (rescission, repairs, inspection, checkout, keys, bank data, etc.) — **excludes** `'Reanálise de reparos [OFF] [POS] [BACK]'` |

**Zendesk → Salesforce migration (`2026-06-25`)** — on **2026-06-25** offboarding support completed
the **full migration from Zendesk to Salesforce**. From that date onward, the trustworthy tables
for ticket classification are **`dw_bpo_performance.segments_perspective`** (front) and
**`dw_bpo_performance.cases_perspective`** (back) — use these as the authoritative sources for
contacts with `ts_ticket_started >= DATE '2026-06-25'`. For contacts **before** that date,
Salesforce tables are incomplete; you must still apply the **legacy Zendesk stack** above
(`fact_customer_contacts`, `fact_services`, `fact_tickets`/`dim_taxonomy` with the filters and
theming adjustments documented below) to capture pre-migration tickets with precision.

**Legacy Zendesk contact theming** — `fact_customer_contacts` itself has **no** `theme` or
`dt_created` column. The correct join brings both in from `dw_support_journey.fact_services`
(aliased `fs`) via `fcc.sk_support_session = fs.sk_support_session_varchar`, filtered to
`is_current = TRUE` rows only (no `ROW_NUMBER` dedup — Ops's live query relies on the
`is_current` flag to pick the active task per session). `fs.theme` / `fs.theme_detail` need
`SUBSTR(x, 3, LENGTH(x) - 4)` to strip bracket/quote wrapping. `dt_created` is
`DATE(fcc.ts_task_created - INTERVAL '3' HOUR)` (UTC→BRT adjustment — dropping this shifts
contacts across day/month boundaries near midnight). The `fact_tickets` + `dim_taxonomy`
subquery (`tp`) is still consulted first via `COALESCE(tp.theme, fs-derived theme)` when a
`sk_ticket` is matched; `fs` is the fallback (and primary source of `dt_created` when no ticket
matched).

**Schema note** — `dw_support_journey.fact_services.is_current` is a genuine `BOOLEAN` in Trino
even though DataHub's synced schema metadata reports every column on this table as `VARCHAR`;
compare with `TRUE`, not `'true'`.

**Known logic changes** — per Ops's Superset query comments:

- **2026-06-14** — ticket-classification tree aligned with
  `dw_bpo_performance."NPS Onboarding - new tree"`.
- **2026-06-25** — **complete Zendesk → Salesforce migration** for offboarding support (see
  Zendesk → Salesforce migration above): post-cutoff contacts rely on `segments_perspective` +
  `cases_perspective`; pre-cutoff contacts require the legacy Zendesk stack.

Historical DW tables may not fully backfill pre-migration Salesforce — flag inconsistencies
when analysing periods spanning `2026-06-25`.

**Salesforce queue exclusions** — `'Reanálise de reparos [OFF] [POS] [BACK]'` is explicitly
**out of scope** for human-support classification (Ops: no human contact on that queue).

**Out of scope for metrics 1–7** — This validation SQL also joins
`datalake_emlio_clean.emlio_logs` (`users-and-journeys-ml-service`) to label TFs as
`encarteiramento inteligente` vs `encarteiramento padrão`, and breaks down `has_repairs` by
segment. These are analysis dimensions only — they do not change the digital / human / SPOC
formulas.

**Mediation** — `is_mediacao = TRUE` from `obt_offboarding.has_mediation_ticket` classifies the
TF as human support even without a matched ticket.

**NPS-to-termination link** — NPS answers from `sandbox.nps_fr` join to terminations via
contract key when `sk_contract` is present, otherwise via `sk_user`. Only answers with
`ts_answered >= ts_termination_request` are kept.

| Column | Description |
| :---- | :---- |
| `sk_contract` | Contract grain for TF metrics; join key to terminations |
| `sk_nps_answer` | NPS answer grain (`sandbox.nps_fr`) |
| `ts_termination_finished` | Pivot date for TF volume metrics (1–3) |
| `ts_response_nps` | Pivot date for NPS metrics (4–7); equals `ts_answered` |
| `score_category` | `promoter` / `passive` / `detractor` — use for NPS calculation |
| `is_spoc_test` | SPOC flag from `sandbox.nps_fr` (excludes SPOC from digital / human NPS) |
| `is_spoc` | SPOC termination flag from `fact_terminations.is_spoc_contract` (TF metrics 1–3) |
| `tipo_ticket` | Non-NULL when a human-support ticket was matched in the offboarding window |
| `is_mediacao` | Mediation flag from `obt_offboarding.has_mediation_ticket` |
| `human_support_no_spoc` | Derived: `(tipo_ticket IS NOT NULL OR is_mediacao) AND NOT is_spoc` |

## Dos and Don'ts

**Do:**

- Use `ts_termination_finished` as the pivot for TF share metrics (1–3) and `ts_response_nps` for
  all NPS metrics (4–7)
- Set `report_start_date` to the user's earliest requested date and derive
  `lookback_start_date = DATE_ADD('month', -6, report_start_date)` for all component CTE scans
- Apply the full ticket-matching logic (three sources + offboarding window + mediation flag)
  before classifying digital vs human support
- Treat SPOC as its own segment — never fold SPOC TFs into digital or human support
- Read offboarding NPS answers from `sandbox.nps_fr` (`campanha_nps = 'offboarding'`) and classify
  by `score_category` — same engine as [`nps_fr.md`](nps_fr.md)
- Use `COUNT(DISTINCT sk_nps_answer)` for NPS numerators and denominators
- Delegate NPS geral, SPOC, and não-SPOC / AS IS to [`nps_fr.md`](nps_fr.md)

**Don't:**

- Don't redefine or compute NPS geral, NPS SPOC, or NPS não-SPOC / AS IS in this file — see
  [`nps_fr.md`](nps_fr.md)
- Don't hardcode a fixed lookback date (e.g. `2025-04-01`) — always compute it as six months
  before the user's `report_start_date`
- Don't query the Superset virtual datasets directly in golden queries — they are reference
  assets only; build from `sandbox.nps_fr` plus the ticket-classification CTEs documented here
- Don't count tickets outside the offboarding window (`ts_termination_request` to
  `ts_termination_finished + 15 days`)
- Don't include non-finished terminations in TF denominators
- Don't include `'Reanálise de reparos [OFF] [POS] [BACK]'` in Salesforce queue filters — Ops
  explicitly excludes it (no human contact)
- Don't apply `ROW_NUMBER` dedup on `fact_services` — the live query filters `is_current = TRUE`
  only
- Don't confuse this family with Journey PC (`metric_entities/journey_pc.md`) — Journey PC
  covers onboarding/ongoing only; this family covers offboarding only
- Don't confuse this family with [`nps_fr.md`](nps_fr.md) for overall offboarding NPS — that
  file is the source of truth for NPS geral, SPOC, and não-SPOC

## Golden Queries

The component CTEs below reproduce the logic behind the Superset reference datasets
`digital_vs_human_support_offboarding[For Rent][U&J]` and
`NPS_digital_vs_human_support_offboarding[For Rent][U&J]`. TF classification uses DW tables;
NPS answers are read from **`sandbox.nps_fr`** (same source as [`nps_fr.md`](nps_fr.md)). What is
exclusive to this metric family is the ticket-classification layer, the offboarding window,
the **rolling six-month lookback** (`lookback_start_date`), and the digital / human / SPOC
segmentation for TF shares and digital / human NPS cuts.

### Query 1 — TF volume shares (metrics 1–3)

Monthly digital, human-support, and SPOC shares of finished offboarding TFs.

Set `report_start_date` / `report_end_date` in `params` to the period the user asked for.
All upstream CTEs scan from `lookback_start_date` (six months earlier).

```sql
WITH params AS (
    -- Replace with the user's requested reporting window (pivot: ts_termination_finished).
    SELECT
        DATE '2026-01-01' AS report_start_date,
        DATE '2026-07-01' AS report_end_date
),
bounds AS (
    SELECT DATE_ADD('month', -6, report_start_date) AS lookback_start_date
    FROM params
),
terminator_enriched AS (
    SELECT
        ft.sk_termination,
        COALESCE(ft.is_spoc_contract, FALSE) AS is_spoc,
        dc.sk_contract,
        dc.status,
        CAST(fc.sk_tenant AS VARCHAR) AS sk_tenant,
        CAST(fc.sk_owner AS VARCHAR) AS sk_owner,
        ft.ts_termination_request AS ts_offboarding_start,
        ft.ts_termination_finished,
        COALESCE(obt.has_mediation_ticket, FALSE) AS is_mediacao
    FROM dw_offboarding.fact_terminations AS ft
    LEFT JOIN dw_rent.dim_contract AS dc
        ON ft.sk_contract = dc.sk_contract
    LEFT JOIN dw_rent.fact_contracts AS fc
        ON fc.sk_contract = dc.sk_contract
    LEFT JOIN dw_offboarding.obt_offboarding AS obt
        ON obt.sk_contract = dc.sk_contract
        AND obt.sk_termination = ft.sk_termination
    CROSS JOIN bounds AS b
    WHERE CAST(ft.ts_termination_request AS DATE) >= b.lookback_start_date
),
fact_service AS (
    -- Theme source for legacy Zendesk contacts (fact_customer_contacts has no theme column).
    SELECT
        fs.sk_support_session,
        CAST(fs.sk_support_session AS VARCHAR) AS sk_support_session_varchar,
        SUBSTR(fs.theme, 3, LENGTH(fs.theme) - 4) AS theme,
        SUBSTR(fs.theme_detail, 3, LENGTH(fs.theme_detail) - 4) AS theme_detail
    FROM dw_support_journey.fact_services AS fs
    CROSS JOIN bounds AS b
    WHERE CAST(fs.dt_task_created AS DATE) >= b.lookback_start_date
        AND fs.is_current = TRUE  -- BOOLEAN in Trino; DataHub reports this table's columns as VARCHAR
        AND fs.sk_support_session IS NOT NULL
        AND fs.sk_support_session != '-1'
),
customer_contacts AS (
    SELECT
        fcc.sk_ticket,
        fcc.sk_user,
        fcc.channel,
        dd.department,
        DATE(fcc.ts_task_created - INTERVAL '3' HOUR) AS dt_created,  -- UTC -> BRT
        fcc.is_last_interaction,
        fs.theme,
        fs.theme_detail
    FROM dw_customer_support.fact_customer_contacts AS fcc
    LEFT JOIN dw_customer_support.dim_department AS dd
        ON dd.sk_department = fcc.sk_department
    LEFT JOIN fact_service AS fs
        ON fcc.sk_support_session = fs.sk_support_session_varchar
    CROSS JOIN bounds AS b
    WHERE fcc.ts_task_created >= CAST(b.lookback_start_date AS TIMESTAMP)
        AND fcc.channel IN ('chat', 'call')
),
last_contacts AS (
    SELECT DISTINCT
        COALESCE(tp.sk_user, cc.sk_user) AS sk_user,
        COALESCE(tp.sk_contract, -1) AS sk_contract,
        cc.sk_ticket,
        COALESCE(tp.theme, cc.theme) AS theme,
        COALESCE(tp.dt_created, cc.dt_created) AS dt_created
    FROM customer_contacts AS cc
    CROSS JOIN bounds AS b
    LEFT JOIN (
        SELECT
            ft.sk_ticket,
            ft.sk_contract,
            dt.theme,
            ft.sk_user,
            DATE(ft.ts_created) AS dt_created
        FROM dw_customer_support.fact_tickets AS ft
        LEFT JOIN dw_customer_support.dim_taxonomy AS dt
            ON dt.sk_taxonomy = ft.sk_taxonomy
        CROSS JOIN bounds AS b2
        WHERE ft.sk_ticket IS NOT NULL
            AND ft.ts_created >= CAST(b2.lookback_start_date AS TIMESTAMP)
    ) AS tp
        ON tp.sk_ticket = cc.sk_ticket
        AND cc.sk_ticket > 0
    WHERE cc.dt_created >= b.lookback_start_date
        AND cc.is_last_interaction = TRUE
        AND cc.department IN (
            'CX Rescisão [FRONT] [POS]',
            '[AeC] CX Rescisão [FRONT] [POS]'
        )
),
front_tickets AS (
    SELECT
        CAST(sk_user AS VARCHAR) AS sk_user,
        dt_created AS ts_ticket_started,
        CAST(sk_ticket AS VARCHAR) AS sk_ticket,
        COALESCE(sk_contract, -1) AS sk_contract_ticket,
        theme AS tipo_ticket
    FROM last_contacts
),
front_tickets_segments AS (
    SELECT DISTINCT
        CAST(sp.sk_user AS VARCHAR) AS sk_user,
        sp.dt_created AS ts_ticket_started,
        CAST(sp.sk_ticket AS VARCHAR) AS sk_ticket,
        -1 AS sk_contract_ticket,
        sp.theme AS tipo_ticket
    FROM dw_bpo_performance.segments_perspective AS sp
    CROSS JOIN bounds AS b
    WHERE sp.dt_created >= b.lookback_start_date
        AND sp.department IN (
            '[AeC] CX Rescisão [FRONT] [POS]',
            'CX Atendimento Escalado Receptivo [OFF] [POS] [BACK]',
            'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
            'CX Rescisão [BACK] [POS]',
            'CX Rescisão [FRONT] [POS]'
        )
        AND sp.is_last_interaction = TRUE
        AND sp.is_answered = TRUE
        AND (
            sp.refined_direction = 'INBOUND'
            OR sp.department IN (
                'Cobrança Proprietários [COL] [POS] [BACK]',
                'Ops Cobrança [BACK] [POS]',
                'Ops Cobrança Onboarding'
            )
        )
        AND sp.sk_user > 0
),
salesforce_cases AS (
    SELECT DISTINCT
        cp.sk_user,
        cp.ts_started AS ts_ticket_started,
        CAST(cp.case_number AS VARCHAR) AS sk_ticket,
        COALESCE(TRY_CAST(cp.sk_contract AS BIGINT), -1) AS sk_contract_ticket,
        cp.theme AS tipo_ticket
    FROM dw_bpo_performance.cases_perspective AS cp
    CROSS JOIN bounds AS b
    WHERE cp.ts_started >= CAST(b.lookback_start_date AS TIMESTAMP)
        AND cp.last_department IN (
        'Offboarding Reparos [OFF] [POS] [BACK]',
        'Checkout Exp CRM [OFF][POS][BACK]',
        'Atendimento Escalado [OFF] [POS] [BACK]',
        'CX Rescisão e Vistoria [OFF] [POS] [FRONT]',
        'Rescisão por Inadimplência [OFF][POS][BACK]',
        '[Produto] Controle Offboarding',
        'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
        'CX Offboarding ETP 1 [BACK] [POS]',
        'Serv. Financeiros - Faturas Off [SO]',
        'Logística Chaves Offboarding [SO]',
        'Dados Bancários [OFF] [POS] [BACK]',
        'Prorrogação de prazo [OFF] [POS] [BACK]',
        'Backoffice Proprietários [COL] [BACK]',
        'Checkout Exp [OFF] [POS] [BACK]',
        'B2B Prime [OFF] [POS] [BACK]',
        'CX Atendimento Escalado Receptivo [OFF] [POS] [BACK]',
        'Agendamento de Vistoria RS [VT] [OFF] [RS]',
        -- 'Reanálise de reparos [OFF] [POS] [BACK]' excluded: no human contact (Ops)
        'Fluxo de Exceção - Constatação [OFF] [POS] [BACK]',
        'Vistorias - Reagendamento Off',
        'Offboarding - AEC',
        'Offboarding - CNX',
        'Logística de chaves - Offboarding',
        'Offboarding - Atento',
        'Offboarding - Dados Bancários',
        'Offboarding For Rent',
        'Offboarding - Finalização de contrato',
        'Serv. Financeiros - Tarefas Invisíveis Off [SO]',
        'Onboarding/Offboarding - Ajustes em Contas de Consumo',
        'AeC - CX Rescisão e Vistoria [OFF] [POS] [FRONT]',
        'Reversão de NPS [OFF] [POS] [BACK]',
        'CARTEIRA OFF CM [PAY] [POS] [BACK]',
        'Pré-Vistoria Offboarding [OFF] [PPM]',
        'RA Offboarding',
        'Collections Backoffice',
        'Collections Backoffice - Fila Temporária',
        'Collections Backoffice FPD e PP',
        'Collections Backoffice - Correções ou reembolso de contas e caução'
    )
),
tickets AS (
    SELECT sk_user, ts_ticket_started, sk_ticket, sk_contract_ticket, tipo_ticket
    FROM front_tickets_segments
    UNION ALL
    SELECT sk_user, ts_ticket_started, sk_ticket, sk_contract_ticket, tipo_ticket
    FROM salesforce_cases
    UNION ALL
    SELECT sk_user, ts_ticket_started, sk_ticket, sk_contract_ticket, tipo_ticket
    FROM front_tickets
),
matched_by_contract AS (
    SELECT
        te.*,
        t.sk_ticket,
        t.tipo_ticket
    FROM terminator_enriched AS te
    INNER JOIN tickets AS t
        ON te.sk_contract = t.sk_contract_ticket
        AND t.sk_contract_ticket != -1
        AND t.ts_ticket_started BETWEEN te.ts_offboarding_start
            AND DATE_ADD('day', 15, te.ts_termination_finished)
),
matched_by_user AS (
    SELECT DISTINCT
        te.*,
        t.sk_ticket,
        t.tipo_ticket
    FROM terminator_enriched AS te
    CROSS JOIN UNNEST(ARRAY[te.sk_tenant, te.sk_owner]) AS u(sk_user_key)
    INNER JOIN tickets AS t
        ON u.sk_user_key = t.sk_user
        AND t.sk_contract_ticket = -1
        AND t.ts_ticket_started BETWEEN te.ts_offboarding_start
            AND DATE_ADD('day', 15, te.ts_termination_finished)
),
terminator_with_tickets AS (
    SELECT * FROM matched_by_contract
    UNION ALL
    SELECT * FROM matched_by_user
    UNION ALL
    SELECT
        te.*,
        CAST(NULL AS VARCHAR) AS sk_ticket,
        CAST(NULL AS VARCHAR) AS tipo_ticket
    FROM terminator_enriched AS te
    WHERE te.sk_termination NOT IN (
        SELECT sk_termination FROM matched_by_contract
        UNION
        SELECT sk_termination FROM matched_by_user
    )
),
tf_base AS (
    SELECT
        sk_contract,
        sk_termination,
        MAX(ts_termination_finished) AS ts_termination_finished,
        MAX(ts_offboarding_start) AS ts_offboarding_start,
        MAX(sk_tenant) AS sk_tenant,
        MAX(sk_owner) AS sk_owner,
        MAX(is_spoc) AS is_spoc,
        MAX(is_mediacao) AS is_mediacao,
        MAX(tipo_ticket) AS tipo_ticket,
        MAX(
            CASE
                WHEN (tipo_ticket IS NOT NULL) OR is_mediacao THEN TRUE
                ELSE FALSE
            END
        ) AS has_ticket,
        MAX(
            CASE
                WHEN ((tipo_ticket IS NOT NULL) OR is_mediacao) AND NOT is_spoc THEN TRUE
                ELSE FALSE
            END
        ) AS human_support_no_spoc
    FROM terminator_with_tickets
    WHERE ts_termination_finished IS NOT NULL
        AND status = 'Finalizado'
    GROUP BY sk_contract, sk_termination
)
SELECT
    DATE_TRUNC('month', DATE(ts_termination_finished)) AS month_finished,
    CAST(
        COUNT(DISTINCT CASE
            WHEN human_support_no_spoc = FALSE AND is_spoc = FALSE THEN sk_contract
        END) AS DOUBLE
    ) / COUNT(DISTINCT sk_contract) AS pct_tfs_digital,
    CAST(
        COUNT(DISTINCT CASE
            WHEN human_support_no_spoc = TRUE THEN sk_contract
        END) AS DOUBLE
    ) / COUNT(DISTINCT sk_contract) AS pct_tfs_human_support,
    CAST(
        COUNT(DISTINCT CASE WHEN is_spoc = TRUE THEN sk_contract END) AS DOUBLE
    ) / COUNT(DISTINCT sk_contract) AS pct_tfs_spoc
FROM tf_base
CROSS JOIN params AS p
WHERE DATE(ts_termination_finished) >= p.report_start_date
    AND DATE(ts_termination_finished) < p.report_end_date
GROUP BY 1
ORDER BY 1
```

### Query 2 — NPS digital / human support and response volumes (metrics 4–7)

Monthly NPS for digital and human-support segments and corresponding response counts. **Prepend
`params`, `bounds`, and all CTEs from Query 1** (`terminator_enriched` through `tf_base`) before
the CTEs below. NPS answers come from `sandbox.nps_fr` — the same base as NPS geral in
[`nps_fr.md`](nps_fr.md).

```sql
-- Prepend params, bounds, and terminator_enriched → tf_base CTEs from Query 1.

WITH nps_answers AS (
    SELECT
        nfr.sk_nps_answer,
        CAST(nfr.sk_user AS VARCHAR) AS sk_user,
        nfr.sk_contract,
        nfr.score_category,
        nfr.is_spoc_test,
        CAST(nfr.ts_answered AS TIMESTAMP) AS ts_response_nps
    FROM sandbox.nps_fr AS nfr
    CROSS JOIN bounds AS b
    WHERE nfr.campanha_nps = 'offboarding'
        AND CAST(nfr.ts_answered AS TIMESTAMP) >= b.lookback_start_date
),
tf_expanded AS (
    SELECT
        tf.sk_contract,
        tf.is_mediacao,
        tf.tipo_ticket,
        tf.ts_offboarding_start,
        keys.match_key,
        keys.match_type
    FROM tf_base AS tf
    CROSS JOIN UNNEST(
        ARRAY[CAST(tf.sk_contract AS VARCHAR), tf.sk_tenant, tf.sk_owner],
        ARRAY['contract', 'user', 'user']
    ) AS keys(match_key, match_type)
    WHERE keys.match_key IS NOT NULL
),
nps_keyed AS (
    SELECT
        nps.sk_nps_answer,
        nps.score_category,
        nps.is_spoc_test,
        nps.ts_response_nps,
        CAST(nps.sk_contract AS VARCHAR) AS match_key,
        'contract' AS match_type
    FROM nps_answers AS nps
    WHERE nps.sk_contract IS NOT NULL
    UNION ALL
    SELECT
        nps.sk_nps_answer,
        nps.score_category,
        nps.is_spoc_test,
        nps.ts_response_nps,
        nps.sk_user AS match_key,
        'user' AS match_type
    FROM nps_answers AS nps
    WHERE nps.sk_contract IS NULL
),
nps_classified AS (
    SELECT
        nk.sk_nps_answer,
        MAX(nk.score_category) AS score_category,
        MAX(nk.is_spoc_test) AS is_spoc_test,
        MAX(nk.ts_response_nps) AS ts_response_nps,
        MAX(fe.tipo_ticket) AS tipo_ticket,
        MAX(fe.is_mediacao) AS is_mediacao
    FROM tf_expanded AS fe
    INNER JOIN nps_keyed AS nk
        ON fe.match_key = nk.match_key
        AND fe.match_type = nk.match_type
        AND nk.ts_response_nps >= fe.ts_offboarding_start
    GROUP BY nk.sk_nps_answer
)
SELECT
    DATE_TRUNC('month', DATE(ts_response_nps)) AS month_response,
    (
        (
            COUNT(DISTINCT CASE
                WHEN score_category = 'promoter'
                    AND ((tipo_ticket IS NOT NULL) OR (is_mediacao = TRUE))
                    AND is_spoc_test = FALSE
                THEN sk_nps_answer
            END)
            - COUNT(DISTINCT CASE
                WHEN score_category = 'detractor'
                    AND ((tipo_ticket IS NOT NULL) OR (is_mediacao = TRUE))
                    AND is_spoc_test = FALSE
                THEN sk_nps_answer
            END)
        ) / CAST(COUNT(DISTINCT CASE
            WHEN ((tipo_ticket IS NOT NULL) OR (is_mediacao = TRUE)) AND is_spoc_test = FALSE
            THEN sk_nps_answer
        END) AS DOUBLE)
    ) * 100 AS nps_human_support,
    (
        (
            COUNT(DISTINCT CASE
                WHEN score_category = 'promoter'
                    AND (tipo_ticket IS NULL) AND (is_mediacao = FALSE) AND (is_spoc_test = FALSE)
                THEN sk_nps_answer
            END)
            - COUNT(DISTINCT CASE
                WHEN score_category = 'detractor'
                    AND (tipo_ticket IS NULL) AND (is_mediacao = FALSE) AND (is_spoc_test = FALSE)
                THEN sk_nps_answer
            END)
        ) / CAST(COUNT(DISTINCT CASE
            WHEN (tipo_ticket IS NULL) AND (is_mediacao = FALSE) AND (is_spoc_test = FALSE)
            THEN sk_nps_answer
        END) AS DOUBLE)
    ) * 100 AS nps_digital,
    COUNT(DISTINCT CASE
        WHEN ((tipo_ticket IS NOT NULL) OR (is_mediacao = TRUE)) AND is_spoc_test = FALSE
        THEN sk_nps_answer
    END) AS qtd_respostas_human_support,
    COUNT(DISTINCT CASE
        WHEN (tipo_ticket IS NULL) AND (is_mediacao = FALSE) AND (is_spoc_test = FALSE)
        THEN sk_nps_answer
    END) AS qtd_respostas_digital
FROM nps_classified
CROSS JOIN params AS p
WHERE DATE(ts_response_nps) >= p.report_start_date
    AND DATE(ts_response_nps) < p.report_end_date
GROUP BY 1
ORDER BY 1
```

## Superset Golden Assets

These Superset virtual datasets are the **reference** for the official numbers. Do **not**
query them directly in golden queries — reproduce the logic from `sandbox.nps_fr` (NPS) and the
DW ticket-classification CTEs above (TF shares and digital / human segmentation).

- **digital_vs_human_support_offboarding[For Rent][U&J]** — reference dataset for TF volume
  metrics (1–3). Grain: one row per finished offboarding contract with `human_support_no_spoc`,
  `is_spoc`, `tipo_ticket`, `is_mediacao`, and `ts_termination_finished`.
- **NPS_digital_vs_human_support_offboarding[For Rent][U&J]** — reference dataset for NPS
  metrics (4–7). Grain: one row per NPS answer with segmentation flags. Superset id: 22972.
- **NPS For Rent Post Contract [Perf.] [Support and Services]** — canonical offboarding NPS base
  (NPS geral, SPOC, não-SPOC / AS IS). Materialized in **`sandbox.nps_fr`** (Superset id 16266).
  See [`nps_fr.md`](nps_fr.md).

