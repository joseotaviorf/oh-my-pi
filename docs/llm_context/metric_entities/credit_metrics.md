# Credit Metrics

## Ownership

**Data Owner:**

- [pedro.wainer@quintoandar.com.br](mailto:pedro.wainer@quintoandar.com.br)

**Data Steward:**

- [pedro.wainer@quintoandar.com.br](mailto:pedro.wainer@quintoandar.com.br)

## Overview

**Credit Metrics** is the set of official metrics used to monitor QuintoAndar's rental credit policy: default performance (**EversXMobY Clean**, **First Payment Default**), conversion (**EC|ES2CS**, **OA2CA**), volume (**Volume of CS**, **Volume of ES / ES Uplift**), listing churn (**Unpublishing Rate**), and decision-mix monitoring (**Mix of Guarantees**, **Risk Profile Mix**). These metrics share the same table skeleton (credit-policy decisions, proposal credit flows, and contracts) and are the standard toolkit for evaluating credit-policy changes and A/B experiments.

**Exists exclusively for For Rent (BR).**

## Related Business Entities

- Credit Analysis
- Credit Policy
- Credit Experiments
- House and Listing
- Losses
- Payments

## Catalog

| Metric | Type |
| :---- | :---- |
| EversXMobY Clean | OKR |
| Volume of CS | Health Metric |
| EC\|ES2CS | OKR |
| Unpublishing Rate | Health Metric |
| Mix of Guarantees | Health Metric |
| Volume of ES | Health Metric |
| OA2CA | Health Metric |
| Risk Profile Mix | Health Metric |
| First Payment Default | OKR |

## DataHub Catalog

- **This metric's data product**: `urn:li:dataProduct:credit-metrics` (published by CI from this file)
- **Upstream business-entity data products** (schema/datasets documented there): `urn:li:dataProduct:credit-analysis`, `urn:li:dataProduct:credit-policy`, `urn:li:dataProduct:credit-experiments`

The specific upstream datasets each metric touches are named in that metric's section (and in the
"Shared Table Skeleton" below); their columns/grain live in the linked business entities' catalogs.

## Glossary and Synonyms

- **ever30mob3**, **EversXMobY**, **evers clean**, **default rate**, **inadimplência**, **ever com acordo / with agreement** → EversXMobY Clean (official golden queries use `is_ever_with_agreement`; strict `is_ever` is the no-agreement view)  
- **CS volume**, **contracts signed**, **contratos assinados** → Volume of CS  
- **EC|ES2CS**, **ES2CS**, **evaluation started to contract signed**, **credit conversion** → EC|ES2CS  
- **unpublishing rate**, **despublicação**, **listing churn** → Unpublishing Rate  
- **mix of guarantees**, **guarantee mix**, **garantias oferecidas** → Mix of Guarantees  
- **ES uplift**, **volume of ES**, **evaluations started**, **avaliações iniciadas** → Volume of ES  
- **OA2CA**, **offer approved to credit analysis**, **oferta aprovada para análise aprovada** → OA2CA  
- **risk profile mix**, **risk band mix**, **mix de bandas de risco** → Risk Profile Mix  
- **FPD**, **first payment default**, **FPD7 / FPD15 / FPD30 / FPD60**, **inadimplência da primeira fatura** → First Payment Default

## Scope

**Included**: For Rent (BR) credit-policy monitoring — default performance (EversXMobY Clean, First Payment Default), conversion (EC|ES2CS, OA2CA), volume (Volume of CS, Volume of ES), listing churn (Unpublishing Rate), and decision-mix monitoring (Mix of Guarantees, Risk Profile Mix). Experiment comparisons when scoped by `experiment_groups` on `policy_report_credit_policy`; new-user flows (`is_retenant = false`, `COALESCE(retenant_type, 'NEW_USER') = 'NEW_USER'`). QuintoAndar-administered rental contracts for FPD (`rental_administrator = 'QUINTOANDAR'`, `country_code = 'BR'`).

**Excluded**: retenants in in-policy experiment comparisons (separate policy matrices); non-BR / non–For Rent contexts; Evers rows before MOB maturity (`dt_reference <= CURRENT_DATE` guard); immature FPD denominators; `CLEAR_NO` and NULL `analysis_category_name` when the question is strictly guarantee-offer mix (see Mix of Guarantees).

## Calculation

This data product documents **nine official metrics** that share the table skeleton below. Each metric section specifies its formula, canonical filter, and nuances; **Golden Queries** holds the canonical SQL. Column semantics, enums, grain, and join caveats live in the linked business entities — not repeated here.

| Metric | Formula (summary) |
| :---- | :---- |
| EversXMobY Clean | `COUNT_IF(is_ever_with_agreement) / COUNT(*)` over mature contracts at `(mob, ever)` |
| Volume of CS | `COUNT(DISTINCT sk_contract)` among signed proposals |
| EC\|ES2CS | `SUM(ec_or_es_to_cs) / COUNT(*)` over client × house flows cohorted by first EC/ES |
| Unpublishing Rate | `COUNT_IF(is_unpublished) / COUNT(*)` over deduplicated houses |
| Mix of Guarantees | `COUNT(*)` per guarantee bucket over policy decisions |
| Volume of ES | `COUNT(DISTINCT id_proposal)` over policy decisions |
| OA2CA | W2 offer-approved → credit-analysis-approved conversion at policy-decision grain |
| Risk Profile Mix | `COUNT(*)` per `risk_category_range` band |
| First Payment Default | `COUNT_IF(late_days >= X) / COUNT_IF(mature for X)` on first tenant invoice |

