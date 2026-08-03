# Property Integrity Offboarding

## Ownership

**Data Owner:**
- carolina.espinoza@quintoandar.com.br
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- victor.prado@quintoandar.com.br

## Overview

**Property Integrity** is a set of three metric-entity docs that cover the For Rent
Post Contract property-integrity theme across the rental lifecycle:

1. **Property Integrity Offboarding** (this file) — exit / termination quality
2. [Property Integrity Onboarding](property_integrity_onboarding.md) — entry inspection
   review engagement
3. **Property Integrity Ongoing** (forthcoming) — ongoing repairs / in-contract integrity

**Property Integrity Offboarding** is the family of offboarding-quality metrics that
measure how a termination resolves repairs and agreements — how often it closes **without
friction** (no mediation), **without repairs**, and, when repairs do exist, how the parties
settle them (mutual agreement vs. compulsory / band-aid) — plus how far the **SPOC** (Single
Point of Contact) operating model has rolled out. It covers five indicators:
**% Offb. W/o Mediation**, **% Without Repairs**, **% Both Agree**, **% Compulsory/Band-Aid 2**,
and **% SPOC Roll Out**.

All five are computed from the pre-joined offboarding table `dw_offboarding.obt_offboarding`,
which already carries every flag these metrics need at one row per termination. **% SPOC Roll
Out** is the exception on scope: it runs over the **whole** `obt_offboarding` base (not the
finished/non-eviction base the other four use) and excludes evictions via `termination_category`
instead of `is_eviction` — see Scope and Calculation below.

**Exists exclusively for For Rent offboarding — these metrics have no equivalent for FS or
other products. Do not mix with Property Integrity Onboarding.**

## Related Business Entities

- Termination
- Inspection
- Repairs

## Catalog

| Metric | Type |
| :---- | :---- |
| % Offb. W/o Mediation | OKR |
| % Without Repairs | Health Metric |
| % Both Agree | Health Metric |
| % Compulsory/Band-Aid 2 | Health Metric |
| % SPOC Roll Out | Health Metric |

## MBR

**Name** Post Contract
**Category** Property Integrity

## Glossary and Synonyms

- **Property Integrity Offboarding**, **Property Integrity**, **integridade do imóvel**, **qualidade do offboarding** → this family of five metrics
- **% Offb. W/o Mediation**, **% Offboarding sem mediação**, **% sem mediação** → % Offb. W/o Mediation
- **% Without Repairs**, **% sem reparos**, **% termos sem reparo** → % Without Repairs
- **% Both Agree**, **% ambos concordam**, **% acordo mútuo**, **both agree** → % Both Agree
- **% Compulsory/Band-Aid 2**, **% compulsório/band-aid**, **compulsory or bandaid resolution** → % Compulsory/Band-Aid 2
- **% SPOC Roll Out**, **% rollout SPOC**, **adesão ao SPOC**, **percentual de casos SPOC** → % SPOC Roll Out
- **band-aid**, **bandaid**, **desconto automático**, **automatic discount** → the automatic-discount agreement flag (`has_discount_agreement`)

## Scope

**Included**: For Rent offboarding terminations that have already **finished** (non-null
`ts_termination_finished`), **excluding evictions**. The reference axis for **% Offb. W/o
Mediation**, **% Without Repairs**, **% Both Agree**, and **% Compulsory/Band-Aid 2** is the
**termination-finished date** — the calendar date of `ts_termination_finished`
(`CAST(ts_termination_finished AS DATE)`, UTC), matching the operational monthly reporting.

**Excluded**: evictions (`is_eviction = TRUE`), canceled terminations (already removed upstream
by the OBT), and terminations that have not yet reached closure (NULL `ts_termination_finished`).

**Exception — % SPOC Roll Out**: does **not** restrict to finished terminations and does not use
`is_eviction`. Its base is every row of `obt_offboarding` (canceled terminations are already
excluded upstream by the OBT), and it excludes evictions via
`termination_category NOT IN ('EVICTION')` instead. See Calculation for the exact formula.

