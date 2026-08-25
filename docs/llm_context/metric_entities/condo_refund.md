# % Condo Refund w/o Human Intervention

## Ownership

**Data Owner:**
- carolina.ellwanger@quintoandar.com.br

**Data Steward:**
- carolina.ellwanger@quintoandar.com.br

## Overview

**% Condo Refund w/o Human Intervention** measures the share of SelfCondo contracts that had a condo reimbursement interaction in a given month and resolved it without any human intervention — that is, Heimdall classified the expense automatically and no CX analyst created or corrected a billing entry in SeuBarriga. The metric exists in two granularities: **Onboarding** (primary OKR, events within the first 40 days of the contract) and **General** (health metric, full contract universe).

The naive calculation — Heimdall auto-approvals divided by Heimdall total — overstates the automation rate because it misses a second human-intervention channel: CX analysts correcting condo billing entries in SeuBarriga (P2), which has no Heimdall footprint and must be sourced from Retsuko. From April 2026 onward, the P2 channel routes through Heimdall via MagicLink and requires a separate filter.

**H2 2026 OKR targets (Dec/26):** Onboarding rate ≥ 82.3% (baseline Jun/26: 65.7%); Reimbursement Coverage in Onboarding ≥ 18.2% (baseline Jun/26: 7.4%).

**Exists exclusively for For Rent, SelfCondo contracts.**

## Related Domain Entities

- Collections

<!-- Note for reviewer: Heimdall and the Retsuko `manual_entry` (P2) reimbursement flow are not yet
     documented as a dedicated domain entity in this repo. Collections is linked here because it
     already covers Retsuko/SeuBarriga billing and is the sibling link used by the related
     `condo_garantido.md` metric entity in the same MBR. The Heimdall/Retsuko schema this metric
     depends on is described inline below (Canonical Filter / Nuances) until a proper business
     entity exists — delete this comment once that gap is resolved or reviewer confirms the link. -->

## Catalog

| Metric | Type |
| :---- | :---- |
| % Condo Refund w/o Human Intervention in Onboarding | OKR |
| % Condo Refund w/o Human Intervention (General) | Health Metric |
| Reimbursement Coverage in Onboarding | OKR |

## MBR

**Name** Post Contract
**Category** Payments

Applies to **% Condo Refund w/o Human Intervention in Onboarding** only.

## Glossary and Synonyms

- **% Condo Refund w/o Human Intervention**, **automation rate**, **taxa de automação de reembolso de condo**, **% sem intervenção humana**, **reembolso sem humano** → this metric
- **Reimbursement Coverage in Onboarding**, **cobertura de reembolso no onboarding**, **% contratos com pedido de reembolso nos primeiros 40 dias** → coverage metric
- **P1** — Heimdall flags for manual analyst review (`is_validated_by_instant_refund = FALSE`)
- **P2** — CX agent creates or edits a condo billing entry in SeuBarriga (via direct edit or MagicLink)
- **Auto** — Heimdall auto-approved with no subsequent CX correction; these contracts count toward "without human intervention"
- **Onboarding window** — first 40 days from `ts_period_started` (contract validity start)

## Scope

**Included:** SelfCondo contracts (`condominium_payer = 'Inquilino'`); condo bill items (`condominium` and `condominium-reserves-funds`); Heimdall activity type `TENANT_REFUND_CONDOMINIUM`; Retsuko CDC rows `op_cdc IN ('c','u')`.

**Excluded:** PP Paga contracts (`condominium_payer = 'Proprietario'`, ~16.6k active contracts); CDC snapshot rows (`op_cdc = 'r'`, October 2025 bulk load); SeuBarriga entries from known system accounts (UiPath robots, service accounts, seubarriga-worker processes — see blocklist in Canonical Filter); MagicLink entries where Heimdall also flagged for manual review (counted in P1 only to avoid double-counting).

## Calculation

The naive path — `Auto / Heimdall_total` — overstates the automation rate by ignoring SeuBarriga corrections (P2) that happen outside or alongside the Heimdall flow. The correct denominator must also include P2 contracts.

The correct calculation is:

```
rate = (denominator − human_intervention_contracts) / denominator
```

where:

- **denominator** = distinct contracts in Auto ∪ P1 ∪ P2 (unique per contract/month via UNION-then-GROUP-BY)
- **human_intervention_contracts** = P1 ∪ P2 (union, deduplicated)
- **Auto** = contracts in Heimdall with `is_validated_by_instant_refund = TRUE` that had no subsequent CX correction in SeuBarriga
- **P1** = contracts where Heimdall could not auto-classify (`is_validated_by_instant_refund = FALSE`, `status != 'pending'`)
- **P2 Direct** = CX agent edits a condo entry directly in SeuBarriga (`source_external_id IS NULL`, human audit email)
- **P2 MagicLink** = CX agent submits via MagicLink → Heimdall auto-approves → writes to SeuBarriga (`source_external_id LIKE 'heimdall%'`, internal email, `is_validated_by_instant_refund = TRUE`)

**Onboarding window:** event timestamps (Heimdall `ts_requested`, SeuBarriga `ts_database_transaction`) must satisfy `DATE_DIFF('day', CAST(mc.ts_period_started AS DATE), CAST(event_ts AS DATE)) BETWEEN 0 AND 40`.

**MagicLink migration (April 2026):** from April 2026, the CX operation adopted MagicLink, shifting P2 from the Direct path (`source_external_id IS NULL`) to the MagicLink path (`source_external_id LIKE 'heimdall%'`). The Direct filter alone misses all post-April CX corrections. Both paths must always be applied; pre-April MagicLink volume is zero and does not affect historical figures.

### Canonical Filter

Apply on `datalake_mission_control_clean.contract`:
```sql
condominium_payer = 'Inquilino'
```

Apply on `datalake_heimdall.activity`:
```sql
type = 'TENANT_REFUND_CONDOMINIUM'
```

Apply on `datalake_retsuko_clean.manual_entry`:
```sql
type IN ('entry.bill-item/condominium', 'entry.bill-item/condominium-reserves-funds')
AND op_cdc IN ('c', 'u')
```

P2 Direct — exclude system actors:
```sql
source_external_id IS NULL
AND aud.email NOT IN (
    'service-account@quintoandar.com.br',
    'fastforward@add.ons',
    'no-identified-user@quintoandar.com.br',
    'service-account-trato-feito@placeholder.org'
)
AND aud.email NOT LIKE '%uipathrobot%'
AND aud.email NOT LIKE '%seubarriga-worker%'
AND aud.email NOT LIKE 'service-account%'
```

P2 MagicLink — CX agent via Heimdall, auto-approved:
```sql
source_external_id LIKE 'heimdall%'
AND aud.email LIKE '%quintoandar.com.br'
AND ae.is_validated_by_instant_refund = TRUE
```

**Warning:** `source_external_id LIKE 'heimdall%'` does NOT mean "no human involved" — it means CX submitted via MagicLink and Heimdall auto-approved it. Filtering it out removes valid P2 signal. Applying `is_validated_by_instant_refund = TRUE` on this path is mandatory to avoid double-counting cases already captured in P1.

### Nuances

**Deduplication:** contracts may appear in multiple populations within the same month. Deduplication is handled by a UNION-then-GROUP-BY pattern that collapses all populations into a single `(month, id_contract, is_human)` row before counting. Each contract is counted exactly once.

**Join keys:**

| Join | Key |
| :---- | :---- |
| Heimdall → Mission Control | `CAST(a.id_external_contract AS VARCHAR) = CAST(mc.id_contract AS VARCHAR)` |
| SeuBarriga → EBDB bridge | `manual_entry.id_contract = invoice.id_contract`, then `CAST(invoice.id_contract_external AS VARCHAR)` |
| SeuBarriga → Mission Control | `CAST(invoice.id_contract_external AS VARCHAR) = CAST(mc.id_contract AS VARCHAR)` |
| P2 MagicLink → Heimdall expense | `ae.id_activity = SPLIT_PART(SPLIT_PART(me.source_external_id,'|',2),':',1)` |

The `invoice` table (`datalake_retsuko.invoice`) is the required bridge between the Retsuko-internal `id_contract` and the EBDB `id_contract_external`.

**`is_validated_by_instant_refund`:** `TRUE` = Heimdall auto-classified (no analyst review). `FALSE` = Heimdall routed to analyst for manual review.