### Canonical Filter

Shared experiment-cohort pattern (metrics 2, 4, 5, 7, 8 when comparing arms):

```sql
ts_created >= TIMESTAMP '{experiment_launch} 00:00:00 UTC'
AND element_at(experiment_groups, '{experiment_key}') IN ('control', 'test')
AND is_retenant = false
AND COALESCE(retenant_type, 'NEW_USER') = 'NEW_USER'
```

Deduplicate by `id_house` (first event by `ts_created`) for house-grain metrics; use `CAST(id_proposal AS BIGINT)` when joining `policy_report_credit_policy` to `fact_proposal_credit_flows`. Per-metric mandatory filters are in each metric section below.

## Shared Table Skeleton

These metrics draw from a small shared set of tables. **Column semantics, enums, grain, and
join caveats are not repeated here** — they live in the linked business entities and in
DataHub / governance metadata:

- funnel flags, stage dates, `sk_*` keys on `fact_proposal_credit_flows` / `fact_early_credit`, the 8-stage funnel and right-censoring → [`credit_analysis.md`](../business_entities/credit_analysis.md)
- `policy_report_credit_policy` scores / `analysis_category_name` / `risk_category_range` → [`credit_policy.md`](../business_entities/credit_policy.md); `experiment_groups` arms, house-level randomization → [`credit_experiments.md`](../business_entities/credit_experiments.md)
- `dim_house_listing` (listing status / SCD versioning) → [`house_and_listing.md`](../business_entities/house_and_listing.md)
- `fact_ever_clean` (delinquency) → [`losses.md`](../business_entities/losses.md); `datalake_retsuko.*` invoices → [`payments.md`](../business_entities/payments.md)

The table below is a quick key-column reminder for the golden queries; each metric section adds the layer exclusive to it.

| Table | Grain | Key columns |
| :---- | :---- | :---- |
| `datalake_sorting_hat.policy_report_credit_policy` | One row per credit-policy decision event | `id_proposal`, `id_house`, `ts_created`, `experiment_groups` (MAP\<VARCHAR,VARCHAR\>), `analysis_category_name`, `risk_category_range` |
| `dw_credit.fact_proposal_credit_flows` | One row per proposal credit flow | `sk_proposal`, `sk_contract`, `sk_client`, `sk_house`, `es_flag`, `cs_flag`, `is_last_credit_evaluation`, `dt_last_credit_evaluation_init`, `dt_contract_signed_date`, `dt_offer_approved_date`, `dt_credit_analysis_approved_date` |
| `dw_credit.fact_early_credit` | One row per `(sk_client, sk_house)` — **latest** early credit only (`is_last_early_credit = TRUE`) | `sk_client`, `sk_house`, `dt_early_credit_created` |
| `datalake_sorting_hat.early_credit_analysis` | One row per early-credit event (use for **earliest** EC date per flow) | `id_user`, `id_house`, `ts_created` |
| `dw_credit_evers.fact_ever_clean` | One row per contract × `mob` × `ever` threshold | `dt_contract_signature`, `mob`, `ever`, `is_ever` |
| `dw_rent.dim_house_listing` | Listing version (SCD) | `id_house`, `house_rent_status`, `country_code`, `is_for_rent`, `is_last_version` |
| `datalake_retsuko.invoice` | One row per invoice | `id`, `id_account`, `id_contract`, `purpose`, `status`, `due_amount`, `dt_due_adjusted`, `ts_paid` |
| `datalake_retsuko_clean.account` | One row per billing account | `id`, `type` |
| `datalake_retsuko_clean.contract` | One row per billing contract | `id`, `id_external` (→ `dim_contract.id_contract`) |
| `dw_rent.dim_contract` | One row per rental contract | `id_contract`, `ts_signature`, `rental_administrator`, `country_code` |

### Shared experiment-cohort pattern

Metrics 2, 4, and 5 are typically computed per experiment group to compare two policies. The canonical cohort comes from `policy_report_credit_policy`:

```sql
-- Replace the experiment key and launch timestamp (not valid Trino bind syntax as written).
SELECT *
FROM datalake_sorting_hat.policy_report_credit_policy
WHERE ts_created >= TIMESTAMP '2026-05-20 00:00:00 UTC'
  AND element_at(experiment_groups, 'rented_anyway_liquidity') IN ('control', 'test')
  AND is_retenant = false
  AND COALESCE(retenant_type, 'NEW_USER') = 'NEW_USER'
```

Retenants use separate policy matrices and are excluded from in-policy experiments — always apply the retenant filter when comparing experiment arms ([`credit_experiments.md`](../business_entities/credit_experiments.md)).

Deduplicate when the unit of analysis repeats across decision events: by `id_house` (keep the first event via `ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_created) = 1`) for house-grain metrics, or by proposal/contract joins for proposal-grain metrics. When the question is not about an experiment, drop the `experiment_groups` filter and keep the rest of the logic.

> For experiment comparisons, [`credit_experiments.md`](../business_entities/credit_experiments.md) is
> the methodology source: randomization is **house-level** (validate the split with
> `count(DISTINCT id_house)` per arm; report/proposal counts are **post-treatment** and are not a
> split check), and the outcome transition to measure depends on the **flip kind** (reject↔paid/free
> → ES→EP or proposal→CS; free↔paid → EP→CS). Confine PROPOSAL analyses to **≥ 2026-05**.