## Calculation

Compute directly from `dw_offboarding.obt_offboarding`, reading the pre-materialized flags and
applying the exact `= true` / `= false` comparisons below (a NULL flag counts as neither `true`
nor `false`).

The first four indicators, all over the same finished-non-eviction base:

```
% Offb. W/o Mediation = count_if(has_mediation_ticket = false) / count(*)

% Without Repairs     = count_if(has_repairs = false) / count(*)

% Both Agree          = count_if(has_repairs = true
                                 AND has_agreement = true
                                 AND (has_early_agreement = true OR has_late_agreement = true))
                        / count_if(has_repairs = true)

% Compulsory/Band-Aid 2 = ( count_if(has_repairs = true AND has_agreement = true AND has_discount_agreement = true)
                          + count_if(has_repairs = true AND has_compulsory_agreement = true) )
                          / count_if(has_repairs = true)
```

The denominators differ by metric: **% Offb. W/o Mediation** and **% Without Repairs** divide by
the whole finished-non-eviction base (`count(*)`); **% Both Agree** and **% Compulsory/Band-Aid 2**
divide by the **with-repairs** subset (`count_if(has_repairs = true)`).

**% SPOC Roll Out** is the fifth indicator and uses a different base — the whole
`obt_offboarding` table, not the finished-non-eviction base above — excluding evictions via
`termination_category` instead of `is_eviction`:

```
% SPOC Roll Out = count_if(is_spoc_test_group_contract = true
                           AND termination_category NOT IN ('EVICTION'))
                 / count(*)
```

where `count(*)` is every row of `obt_offboarding` (canceled terminations already excluded
upstream), regardless of `ts_termination_finished` or `is_eviction`.

### Canonical Filter

Apply on `dw_offboarding.obt_offboarding`:

```sql
is_eviction = false
AND ts_termination_finished IS NOT NULL   -- finished terminations only (see Warning)
```

**Warning**: dropping `is_eviction = false` lets evictions into the base and inflates every
ratio, since eviction terminations behave very differently on repairs and mediation. Restricting
to finished terminations (non-null `ts_termination_finished`) is required for **% Offb. W/o
Mediation**: `has_mediation_ticket` is only populated once a termination reaches `DONE`, so
still-open terminations would be counted as "without mediation" and understate the mediation
rate. Using `ts_termination_finished` as the axis naturally enforces this scope.

**Does not apply to % SPOC Roll Out** — that metric is computed over the unfiltered
`obt_offboarding` base and excludes evictions with `termination_category NOT IN ('EVICTION')`
inline in its numerator instead of this canonical filter (see Calculation).

### Nuances

Every concept these metrics need is already a column in `dw_offboarding.obt_offboarding` — read
it directly. Concept → column:

| Concept | `obt_offboarding` column |
| :---- | :---- |
| Mediation ticket present on the termination | `has_mediation_ticket` |
| Termination had tenant repairs | `has_repairs` |
| Any agreement (early, late/budget, or discount) | `has_agreement` |
| Early both-agree agreement | `has_early_agreement` |
| Late agreement via budget approval | `has_late_agreement` |
| Band-aid / automatic-discount agreement | `has_discount_agreement` |
| Compulsory owner-approval settlement | `has_compulsory_agreement` |
| Eviction termination | `is_eviction` |
| Termination-finished date (axis) | `CAST(ts_termination_finished AS DATE)` (UTC calendar date) |
| SPOC test-group flag (net of control group) | `is_spoc_test_group_contract` |
| Raw termination category (includes `EVICTION`) | `termination_category` |

**SPOC flag already nets out the control group**: `is_spoc_test_group_contract` in
`obt_offboarding` is `is_spoc_contract AND NOT is_spoc_control_group` from
`dw_offboarding.fact_terminations` — it is already `TRUE` only for the SPOC treatment group, not
the raw SPOC test-membership flag. Do not re-apply a control-group exclusion on top of it.