**Coverage cohort completeness:** the Coverage metric must only use cohorts where `mc.ts_period_started <= CURRENT_DATE - INTERVAL '40' DAY`. Contracts starting within the last 40 days have an incomplete observation window and will understate the metric.

**P1 SelfCondo:** the activity type `TENANT_REFUND_CONDOMINIUM` maps 99%+ to SelfCondo (`condominium_payer = 'Inquilino'`). No additional mission_control join is needed in the Heimdall CTE for the General variant.

## Dos and Don'ts

**Do:**
- Apply both P2 paths (Direct + MagicLink) for any query covering data from April 2026 onwards
- Deduplicate contracts across P1 and P2 via UNION-then-GROUP-BY before computing rates
- Cast all contract ID joins to VARCHAR to avoid implicit type comparison failures
- Exclude `op_cdc = 'r'` rows (October 2025 CDC snapshot bulk load, not real actions)
- For Coverage: filter `mc.ts_period_started <= CURRENT_DATE - INTERVAL '40' DAY` to exclude incomplete cohorts

**Don't:**
- Use P1 alone as the human-intervention signal — this ignores SeuBarriga corrections and overstates the automation rate
- Interpret `source_external_id LIKE 'heimdall%'` as "automated, no human involved" — it marks the MagicLink submission path, which is human-initiated
- Filter P2 MagicLink with `is_validated_by_instant_refund = FALSE` — that would target P1 overlap, not P2
- Compare pre-April and post-April P2 Direct volumes directly without accounting for the MagicLink migration structural break
- Use July 2026 or later cohorts as the Coverage baseline without verifying 40-day window completeness

## Golden Queries

### % Condo Refund w/o Human Intervention — Onboarding (OKR)

Events within the first 40 days of each contract's validity start (`ts_period_started`). The `flags` CTE collapses all three populations into one row per `(month, id_contract)` before the final aggregation. This query has no date lower-bound — it aggregates every month present in the data; do not add a `ts_requested`/`ts_database_transaction` cutoff filter.