---

## Metric 1 — EversXMobY Clean

### Overview

**EversXMobY Clean** is the percentage of contracts that were ever X+ days past due within their first Y months on book (MOB). "Clean" means the base excludes contracts that would distort the default reading (per the upstream `fact_ever_clean` construction). Example: **Ever30MOB3** \= % of contracts ever 30+ days past due within the first 3 months.

### Calculation

```
EversXMobY = COUNT_IF(is_ever_with_agreement) / COUNT(*) over mature contracts, per signature month
```

(Use `is_ever` instead of `is_ever_with_agreement` for the strict no-agreement view.)

`dw_credit_evers.fact_ever_clean` is pre-computed at contract × `mob` × `ever` grain: pick the row where `mob = Y` and `ever = X`. Rows exist before the MOB window closes — restrict to `dt_reference <= CURRENT_DATE` so only mature contracts enter the denominator (`dt_reference` = signature date + `mob` months).

The table carries **two ever flags**, and analyses are usually broken down by agreement status:

| Flag | Meaning |
| :---- | :---- |
| `is_ever` | Contract had an invoice with X+ days of delay (strict view, ignoring agreements) |
| `is_ever_with_agreement` | Contract had a delay **including** delays originated by a broken agreement — a superset of `is_ever` (the delta is contracts whose only delay came from a broken agreement) |

Choose the flag deliberately: `is_ever` for the strict default reading (ignoring broken agreements), `is_ever_with_agreement` for the with-agreement view — **the official policy number and golden queries below use `is_ever_with_agreement`**.

### Canonical Filter

Apply on `dw_credit_evers.fact_ever_clean`:

```sql
mob = :Y      -- months on book, e.g. 3
AND ever = :X -- days past due threshold, e.g. 30
AND dt_reference <= CURRENT_DATE
```

**Warning**: never mix rows of different `mob`/`ever` in the same aggregation — the table has one row per threshold combination and pooling them double-counts contracts. Without the `dt_reference` guard, recent signature months enter the denominator before the MOB window closes and the rate reads artificially low.

For the with-agreement view — or to attach ever flags to another cohort — see **Golden Queries** → Query 1b (agreement breakdown).

---

## Metric 2 — Volume of CS (Contracts Signed)

### Overview

**Volume of CS** is the count of distinct contracts successfully signed. It is the standard volume metric to compare the net monetary effect of two policies (an approval-rate gain means nothing if signed contracts do not grow).

### Calculation

```
Volume of CS = COUNT(DISTINCT sk_contract) among proposals with a signed contract
```

The proposal universe comes from `policy_report_credit_policy` (joined to `fact_proposal_credit_flows` on proposal id); a signed contract is `dt_contract_signed_date IS NOT NULL`.

**Time axis:** the experiment golden query below buckets by `date_trunc('week', p.ts_created)` — the week of the **policy report event**, not the week of contract signature. Within each week, `COUNT(DISTINCT sk_contract)` is correct; **do not sum weekly counts** to get total volume when a contract's policy events span multiple weeks (that overstates volume). For signature-cohort volume, bucket by `f.dt_contract_signed_date` instead.

### Canonical Filter

Apply on the join of `policy_report_credit_policy` (`p`) and `dw_credit.fact_proposal_credit_flows` (`f`):

```sql
p.id_proposal IS NOT NULL
AND f.dt_contract_signed_date IS NOT NULL
```

**Warning**: `p.id_proposal` is VARCHAR and `f.sk_proposal` is BIGINT — always `CAST(p.id_proposal AS BIGINT)` in the join. Count `DISTINCT sk_contract`, not rows, because a proposal can generate multiple policy-decision events.

---

## Metric 3 — EC|ES2CS

### Overview

**EC|ES2CS** (Early Credit or Evaluation Started to Contract Signed) is the golden conversion metric for credit policy: among client × house flows that had at least one Early Credit (EC) or Evaluation Started (ES) event, the share that reached Contract Signed (CS). It measures conversion from the exact touchpoints credit-policy making actually impacts.

### Calculation

The naive path — dividing total CS by total ES — is wrong: it misses flows that start at Early Credit and double-counts clients with multiple evaluations on the same house.

The correct calculation is:

```
EC|ES2CS = SUM(ec_or_es_to_cs) / COUNT(*) over client × house flows cohorted by first EC/ES date
```

where a **flow** is a distinct `(sk_client, sk_house)` pair, its **entry date** is the earliest EC or ES event, and `ec_or_es_to_cs = 1` if any of its flows reached CS (`cs_flag = 1`).

### Canonical Filter

On `datalake_sorting_hat.early_credit_analysis` (EC side — use the event table, not `fact_early_credit`, which keeps only the **latest** early credit per `(sk_client, sk_house)`):

```sql
id_user IS NOT NULL
AND id_house IS NOT NULL
AND ts_created IS NOT NULL
```

On `dw_credit.fact_proposal_credit_flows` (ES/CS side):

```sql
is_last_credit_evaluation = true
AND sk_client IS NOT NULL AND sk_client <> -1
AND sk_house IS NOT NULL AND sk_house <> -1
```