**Do not confuse the two SPOC flags**: `fact_terminations.is_spoc_contract` is the raw
test-membership flag and includes the control group, while `obt_offboarding.is_spoc_test_group_contract`
is the treatment group only. `obt_offboarding` has no column named `is_spoc_contract` — using that
name against the OBT fails, and using the `fact_terminations` flag as a substitute overstates
**% SPOC Roll Out**.

**`termination_category` vs. `is_eviction`**: `is_eviction` is derived from
`termination_reason = 'EVICTION'`; `termination_category` is a separate raw classification
column (`STANDARD`, `NEGOTIATION_ATTENDANCE`, `JOB_TRANSFER`, `EVICTION`,
`SOLD_TO_THIRD_PARTIES`, …) sourced from `dw_offboarding.dim_termination.category`. **% SPOC
Roll Out** excludes evictions via `termination_category NOT IN ('EVICTION')`, not via
`is_eviction` — the two columns can disagree on edge cases, so do not substitute one for the
other.

**Band-aid flag**: the band-aid (automatic discount) is `has_discount_agreement`
("agreement reached through the application of automatic discounts"). This is the canonical
band-aid flag documented in `business_entities/termination.md`. Do **not** use
`model_discount_type` (also a column in `obt_offboarding`) to identify band-aid — it only
distinguishes the discount application mode (`AUTOMATIC_BANDAID` vs `OFFERED_DISCOUNT`), not
whether a band-aid agreement happened.

**Grain**: `obt_offboarding` is 1 row per termination (most recent exit inspection, canceled
terminations excluded), so `count(*)` / `count_if(...)` need no dedup.

## Dos and Don'ts

**Do:**

- Read the flags directly from `dw_offboarding.obt_offboarding`.
- Always apply the full canonical filter (`is_eviction = false` AND finished terminations only).
- Use the **calendar date** of `ts_termination_finished` (`CAST(ts_termination_finished AS DATE)`,
  UTC) as the reference axis, so monthly buckets match the operational reporting.
- Keep the exact `= true` / `= false` comparisons — a NULL flag is neither `true` nor `false`.
- Divide **% Both Agree** and **% Compulsory/Band-Aid 2** by `count_if(has_repairs = true)`, not
  by `count(*)`.
- For **% SPOC Roll Out**, use `is_spoc_test_group_contract` (already net of the control group) and
  `termination_category NOT IN ('EVICTION')` over the full, unfiltered `obt_offboarding` base.

**Don't:**

- Don't map the band-aid flag to `model_discount_type`; use `has_discount_agreement`.
- Don't include evictions, canceled, or still-open terminations in any denominator for the first
  four indicators.
- Don't `COALESCE` the agreement flags to `FALSE` before comparing with `= true` — it changes
  nothing (a NULL is already not `true`) and only obscures the intent.
- Don't apply the finished-only / `is_eviction` canonical filter to **% SPOC Roll Out** — its
  denominator is deliberately the whole table.
- Don't use `is_eviction` or the raw `is_spoc_contract` flag from `fact_terminations` for **% SPOC
  Roll Out** — use `termination_category` and `is_spoc_test_group_contract` respectively.

## Golden Queries

The first four metrics share the same base, axis and filter, so a single scan of
`dw_offboarding.obt_offboarding` produces them side by side. **% SPOC Roll Out** uses a
different base and axis (see Scope and Calculation), so it needs its own query. Trino dialect.

### Query 1 — Property Integrity Offboarding (first four metrics by month)

The month axis and the range predicates below bucket by the **calendar date** of
`ts_termination_finished` (`CAST(... AS DATE)`, i.e. the UTC date), matching the operational
monthly reporting convention — a termination finished in the early UTC hours of the 1st counts in
that new month, not the previous one. The range predicates are for partition pruning / performance
(adjust or drop the window as needed); only `is_eviction = false` and the finished-only scope are
required by the calculation.

