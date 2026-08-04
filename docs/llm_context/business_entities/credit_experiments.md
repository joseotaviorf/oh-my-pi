# Credit Experiments & Policy Dimensions

## Ownership

**Data Owner:**
- marcus.silva@quintoandar.com.br

**Data Steward:**
- davi.figueiredo@quintoandar.com.br

## Overview

**This doc** is the **experimentation** reference — what the tables alone don't make obvious:

1. how **experiments** are configured and how to **observe / query** them (variant + in-policy layers);
2. a **registry** of in-policy experiments (hypotheses, gates, windows) that cannot live in column metadata.

The policy **dimensions** and the **decision matrix** (cell → outcome, BAU and experiment arms)
live in
[`credit_policy.md` → The policy decision matrix](credit_policy.md#the-policy-decision-matrix),
derived **from data** (queries) rather than hardcoded. This doc covers what experiments do *on top*
of that matrix.

> Behaviour source of truth = Sorting Hat policy code. Dates / status below are
> **observed from data** (mid-Jun 2026) — re-run the discovery query for the current picture.
> Column semantics, enums, and join/coverage rules → DataHub metadata for
> `datalake_sorting_hat.policy_report_credit_policy`.

## Related Business Entities

- [`credit_analysis.md`](credit_analysis.md) — funnel & outcomes.
- [`credit_policy.md`](credit_policy.md) — scores, policy, models, rejection internals.

## Related Metric Entities

- [Credit Metrics](../metric_entities/credit_metrics.md) — official credit-policy monitoring toolkit (Evers, FPD, EC|ES2CS, OA2CA, volume, unpublishing, guarantee/risk mix).

## Glossary and Synonyms

- **Experiment / teste / A-B** → `experiment_groups` arm (`test` / `control`) or variant-level rollout
- **Variant** → model + policy + doc config per user (`dim_variant.variant_name` / `policy_report.variant`)
- **In-policy experiment** → house-randomized toggle; unit = **house** (`id_house % 100`)
- **Arm / braço** → `element_at(experiment_groups, '<name>')` → `test` | `control`
- **Policy dimension / cell** → `(risk_category_range × income_group × city_group × retenant × arm)`
- **CGRM** → standing contract-maximization for growth cities; `rj_cgrm` = RJ experiment on same objective
- **BAU** → Business As Usual — the no-experiment baseline policy (the `control` arm / standing matrix)
- **ITT** → analyse every assigned house/user, not only post-treatment survivors

## Tables

| You need… | Use this table |
|-----------|----------------|
| **Discover experiments & arms** | `datalake_sorting_hat.policy_report_credit_policy` — `UNNEST(experiment_groups)` |
| **Variant assignment** | `dw_credit.dim_variant`; string also on `policy_report.variant`. (`dim_experiment` is **deprecated/legacy** — see "Two layers" below) |
| **Funnel outcomes by arm** | `policy_report` JOIN `fpcf` on `CAST(pr.id_proposal AS BIGINT) = f.sk_proposal AND pr.external_source = 'PROPOSAL'`; add `f.is_last_credit_evaluation = true` for latest-analysis outcomes (see evaluation-grain note in [`credit_policy.md`](credit_policy.md)) |
| **House-level split check** | `policy_report` — `count(DISTINCT id_house)` per arm × cell |
| **Policy dimensions** | columns on `policy_report_credit_policy` (categories in metadata) |
| **Current rent-liquidity** | `dw_liquidity.fact_house_rent_liquidity`, `fact_house_listing_rent_liquidity` |

**Critical rules:**

- Read arms with `element_at(experiment_groups, '<name>')` — Trino `map[key]` throws if absent.
- Exclude retenants: `is_retenant = false AND COALESCE(retenant_type, 'NEW_USER') = 'NEW_USER'`.
- Confine PROPOSAL experiment analyses to **≥ 2026-05**.
- Validate randomization at **house** grain — report/proposal counts are post-treatment.

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) for **official** credit-policy outcome metrics when evaluating experiments. The bullets below are **component** experiment diagnostics.

### Official metrics (metric entities)