**Warning**: omitting `is_last_credit_evaluation = true` counts every re-evaluation of the same proposal and inflates the denominator. The `-1` values are unknown-member surrogate keys and must be excluded. Using `dw_credit.fact_early_credit` instead of `early_credit_analysis` shifts repeat-EC flows to the **last** EC date and mis-cohorts them — always aggregate `MIN(ts_created)` from `early_credit_analysis` for the entry date.

---

## Metric 4 — Unpublishing Rate

### Overview

**Unpublishing Rate** is the share of listings (houses) that end up unpublished, used to compare the listing-side impact of two policies (a stricter policy may push landlords to unpublish).

### Calculation

```
Unpublishing Rate = COUNT_IF(is_unpublished) / COUNT(*) over distinct houses in the cohort
```

where a house is unpublished if its current listing version has `house_rent_status = 'UNPUBLISHED'`.

### Canonical Filter

Cohort: shared experiment-cohort pattern on `policy_report_credit_policy`, deduplicated to one row per `id_house` (first event by `ts_created`), with `id_house IS NOT NULL`.

Listing status, on `dw_rent.dim_house_listing`:

```sql
country_code = 'BR'
AND is_for_rent = TRUE
AND is_last_version = TRUE
```

**Warning**: without `is_last_version = TRUE` the SCD returns multiple versions per house; without house-level deduplication of the cohort, houses with many proposals are over-weighted. Use a LEFT JOIN so houses without a listing row stay in the denominator.

---

## Metric 5 — Mix of Guarantees

### Overview

**Mix of Guarantees** is the distribution of guarantee products offered on credit-policy decisions, used to check whether the offered mix matches expectations. Official buckets: **Free**, **Paid 4%**, **Paid 6%**, **Paid 8%**; anything else is flagged as **Others**.

### Calculation

```
Mix of Guarantees = COUNT(*) per guarantee bucket per period, over policy decisions with a proposal
```

Bucket mapping on `analysis_category_name`:

| `analysis_category_name` | Bucket |
| :---- | :---- |
| `FREE` | Free |
| `PRO_GUARANTOR_50_PERC` | Paid 4% |
| `PRO_GUARANTOR_75_PERC` | Paid 6% |
| `PRO_GUARANTOR_100_PERC` | Paid 8% |
| `CLEAR_NO` | Clear No \- Score (rejection, not a guarantee offer) |
| `NULL` | Others — pre-policy gate (`INSUFFICIENT_INCOME`), external override, or auto-reject where `analysis_category_name` was not set |
| any other non-NULL value | Others |

### Canonical Filter

Apply on `datalake_sorting_hat.policy_report_credit_policy`:

```sql
id_proposal IS NOT NULL
```

**Warning**: any `analysis_category_name` outside the mapped values must land in "Others" — never silently drop it. In practice, **most "Others" volume is `analysis_category_name IS NULL`** (policy bypass or override), not unmapped guarantee strings — see [`credit_policy.md`](../business_entities/credit_policy.md). `CLEAR_NO` is a rejection; include it for the full decision picture, but exclude it (and usually NULL) if the question is strictly about the mix among guarantee offers.

---

## Metric 6 — Volume of ES (ES Uplift)

### Overview

**Volume of ES** is the count of distinct proposals that started a credit evaluation. Every credit-policy decision event with a proposal represents an Evaluation Started, so the metric comes straight from `policy_report_credit_policy` — no join needed. Like Volume of CS, it is used to compare the top-of-funnel effect of two policies (ES uplift).

### Calculation

```
Volume of ES = COUNT(DISTINCT id_proposal) over policy decisions, per period/group
```

A per-house variant (`COUNT(DISTINCT id_house)` as listings) is valid when the question is about listings reached rather than proposals.

### Canonical Filter

Apply on `datalake_sorting_hat.policy_report_credit_policy`:

```sql
id_proposal IS NOT NULL
```

**Warning**: count `DISTINCT id_proposal`, not rows — a proposal can generate multiple policy-decision events and row counts inflate the volume.

---

## Metric 7 — OA2CA

### Overview

**OA2CA** (Offer Approved to Credit Analysis approved) is the share of offer-approved proposals whose credit analysis was approved by the end of the week following the offer-approval week (usually, the "W2" window). It measures how efficiently approved offers convert into approved credit analyses under a given policy.

### Calculation

```
OA2CA = COUNT_IF(dt_ca within W2 window AND dt_ca >= dt_oa) / COUNT(*) over offer-approved rows, per OA week
```

The population is at **policy-decision grain** — a proposal with multiple decision events in the window counts more than once. Deduplicate by `sk_proposal` if a proposal-grain rate is required; the official metric as computed today does not deduplicate.

where `dt_oa = dt_offer_approved_date`, `dt_ca = dt_credit_analysis_approved_date` (both from `fact_proposal_credit_flows` at `is_last_credit_evaluation = TRUE`), and the W2 window is:

```sql
dt_ca IS NOT NULL
AND dt_ca >= dt_oa
AND date_trunc('week', dt_ca) <= date_trunc('week', dt_oa) + INTERVAL '7' DAY
```

The axis is the **offer-approval week** (`date_trunc('week', dt_oa)`), not the policy-decision date.

The user may want different time windows, or no window at all. Change the interval parameter: for W3 use 14 days, W4 use 21 days, and so on. If the user doesn't want a cohort window, omit the interval predicate.