```sql
WITH
heimdall AS (
  SELECT
    DATE_FORMAT(a.ts_requested, '%Y-%m')    AS month,
    CAST(a.id_external_contract AS VARCHAR) AS id_contract,
    MAX(CASE WHEN ae.is_validated_by_instant_refund = FALSE
             AND ae.status != 'pending' THEN 1 ELSE 0 END) AS is_p1
  FROM datalake_heimdall.activity a
  JOIN datalake_heimdall.auditable_expenses ae
    ON ae.id_activity = a.id
  JOIN datalake_mission_control_clean.contract mc
    ON CAST(a.id_external_contract AS VARCHAR) = CAST(mc.id_contract AS VARCHAR)
  WHERE a.type = 'TENANT_REFUND_CONDOMINIUM'
    AND mc.condominium_payer = 'Inquilino'
    AND DATE_DIFF('day',
          CAST(mc.ts_period_started AS DATE),
          CAST(a.ts_requested AS DATE)) BETWEEN 0 AND 40
  GROUP BY 1, 2
),
p2_direct AS (
  SELECT
    DATE_FORMAT(me.ts_database_transaction, '%Y-%m') AS month,
    CAST(i.id_contract_external AS VARCHAR)          AS id_contract
  FROM datalake_retsuko_clean.manual_entry me
  JOIN datalake_retsuko_clean.audit aud ON me.id_audit = aud.id
  JOIN datalake_retsuko.invoice i ON me.id_contract = i.id_contract
  LEFT JOIN datalake_mission_control_clean.contract mc
    ON CAST(i.id_contract_external AS VARCHAR) = CAST(mc.id_contract AS VARCHAR)
  WHERE me.type IN ('entry.bill-item/condominium','entry.bill-item/condominium-reserves-funds')
    AND me.op_cdc IN ('c','u')
    AND me.source_external_id IS NULL
    AND mc.condominium_payer = 'Inquilino'
    AND aud.email NOT IN (
        'service-account@quintoandar.com.br', 'fastforward@add.ons',
        'no-identified-user@quintoandar.com.br', 'service-account-trato-feito@placeholder.org'
    )
    AND aud.email NOT LIKE '%uipathrobot%'
    AND aud.email NOT LIKE '%seubarriga-worker%'
    AND aud.email NOT LIKE 'service-account%'
    AND DATE_DIFF('day',
          CAST(mc.ts_period_started AS DATE),
          CAST(me.ts_database_transaction AS DATE)) BETWEEN 0 AND 40
),
p2_magiclink AS (
  SELECT
    DATE_FORMAT(me.ts_database_transaction, '%Y-%m') AS month,
    CAST(i.id_contract_external AS VARCHAR)          AS id_contract
  FROM datalake_retsuko_clean.manual_entry me
  JOIN datalake_retsuko_clean.audit aud ON me.id_audit = aud.id
  JOIN datalake_retsuko.invoice i ON me.id_contract = i.id_contract
  JOIN datalake_heimdall.auditable_expenses ae
    ON ae.id_activity = SPLIT_PART(SPLIT_PART(me.source_external_id,'|',2),':',1)
  LEFT JOIN datalake_mission_control_clean.contract mc
    ON CAST(i.id_contract_external AS VARCHAR) = CAST(mc.id_contract AS VARCHAR)
  WHERE me.type IN ('entry.bill-item/condominium','entry.bill-item/condominium-reserves-funds')
    AND me.op_cdc IN ('c','u')
    AND me.source_external_id LIKE 'heimdall%'
    AND aud.email LIKE '%quintoandar.com.br'
    AND ae.is_validated_by_instant_refund = TRUE
    AND mc.condominium_payer = 'Inquilino'
    AND DATE_DIFF('day',
          CAST(mc.ts_period_started AS DATE),
          CAST(me.ts_database_transaction AS DATE)) BETWEEN 0 AND 40
),
flags AS (
  SELECT month, id_contract, MAX(is_human) AS is_human
  FROM (
    SELECT month, id_contract, CAST(is_p1 AS INTEGER) AS is_human FROM heimdall
    UNION ALL
    SELECT month, id_contract, 1 FROM p2_direct
    UNION ALL
    SELECT month, id_contract, 1 FROM p2_magiclink
  ) t
  GROUP BY 1, 2
)
SELECT
  month,
  COUNT(*)                                                            AS total_contracts,
  COUNT(*) FILTER (WHERE is_human = 0)                               AS without_human_intervention,
  ROUND(100.0 * COUNT(*) FILTER (WHERE is_human = 0) / COUNT(*), 1) AS pct_without_human_intervention
FROM flags
GROUP BY 1
ORDER BY 1
```

### % Condo Refund w/o Human Intervention — General (Health Metric)

Full contract universe, no onboarding window. The `heimdall` CTE does not require the mission_control join because `TENANT_REFUND_CONDOMINIUM` is already SelfCondo-exclusive. The P2 CTEs retain the mission_control join for the SelfCondo filter.