| When you need… | Metric entity |
|----------------|---------------|
| Evers, FPD, EC\|ES2CS, OA2CA, volume, unpublishing, guarantee/risk mix | [Credit Metrics](../metric_entities/credit_metrics.md) |

### Component / exploratory metrics

- **Outcome by arm × cell** — pick the transition by **flip kind** (reject↔paid/free → ES→EP or proposal→CS; free↔paid → EP→CS), gated to the affected cell
- **House-level arm balance** — `count(DISTINCT id_house)` per arm (~50/50 target)
- **Composition-standardized uplift** — reweight strata before comparing arms
- **Variant traffic share** — `count(*)` by `policy_report.variant`
- **Active experiment volume** — `count(*)` by `element_at(experiment_groups, '<name>')`

## Policy dimensions & decision matrix → `credit_policy.md`

The dimensions the matrix segments on (`income_group`, `risk_category_range`, `city_group`,
`retenant_type`, `package_value`, `policy_dti`) and the **decision matrix** (cell → guarantee
product, including experiment overlays via distinct `policy_matrix` names) live in
[`credit_policy.md` → The policy decision matrix](credit_policy.md#the-policy-decision-matrix),
derived from data via Query M1/M2 in
[`credit_policy.md` → Additional queries](credit_policy.md#additional-queries--decision-matrix-discovery)
(not hardcoded here — they change with each policy). M1 shows input → matrix selection
(`experiment_groups` / city / retenant); M2 is the cell → outcome table per `policy_matrix`.

For experiment analysis, **always segment by `risk_category_range` AND `income_group`**: in-policy
arms typically move only a **few mid-risk cells** (often one income half of one band), not the
whole matrix. Which cells and what they flip to is **policy-specific** — recover the current
affected cells via M1/M2 or the flip query below rather than hardcoding bands.

## Two layers of experimentation

Nested: **variant** first (per **user**), then **in-policy** arms (per **house**). An in-policy
experiment can be **pooled across variants that share the same matrices** (filtering
`experiment_groups` by name); do not pool across **model lineages** or when a policy
**changed** that experiment.

1. **Variant-level (per USER)** — which model + policy + doc policy. Arm = `variant_name`
   string (parse; see `dim_variant` metadata). `policy-N` resets per model lineage.
   **`dim_experiment` is deprecated — ignore it.** Confirmed in Sorting Hat code: variant
   assignment is **feature-flag / ConfigCat-driven**, and the experiment's `start_date` /
   `end_date` / `is_experiment_running` semantics are **dead** (nothing in production reads them;
   the single row flagged running, `internal-target-v5-docs-scr`, is a stale 2024 seed). All
   current variants hang off one constant `feature-flag-experiment` row, so the table groups
   nothing useful. `variant_percentage_paticipation_on_test` is likewise not the live split — for
   what's actually live use observed `policy_report.variant` traffic (variant layer) and
   `experiment_groups` (in-policy layer).
   - Alpha lineage: policy **4** introduced `rj_cgrm` + `rented_anyway_package`; **5** added
     rent-liquidity (`rented_anyway_liquidity`); **6** added `liquidity_mid` / `liquidity_low`.
2. **In-policy (per HOUSE)** — `experiment_groups` MAP; assignment by `house_id % 100` vs
   per-city ranges. This is what the Registry documents.

## Registry of known in-policy experiments

> Volumes / dates observed from `policy_report_credit_policy.ts_created` (mid-Jun 2026).
> PROPOSAL feed ramped Apr–May 2026 — April volumes understated; windows from May are reliable.

### Reading an experiment's flip from data

Every in-policy experiment below flips the outcome in a small set of mid-risk cells.
Rather than hardcode BAU/test values, read the current `control` (= BAU) vs `test`
outcome per cell straight from the policy report:

```sql
SELECT
    element_at(pr.experiment_groups, 'rj_cgrm') AS arm,   -- swap the experiment name
    pr.city_group, pr.income_group, pr.risk_category_range,
    pr.analysis_category_name AS outcome,
    count(*) AS n
FROM datalake_sorting_hat.policy_report_credit_policy AS pr
WHERE pr.external_source = 'PROPOSAL'
  AND pr.ts_created >= TIMESTAMP '2026-05-01 00:00:00 UTC'
  AND pr.is_retenant = false
  AND element_at(pr.experiment_groups, 'rj_cgrm') IN ('test', 'control')
GROUP BY 1, 2, 3, 4, 5
ORDER BY 2, 3, 4, 1;
```

`control` vs `test` on the same cell = the flip; the **flip kind** then picks the metric (reject↔paid/free
→ ES→EP or proposal→CS; free↔paid → EP→CS). `CITY_GROWTH_ROADMAP` (non-RJ) is a **standing**
matrix with **no `control`** — read it from Query M2 in
[`credit_policy.md` → Additional queries](credit_policy.md#additional-queries--decision-matrix-discovery)
(filter `city_group = 'CITY_GROWTH_ROADMAP'` / the standing `policy_matrix`),
not from `experiment_groups`. The entries below add the non-queryable knowledge (hypothesis, gate,
window, flip kind) for each experiment.

### `rj_cgrm` — City Growth Roadmap (RJ)

| Field | Detail |
|---|---|
| **Hypothesis** | Contract maximization in CGRM cities — approve more marginal proposals. |
| **Mechanism** | Only `CITY_RJ` × `[F2,I2]` × `HIGH_INCOME`; new users only. |
| **Arms** | `test` / `control` ~50/50 by `house_random_percentage`. |
| **Window** | 2026-04-21 → present (**active**). |
| **Caveats** | Lift is **margin-extensive** (more reach EP); EP→CS ~equal across arms. Check sample-ratio in the affected cell. |

### `rented_anyway_liquidity` — stricter for high-liquidity houses

| Field | Detail |
|---|---|
| **Hypothesis** | High rent-liquidity houses will rent anyway → reject borderline tenants rather than paid guarantee. |
| **Gate** | `rent_liquidity_score >= 0.25`; new users; policy 5+ (successor to `rented_anyway_package`). |
| **Arms** | 50/50 by `house_id % 100`; shared split with mid/low arms in policy 6. |
| **Window** | 2026-05-17 → present (**active**). |
| **Data** | Analysis-time: `policy_report.house_rent_liquidity_score`; current: `dw_liquidity.*`. |

### `liquidity_mid` / `liquidity_low` — more permissive for mid/low liquidity (policy 6)

| Field | Detail |
|---|---|
| **Hypothesis** | Opposite of RAL: mid/low liquidity → waive guarantee (`FREE`) rather than hold out. |
| **Gate** | **`CITY_SP` only**; mid `0.15`–`<0.25` → `liquidity_mid`; low `<0.15` → `liquidity_low` (high → RAL). |
| **Arms** | Same house split as RAL. |
| **Status** | Live under `alpha-v1.1-policy-6` (SP only). |

### `rented_anyway_package` — retired predecessor

Same test matrix as RAL but gated on low **`package_value`** (≤ ~R$2,500); policy 4.
Window **2026-04-20 → 2026-06-01** (ended). Arms were imbalanced — check sample-ratio.

## How to observe & query any experiment

Discover which in-policy experiments are live (names, arms, first/last seen). For the full
**decision matrix** (selection + cell → outcome), use Query M1/M2 in
[`credit_policy.md` → Additional queries](credit_policy.md#additional-queries--decision-matrix-discovery)
instead — do not duplicate those here. Experiments select different `policy_matrix` values (see M1);
M2 grains on that matrix name, not on `experiment_groups`.

```sql
SELECT
    t.experiment_name,
    t.assigned_group,
    count(*) AS n,
    min(date(pr.ts_created)) AS first_seen,
    max(date(pr.ts_created)) AS last_seen
FROM datalake_sorting_hat.policy_report_credit_policy AS pr
CROSS JOIN UNNEST(pr.experiment_groups) AS t(experiment_name, assigned_group)
GROUP BY 1, 2
ORDER BY 1, 2;
```

Named experiment checklist:

- Arm: `element_at(pr.experiment_groups, '<name>') IN ('test', 'control')`.
- Funnel join: `CAST(pr.id_proposal AS BIGINT) = f.sk_proposal AND pr.external_source = 'PROPOSAL'`,
  `f.is_last_credit_evaluation = true` (latest analysis; policy report is evaluation-grain).
- Exclude retenants; segment by affected dimensions.
- **Metric by flip kind:** reject ↔ paid/free → **ES→EP**; free ↔ paid → **EP→CS**.
- Measure with `cs_flag`, not `is_guarantee_accepted` ([`credit_analysis.md` Don'ts](credit_analysis.md#dos-and-donts)).
- Coverage ≥ 2026-05; **don't** judge the split from report/proposal shares (post-treatment).
- To read control vs test **outcomes in the flipped cells**, use the flip query under
  [Reading an experiment's flip from data](#reading-an-experiments-flip-from-data) (or filter M2
  to the experiment's `policy_matrix` names from M1).

## Interpreting results: randomization is house-level

Match analysis grain to the layer (variant → **user**; in-policy → **house**). Report/proposal
counts in the **affected cell** will look imbalanced even when randomization is fine
(restrictive arm → fewer proposals, more early-credit retries; opposite for permissive).
`CREDIT_EVALUATION` and `PROPOSAL` reports coexist — a ~50/50 merged share can be cancellation,
not overwrite.

1. Validate split at house grain (`count(DISTINCT id_house)` per arm × cell).
2. Gate to the cell the policy actually changes; confirm the *un*gated sub-cell stays ~50/50.
3. Prefer ITT at house/user grain.
4. If comparing at proposal level, composition-standardize (Golden query below).

## Relationships with Other Entities

- `fpcf` ↔ policy report: evaluation-grain (`id_credit_evaluation`); proposal shortcut =
  `CAST(pr.id_proposal AS BIGINT) = f.sk_proposal AND pr.external_source = 'PROPOSAL'` with
  `f.is_last_credit_evaluation = true` for latest-analysis joins (not 1:1 when re-evaluated).
- `fpcf.sk_last_variant_not_null` → `dim_variant` (its `id_experiment` → `dim_experiment` is
  **deprecated/legacy**).
- House checks: `policy_report.id_house`; listing via `fpcf.sk_house_listing`
  ([`house_and_listing.md`](house_and_listing.md)).

## Dos and don'ts

**Do:**

- `element_at(experiment_groups, '<name>')`; exclude retenants; segment by affected dimensions.
- Pick metric by flip kind; measure with `cs_flag`; confine to ≥ 2026-05.
- Validate randomization at house grain.

**Don't:**

- Judge the split from report/proposal counts.
- Compare/pool by `policy-N` across model lineages.
- Segment by coarse `risk_category` (A–E).

## Golden queries

### Experiment-group assignment

```sql
SELECT
    element_at(pr.experiment_groups, 'rented_anyway_package') AS assigned_group,
    pr.analysis_category_name,
    count(*) AS credit_evaluations
FROM datalake_sorting_hat.policy_report_credit_policy AS pr
WHERE pr.external_source = 'PROPOSAL'
  AND pr.ts_created >= TIMESTAMP '2026-01-01 00:00:00 UTC'
  AND element_at(pr.experiment_groups, 'rented_anyway_package') IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
```

### In-policy effect (CGRM RJ) — descriptive only at proposal grain

> Proposal-grain counts are **descriptive**; randomization is by house. For valid arm
> comparison use the house-level split check and composition-standardized uplift below.

```sql
WITH base AS (
    SELECT
        element_at(pr.experiment_groups, 'rj_cgrm') AS arm,
        pr.risk_category_range,
        f.ep_flag,
        f.cs_flag
    FROM datalake_sorting_hat.policy_report_credit_policy AS pr
    JOIN dw_credit.fact_proposal_credit_flows AS f
        ON CAST(pr.id_proposal AS BIGINT) = f.sk_proposal
        AND f.is_last_credit_evaluation = true
    WHERE pr.external_source = 'PROPOSAL'
      AND element_at(pr.experiment_groups, 'rj_cgrm') IN ('test', 'control')
      AND pr.is_retenant = false
      AND COALESCE(pr.retenant_type, 'NEW_USER') = 'NEW_USER'
)
SELECT
    risk_category_range,
    arm,
    count(*) AS proposals,
    SUM(ep_flag) AS evaluation_positive,
    SUM(cs_flag) AS contracts_signed,
    CAST(SUM(cs_flag) AS DOUBLE) / NULLIF(count(*), 0) AS proposal_to_cs,
    CAST(SUM(cs_flag) AS DOUBLE) / NULLIF(SUM(ep_flag), 0) AS ep_to_cs
FROM base
GROUP BY 1, 2
ORDER BY 1, 2;
```

### House-level split check

```sql
SELECT
    city_group,
    risk_category_range = '[F2,I2]' AS affected,
    element_at(experiment_groups, 'rj_cgrm') AS arm,
    count(DISTINCT id_house) AS houses
FROM datalake_sorting_hat.policy_report_credit_policy
WHERE external_source = 'PROPOSAL'
  AND element_at(experiment_groups, 'rj_cgrm') IN ('test', 'control')
  AND ts_created >= TIMESTAMP '2026-05-01 00:00:00 UTC'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
```

### Composition-standardized uplift

> **KPI must match the flip.** `rj_cgrm` flips `CLEAR_NO`→paid (a **reject↔paid** flip → **ES→EP**),
> so its lift is **margin-extensive** (more proposals reach EP) and shows up in **proposal→CS**;
> EP→CS is ~flat across arms, so standardizing EP→CS would (correctly) show ~no uplift and hide the
> real effect. This template standardizes **proposal→CS**. For a **free↔paid** experiment
> (`liquidity_mid` / `liquidity_low`), swap the KPI to EP→CS (`SUM(cs_flag) / SUM(ep_flag)`).

```sql
WITH base AS (
    SELECT
        element_at(pr.experiment_groups, 'rj_cgrm') AS arm,
        CASE WHEN pr.risk_category_range = '[F2,I2]' AND pr.income_group = 'HIGH_INCOME'
             THEN 'affected' ELSE 'other' END AS stratum,
        f.ep_flag, f.cs_flag
    FROM datalake_sorting_hat.policy_report_credit_policy AS pr
    JOIN dw_credit.fact_proposal_credit_flows AS f
        ON CAST(pr.id_proposal AS BIGINT) = f.sk_proposal
        AND f.is_last_credit_evaluation = true
    WHERE pr.external_source = 'PROPOSAL'
      AND pr.city_group = 'CITY_RJ'
      AND element_at(pr.experiment_groups, 'rj_cgrm') IN ('test', 'control')
      AND pr.is_retenant = false
      AND pr.ts_created >= TIMESTAMP '2026-05-01 00:00:00 UTC'
),
cell AS (
    SELECT
        arm,
        stratum,
        count(*) AS n,
        CAST(SUM(cs_flag) AS DOUBLE) / NULLIF(count(*), 0) AS proposal_to_cs
    FROM base
    GROUP BY arm, stratum
),
w AS (
    SELECT stratum, CAST(n AS DOUBLE) / SUM(n) OVER () AS weight
    FROM cell WHERE arm = 'control'
)
SELECT c.arm, SUM(c.proposal_to_cs * w.weight) AS standardized_proposal_to_cs
FROM cell AS c JOIN w USING (stratum)
GROUP BY c.arm;
```

## Models behind the policies

See [Models behind the policies](credit_policy.md#models-behind-the-policies) and
[Known gaps](credit_policy.md#known-gaps-future-work).

## DataHub catalog

- **Data Product:** published by CI (`credit_experiments.md` → `credit-experiments`).
- **Primary datasets:** `datalake_sorting_hat.policy_report_credit_policy`,
  `dw_credit.dim_variant`, `dw_credit.fact_proposal_credit_flows`.
  (`dw_credit.dim_experiment` is **deprecated/legacy** — see "Two layers".)