### Canonical Filter

On the join of `policy_report_credit_policy` (`p`) and `fact_proposal_credit_flows` (`f`, joined with `f.is_last_credit_evaluation = TRUE` in the ON clause):

```sql
p.id_proposal IS NOT NULL
AND dt_oa IS NOT NULL
```

Exclude immature offer-approval weeks from the axis: the W2 window needs one full week after the OA week to close, so drop the **last two** OA weeks (rolling):

```sql
date_trunc('week', dt_oa) < date_trunc('week', CURRENT_DATE) - INTERVAL '14' DAY
```

---

## Metric 8 — Risk Profile Mix

### Overview

**Risk Profile Mix** is the distribution of proposals across risk bands (`risk_category_range`) for a given policy or experiment group, used to check whether a policy shifts the risk profile of the evaluated population.

### Calculation

```
Risk Profile Mix = COUNT(*) per risk band per period, over policy decisions with a proposal
```

`risk_category_range` groups `risk_category_canon` into 6 official bands. Parse the raw `[X,Y]` format into a readable label with `replace(replace(replace(risk_category_range, '[', ''), ']', ''), ',', '-')`:

| Raw value | Label | Meaning |
| :---- | :---- | :---- |
| `[A1,A3]` | `A1-A3` | lowest risk |
| `[A4,B1]` | `A4-B1` |  |
| `[B2,D2]` | `B2-D2` |  |
| `[D3,F1]` | `D3-F1` |  |
| `[F2,I2]` | `F2-I2` |  |
| `[I3,J1]` | `I3-J1` | highest risk |

When new policies change the official bands, use `risk_category_canon` to group the risk profile (only when the user explicitly references a policy change).

### Canonical Filter

Apply on `datalake_sorting_hat.policy_report_credit_policy`:

```sql
id_proposal IS NOT NULL
```

**Warning**: when comparing test vs control, compute the mix **within** each group (share per band) — absolute counts are distorted by unequal allocation.

---

## Metric 9 — First Payment Default (FPD)

### Overview

**First Payment Default (FPD-X)** is the share of contracts whose **first tenant invoice** was paid X or more days late — or never paid — cohorted by contract-signature month. Standard thresholds: FPD1, FPD7, FPD15, FPD30, FPD60. It is the earliest default signal available for a policy (Evers need 3+ months of maturity; FPD reads after the first due date).

### Calculation

```
FPD-X = COUNT_IF(late_days >= X) / COUNT_IF(mature for X), per signature-month cohort
```

where, for each contract's first invoice (earliest `dt_due_adjusted`, tie-broken by invoice `id`):

- `late_days = DATE_DIFF('day', dt_due, COALESCE(ts_paid, yesterday))` — unpaid invoices accumulate lateness up to yesterday;
- **maturity-aware denominator**: an invoice only enters the FPD-X denominator when `days_since_due >= X` (its due date is at least X days in the past) **or** it was already paid. Each threshold therefore has its own denominator.

The naive path — dividing late invoices by all first invoices — understates FPD for recent cohorts, because invoices that have not yet had X days to become late would sit in the denominator.

### Canonical Filter

On the join `datalake_retsuko.invoice` × `datalake_retsuko_clean.account` × `datalake_retsuko_clean.contract` × `dw_rent.dim_contract`:

```sql
d.type = 'tenant'
AND i.purpose IN ('monthly', 'onboarding')
AND i.status <> 'canceled'
AND i.due_amount < 0
AND dc.ts_signature IS NOT NULL
AND dc.rental_administrator = 'QUINTOANDAR'
AND dc.country_code = 'BR'
```

**Join path**: `invoice.id_account = account.id`, `invoice.id_contract = contract.id`, `contract.id_external = dim_contract.id_contract`.

**Warning**: `due_amount < 0` is the sign convention for tenant-owed invoices — dropping it mixes in payouts. Without `d.type = 'tenant'` the base includes owner accounts. Use the **first invoice per contract** (`ROW_NUMBER` by `dt_due_adjusted`), never all invoices.

---

## Golden Queries

Per-metric CTEs reuse the shared table skeleton and experiment-cohort pattern documented above; what is exclusive to each metric is its aggregation layer and canonical filter.

### Query 1 — EversXMobY Clean

Monthly Ever30MOB3 Clean by contract-signature month. Swap `mob`/`ever` for other X/Y combinations.

```sql
SELECT
  CAST(DATE_TRUNC('month', dt_contract_signature) AS DATE) AS signature_month,
  COUNT(*) AS mature_contracts,
  COUNT_IF(is_ever_with_agreement) AS ever_contracts,
  ROUND(100.0 * COUNT_IF(is_ever_with_agreement) / NULLIF(COUNT(*), 0), 4) AS ever_rate_pct
FROM dw_credit_evers.fact_ever_clean
WHERE mob = 3
  AND ever = 30
  AND dt_reference <= CURRENT_DATE
  AND dt_contract_signature >= DATE '2025-01-01'
GROUP BY 1
ORDER BY 1
```

### Query 1b — Evers agreement breakdown (contract-grain flags)

Build contract-grain ever flags with `MAX(CASE ...)`, one flag per `ever`/`mob` combination. Swap `is_ever_with_agreement` for `is_ever` for the strict view.

