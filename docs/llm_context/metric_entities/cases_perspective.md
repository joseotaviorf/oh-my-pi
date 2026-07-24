# Cases Perspective (Post Contract Back)

## Ownership

**Data Owner:**

- [joao.mariani@quintoandar.com.br](mailto:joao.mariani@quintoandar.com.br)

**Data Steward:**

- [victor.prado@quintoandar.com.br](mailto:victor.prado@quintoandar.com.br)
- [alef.vieira@quintoandar.com.br](mailto:alef.vieira@quintoandar.com.br)
- [diego.carvalho@quintoandar.com.br](mailto:diego.carvalho@quintoandar.com.br)
- [romario.nascimento@quintoandar.com.br](mailto:romario.nascimento@quintoandar.com.br)

## Overview

**Cases Perspective** is the family of operational-performance metrics for the **Back Office**, built on `dw_bpo_performance.cases_perspective`. The source table carries **both** Front Office and Back Office cases, so every metric in this family must always apply `LOWER(front_or_back) = 'back'`.

This family is restricted to the official **Post Contract Back Office** scope. It excludes departments tied to service-line operations (repairs, mediation, inspections, reports, …) that are not in the official whitelist (`last_department`).

**Department-level scope is not the whole story.** Even after the `last_department` whitelist and the `front_or_back` / `channel` filters are applied, the resulting population still contains a small number of `last_team` values that are administratively Pre-Contract, Front Office, or otherwise out of scope for Post Contract Back reporting (their cases happen to be routed, at some point, through an in-scope department/queue). These `last_team` values must be excluded explicitly — see [Scope → Business context](#business-context-pre-contract-vs-post-contract-vs-other) and [Calculation → Canonical Filter](#canonical-filter). This exclusion was validated against the official Post Contract Back dashboard in **June–July 2026** and is now a **permanent, mandatory** part of the scope for **every** metric in this family (SLA Back, DSAT Back, Resolution Rate Back, Inbound Volume, Outbound Volume, DSAT Response Analysis) — not only for operation-level breakdowns.

The metrics covered by this document:

- SLA Back
- DSAT Back
- Resolution Rate Back
- Inbound Volume
- Outbound Volume
- DSAT Response Analysis
- Open, Created and Solved Case Analysis

## Related Business Entities

- Contact
- Ticket
- Satisfaction
- Department

## Glossary and Synonyms

- **SLA Back**, **Back SLA**, **percentage solved within SLA**, **SLA Back por time**, **SLA Back por operação**, **SLA Back by team**, **SLA Back by operation** → SLA Back; when broken down by operation, use `last_team_adjusted` (same field as DSAT Back and Resolution Rate Back — see [Derived operation mapping](#last_team_adjusted--official-post-contract-back-operation-mapping) and the "SLA Back by Operation" golden query)
- **DSAT Back**, **Dissatisfaction Rate Back**, **Back dissatisfaction rate** → DSAT Back
- **Resolution Rate Back**, **Back resolution rate**, **Resolution Rate Back por time**, **Resolution Rate Back por operação**, **Resolution Rate Back by team**, **Resolution Rate Back by operation** → Resolution Rate Back; when broken down by operation, use `last_team_adjusted` (same field as DSAT Back — see [Derived operation mapping](#last_team_adjusted--official-post-contract-back-operation-mapping) and the "Resolution Rate Back by Operation" golden query)
- **Inbound Volume**, **created volume**, **cases created during the period** → Inbound Volume
- **Outbound Volume**, **solved volume**, **cases solved during the period** → Outbound Volume
- **DSAT Analysis**, **CSAT comments**, **qualitative DSAT analysis** → DSAT Response Analysis
- **Operação**, **macro operação (Post Contract Back)**, **DSAT Back por time**, **DSAT Back por operação**, **DSAT Back by team**, **DSAT Back by operation** → breakdown by `last_team_adjusted` (see [Derived operation mapping](#last_team_adjusted--official-post-contract-back-operation-mapping))

## Scope

**Included**: cases from `dw_bpo_performance.cases_perspective` that meet **all** of the following, applied in this exact order — (1) the canonical Back filter (`front_or_back` + `channel`), (2) the official department whitelist (`last_department`), and (3) the mandatory `last_team` exclusion list. See [Canonical Filter](#canonical-filter) for the exact SQL.

**Excluded**:

- any case where `LOWER(front_or_back) <> 'back'`;
- any case where `channel <> 'email'`;
- any department outside the official whitelist;
- any of the six mandatory `last_team` exclusions (see below);
- service-line departments such as repairs, mediation, inspections and reports when they are outside the whitelist;
- records outside the user-requested period.

### Business context: Pre-Contract vs. Post-Contract vs. Other

This document reports only the **Post-Contract** stage of the customer journey — support given to a tenant/owner **after** a rental contract is active (onboarding into the contract, ongoing servicing, payments/bank-details maintenance, offboarding at the end of the contract). It deliberately excludes the **Pre-Contract** stage — support given **before** a contract exists (commercial proposals, deal/lease closing negotiations, dedicated account management during the sales funnel) — even when a Pre-Contract case happens to be routed through a `last_department` queue that carries a `[BACK]` tag in its name. **Department name tags are not a reliable classifier by themselves** — see [Name collisions](#name-collisions--read-carefully-before-writing-sql).

The `last_team` values below are Pre-Contract and must always be excluded from this metric family, regardless of which department they were logged under:

| `last_team` | Why it is excluded |
| :---- | :---- |
| `CX Expert` | Pre-Contract — dedicated/VIP account management before contract signing |
| `Propostas` | Pre-Contract — commercial proposal negotiation |
| `Closing` | Pre-Contract — deal/lease **closing** negotiation (the sales-funnel sense of "closing a deal", not "closing a support case") |
| `CX Partners` | Pre-Contract — real-estate partner relationship management before contract signing |

One additional `last_team` is excluded for a different reason — it is genuinely Front Office despite carrying `front_or_back = 'back'` in the data:

| `last_team` | Why it is excluded |
| :---- | :---- |
| `Payment FR - Dados Bancários Front` | Front Office team (organizational classification), independent of the `front_or_back` column value — see the note under [Canonical Filter](#canonical-filter) |

Finally, one `last_team` is excluded because it is **neither** Pre- nor Post-Contract — it is a different kind of operation altogether (classified as "Other" by the Data Steward), and reporting it inside Post Contract would overstate/understate the consolidated figure:

| `last_team` | Why it is excluded |
| :---- | :---- |
| `Payment FR - Condomínio Interno` | "Other" — not part of the official Post Contract Back operation taxonomy. **Do not confuse with `Payment FR - Condomínio Geral`, which IS in scope and belongs to Payments Ativo Back** — the two names differ only in the last word ("Interno" vs. "Geral") and are easy to swap by mistake |

### Temporal reference axis

Each metric has its own official temporal anchor — there is no single cutoff field for the whole table.

| Metric | Temporal anchor | Meaning |
| :---- | :---- | :---- |
| SLA Back | `CAST(ts_solved AS DATE)` | Date when the case was solved |
| DSAT Back | `CAST(first_csat_ts_response AS DATE)` | Date when the first CSAT response was submitted |
| Resolution Rate Back | `CAST(first_csat_ts_response AS DATE)` | Date of the customer survey response |
| Inbound Volume | `CAST(ts_started AS DATE)` | Date when the case was created |
| Outbound Volume | `CAST(ts_solved AS DATE)` | Date when the case was solved |
| DSAT Response Analysis | `CAST(first_csat_ts_response AS DATE)` | Default reference date for qualitative analysis |

**Never use `year`, `month` or `day` as the temporal reference for these metrics.**

## Calculation

This family covers seven metrics, each computed independently over the same canonical Back scope (see [Canonical Filter](#canonical-filter)).

### 1. SLA Back

SLA Back measures the percentage of Back Office cases solved within the official SLA.

```
SLA Back =
    COUNT(DISTINCT CASE WHEN is_ticket_solved_within_sla = TRUE THEN case_number END)
    / COUNT(DISTINCT case_number)
```

Computed from `is_ticket_solved_within_sla` and `case_number`, anchored on `ts_solved`. Apply `ts_solved IS NOT NULL` explicitly in addition to the temporal-window filter — an unsolved case has no `ts_solved` value and must not be counted in either the numerator or the denominator.

When presenting the result, also return whenever possible: Tickets/Cases SLA (`cases_within_sla`, the numerator), Total Tickets/Cases (`solved_cases`, the denominator), and SLA Back (the rate).

Never average previously calculated SLA Back percentages. Always recalculate the numerator and denominator from the underlying distinct cases — this applies both to the Post Contract consolidated row and to every `last_team_adjusted` operation row, exactly as required for DSAT Back and Resolution Rate Back. The Post Contract row must be computed directly over the full scoped population, never as an average (simple or weighted) of the operation rows.

> **Do not use `first_csat_ts_response`, `first_csat_score`, or `resolution_survey` for this metric.** SLA Back is computed entirely from `is_ticket_solved_within_sla` and `case_number`, anchored on `ts_solved` — it has no dependency on the CSAT survey or the resolution survey. Validated on the Aug/2025–Jul/2026 dataset: `is_ticket_solved_within_sla` has zero nulls in every month for the in-scope population, so there is no historical-coverage gap to account for on this column.

### 2. DSAT Back

DSAT Back measures the percentage of evaluated cases with CSAT score 1 or 2.

```
DSAT Back =
    COUNT(DISTINCT CASE WHEN first_csat_score IN (1, 2) THEN case_number END)
    / COUNT(DISTINCT CASE WHEN first_csat_score IS NOT NULL THEN case_number END)
```

Anchored on `first_csat_ts_response`. When presenting the result, also return whenever possible: DSAT cases, answered evaluations, and the DSAT rate.

Never average previously calculated DSAT percentages. Always recalculate the numerator and denominator from the underlying distinct cases — this applies both to the Post Contract consolidated row and to every `last_team_adjusted` operation row. The Post Contract row must be computed directly over the full scoped population, never as an average (simple or weighted) of the operation rows.

### 3. Resolution Rate Back

Resolution Rate Back measures the percentage of customers who reported that their issue was resolved.

```
Resolution Rate Back =
    COUNT(DISTINCT CASE WHEN resolution_survey = TRUE THEN case_number END)
    / COUNT(DISTINCT CASE WHEN resolution_survey IS NOT NULL THEN case_number END)
```

Anchored on `first_csat_ts_response`. When presenting the result, also return whenever possible: Resolution Tickets/Cases (the numerator), Respostas Resolution / answered resolution surveys (the denominator), and Resolution Rate Back (the rate).

Never average previously calculated Resolution Rate percentages. Always recalculate the numerator and denominator from the underlying distinct cases — this applies both to the Post Contract consolidated row and to every `last_team_adjusted` operation row, exactly as required for DSAT Back.

> **`first_csat_score` must never be used for this metric.** Resolution Rate Back is answered independently of the CSAT score question — a case can have `resolution_survey IS NOT NULL` with `first_csat_score IS NULL`, and vice versa. Do not add `AND first_csat_score IS NOT NULL` (or any other `first_csat_score` condition) to the numerator, the denominator, or the `WHERE` clause of a Resolution Rate Back query — doing so silently shrinks the denominator and produces a different (incorrect) rate. `first_csat_ts_response` is still the correct temporal anchor (it dates when the survey was answered) — only the score column, not the timestamp column, is off-limits here.

### 4. Inbound Volume

Inbound Volume is the total number of distinct cases created during the selected period.

```
Inbound Volume = COUNT(DISTINCT case_number)
```

Anchored on `ts_started`.

### 5. Outbound Volume

Outbound Volume is the total number of distinct cases solved during the selected period.

```
Outbound Volume = COUNT(DISTINCT case_number)
```

Anchored on `ts_solved`.

Inbound Volume and Outbound Volume use the same aggregation formula, but they must not be treated as the same metric because they use different temporal anchors.

### 6. DSAT Response Analysis

DSAT Response Analysis is a qualitative, record-level view based on `first_csat_comment`. This is **not** a ratio metric. When requested, return at least: `case_number`, `first_csat_ts_response`, `first_csat_score`, `first_csat_comment`, `last_department`, `last_team`, `last_agent_organization`, `platform`.

### 7. Created, Solved and Open Case Analysis

```
Created = COUNT(DISTINCT case_number) WHERE ts_started BETWEEN <start_date> AND <end_date>

Solved = COUNT(DISTINCT case_number)
         WHERE ts_solved IS NOT NULL AND ts_solved BETWEEN <start_date> AND <end_date>

Open at cutoff date = COUNT(DISTINCT case_number)
                       WHERE ts_started <= <cutoff_date>
                         AND (ts_solved IS NULL OR ts_solved > <cutoff_date>)
```

Created and Solved are flow metrics. Open is a **stock** metric and must be calculated using a cutoff date.

### Canonical Filter

Apply on `dw_bpo_performance.cases_perspective` (alias `cp`), in this exact order.

**1. Canonical Back filter:**

```sql
LOWER(cp.front_or_back) = 'back'
AND cp.channel = 'email'
```

**2. Department whitelist** (`last_department`) — unchanged by this revision, the gap addressed below is entirely at the `last_team` grain:

```sql
cp.last_department IN (
    'CX Partners Tarefas [PRE] [BACK]',
    'CX Propostas Tarefas [PRE] [BACK]',
    'Aditivos [REP] [POS] [BACK]',
    'Entrada no imóvel [ONB] [POS] [BACK]',
    'CX Pagamentos Ativo [POS] [BACK] [PAY]',
    'Alteração de dados bancários [BACK]',
    'Atendimento Escalado [OFF] [POS] [BACK]',
    'CX Rescisão [FRONT] [POS]',
    'Rescisão por Inadimplência [OFF][POS][BACK]',
    'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
    'Offboarding pré saída [OFF] [POS] [BACK]',
    'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
    'FUP Carteirização B2C [CLO] [PRE] [BACK]',
    'EARLY DEMAND [CLOSING] [BACK]',
    'Closing PP Multi [CLO] [PRE] [BACK]',
    'CX Expert [BACK] [KA]',
    'CX PP Multi Diamond [POS] [BACK]',
    'Concierge PP Multi [PRE] [POS] [ESC]',
    'Ongoing Back',
    'Aditivos [POS] [BACK] [WH]',
    'Onboarding Back',
    'Condo Garantido [ONB] [POS] [BACK]',
    'Onboarding ForRent',
    'Ongoing FR - Geral',
    'Ongoing FR - Informe de Rendimentos',
    'Payment FR - Aluguel',
    'Payment FR - Dados Bancários',
    'Payment FR - Condomínio Geral',
    'Payment FR - Reembolso de Condomínio',
    'Payment FR - Condomínio Interno',
    'Payment_FR_GeneralCondominium',
    'Payment FR - PP Multi',
    'Payment FR - Dados Bancários Front',
    'Offboarding - AEC',
    'Offboarding - CNX',
    'Offboarding - Atento'
)
```

**3. Team-level exclusions (MANDATORY — new in this revision).** Apply this to **every** metric in this family, regardless of whether the result will be broken down by operation or reported only as the Post Contract consolidated figure — it changes the Post Contract numerator and denominator themselves, it is not an optional/cosmetic filter for the breakdown table:

```sql
AND cp.last_team NOT IN (
    'CX Expert',                            -- Pre-Contract
    'Propostas',                            -- Pre-Contract
    'Closing',                              -- Pre-Contract
    'CX Partners',                          -- Pre-Contract
    'Payment FR - Dados Bancários Front',   -- Front Office (see note below)
    'Payment FR - Condomínio Interno'       -- Other (neither Pre- nor Post-Contract)
)
```

**Note on `Payment FR - Dados Bancários Front`**: validated on the July/2026 dataset — 100% of its cases in scope carry `front_or_back = 'back'` (no data quality bug; `LOWER(front_or_back) = 'back'` behaves correctly). The word "Front" in the team name is legacy/organizational naming, not a reflection of the `front_or_back` flag. **Exclude this team regardless of the value of `front_or_back`** — this is a business-rule override validated against the official dashboard, not a data correction. If a future data refresh shows this team with `front_or_back` values other than `'back'`, the exclusion still applies unconditionally.

### Name collisions — read carefully before writing SQL

The following `last_team` names are easy to confuse with each other or with unrelated fields. Misreading any of these is the single most common source of an incorrect Post Contract Back number:

- **`Payment FR - Condomínio Interno`** (excluded, "Other") **vs. `Payment FR - Condomínio Geral`** (in scope, part of Payments Ativo Back). Only one word differs — double-check which one you are filtering/grouping.
- **`Payments`** (generic, maps to Dados Bancários) **vs. `Payments Ativo Back`** (its own operation). Despite the similar name, the generic `Payments` team is **not** part of Payments Ativo Back — it is historically the same underlying operation as `Payment FR - Dados Bancários`, and both are reported together as Dados Bancários. This is a naming legacy, not a logical relationship you can infer from the strings alone — follow the `last_team_adjusted` mapping exactly.
- **`Closing`** (excluded, Pre-Contract "deal closing") — does not mean "case closed/resolved". It is the name of the Pre-Contract negotiation team.
- **`Offboarding - AEC` / `Offboarding - Atento` / `Offboarding - CNX`** are `last_team` values (BPO-specific Offboarding queues), not `last_agent_organization` values, even though the suffix looks like a vendor/BPO name. Group them under Offboarding Back via `last_team_adjusted` — do not attempt to derive them from `last_agent_organization`.
- **The Dados Bancários operation label** (derived, `last_team_adjusted`) **vs. the `Alteração de dados bancários [BACK]` department** (`last_department`). They are different fields describing different things, only related in that both happen to be part of the same official scope — do not assume one implies the other.

### `last_team_adjusted` — official Post Contract Back operation mapping

Apply this **only after** the Canonical Filter above has already been applied. This mapping is the authoritative operation breakdown for DSAT Back, SLA Back, Resolution Rate Back, Inbound Volume and Outbound Volume, and was validated against the official Post Contract Back dashboard for **Aug/2025–Jul/2026**:

```sql
CASE
    WHEN last_team IN (
        'Offboarding Back', 'Offboarding - AEC', 'Offboarding - Atento', 'Offboarding - CNX'
    ) THEN 'Offboarding Back'
    WHEN last_team IN (
        'Onboarding Back', 'Onboarding ForRent'
    ) THEN 'Onboarding Back'
    WHEN last_team IN (
        'Ongoing Back', 'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos'
    ) THEN 'Ongoing Back'
    WHEN last_team IN (
        'Payments Ativo Back', 'Payment FR - Aluguel', 'Payment FR - Condomínio Geral',
        'Payment FR - Reembolso de Condomínio', 'Payment FR - PP Multi'
    ) THEN 'Payments Ativo Back'
    WHEN last_team IN (
        'Payments', 'Payment FR - Dados Bancários'
    ) THEN 'Dados Bancários'
    ELSE last_team
END AS last_team_adjusted
```

Do **not** include `Payment FR - Dados Bancários` in Payments Ativo Back — it belongs to Dados Bancários, a validated, separate operation. The six `last_team` values excluded by the Canonical Filter (`CX Expert`, `Propostas`, `Closing`, `CX Partners`, `Payment FR - Dados Bancários Front`, `Payment FR - Condomínio Interno`) must never reach this `CASE` — they are removed by the `WHERE` clause beforehand, not mapped to any operation here.

**Unvalidated legacy alias — `Payments - DB`**: appears in the department whitelist / in the legacy `team_adjusted` mapping (see below) but was **not observed** as a `last_team` value in the Aug/2025–Jul/2026 data used for validation. If it appears in a future refresh, confirm with the Data Steward before assuming it maps to Dados Bancários — do not guess.

**Unvalidated legacy alias — `Payment_FR_GeneralCondominium`**: observed as a `last_team` value in the Aug/2025–Jul/2026 data (exactly 1 case, `ts_solved` in May/2026, 100% within SLA) during the Outbound Volume and SLA Back validation passes. It is **not** included in this `CASE` mapping — it falls through to `ELSE last_team` and is reported under its own literal name, not folded into Payments Ativo Back or Dados Bancários, despite the name's apparent similarity to `Payment FR - Condomínio Geral`. See [Open decision](#open-decision--payment_fr_generalcondominium) below.

**`team_adjusted` is prohibited for this metric family.** The legacy `team_adjusted` mapping (used elsewhere, including a differently-defined `last_team_adjusted` macro-categorization for the *Front Office* family documented in `customer_contacts_front.md`, which is a distinct table and a distinct mapping) must **not** be used for any Post Contract Back metric or operation breakdown described in this document — for SLA Back, DSAT Back, Resolution Rate Back, Inbound Volume, Outbound Volume, or any Post Contract Back operation breakdown. It may exist in other dashboards or domains, but it is documented here only to prevent accidental use. Do not recreate, infer, or apply `team_adjusted` for this family — use the validated `last_team_adjusted` mapping above instead.

### Open decision — `Payment_FR_GeneralCondominium`

The value `Payment_FR_GeneralCondominium` was observed as a `last_team` value during validation, with exactly one solved case in May/2026. Its official operation classification has **not yet been confirmed** by the Data Steward. Until a formal decision is provided:

- do not map it to Payments Ativo Back by inference;
- do not map it to Dados Bancários by inference;
- do not exclude it by inference;
- preserve its original `last_team` value through the `ELSE last_team` branch;
- report it separately whenever it appears in a result;
- flag its presence in validation or auditing responses.

Once the Data Steward confirms the official treatment, update: (1) the `last_team_adjusted` mapping, (2) all operation-level golden queries, (3) this section, (4) the validation status.

### Supported Breakdowns

| Dimension | Field |
| :---- | :---- |
| Date | Metric-specific temporal anchor |
| Department | `last_department` |
| Detailed team | `last_team` |
| **Operation (Post Contract Back, validated)** | **`last_team_adjusted`** |
| Macro operation (other domains, not this family) | `team_adjusted` |
| BPO | `last_agent_organization` |
| Platform | `platform` |
| PP Multi | `is_pp_multi` |
| Agent | `last_agent_email` |
| Theme | `theme` |
| Theme detail | `theme_detail` |

Apply all requested filters before calculating the metric numerator and denominator. When the breakdown is "by operation" / "por operação" / "por time" for this metric family, use `last_team_adjusted`, computed strictly after the Canonical Filter — **not** `last_team` and **not** `team_adjusted`.

**Join key**: none — every metric is computed from a single table, `dw_bpo_performance.cases_perspective`, at the `case_number` grain.

**Fallback**: not applicable — there is no external parameter table to fall back to.

## Dos and Don'ts

**Do:**

- Always apply `LOWER(front_or_back) = 'back'`.
- Always apply `channel = 'email'`.
- Always apply the official department whitelist.
- Always apply the mandatory `last_team` exclusion list, even when no operation breakdown is requested — it affects the Post Contract consolidated numerator and denominator directly.
- Use `COUNT(DISTINCT case_number)` in all case-based numerators and denominators.
- Use the metric-specific temporal anchor.
- Use `last_team_adjusted` (not `last_team`, not `team_adjusted`) for official Post Contract Back operation breakdowns.
- Apply the requested filters before calculating numerator and denominator.
- Show both numerator and denominator when presenting rate metrics whenever possible.
- Return the SQL query used when the user requests validation or auditing.
- Recompute the Post Contract row directly over the full scoped population; never average the operation-level rates (simple or weighted).

**Don't:**

- Don't include Front Office cases.
- Don't include chat or call records in the official metric family.
- Don't include departments outside the official whitelist.
- Don't include `Closing`, `CX Partners`, `CX Expert`, or `Propostas` — they are Pre-Contract and must be excluded from the scope entirely, not just left unlabeled in a breakdown.
- Don't include `Payment FR - Dados Bancários Front` — exclude it unconditionally, even if its `front_or_back` value reads `'back'`.
- Don't include `Payment FR - Condomínio Interno` — it is neither Pre- nor Post-Contract for this metric family and must be excluded.
- Don't group `Payment FR - Dados Bancários` into Payments Ativo Back — it belongs to the separate Dados Bancários operation.
- Don't use `first_csat_score` anywhere in a Resolution Rate Back calculation (numerator, denominator, or `WHERE` clause) and don't require it to be filled — `resolution_survey` is answered independently of the CSAT score question.
- Don't use `first_csat_ts_response`, `first_csat_score`, or `resolution_survey` anywhere in a SLA Back calculation — it is computed entirely from `is_ticket_solved_within_sla`, anchored on `ts_solved`. Don't omit `WHERE ts_solved IS NOT NULL` — an unsolved case has no `ts_solved` and must be excluded from both numerator and denominator.
- Don't replace a missing SLA Back cell with 0% without first checking whether `is_ticket_solved_within_sla` has real historical coverage for that month/operation — validated as 100% populated (zero nulls) for Aug/2025–Jul/2026 in the in-scope population, so an empty cell in that window should be treated as a query or scope error, not assumed to be a real zero.
- Don't use `team_adjusted` for this metric family's operation breakdowns — use `last_team_adjusted`.
- Don't use `year`, `month` or `day` as the metric date.
- Don't average percentages across teams, periods or BPOs.
- Don't replace `COUNT(DISTINCT case_number)` with row counts.
- Don't apply a rolling 12-month period unless explicitly requested.
- Don't apply a result limit to metric calculations.
- Don't use the text inside department brackets as the sole source of truth for classification.

## Golden Queries

All queries apply the Canonical Filter documented above; what differs per query is the aggregation layer (consolidated vs. by `last_team_adjusted`) and the metric-specific temporal anchor. Trino dialect.

### Query 1 — DSAT Back and Resolution Rate Back (Post Contract consolidated)

```sql
SELECT
    DATE_TRUNC('month', CAST(cp.first_csat_ts_response AS DATE)) AS ref_month,
    COUNT(DISTINCT CASE WHEN cp.first_csat_score IN (1, 2) THEN cp.case_number END) AS dsat_cases,
    COUNT(DISTINCT CASE WHEN cp.first_csat_score IS NOT NULL THEN cp.case_number END) AS answered_evaluations,
    CAST(COUNT(DISTINCT CASE WHEN cp.first_csat_score IN (1, 2) THEN cp.case_number END) AS DOUBLE)
        / NULLIF(CAST(COUNT(DISTINCT CASE WHEN cp.first_csat_score IS NOT NULL THEN cp.case_number END) AS DOUBLE), 0) AS dsat_back,
    COUNT(DISTINCT CASE WHEN cp.resolution_survey = TRUE THEN cp.case_number END) AS resolution_cases,
    COUNT(DISTINCT CASE WHEN cp.resolution_survey IS NOT NULL THEN cp.case_number END) AS answered_resolution_surveys,
    CAST(COUNT(DISTINCT CASE WHEN cp.resolution_survey = TRUE THEN cp.case_number END) AS DOUBLE)
        / NULLIF(CAST(COUNT(DISTINCT CASE WHEN cp.resolution_survey IS NOT NULL THEN cp.case_number END) AS DOUBLE), 0) AS resolution_rate_back
FROM dw_bpo_performance.cases_perspective AS cp
WHERE (LOWER(cp.front_or_back) = 'back' OR cp.front_or_back IS NULL)
    AND cp.channel = 'email'
    AND cp.first_csat_ts_response >= DATE('<start_date>')
    AND cp.first_csat_ts_response < DATE('<end_date>') + INTERVAL '1' DAY
    AND cp.last_department IN (
        'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
        'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
        'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
        'Atendimento Escalado [OFF] [POS] [BACK]', 'CX Rescisão [FRONT] [POS]',
        'Rescisão por Inadimplência [OFF][POS][BACK]', 'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
        'Offboarding pré saída [OFF] [POS] [BACK]', 'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
        'FUP Carteirização B2C [CLO] [PRE] [BACK]', 'EARLY DEMAND [CLOSING] [BACK]',
        'Closing PP Multi [CLO] [PRE] [BACK]', 'CX Expert [BACK] [KA]',
        'CX PP Multi Diamond [POS] [BACK]', 'Concierge PP Multi [PRE] [POS] [ESC]',
        'Ongoing Back', 'Aditivos [POS] [BACK] [WH]', 'Onboarding Back',
        'Condo Garantido [ONB] [POS] [BACK]', 'Onboarding ForRent', 'Ongoing FR - Geral',
        'Ongoing FR - Informe de Rendimentos', 'Payment FR - Aluguel', 'Payment FR - Dados Bancários',
        'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio',
        'Payment FR - Condomínio Interno', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
        'Payment FR - Dados Bancários Front', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding - Atento'
    )
    AND cp.last_team NOT IN (
        'CX Expert', 'Propostas', 'Closing', 'CX Partners',
        'Payment FR - Dados Bancários Front', 'Payment FR - Condomínio Interno'
    )
GROUP BY 1
ORDER BY 1
```

### Query 2 — DSAT Back by Operation (`last_team_adjusted`) with Post Contract consolidated row

Only `<start_date>` and `<end_date>` should be changed to reproduce this query for a different period. `tt.total_answered > 0` hides an operation **only** if it had zero answered evaluations across the **entire** requested period (not per month) — a display convenience to avoid listing an all-"-" operation row; it never affects the Post Contract consolidated row, which is always computed from `consolidated_month`. Sort each operation's monthly values into a matrix (operations as rows, months as columns) and render an `answered_evaluations = 0` month as "-" instead of "0.0%" when presenting the result.

```sql
WITH scoped AS (
    SELECT
        cp.case_number,
        cp.last_team,
        CASE
            WHEN cp.last_team IN (
                'Offboarding Back', 'Offboarding - AEC', 'Offboarding - Atento', 'Offboarding - CNX'
            ) THEN 'Offboarding Back'
            WHEN cp.last_team IN (
                'Onboarding Back', 'Onboarding ForRent'
            ) THEN 'Onboarding Back'
            WHEN cp.last_team IN (
                'Ongoing Back', 'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos'
            ) THEN 'Ongoing Back'
            WHEN cp.last_team IN (
                'Payments Ativo Back', 'Payment FR - Aluguel', 'Payment FR - Condomínio Geral',
                'Payment FR - Reembolso de Condomínio', 'Payment FR - PP Multi'
            ) THEN 'Payments Ativo Back'
            WHEN cp.last_team IN (
                'Payments', 'Payment FR - Dados Bancários'
            ) THEN 'Dados Bancários'
            ELSE cp.last_team
        END AS last_team_adjusted,
        cp.first_csat_score,
        DATE_TRUNC('month', CAST(cp.first_csat_ts_response AS DATE)) AS ref_month
    FROM dw_bpo_performance.cases_perspective AS cp
    WHERE (LOWER(cp.front_or_back) = 'back' OR cp.front_or_back IS NULL)
        AND cp.channel = 'email'
        AND cp.first_csat_ts_response >= DATE('<start_date>')
        AND cp.first_csat_ts_response < DATE('<end_date>') + INTERVAL '1' DAY
        AND cp.last_department IN (
            'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
            'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
            'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
            'Atendimento Escalado [OFF] [POS] [BACK]', 'CX Rescisão [FRONT] [POS]',
            'Rescisão por Inadimplência [OFF][POS][BACK]', 'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
            'Offboarding pré saída [OFF] [POS] [BACK]', 'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
            'FUP Carteirização B2C [CLO] [PRE] [BACK]', 'EARLY DEMAND [CLOSING] [BACK]',
            'Closing PP Multi [CLO] [PRE] [BACK]', 'CX Expert [BACK] [KA]',
            'CX PP Multi Diamond [POS] [BACK]', 'Concierge PP Multi [PRE] [POS] [ESC]',
            'Ongoing Back', 'Aditivos [POS] [BACK] [WH]', 'Onboarding Back',
            'Condo Garantido [ONB] [POS] [BACK]', 'Onboarding ForRent', 'Ongoing FR - Geral',
            'Ongoing FR - Informe de Rendimentos', 'Payment FR - Aluguel', 'Payment FR - Dados Bancários',
            'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio',
            'Payment FR - Condomínio Interno', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
            'Payment FR - Dados Bancários Front', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding - Atento'
        )
        AND cp.last_team NOT IN (
            'CX Expert', 'Propostas', 'Closing', 'CX Partners',
            'Payment FR - Dados Bancários Front', 'Payment FR - Condomínio Interno'
        )
),
adj_team_month AS (
    SELECT
        last_team_adjusted, ref_month,
        COUNT(DISTINCT CASE WHEN first_csat_score IN (1, 2) THEN case_number END) AS dsat_cases,
        COUNT(DISTINCT CASE WHEN first_csat_score IS NOT NULL THEN case_number END) AS answered_evaluations
    FROM scoped
    GROUP BY last_team_adjusted, ref_month
),
adj_team_totals AS (
    SELECT last_team_adjusted, SUM(answered_evaluations) AS total_answered
    FROM adj_team_month
    GROUP BY last_team_adjusted
),
consolidated_month AS (
    SELECT
        'Post Contract' AS last_team_adjusted, ref_month,
        COUNT(DISTINCT CASE WHEN first_csat_score IN (1, 2) THEN case_number END) AS dsat_cases,
        COUNT(DISTINCT CASE WHEN first_csat_score IS NOT NULL THEN case_number END) AS answered_evaluations
    FROM scoped
    GROUP BY ref_month
)
SELECT
    0 AS team_order, cm.last_team_adjusted, cm.ref_month, cm.dsat_cases, cm.answered_evaluations,
    CAST(NULL AS BIGINT) AS total_answered
FROM consolidated_month cm
UNION ALL
SELECT
    1 AS team_order, tm.last_team_adjusted, tm.ref_month, tm.dsat_cases, tm.answered_evaluations, tt.total_answered
FROM adj_team_month tm
JOIN adj_team_totals tt ON tt.last_team_adjusted = tm.last_team_adjusted
WHERE tt.total_answered > 0
ORDER BY team_order, total_answered DESC, last_team_adjusted, ref_month
```

### Query 3 — Resolution Rate Back by Operation (`last_team_adjusted`) with Post Contract consolidated row

Same structure as Query 2. This query intentionally does **not** select or filter on `first_csat_score` anywhere — see [Calculation → Resolution Rate Back](#3-resolution-rate-back) and Dos and Don'ts. `tt.total_answered > 0` is the same per-period (not per-month) display convenience as Query 2 and never affects the consolidated row.

```sql
WITH scoped AS (
    SELECT
        cp.case_number,
        cp.last_team,
        CASE
            WHEN cp.last_team IN (
                'Offboarding Back', 'Offboarding - AEC', 'Offboarding - Atento', 'Offboarding - CNX'
            ) THEN 'Offboarding Back'
            WHEN cp.last_team IN (
                'Onboarding Back', 'Onboarding ForRent'
            ) THEN 'Onboarding Back'
            WHEN cp.last_team IN (
                'Ongoing Back', 'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos'
            ) THEN 'Ongoing Back'
            WHEN cp.last_team IN (
                'Payments Ativo Back', 'Payment FR - Aluguel', 'Payment FR - Condomínio Geral',
                'Payment FR - Reembolso de Condomínio', 'Payment FR - PP Multi'
            ) THEN 'Payments Ativo Back'
            WHEN cp.last_team IN (
                'Payments', 'Payment FR - Dados Bancários'
            ) THEN 'Dados Bancários'
            ELSE cp.last_team
        END AS last_team_adjusted,
        cp.resolution_survey,
        DATE_TRUNC('month', CAST(cp.first_csat_ts_response AS DATE)) AS ref_month
    FROM dw_bpo_performance.cases_perspective AS cp
    WHERE (LOWER(cp.front_or_back) = 'back' OR cp.front_or_back IS NULL)
        AND cp.channel = 'email'
        AND cp.first_csat_ts_response >= DATE('<start_date>')
        AND cp.first_csat_ts_response < DATE('<end_date>') + INTERVAL '1' DAY
        AND cp.last_department IN (
            'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
            'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
            'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
            'Atendimento Escalado [OFF] [POS] [BACK]', 'CX Rescisão [FRONT] [POS]',
            'Rescisão por Inadimplência [OFF][POS][BACK]', 'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
            'Offboarding pré saída [OFF] [POS] [BACK]', 'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
            'FUP Carteirização B2C [CLO] [PRE] [BACK]', 'EARLY DEMAND [CLOSING] [BACK]',
            'Closing PP Multi [CLO] [PRE] [BACK]', 'CX Expert [BACK] [KA]',
            'CX PP Multi Diamond [POS] [BACK]', 'Concierge PP Multi [PRE] [POS] [ESC]',
            'Ongoing Back', 'Aditivos [POS] [BACK] [WH]', 'Onboarding Back',
            'Condo Garantido [ONB] [POS] [BACK]', 'Onboarding ForRent', 'Ongoing FR - Geral',
            'Ongoing FR - Informe de Rendimentos', 'Payment FR - Aluguel', 'Payment FR - Dados Bancários',
            'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio',
            'Payment FR - Condomínio Interno', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
            'Payment FR - Dados Bancários Front', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding - Atento'
        )
        AND cp.last_team NOT IN (
            'CX Expert', 'Propostas', 'Closing', 'CX Partners',
            'Payment FR - Dados Bancários Front', 'Payment FR - Condomínio Interno'
        )
),
adj_team_month AS (
    SELECT
        last_team_adjusted, ref_month,
        COUNT(DISTINCT CASE WHEN resolution_survey = TRUE THEN case_number END) AS resolution_cases,
        COUNT(DISTINCT CASE WHEN resolution_survey IS NOT NULL THEN case_number END) AS answered_resolution_surveys
    FROM scoped
    GROUP BY last_team_adjusted, ref_month
),
adj_team_totals AS (
    SELECT last_team_adjusted, SUM(answered_resolution_surveys) AS total_answered
    FROM adj_team_month
    GROUP BY last_team_adjusted
),
consolidated_month AS (
    SELECT
        'Post Contract' AS last_team_adjusted, ref_month,
        COUNT(DISTINCT CASE WHEN resolution_survey = TRUE THEN case_number END) AS resolution_cases,
        COUNT(DISTINCT CASE WHEN resolution_survey IS NOT NULL THEN case_number END) AS answered_resolution_surveys
    FROM scoped
    GROUP BY ref_month
)
SELECT
    0 AS team_order, cm.last_team_adjusted, cm.ref_month, cm.resolution_cases, cm.answered_resolution_surveys,
    CAST(NULL AS BIGINT) AS total_answered
FROM consolidated_month cm
UNION ALL
SELECT
    1 AS team_order, tm.last_team_adjusted, tm.ref_month, tm.resolution_cases, tm.answered_resolution_surveys, tt.total_answered
FROM adj_team_month tm
JOIN adj_team_totals tt ON tt.last_team_adjusted = tm.last_team_adjusted
WHERE tt.total_answered > 0
ORDER BY team_order, total_answered DESC, last_team_adjusted, ref_month
```

### Query 4 — SLA Back (Post Contract consolidated)

```sql
SELECT
    DATE_TRUNC('month', CAST(cp.ts_solved AS DATE)) AS ref_month,
    COUNT(DISTINCT CASE WHEN cp.is_ticket_solved_within_sla = TRUE THEN cp.case_number END) AS cases_within_sla,
    COUNT(DISTINCT cp.case_number) AS solved_cases,
    CAST(COUNT(DISTINCT CASE WHEN cp.is_ticket_solved_within_sla = TRUE THEN cp.case_number END) AS DOUBLE)
        / NULLIF(CAST(COUNT(DISTINCT cp.case_number) AS DOUBLE), 0) AS sla_back
FROM dw_bpo_performance.cases_perspective AS cp
WHERE (LOWER(cp.front_or_back) = 'back' OR cp.front_or_back IS NULL)
    AND cp.channel = 'email'
    AND cp.ts_solved IS NOT NULL
    AND cp.ts_solved >= DATE('<start_date>')
    AND cp.ts_solved < DATE('<end_date>') + INTERVAL '1' DAY
    AND cp.last_department IN (
        'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
        'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
        'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
        'Atendimento Escalado [OFF] [POS] [BACK]', 'CX Rescisão [FRONT] [POS]',
        'Rescisão por Inadimplência [OFF][POS][BACK]', 'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
        'Offboarding pré saída [OFF] [POS] [BACK]', 'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
        'FUP Carteirização B2C [CLO] [PRE] [BACK]', 'EARLY DEMAND [CLOSING] [BACK]',
        'Closing PP Multi [CLO] [PRE] [BACK]', 'CX Expert [BACK] [KA]',
        'CX PP Multi Diamond [POS] [BACK]', 'Concierge PP Multi [PRE] [POS] [ESC]',
        'Ongoing Back', 'Aditivos [POS] [BACK] [WH]', 'Onboarding Back',
        'Condo Garantido [ONB] [POS] [BACK]', 'Onboarding ForRent', 'Ongoing FR - Geral',
        'Ongoing FR - Informe de Rendimentos', 'Payment FR - Aluguel', 'Payment FR - Dados Bancários',
        'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio',
        'Payment FR - Condomínio Interno', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
        'Payment FR - Dados Bancários Front', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding - Atento'
    )
    AND cp.last_team NOT IN (
        'CX Expert', 'Propostas', 'Closing', 'CX Partners',
        'Payment FR - Dados Bancários Front', 'Payment FR - Condomínio Interno'
    )
GROUP BY 1
ORDER BY 1
```

### Query 5 — SLA Back by Operation (`last_team_adjusted`) with Post Contract consolidated row

`tt.total_solved > 0` is the same per-period display convenience as Query 2/3 and never affects the consolidated row — it has not hidden any of the 5 validated operations for Aug/2025–Jul/2026 (all had solved cases in every month of that period). This query intentionally does **not** select or filter on `first_csat_ts_response`, `first_csat_score`, or `resolution_survey` anywhere — see [Calculation → SLA Back](#1-sla-back).

```sql
WITH scoped AS (
    SELECT
        cp.case_number,
        cp.last_team,
        CASE
            WHEN cp.last_team IN (
                'Offboarding Back', 'Offboarding - AEC', 'Offboarding - Atento', 'Offboarding - CNX'
            ) THEN 'Offboarding Back'
            WHEN cp.last_team IN (
                'Onboarding Back', 'Onboarding ForRent'
            ) THEN 'Onboarding Back'
            WHEN cp.last_team IN (
                'Ongoing Back', 'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos'
            ) THEN 'Ongoing Back'
            WHEN cp.last_team IN (
                'Payments Ativo Back', 'Payment FR - Aluguel', 'Payment FR - Condomínio Geral',
                'Payment FR - Reembolso de Condomínio', 'Payment FR - PP Multi'
            ) THEN 'Payments Ativo Back'
            WHEN cp.last_team IN (
                'Payments', 'Payment FR - Dados Bancários'
            ) THEN 'Dados Bancários'
            ELSE cp.last_team
        END AS last_team_adjusted,
        cp.is_ticket_solved_within_sla,
        cp.ts_solved,
        DATE_TRUNC('month', CAST(cp.ts_solved AS DATE)) AS ref_month
    FROM dw_bpo_performance.cases_perspective AS cp
    WHERE (LOWER(cp.front_or_back) = 'back' OR cp.front_or_back IS NULL)
        AND cp.channel = 'email'
        AND cp.ts_solved IS NOT NULL
        AND cp.ts_solved >= DATE('<start_date>')
        AND cp.ts_solved < DATE('<end_date>') + INTERVAL '1' DAY
        AND cp.last_department IN (
            'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
            'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
            'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
            'Atendimento Escalado [OFF] [POS] [BACK]', 'CX Rescisão [FRONT] [POS]',
            'Rescisão por Inadimplência [OFF][POS][BACK]', 'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
            'Offboarding pré saída [OFF] [POS] [BACK]', 'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
            'FUP Carteirização B2C [CLO] [PRE] [BACK]', 'EARLY DEMAND [CLOSING] [BACK]',
            'Closing PP Multi [CLO] [PRE] [BACK]', 'CX Expert [BACK] [KA]',
            'CX PP Multi Diamond [POS] [BACK]', 'Concierge PP Multi [PRE] [POS] [ESC]',
            'Ongoing Back', 'Aditivos [POS] [BACK] [WH]', 'Onboarding Back',
            'Condo Garantido [ONB] [POS] [BACK]', 'Onboarding ForRent', 'Ongoing FR - Geral',
            'Ongoing FR - Informe de Rendimentos', 'Payment FR - Aluguel', 'Payment FR - Dados Bancários',
            'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio',
            'Payment FR - Condomínio Interno', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
            'Payment FR - Dados Bancários Front', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding - Atento'
        )
        AND cp.last_team NOT IN (
            'CX Expert', 'Propostas', 'Closing', 'CX Partners',
            'Payment FR - Dados Bancários Front', 'Payment FR - Condomínio Interno'
        )
),
adj_team_month AS (
    SELECT
        last_team_adjusted, ref_month,
        COUNT(DISTINCT CASE WHEN is_ticket_solved_within_sla = TRUE THEN case_number END) AS cases_within_sla,
        COUNT(DISTINCT case_number) AS solved_cases
    FROM scoped
    GROUP BY last_team_adjusted, ref_month
),
adj_team_totals AS (
    SELECT last_team_adjusted, SUM(solved_cases) AS total_solved
    FROM adj_team_month
    GROUP BY last_team_adjusted
),
consolidated_month AS (
    SELECT
        'Post Contract' AS last_team_adjusted, ref_month,
        COUNT(DISTINCT CASE WHEN is_ticket_solved_within_sla = TRUE THEN case_number END) AS cases_within_sla,
        COUNT(DISTINCT case_number) AS solved_cases
    FROM scoped
    GROUP BY ref_month
)
SELECT
    0 AS team_order, cm.last_team_adjusted, cm.ref_month, cm.cases_within_sla, cm.solved_cases,
    CAST(NULL AS BIGINT) AS total_solved
FROM consolidated_month cm
UNION ALL
SELECT
    1 AS team_order, tm.last_team_adjusted, tm.ref_month, tm.cases_within_sla, tm.solved_cases, tt.total_solved
FROM adj_team_month tm
JOIN adj_team_totals tt ON tt.last_team_adjusted = tm.last_team_adjusted
WHERE tt.total_solved > 0
ORDER BY team_order, total_solved DESC, last_team_adjusted, ref_month
```

### Query 6 — Inbound Volume (Post Contract consolidated)

```sql
SELECT
    DATE_TRUNC('month', CAST(cp.ts_started AS DATE)) AS ref_month,
    COUNT(DISTINCT cp.case_number) AS inbound_volume
FROM dw_bpo_performance.cases_perspective AS cp
WHERE (LOWER(cp.front_or_back) = 'back' OR cp.front_or_back IS NULL)
    AND cp.channel = 'email'
    AND cp.ts_started >= DATE('<start_date>')
    AND cp.ts_started < DATE('<end_date>') + INTERVAL '1' DAY
    AND cp.last_department IN (
        'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
        'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
        'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
        'Atendimento Escalado [OFF] [POS] [BACK]', 'CX Rescisão [FRONT] [POS]',
        'Rescisão por Inadimplência [OFF][POS][BACK]', 'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
        'Offboarding pré saída [OFF] [POS] [BACK]', 'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
        'FUP Carteirização B2C [CLO] [PRE] [BACK]', 'EARLY DEMAND [CLOSING] [BACK]',
        'Closing PP Multi [CLO] [PRE] [BACK]', 'CX Expert [BACK] [KA]',
        'CX PP Multi Diamond [POS] [BACK]', 'Concierge PP Multi [PRE] [POS] [ESC]',
        'Ongoing Back', 'Aditivos [POS] [BACK] [WH]', 'Onboarding Back',
        'Condo Garantido [ONB] [POS] [BACK]', 'Onboarding ForRent', 'Ongoing FR - Geral',
        'Ongoing FR - Informe de Rendimentos', 'Payment FR - Aluguel', 'Payment FR - Dados Bancários',
        'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio',
        'Payment FR - Condomínio Interno', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
        'Payment FR - Dados Bancários Front', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding - Atento'
    )
    AND cp.last_team NOT IN (
        'CX Expert', 'Propostas', 'Closing', 'CX Partners',
        'Payment FR - Dados Bancários Front', 'Payment FR - Condomínio Interno'
    )
GROUP BY 1
ORDER BY 1
```

### Query 7 — Outbound Volume (Post Contract consolidated)

```sql
SELECT
    DATE_TRUNC('month', CAST(cp.ts_solved AS DATE)) AS ref_month,
    COUNT(DISTINCT cp.case_number) AS outbound_volume
FROM dw_bpo_performance.cases_perspective AS cp
WHERE (LOWER(cp.front_or_back) = 'back' OR cp.front_or_back IS NULL)
    AND cp.channel = 'email'
    AND cp.ts_solved IS NOT NULL
    AND cp.ts_solved >= DATE('<start_date>')
    AND cp.ts_solved < DATE('<end_date>') + INTERVAL '1' DAY
    AND cp.last_department IN (
        'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
        'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
        'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
        'Atendimento Escalado [OFF] [POS] [BACK]', 'CX Rescisão [FRONT] [POS]',
        'Rescisão por Inadimplência [OFF][POS][BACK]', 'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
        'Offboarding pré saída [OFF] [POS] [BACK]', 'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
        'FUP Carteirização B2C [CLO] [PRE] [BACK]', 'EARLY DEMAND [CLOSING] [BACK]',
        'Closing PP Multi [CLO] [PRE] [BACK]', 'CX Expert [BACK] [KA]',
        'CX PP Multi Diamond [POS] [BACK]', 'Concierge PP Multi [PRE] [POS] [ESC]',
        'Ongoing Back', 'Aditivos [POS] [BACK] [WH]', 'Onboarding Back',
        'Condo Garantido [ONB] [POS] [BACK]', 'Onboarding ForRent', 'Ongoing FR - Geral',
        'Ongoing FR - Informe de Rendimentos', 'Payment FR - Aluguel', 'Payment FR - Dados Bancários',
        'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio',
        'Payment FR - Condomínio Interno', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
        'Payment FR - Dados Bancários Front', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding - Atento'
    )
    AND cp.last_team NOT IN (
        'CX Expert', 'Propostas', 'Closing', 'CX Partners',
        'Payment FR - Dados Bancários Front', 'Payment FR - Condomínio Interno'
    )
GROUP BY 1
ORDER BY 1
```

### Query 8 — Inbound Volume by Operation (`last_team_adjusted`) with Post Contract consolidated row

```sql
WITH scoped AS (
    SELECT
        cp.case_number,
        cp.last_team,
        CASE
            WHEN cp.last_team IN (
                'Offboarding Back', 'Offboarding - AEC', 'Offboarding - Atento', 'Offboarding - CNX'
            ) THEN 'Offboarding Back'
            WHEN cp.last_team IN (
                'Onboarding Back', 'Onboarding ForRent'
            ) THEN 'Onboarding Back'
            WHEN cp.last_team IN (
                'Ongoing Back', 'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos'
            ) THEN 'Ongoing Back'
            WHEN cp.last_team IN (
                'Payments Ativo Back', 'Payment FR - Aluguel', 'Payment FR - Condomínio Geral',
                'Payment FR - Reembolso de Condomínio', 'Payment FR - PP Multi'
            ) THEN 'Payments Ativo Back'
            WHEN cp.last_team IN (
                'Payments', 'Payment FR - Dados Bancários'
            ) THEN 'Dados Bancários'
            ELSE cp.last_team
        END AS last_team_adjusted,
        DATE_TRUNC('month', CAST(cp.ts_started AS DATE)) AS ref_month
    FROM dw_bpo_performance.cases_perspective AS cp
    WHERE (LOWER(cp.front_or_back) = 'back' OR cp.front_or_back IS NULL)
        AND cp.channel = 'email'
        AND cp.ts_started >= DATE('<start_date>')
        AND cp.ts_started < DATE('<end_date>') + INTERVAL '1' DAY
        AND cp.last_department IN (
            'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
            'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
            'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
            'Atendimento Escalado [OFF] [POS] [BACK]', 'CX Rescisão [FRONT] [POS]',
            'Rescisão por Inadimplência [OFF][POS][BACK]', 'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
            'Offboarding pré saída [OFF] [POS] [BACK]', 'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
            'FUP Carteirização B2C [CLO] [PRE] [BACK]', 'EARLY DEMAND [CLOSING] [BACK]',
            'Closing PP Multi [CLO] [PRE] [BACK]', 'CX Expert [BACK] [KA]',
            'CX PP Multi Diamond [POS] [BACK]', 'Concierge PP Multi [PRE] [POS] [ESC]',
            'Ongoing Back', 'Aditivos [POS] [BACK] [WH]', 'Onboarding Back',
            'Condo Garantido [ONB] [POS] [BACK]', 'Onboarding ForRent', 'Ongoing FR - Geral',
            'Ongoing FR - Informe de Rendimentos', 'Payment FR - Aluguel', 'Payment FR - Dados Bancários',
            'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio',
            'Payment FR - Condomínio Interno', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
            'Payment FR - Dados Bancários Front', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding - Atento'
        )
        AND cp.last_team NOT IN (
            'CX Expert', 'Propostas', 'Closing', 'CX Partners',
            'Payment FR - Dados Bancários Front', 'Payment FR - Condomínio Interno'
        )
),
operation_month AS (
    SELECT last_team_adjusted, ref_month, COUNT(DISTINCT case_number) AS inbound_volume
    FROM scoped
    GROUP BY 1, 2
),
consolidated_month AS (
    SELECT 'Post Contract' AS last_team_adjusted, ref_month, COUNT(DISTINCT case_number) AS inbound_volume
    FROM scoped
    GROUP BY 2
)
SELECT 0 AS team_order, last_team_adjusted, ref_month, inbound_volume FROM consolidated_month
UNION ALL
SELECT 1 AS team_order, last_team_adjusted, ref_month, inbound_volume FROM operation_month
ORDER BY team_order, last_team_adjusted, ref_month
```

### Query 9 — Outbound Volume by Operation (`last_team_adjusted`) with Post Contract consolidated record

```sql
WITH scoped AS (
    SELECT
        cp.case_number,
        cp.last_team,
        CASE
            WHEN cp.last_team IN (
                'Offboarding Back', 'Offboarding - AEC', 'Offboarding - Atento', 'Offboarding - CNX'
            ) THEN 'Offboarding Back'
            WHEN cp.last_team IN (
                'Onboarding Back', 'Onboarding ForRent'
            ) THEN 'Onboarding Back'
            WHEN cp.last_team IN (
                'Ongoing Back', 'Ongoing FR - Geral', 'Ongoing FR - Informe de Rendimentos'
            ) THEN 'Ongoing Back'
            WHEN cp.last_team IN (
                'Payments Ativo Back', 'Payment FR - Aluguel', 'Payment FR - Condomínio Geral',
                'Payment FR - Reembolso de Condomínio', 'Payment FR - PP Multi'
            ) THEN 'Payments Ativo Back'
            WHEN cp.last_team IN (
                'Payments', 'Payment FR - Dados Bancários'
            ) THEN 'Dados Bancários'
            ELSE cp.last_team
        END AS last_team_adjusted,
        DATE_TRUNC('month', CAST(cp.ts_solved AS DATE)) AS ref_month
    FROM dw_bpo_performance.cases_perspective AS cp
    WHERE (LOWER(cp.front_or_back) = 'back' OR cp.front_or_back IS NULL)
        AND cp.channel = 'email'
        AND cp.ts_solved IS NOT NULL
        AND cp.ts_solved >= DATE('<start_date>')
        AND cp.ts_solved < DATE('<end_date>') + INTERVAL '1' DAY
        AND cp.last_department IN (
            'CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]',
            'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]',
            'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]',
            'Atendimento Escalado [OFF] [POS] [BACK]', 'CX Rescisão [FRONT] [POS]',
            'Rescisão por Inadimplência [OFF][POS][BACK]', 'CX Offboarding Reparos Receptivo [OFF] [POS] [BACK]',
            'Offboarding pré saída [OFF] [POS] [BACK]', 'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
            'FUP Carteirização B2C [CLO] [PRE] [BACK]', 'EARLY DEMAND [CLOSING] [BACK]',
            'Closing PP Multi [CLO] [PRE] [BACK]', 'CX Expert [BACK] [KA]',
            'CX PP Multi Diamond [POS] [BACK]', 'Concierge PP Multi [PRE] [POS] [ESC]',
            'Ongoing Back', 'Aditivos [POS] [BACK] [WH]', 'Onboarding Back',
            'Condo Garantido [ONB] [POS] [BACK]', 'Onboarding ForRent', 'Ongoing FR - Geral',
            'Ongoing FR - Informe de Rendimentos', 'Payment FR - Aluguel', 'Payment FR - Dados Bancários',
            'Payment FR - Condomínio Geral', 'Payment FR - Reembolso de Condomínio',
            'Payment FR - Condomínio Interno', 'Payment_FR_GeneralCondominium', 'Payment FR - PP Multi',
            'Payment FR - Dados Bancários Front', 'Offboarding - AEC', 'Offboarding - CNX', 'Offboarding - Atento'
        )
        AND cp.last_team NOT IN (
            'CX Expert', 'Propostas', 'Closing', 'CX Partners',
            'Payment FR - Dados Bancários Front', 'Payment FR - Condomínio Interno'
        )
),
operation_month AS (
    SELECT last_team_adjusted, ref_month, COUNT(DISTINCT case_number) AS outbound_volume
    FROM scoped
    GROUP BY 1, 2
),
consolidated_month AS (
    SELECT 'Post Contract' AS last_team_adjusted, ref_month, COUNT(DISTINCT case_number) AS outbound_volume
    FROM scoped
    GROUP BY 2
)
SELECT 0 AS team_order, last_team_adjusted, ref_month, outbound_volume FROM consolidated_month
UNION ALL
SELECT 1 AS team_order, last_team_adjusted, ref_month, outbound_volume FROM operation_month
ORDER BY team_order, last_team_adjusted, ref_month
```

### Validation

The following metrics were validated against the official Post Contract Back source for **August 2025 to July 2026**, across the Post Contract consolidated row and the five official operations (Onboarding Back, Ongoing Back, Payments Ativo Back, Dados Bancários, Offboarding Back):

| Metric | Status |
| :---- | :---- |
| DSAT Back | **VALIDATED** |
| Resolution Rate Back | **VALIDATED** |
| Inbound Volume | **VALIDATED** |
| Outbound Volume | **VALIDATED** |
| SLA Back | **VALIDATED** |

Confirmed for the validated period: DSAT Back used `first_csat_ts_response`, detractor scores 1/2, and distinct `case_number`; Resolution Rate Back used `first_csat_ts_response` and `resolution_survey`, with no dependency on `first_csat_score`; Inbound Volume used `ts_started`; Outbound Volume used `ts_solved`; SLA Back used `ts_solved`, `is_ticket_solved_within_sla`, and distinct solved cases; the Post Contract row was recalculated directly (never obtained by averaging operation rows); all six mandatory `last_team` exclusions were applied; `Payment FR - Dados Bancários` remained under Dados Bancários; and `Payment FR - Aluguel`, `Payment FR - Condomínio Geral`, `Payment FR - Reembolso de Condomínio`, and `Payment FR - PP Multi` were included in Payments Ativo Back.

**Mandatory regression tests whenever this document changes**: (1) one complete closed month for every metric; (2) the full Aug/2025–Jul/2026 validation window when scope or mappings change; (3) Post Contract consolidated results; (4) all five validated operations; (5) numerator and denominator for every rate metric; (6) one period with no results; (7) confirmation that excluded teams never contribute to operation rows or Post Contract; (8) confirmation that `Payment_FR_GeneralCondominium`, if present, remains separate until formally classified by the Data Steward.

**A document revision must not be promoted if it changes any previously validated result without an approved business-rule change.**