```sql
SELECT
    DATE_TRUNC('month', CAST(obt.ts_termination_finished AS DATE)) AS ref_month,
    COUNT(*) AS total_terminations,
    CAST(COUNT_IF(obt.has_mediation_ticket = false) AS DOUBLE)
        / COUNT(*) AS pct_offb_wo_mediation,
    CAST(COUNT_IF(obt.has_repairs = false) AS DOUBLE)
        / COUNT(*) AS pct_without_repairs,
    CAST(
        COUNT_IF(
            obt.has_repairs = true
            AND obt.has_agreement = true
            AND (obt.has_early_agreement = true OR obt.has_late_agreement = true)
        ) AS DOUBLE
    ) / CAST(NULLIF(COUNT_IF(obt.has_repairs = true), 0) AS DOUBLE) AS pct_both_agree,
    (
        CAST(
            COUNT_IF(
                obt.has_repairs = true
                AND obt.has_agreement = true
                AND obt.has_discount_agreement = true
            ) AS DOUBLE
        )
        + CAST(
            COUNT_IF(
                obt.has_repairs = true
                AND obt.has_compulsory_agreement = true
            ) AS DOUBLE
        )
    ) / CAST(NULLIF(COUNT_IF(obt.has_repairs = true), 0) AS DOUBLE) AS pct_compulsory_bandaid2
FROM dw_offboarding.obt_offboarding AS obt
WHERE obt.is_eviction = false
    AND obt.ts_termination_finished IS NOT NULL
    AND CAST(obt.ts_termination_finished AS DATE) >= DATE_ADD('month', -24, CURRENT_DATE)
    AND CAST(obt.ts_termination_finished AS DATE) < CURRENT_DATE
GROUP BY 1
ORDER BY 1
```

To isolate a single indicator, keep only its numerator/denominator pair and the same
`FROM` / `WHERE`.

### Query 2 — % SPOC Roll Out (by month)

**% SPOC Roll Out** does not restrict to finished terminations, so it uses the
**termination-request date** (`ts_termination_request`) as axis instead of
`ts_termination_finished` — every row has a request date, but not every row has finished yet.
The range predicate is for partition pruning / performance only; the only predicate required by
the calculation is the `termination_category` exclusion inside `COUNT_IF`.

```sql
SELECT
    DATE_TRUNC('month', CAST(obt.ts_termination_request AS DATE)) AS ref_month,
    COUNT(*) AS total_terminations,
    CAST(
        COUNT_IF(
            obt.is_spoc_test_group_contract = true
            AND obt.termination_category NOT IN ('EVICTION')
        ) AS DOUBLE
    ) / COUNT(*) AS pct_spoc_rollout
FROM dw_offboarding.obt_offboarding AS obt
WHERE CAST(obt.ts_termination_request AS DATE) >= DATE_ADD('month', -24, CURRENT_DATE)
    AND CAST(obt.ts_termination_request AS DATE) < CURRENT_DATE
GROUP BY 1
ORDER BY 1
```

## Superset Golden Assets

<!--
BI reference only — where the user can find these indicators in Superset. NOT used in the
calculation.
-->

Superset charts where these indicators are published (BI reference only — not used in the
calculation):

- **Property Integrity — Superset chart** — URN: `urn:li:chart:(superset,chart.56400)` ([link](https://datahub.apps.data-prd.habitat.zone/chart/urn:li:chart:(superset,chart.56400)/Documentation?is_lineage_mode=false))
- **Property Integrity — Superset chart** — URN: `urn:li:chart:(superset,chart.57915)` ([link](https://datahub.apps.data-prd.habitat.zone/chart/urn:li:chart:(superset,chart.57915)/Documentation?is_lineage_mode=false))