```sql
SELECT
  sk_contract,
  dt_contract_signature AS cs,
  MAX(CASE WHEN ever = 30 AND mob = 3 AND is_ever_with_agreement THEN 1 ELSE 0 END) AS ever30m3_flag,
  MAX(CASE WHEN ever = 60 AND mob = 6 AND is_ever_with_agreement THEN 1 ELSE 0 END) AS ever60m6_flag
FROM dw_credit_evers.fact_ever_clean
GROUP BY sk_contract, dt_contract_signature
```

### Query 2 — Volume of CS

Weekly signed-contract volume per experiment group (parameterize experiment name and start date; drop the experiment filter for overall volume).

```sql
SELECT
  date_trunc('week', p.ts_created) AS week,
  element_at(p.experiment_groups, 'rented_anyway_liquidity') AS experiment_group,
  COUNT(DISTINCT f.sk_contract) AS contracts
FROM datalake_sorting_hat.policy_report_credit_policy AS p
JOIN dw_credit.fact_proposal_credit_flows AS f
  ON CAST(p.id_proposal AS BIGINT) = f.sk_proposal
WHERE p.ts_created >= TIMESTAMP '2026-05-20 00:00:00 UTC'
  AND p.id_proposal IS NOT NULL
  AND f.dt_contract_signed_date IS NOT NULL
  AND element_at(p.experiment_groups, 'rented_anyway_liquidity') IN ('control', 'test')
  AND p.is_retenant = false
  AND COALESCE(p.retenant_type, 'NEW_USER') = 'NEW_USER'
GROUP BY 1, 2
ORDER BY 1, 2
```

### Query 3 — EC|ES2CS

Monthly EC|ES2CS, cohorted by the month of the flow's first EC/ES entry.

```sql
WITH ec_rows AS (
  SELECT
    id_user AS sk_client,
    id_house AS sk_house,
    MIN(CAST(ts_created AS DATE)) AS first_entry_date,
    1 AS has_ec,
    0 AS has_es,
    0 AS has_cs
  FROM datalake_sorting_hat.early_credit_analysis
  WHERE id_user IS NOT NULL
    AND id_house IS NOT NULL
    AND ts_created IS NOT NULL
  GROUP BY id_user, id_house
),
es_rows AS (
  SELECT
    sk_client,
    sk_house,
    MIN(CASE WHEN es_flag = 1 THEN dt_last_credit_evaluation_init END) AS first_entry_date,
    0 AS has_ec,
    MAX(CASE WHEN es_flag = 1 THEN 1 ELSE 0 END) AS has_es,
    MAX(CASE WHEN cs_flag = 1 THEN 1 ELSE 0 END) AS has_cs
  FROM dw_credit.fact_proposal_credit_flows
  WHERE is_last_credit_evaluation = true
    AND sk_client IS NOT NULL AND sk_client <> -1
    AND sk_house IS NOT NULL AND sk_house <> -1
  GROUP BY sk_client, sk_house
),
flow_cohort AS (
  SELECT
    sk_client,
    sk_house,
    MIN(first_entry_date) AS first_entry_date,
    MAX(has_ec) AS has_ec,
    MAX(has_es) AS has_es,
    MAX(has_cs) AS ec_or_es_to_cs
  FROM (
    SELECT * FROM ec_rows
    UNION ALL
    SELECT * FROM es_rows WHERE first_entry_date IS NOT NULL
  ) events
  WHERE first_entry_date IS NOT NULL
  GROUP BY sk_client, sk_house
)
SELECT
  date_trunc('month', first_entry_date) AS entry_month,
  COUNT(*) AS n_ec_or_es_flows,
  SUM(ec_or_es_to_cs) AS conversions,
  ROUND(AVG(CAST(ec_or_es_to_cs AS DOUBLE)) * 100.0, 2) AS conversion_rate_pct
FROM flow_cohort
WHERE first_entry_date >= DATE '2026-01-01'
GROUP BY 1
ORDER BY 1
```

### Query 4 — Unpublishing Rate

Unpublishing rate per experiment group (parameterize experiment name and start date).

```sql
WITH exp AS (
  SELECT
    id_house,
    element_at(experiment_groups, 'rented_anyway_liquidity') AS experiment_group,
    ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_created) AS rn
  FROM datalake_sorting_hat.policy_report_credit_policy
  WHERE ts_created >= TIMESTAMP '2026-05-20 00:00:00 UTC'
    AND id_house IS NOT NULL
    AND element_at(experiment_groups, 'rented_anyway_liquidity') IN ('test', 'control')
    AND is_retenant = false
    AND COALESCE(retenant_type, 'NEW_USER') = 'NEW_USER'
),
listing AS (
  SELECT
    id_house,
    MAX(CASE WHEN house_rent_status = 'UNPUBLISHED' THEN 1 ELSE 0 END) AS is_unpublished
  FROM dw_rent.dim_house_listing
  WHERE country_code = 'BR'
    AND is_for_rent = TRUE
    AND is_last_version = TRUE
  GROUP BY id_house
)
SELECT
  e.experiment_group,
  COUNT(*) AS houses,
  COUNT_IF(l.is_unpublished = 1) AS unpublished,
  1.0 * COUNT_IF(l.is_unpublished = 1) / COUNT(*) AS unpublishing_rate
FROM exp e
LEFT JOIN listing l ON e.id_house = l.id_house
WHERE e.rn = 1
GROUP BY 1
ORDER BY unpublishing_rate DESC
```