```sql
WITH
heimdall AS (
  SELECT
    DATE_FORMAT(a.ts_requested, '%Y-%m')    AS month,
    CAST(a.id_external_contract AS VARCHAR) AS id_contract,
    MAX(CASE WHEN ae.is_validated_by_instant_refund = FALSE
             AND ae.status != 'pending' THEN 1 ELSE 0 END) AS is_p1
  FROM datalake_heimdall.activity a
  JOIN datalake_heimdall.auditable_expenses ae
    ON ae.id_activity = a.id
  WHERE a.type = 'TENANT_REFUND_CONDOMINIUM'
  GROUP BY 1, 2
),
p2_direct AS (
  SELECT
    DATE_FORMAT(me.ts_database_transaction, '%Y-%m') AS month,
    CAST(i.id_contract_external AS VARCHAR)          AS id_contract
  FROM datalake_retsuko_clean.manual_entry me
  JOIN datalake_retsuko_clean.audit aud ON me.id_audit = aud.id
  JOIN datalake_retsuko.invoice i ON me.id_contract = i.id_contract
  LEFT JOIN datalake_mission_control_clean.contract mc
    ON CAST(i.id_contract_external AS VARCHAR) = CAST(mc.id_contract AS VARCHAR)
  WHERE me.type IN ('entry.bill-item/condominium','entry.bill-item/condominium-reserves-funds')
    AND me.op_cdc IN ('c','u')
    AND me.source_external_id IS NULL
    AND mc.condominium_payer = 'Inquilino'
    AND aud.email NOT IN (
        'service-account@quintoandar.com.br', 'fastforward@add.ons',
        'no-identified-user@quintoandar.com.br', 'service-account-trato-feito@placeholder.org'
    )
    AND aud.email NOT LIKE '%uipathrobot%'
    AND aud.email NOT LIKE '%seubarriga-worker%'
    AND aud.email NOT LIKE 'service-account%'
),
p2_magiclink AS (
  SELECT
    DATE_FORMAT(me.ts_database_transaction, '%Y-%m') AS month,
    CAST(i.id_contract_external AS VARCHAR)          AS id_contract
  FROM datalake_retsuko_clean.manual_entry me
  JOIN datalake_retsuko_clean.audit aud ON me.id_audit = aud.id
  JOIN datalake_retsuko.invoice i ON me.id_contract = i.id_contract
  JOIN datalake_heimdall.auditable_expenses ae
    ON ae.id_activity = SPLIT_PART(SPLIT_PART(me.source_external_id,'|',2),':',1)
  LEFT JOIN datalake_mission_control_clean.contract mc
    ON CAST(i.id_contract_external AS VARCHAR) = CAST(mc.id_contract AS VARCHAR)
  WHERE me.type IN ('entry.bill-item/condominium','entry.bill-item/condominium-reserves-funds')
    AND me.op_cdc IN ('c','u')
    AND me.source_external_id LIKE 'heimdall%'
    AND aud.email LIKE '%quintoandar.com.br'
    AND ae.is_validated_by_instant_refund = TRUE
    AND mc.condominium_payer = 'Inquilino'
),
flags AS (
  SELECT month, id_contract, MAX(is_human) AS is_human
  FROM (
    SELECT month, id_contract, CAST(is_p1 AS INTEGER) AS is_human FROM heimdall
    UNION ALL
    SELECT month, id_contract, 1 FROM p2_direct
    UNION ALL
    SELECT month, id_contract, 1 FROM p2_magiclink
  ) t
  GROUP BY 1, 2
)
SELECT
  month,
  COUNT(*)                                                            AS total_contracts,
  COUNT(*) FILTER (WHERE is_human = 0)                               AS without_human_intervention,
  ROUND(100.0 * COUNT(*) FILTER (WHERE is_human = 0) / COUNT(*), 1) AS pct_without_human_intervention
FROM flags
GROUP BY 1
ORDER BY 1
```

### Reimbursement Coverage in Onboarding (OKR)

Share of SelfCondo contracts that started in month X and had at least one Heimdall reimbursement request (`TENANT_REFUND_CONDOMINIUM`) within their first 40 days. The denominator is the full onboarding universe, not just contracts with a reimbursement event. Only include cohorts where `ts_period_started <= CURRENT_DATE - INTERVAL '40' DAY`.

```sql
SELECT
  DATE_FORMAT(mc.ts_period_started, '%Y-%m')                    AS cohort_month,
  COUNT(DISTINCT CAST(mc.id_contract AS VARCHAR))                AS total_onboarding,
  COUNT(DISTINCT CASE WHEN a.id IS NOT NULL
                      THEN CAST(mc.id_contract AS VARCHAR) END)  AS with_reimbursement_request,
  ROUND(100.0 *
    COUNT(DISTINCT CASE WHEN a.id IS NOT NULL
                        THEN CAST(mc.id_contract AS VARCHAR) END)
    / COUNT(DISTINCT CAST(mc.id_contract AS VARCHAR)), 1)        AS coverage_pct
FROM datalake_mission_control_clean.contract mc
LEFT JOIN datalake_heimdall.activity a
  ON CAST(a.id_external_contract AS VARCHAR) = CAST(mc.id_contract AS VARCHAR)
  AND a.type = 'TENANT_REFUND_CONDOMINIUM'
  AND DATE_DIFF('day',
        CAST(mc.ts_period_started AS DATE),
        CAST(a.ts_requested AS DATE)) BETWEEN 0 AND 40
WHERE mc.condominium_payer = 'Inquilino'
  AND mc.ts_period_started >= TIMESTAMP '2025-11-01 00:00:00'
  AND mc.ts_period_started <= CURRENT_TIMESTAMP - INTERVAL '40' DAY
GROUP BY 1
ORDER BY 1
```