### Query 5 — Mix of Guarantees

Weekly count of proposals per guarantee bucket (add the shared experiment filter to slice by group).

```sql
SELECT
  date_trunc('week', ts_created) AS week,
  CASE
    WHEN analysis_category_name = 'FREE'                   THEN 'a. Free'
    WHEN analysis_category_name = 'PRO_GUARANTOR_50_PERC'  THEN 'b. Paid 4%'
    WHEN analysis_category_name = 'PRO_GUARANTOR_75_PERC'  THEN 'c. Paid 6%'
    WHEN analysis_category_name = 'PRO_GUARANTOR_100_PERC' THEN 'd. Paid 8%'
    WHEN analysis_category_name = 'CLEAR_NO'               THEN 'm. Clear No - Score'
    ELSE 'z. Others'
  END AS guarantee_offered,
  COUNT(*) AS proposals
FROM datalake_sorting_hat.policy_report_credit_policy
WHERE ts_created >= TIMESTAMP '2026-05-20 00:00:00 UTC'
  AND id_proposal IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2
```

### Query 6 — Volume of ES

Weekly ES volume per experiment group (parameterize experiment name and start date; drop the experiment filter for overall volume).

```sql
SELECT
  date_trunc('week', ts_created) AS week,
  element_at(experiment_groups, 'rented_anyway_liquidity') AS experiment_group,
  COUNT(DISTINCT id_proposal) AS es_proposals
FROM datalake_sorting_hat.policy_report_credit_policy
WHERE ts_created >= TIMESTAMP '2026-05-20 00:00:00 UTC'
  AND id_proposal IS NOT NULL
  AND element_at(experiment_groups, 'rented_anyway_liquidity') IN ('control', 'test')
  AND is_retenant = false
  AND COALESCE(retenant_type, 'NEW_USER') = 'NEW_USER'
GROUP BY 1, 2
ORDER BY 1, 2
```

### Query 7 — OA2CA

Weekly OA2CA per experiment group (parameterize experiment name and dates; drop the experiment filter for overall OA2CA).

```sql
WITH base AS (
  SELECT
    f.dt_offer_approved_date AS dt_oa,
    f.dt_credit_analysis_approved_date AS dt_ca,
    element_at(p.experiment_groups, 'rented_anyway_liquidity') AS experiment_group
  FROM datalake_sorting_hat.policy_report_credit_policy AS p
  LEFT JOIN dw_credit.fact_proposal_credit_flows AS f
    ON CAST(p.id_proposal AS BIGINT) = f.sk_proposal
    AND f.is_last_credit_evaluation = TRUE
  WHERE p.ts_created >= TIMESTAMP '2026-05-20 00:00:00 UTC'
    AND p.id_proposal IS NOT NULL
    AND element_at(p.experiment_groups, 'rented_anyway_liquidity') IN ('test', 'control')
    AND p.is_retenant = false
    AND COALESCE(p.retenant_type, 'NEW_USER') = 'NEW_USER'
)
SELECT
  date_trunc('week', dt_oa) AS week,
  experiment_group,
  COUNT(*) AS pop,
  COUNT_IF(
    dt_ca IS NOT NULL
    AND dt_ca >= dt_oa
    AND date_trunc('week', dt_ca) <= date_trunc('week', dt_oa) + INTERVAL '7' DAY
  ) AS converted_w2,
  1.0000 * COUNT_IF(
    dt_ca IS NOT NULL
    AND dt_ca >= dt_oa
    AND date_trunc('week', dt_ca) <= date_trunc('week', dt_oa) + INTERVAL '7' DAY
  ) / NULLIF(COUNT(*), 0) AS conversion_rate
FROM base
WHERE dt_oa IS NOT NULL
  AND date_trunc('week', dt_oa) >= DATE '2026-05-18'
  AND date_trunc('week', dt_oa) < date_trunc('week', CURRENT_DATE) - INTERVAL '14' DAY
GROUP BY 1, 2
ORDER BY 1, 2
```

### Query 8 — Risk Profile Mix

Weekly count of proposals per risk band for one experiment group (parameterize experiment name, group, and start date).

```sql
SELECT
  date_trunc('week', ts_created) AS week,
  replace(replace(replace(risk_category_range, '[', ''), ']', ''), ',', '-') AS risk_range,
  COUNT(*) AS proposals
FROM datalake_sorting_hat.policy_report_credit_policy
WHERE ts_created >= TIMESTAMP '2026-05-20 00:00:00 UTC'
  AND id_proposal IS NOT NULL
  AND element_at(experiment_groups, 'rented_anyway_liquidity') = 'test'
  AND is_retenant = false
  AND COALESCE(retenant_type, 'NEW_USER') = 'NEW_USER'
GROUP BY 1, 2
ORDER BY 1, 2
```

### Query 9 — First Payment Default

Monthly FPD1/7/15/30/60 for contracts signed in the last ~13 closed months.

```sql
WITH base AS (
  SELECT
    i.id AS id_invoice,
    dc.id_contract,
    CAST(dc.ts_signature AS DATE) AS dt_cs,
    CAST(i.dt_due_adjusted AS DATE) AS dt_due,
    CAST(i.ts_paid AS DATE) AS ts_paid,
    ROW_NUMBER() OVER (
      PARTITION BY dc.id_contract
      ORDER BY CAST(i.dt_due_adjusted AS DATE), i.id
    ) AS rn
  FROM datalake_retsuko.invoice AS i
  INNER JOIN datalake_retsuko_clean.account AS d
    ON i.id_account = d.id
    AND d.type = 'tenant'
  INNER JOIN datalake_retsuko_clean.contract AS c
    ON i.id_contract = c.id
  INNER JOIN dw_rent.dim_contract AS dc
    ON dc.id_contract = c.id_external
  WHERE dc.ts_signature IS NOT NULL
    AND dc.rental_administrator = 'QUINTOANDAR'
    AND i.purpose IN ('monthly', 'onboarding')
    AND i.status <> 'canceled'
    AND i.due_amount < 0
    AND dc.country_code = 'BR'
    AND CAST(dc.ts_signature AS DATE) >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '13' MONTH)
    AND CAST(dc.ts_signature AS DATE) < DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1' DAY)
),
first_inv AS (
  SELECT
    dt_cs,
    dt_due,
    ts_paid,
    DATE_DIFF('day', dt_due, COALESCE(ts_paid, CURRENT_DATE - INTERVAL '1' DAY)) AS late_days,
    DATE_DIFF('day', dt_due, CURRENT_DATE - INTERVAL '1' DAY) AS days_since_due
  FROM base
  WHERE rn = 1
    AND id_invoice IS NOT NULL
)
SELECT
  DATE_FORMAT(DATE_TRUNC('month', dt_cs), '%Y-%m') AS cohort,
  CAST(SUM(CASE WHEN late_days > 0 THEN 1 ELSE 0 END) AS DOUBLE)
    / NULLIF(SUM(CASE WHEN days_since_due >= 1 OR ts_paid IS NOT NULL THEN 1 ELSE 0 END), 0) AS fpd_001,
  CAST(SUM(CASE WHEN late_days >= 7 THEN 1 ELSE 0 END) AS DOUBLE)
    / NULLIF(SUM(CASE WHEN days_since_due >= 7 OR ts_paid IS NOT NULL THEN 1 ELSE 0 END), 0) AS fpd_007,
  CAST(SUM(CASE WHEN late_days >= 15 THEN 1 ELSE 0 END) AS DOUBLE)
    / NULLIF(SUM(CASE WHEN days_since_due >= 15 OR ts_paid IS NOT NULL THEN 1 ELSE 0 END), 0) AS fpd_015,
  CAST(SUM(CASE WHEN late_days >= 30 THEN 1 ELSE 0 END) AS DOUBLE)
    / NULLIF(SUM(CASE WHEN days_since_due >= 30 OR ts_paid IS NOT NULL THEN 1 ELSE 0 END), 0) AS fpd_030,
  CAST(SUM(CASE WHEN late_days >= 60 THEN 1 ELSE 0 END) AS DOUBLE)
    / NULLIF(SUM(CASE WHEN days_since_due >= 60 OR ts_paid IS NOT NULL THEN 1 ELSE 0 END), 0) AS fpd_060
FROM first_inv
GROUP BY 1
ORDER BY 1
```

## Dos and Don'ts

**Do:**

- Reuse the shared experiment-cohort pattern for any policy-comparison question; parameterize the experiment key and start timestamp instead of copying hardcoded values — include the retenant exclusion (`is_retenant = false`, `COALESCE(retenant_type, 'NEW_USER') = 'NEW_USER'`).  
- Match the aggregation grain to the metric: contracts for Evers and CS volume, client × house flows for EC|ES2CS, houses for Unpublishing Rate, decisions/proposals for Mix of Guarantees.  
- `CAST(id_proposal AS BIGINT)` when joining `policy_report_credit_policy` to `fact_proposal_credit_flows`.  
- Keep the exact bucket labels of Mix of Guarantees (including the letter prefixes used for sort order).

**Don't:**

- Don't compute Evers from raw payment/installment tables — `dw_credit_evers.fact_ever_clean` is the source of truth for the "clean" base.  
- Don't compute EC|ES2CS as CS ÷ ES from `fact_proposal_credit_flows` alone — it ignores Early Credit entries and re-evaluations. Use `datalake_sorting_hat.early_credit_analysis` (not `fact_early_credit`) for the earliest EC date per flow.  
- Don't count rows instead of `DISTINCT sk_contract` for CS volume.  
- Don't sum weekly CS volume buckets when the axis is `p.ts_created` — contracts with policy events in multiple weeks appear in more than one bucket; use signature-date bucketing for totals.  
- Don't compare experiment arms without excluding retenants — they use separate policy matrices ([`credit_experiments.md`](../business_entities/credit_experiments.md)).  
- Don't use listing versions other than `is_last_version = TRUE` for unpublishing status.  
- Don't hardcode experiment dates/names when the user's question references a different experiment.  
- Don't include immature OA weeks in OA2CA — the W2 window needs one full week after the OA week to close; exclude the last two OA weeks with a rolling `date_trunc('week', dt_oa)` cap.
- Don't aggregate Evers without `dt_reference <= CURRENT_DATE` — immature MOB rows bias recent signature months low.  
- Don't pool FPD thresholds over a single denominator — each FPD-X has its own maturity-aware denominator (`days_since_due >= X` or paid).  
- Don't compute FPD over all invoices — only the first invoice per contract counts.  
- Don't compare Risk Profile Mix or Mix of Guarantees across groups by absolute counts — use within-group shares.

