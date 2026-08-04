# Credit Policy, Scoring & Decisioning

## Ownership

**Data Owner:**
- marcus.silva@quintoandar.com.br

**Data Steward:**
- davi.figueiredo@quintoandar.com.br

## Overview

The **decisioning internals** behind the For-Rent credit funnel: how Sorting Hat turns a
proponent into a decision — **scores** and **policy inputs**, **variant → model → policy**,
the **credit-evaluation lifecycle**, **rejection reasons** (score/policy vs rule hard-stops),
and **rent-liquidity**.

Column-level detail (enums, grain, join caveats, coverage windows) lives in **DataHub /
governance metadata** for the tables below — this doc is the routing & methodology layer.

> **What Tars can't see directly:** the per-prediction **model** I/O (Alpha's feature vector /
> output) is not analyst-queryable — see [Known gaps](#known-gaps-future-work). **Bureau data,
> however, is available** (it's the models' *input*, not their output): raw provider pulls in
> `datalake_arquivo_confidencial_clean.integration_report` (`integration_provider` — Boa Vista/BVS,
> Serasa, TransUnion, BigDataCorp, plus SCR), and `datalake_arquivo_confidencial.scr` / `scr_pivot`.
> All keyed by **`cpf`** (PII — only on `fact_proponent_income_sources` here), so it's PII-gated in
> practice and can't be joined to the funnel without CPF.

## Related Business Entities

- [`credit_analysis.md`](credit_analysis.md) — funnel & outcomes (`fpcf`, `dim_credit_analysis`).
- [`credit_experiments.md`](credit_experiments.md) — experiment registry & policy dimensions.

## Related Metric Entities

- [Credit Metrics](../metric_entities/credit_metrics.md) — official credit-policy monitoring toolkit (Evers, FPD, EC|ES2CS, OA2CA, volume, unpublishing, guarantee/risk mix).

## Glossary and Synonyms

- **Model** → ML service (Alpha, income-verifier, liquidity_rent); summarised into score/risk columns
- **Policy** → decision matrix → guarantee product + documentation depth
- **Variant** → `dim_variant.variant_name` (full model+policy+doc string; parse — see metadata)
- **CreditAnalysisCategory** → guarantee product → `guarantee_offered` / `analysis_category_name`
- **AnalysisType** → documentation depth only (`FULL` / `FLEX` / `LIGHT_APPROVAL` /
  `FULL_CONTROL_GROUP`) — configured on the analysis; **not** “docs reviewed” / not approval
  (see [Evaluation sequence](#evaluation-sequence-on-sorting-hat-credit_analysis))
- **Screening / score** → use `risk_category_canon` / `risk_category_range`; `risk_category` (A–E) is **legacy**
- **PV (Present Value)** → expected contract earnings; default policy objective is maximize PV
- **Contract maximization** → approve everything with positive expected PV (CGRM cities)
- **CGRM** → City Growth Roadmap — `city_group = 'CITY_GROWTH_ROADMAP'` + `rj_cgrm` in RJ
- **Bypass** → auto-decision short-circuit — enums in `dim_credit_analysis.bypass` metadata
- **DTI / `policy_dti`** → income-to-rent affordability cap (rent-package share of income; buckets in metadata), **not** bureau debt-to-income; Credit Passport only
- **5A** → QuintoAndar (e.g. `score_5a`), not the engine

## Tables

| You need… | Use this table |
|-----------|----------------|
| **Scores, policy inputs, `experiment_groups`** (no DW equivalent) | `datalake_sorting_hat.policy_report_credit_policy` |
| **Credit-evaluation lifecycle** (all sources, not passport-only) | `dw_credit_passport.fact_credit_evaluation` |
| **Current rent-liquidity** (house / listing) | `dw_liquidity.fact_house_rent_liquidity`, `dw_liquidity.fact_house_listing_rent_liquidity` |
| Credit-engine checklist (compliance) | `dw_credit.fact_credit_engine_analysis_request` |
| **Granular hard-stop rejection reason** | `datalake_sorting_hat_clean.analysis_state_group` (+ `analysis_machine`) |
| Documentation submitted | `datalake_docx.income_documentation`, `identity_documentation`, `personal_documentation`, `address_documentation` |
| Fall-back: `liquidity` / `max_ca_category` | `datalake_credit_analysis.credit_analysis` |
| Fall-back: raw docx events | `datalake_docx.credit_evaluation`, `credit_evaluation_events` |

**Critical rules** (also on table/column metadata):

- PROPOSAL funnel join: `policy_report` is **evaluation-grain** (one row per `id_policy_report` /
  `id_credit_evaluation`, overwritten on re-run — not 1:1 with `id_proposal` when a proposal is
  re-evaluated). Join `fpcf` on `CAST(pr.id_proposal AS BIGINT) = f.sk_proposal` **and**
  `pr.external_source = 'PROPOSAL'`; add `f.is_last_credit_evaluation = true` when you want the
  latest analysis outcome. Restrict to **≥ 2026-05** (PROPOSAL feed ramp).
- Early credit: `id_credit_evaluation` + `external_source = 'CREDIT_EVALUATION'` (`id_proposal` NULL).
- No version dedup on policy report (overwrite-in-place; `version` counts re-runs).
- Trust `retenant_type` only when `is_retenant_type_trusted = true`.
- Hard-stop *why* lives in **clean** `analysis_state_group` — sanctioned DW exception.
- Analysis-time liquidity = `policy_report.house_rent_liquidity_score`; current = `dw_liquidity.*`.

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) for **official** credit-policy monitoring metrics (Evers, FPD, EC|ES2CS, etc.). The bullets below are **component** policy diagnostics on `policy_report` and related tables.

### Official metrics (metric entities)

| When you need… | Metric entity |
|----------------|---------------|
| Evers, FPD, EC\|ES2CS, OA2CA, volume, unpublishing, guarantee/risk mix | [Credit Metrics](../metric_entities/credit_metrics.md) |

### Component / exploratory metrics

- **Guarantee mix by risk × income** — `analysis_category_name` × `risk_category_range` × `income_group`
- **Policy clear-no rate** — `BAD_SCORE_ALL_PROPONENTS` among `guarantee_offered = 'CLEAR_NO'` /
  `category IS NULL` (policy ran). Keep **`INSUFFICIENT_INCOME` separate** — pre-policy gate
  (matrix never evaluated); see [Disambiguating `reason = CLEAR_NO`](#disambiguating-reason--clear_no).
- **Post-policy pre-docs auto-reject rate** — `reason = CLEAR_NO` with product `category` and
  `automatic_decision_reason IN ('INSTABLE_INCOME', 'HIGH_DTI')` (funnel: ES yes, EP no)
- **Rule hard-stop rate** — distinct proposals via `analysis_state_group` (Query P4)
- **Variant traffic share** — `count(*)` by `policy_report.variant` / `dim_variant.variant_name`
- **Rent-liquidity band × outcome** — join `fpcf` to `fact_house_listing_rent_liquidity`

## How a decision is configured: variant → model → policy

1. **Variant** — assigned **per user** (feature-flag rollout); picks *which* model + policy +
   documentation policy run. Full string on `dim_variant.variant_name` / `policy_report.variant`
   — grammar and `policy-N` lineage caveats in **metadata**. Live split = observed traffic, not
   `variant_percentage_paticipation_on_test`.
2. **Models** (separate *quintoml* services; only summarised outputs are queryable):
   - **Alpha** → default probability → risk/score columns (replacing *internal-target*).
   - **income-verifier** → declared-income credibility.
   - **liquidity_rent** → rent-liquidity score (policy input + `dw_liquidity.*`).
3. **Policy** — matrix → free / paid guarantee / `CLEAR_NO` + documentation depth. Default
   objective = maximize **PV**; CGRM = contract maximization.

Experiments (variant + in-policy arms) → [`credit_experiments.md`](credit_experiments.md).

**Policy ↔ funnel mapping:** `analysis_category_name` → `fpcf.guarantee_offered`
(`PRO_GUARANTOR_*` → `PRO_GUARANTOR`; `FREE` / `CLEAR_NO` map 1:1).

## The policy decision matrix

The policy maps a few **dimensions** to a **guarantee product** (`analysis_category_name`) plus a
**documentation depth** (`AnalysisType`). Dimensions — all on `policy_report_credit_policy`; bucket
enums and volatility caveats in column metadata:

| Dimension | Column | Notes |
|---|---|---|
| **Income** | `income_group` | `LOW_INCOME` / `HIGH_INCOME`; cutoffs are **policy-specific** — observe them per policy via [Additional queries](#additional-queries--decision-matrix-discovery) M1/M2 (and column metadata) |
| **Risk band** | `risk_category_range` | Band labels are **policy-specific** (M1/M2); **not** legacy `risk_category` (A–E) |
| **City group** | `city_group` | `CITY_SP` / `CITY_RJ` / `CITY_GROWTH_ROADMAP` / `CITY_OTHER` — selects which `policy_matrix` runs |
| **Retenant** | `retenant_type` | separate matrices; excluded from current experiments |
| **Package / DTI** | `package_value` / `policy_dti` | some experiments gate on package; `policy_dti` is Credit Passport only |

Bucket boundaries change with each new policy — always read the *current* matrix from data
rather than trusting a hardcoded table. As of Alpha v1.1 / v2 the `income_group` cut is
**R$7,500** (same for both); **risk bands vary** by policy/model. Shape of outcomes (which
bands map to `FREE` / paid / `CLEAR_NO`, which cells are multi-outcome) is also
policy-specific — recover it with **Query M1** (matrix selection) then **Query M2** (cell →
outcome) in [Additional queries](#additional-queries--decision-matrix-discovery). Keep
**`variant`** in the grain (variants can reuse a `policy_matrix` *name* with different contents).
In-policy experiments (and retenants) pick a **different `policy_matrix`**, so M2 grains on
`policy_matrix` rather than on `experiment_groups` / `city_group` / `retenant_type` (those belong
in M1). M1 still shows which inputs selected which matrix.

> Source of truth for policy *behaviour* is the Sorting Hat policy code; M1/M2 read the
> **observed current** matrix (verified deterministic — one outcome per cell). For how
> experiments overlay on this matrix and how to compare arms, see
> [`credit_experiments.md`](credit_experiments.md).

## Rejection / decision reasons (which field to use)

| Kind | Where | Use for |
|------|-------|---------|
| Coarse approve/reject | `fpcf.decision_reason` (`CLEAR_YES` / `CLEAR_NO` / `DOCPILOT_CLEAR_YES`) | funnel automation flag (checklist-derived — **not** Sorting Hat `reason`) |
| Auto vs manual (mesa) | `fpcf.decision_type` / `dim_credit_analysis.is_manual_analysis` | automation split |
| Decision *path* | Sorting Hat `credit_analysis.reason` / `dim_credit_analysis.reason` | which auto/manual path ran — **overloaded** (see below); not granular *why* |
| Auto *why* on the analysis | `datalake_sorting_hat_clean.credit_analysis.automatic_decision_reason` | disambiguate `reason = CLEAR_NO` (not on DW `dim_credit_analysis` today) |
| Score / policy *why* (report) | `policy_report_credit_policy.rejection_reason` | `BAD_SCORE_ALL_PROPONENTS` / `INSUFFICIENT_INCOME` / `OTHER` |
| Rule / hard-stop *why* (docs machine) | `datalake_sorting_hat_clean.analysis_state_group` | `AUTOMATIC_DECISION_ELIGIBILITY_REJECTION_BY_<X>` + `result = 'SATISFIED'` |

### Evaluation sequence on Sorting Hat `credit_analysis`

Same-looking labels mean different things. Within one evaluation, fields are filled in order:

1. **Pre-policy gate** — can reject before the matrix runs (`automatic_decision_reason =
   INSUFFICIENT_INCOME` → policy bypassed; `category` stays null).
2. **Credit policy** → `category` (null = policy clear no; `0` = FREE; `25`/`26`/`55` ≈
   PRO_GUARANTOR tiers, …). Score clear-no typically stamps
   `automatic_decision_reason = BAD_SCORE_ALL_PROPONENTS`.
3. **Docs policy** → `type` / `documentation_policy` (`LIGHT_APPROVAL` / `FULL` / …) — only the
   *configured* docs depth. **Not** “docs were reviewed” and **not** an approval.
4. **Evaluation auto-rules** (declared income / DTI, still **pre-docs**) → can reject and stamp
   `reason = CLEAR_NO` with `automatic_decision_reason` in `{INSTABLE_INCOME, HIGH_DTI}` while
   `category` still holds the product the policy offered.
5. **After docs / checklist machine** → rejection uses `reason = AUTOMATIC_REJECTION_*`
   (not `CLEAR_NO`).

### Disambiguating `reason = CLEAR_NO`

| Kind | `category` | `reason` | Typical `automatic_decision_reason` | Funnel (`fpcf`) |
|------|------------|----------|-------------------------------------|-----------------|
| Pre-policy auto | `NULL` | `CLEAR_NO` | `INSUFFICIENT_INCOME` | Reached **ES**, never **EP** (`es_flag = 1`, `ep_flag = 0`, drop `ES2EP`). `guarantee_offered = CLEAR_NO`. |
| Policy clear no | `NULL` | `CLEAR_NO` | `BAD_SCORE_ALL_PROPONENTS` | Same: **ES** yes, **EP** no. `guarantee_offered = CLEAR_NO`. |
| Post-policy auto (pre-docs) | product set (e.g. paid / free) | `CLEAR_NO` | `INSTABLE_INCOME`, `HIGH_DTI` | Same: **ES** yes, **EP** no. Policy offered a product + docs `type`; evaluation rules rejected before docs. `guarantee_offered` often still shows the **product** (e.g. `PRO_GUARANTOR`) — do **not** read that as “reached EP / accepted offer.” |
| Post-docs auto | product set | `AUTOMATIC_REJECTION_*` | (often null / other) | Can have reached **EP** (and often **DS**), then fail before **CA** (`ep_flag = 1`, `ca_flag = 0`, drop often `DS2CA`). |

**Do not** read `type = LIGHT_APPROVAL` + `reason = CLEAR_NO` as “light approval of a clear no.”
The rejection wins; `LIGHT_APPROVAL` is only the docs-policy type the matrix would have applied
(SOX / contract: outcome = reject).

July-2026 shape (illustrative): most scary `LIGHT_APPROVAL` + `CLEAR_NO` volume is the
**post-policy** row (~paid `category` + `INSTABLE_INCOME`/`HIGH_DTI`); policy clear-no with
`LIGHT_APPROVAL` is residual (`category` null + `BAD_SCORE_ALL_PROPONENTS`).

Source for the split: `datalake_sorting_hat_clean.credit_analysis`. Prefer it (or join via
`id_credit_analysis`) when you need `automatic_decision_reason` — that column is **not** on
`dw_credit.dim_credit_analysis` today.

Funnel flags / `guarantee_offered` live on `fpcf` — see [`credit_analysis.md`](credit_analysis.md).

### Docs / eligibility state machine (post-docs hard-stops)

The credit engine runs documentation / eligibility checks as a **versioned state machine**
(`analysis_machine`): each (re-)run creates a new **machine version**, and
`is_current_machine = true` marks the latest one (older versions are superseded — don't mix
them). `analysis_state_group` holds the per-check results within a machine run.

**State-machine join** (~97% match): `fpcf.sk_analysis_request` =
`analysis_machine.id_analysis_request` (`is_current_machine = true`) →
`analysis_state_group.id_machine`. Join on `id_analysis_request`, not `id_proposal`
(documentation machines often have NULL `id_proposal`). Checklist compliance view:
`dw_credit.fact_credit_engine_analysis_request`.

## Models behind the policies

| Model | Produces | Notes |
|---|---|---|
| **Alpha** | tenant default probability → risk/score columns | Replacing *internal-target* |
| **income-verifier** | credibility of declared income | Feeds income-data flow |
| **liquidity_rent** | rent-liquidity score | Policy 5+ input; also `dw_liquidity.*` |

Raw per-inference I/O is not analyst-queryable ([Known gaps](#known-gaps-future-work)).

## Early credit vs proposal reports

A proposal evaluation writes its own `PROPOSAL` policy report; early credit writes a separate
`CREDIT_EVALUATION` report — distinct `id_credit_evaluation`s, neither overwrites the other
(~99% of evaluated proposals have a `PROPOSAL` report since May 2026).
`fpcf.sk_early_credit_analysis` is a DW offer correlation, not a reuse flag (see `fpcf` metadata).

**Feed history:** before ~April 2026 only Credit Passport wrote policy reports; regular
`PROPOSAL` / house-based `CREDIT_EVALUATION` began April 2026. Passport is discontinued
(`CREDIT_EVALUATION` with `id_house` NULL stop after early 2026).

## Relationships with Other Entities

- `fpcf.sk_last_variant_not_null` → `dim_variant.id_variant`.
- `fpcf` ↔ `policy_report`: evaluation-grain on `id_credit_evaluation` (see Critical rules); proposal
  shortcut `CAST(pr.id_proposal AS BIGINT) = f.sk_proposal AND pr.external_source = 'PROPOSAL'` with
  `f.is_last_credit_evaluation = true` for latest-analysis joins (≥ 2026-05).
- Early credit ↔ policy report on `id_credit_evaluation` + `CREDIT_EVALUATION`.
- `fpcf.sk_analysis_request` → `analysis_machine` → `analysis_state_group` (hard-stops).

## Dos and don'ts

**Do:**

- Risk band / internal score on an analysis → `dim_credit_analysis` (`risk_category_canon`,
  `internal_score`). Screening / calibrated scores, policy inputs, `experiment_groups` →
  `policy_report_credit_policy` (see metadata for join/coverage).
- Prefer `analysis_category_name` / `guarantee_offered` over raw int codes.
- Split rejection *why* by kind (pre-policy / policy clear-no / post-policy pre-docs /
  post-docs) using `category` + `reason` + `automatic_decision_reason` as in the table above.

**Don't:**

- Treat every `reason = CLEAR_NO` as policy clear-no — check `category` and
  `automatic_decision_reason` (`INSUFFICIENT_INCOME` = pre-policy; `BAD_SCORE_*` = policy;
  `INSTABLE_INCOME` / `HIGH_DTI` = post-policy pre-docs).
- Read `type` / `documentation_policy = LIGHT_APPROVAL` as “reached docs” or “light approval”
  when `result = REJECTED`.
- Look for granular auto-rejection *why* in `dim_credit_analysis.reason` alone (path only;
  use `automatic_decision_reason` on clean Sorting Hat).
- Segment by coarse `risk_category` (A–E) — use `risk_category_canon` / `risk_category_range`.
- Compare `FREE` vs paid without controlling for risk band and population (policy-selected,
  not randomised).
- Group by `policy-N` across model lineages — see `dim_variant` metadata.
- Expect raw Alpha / model I/O as columns (Known gaps).
- Include **stale machine-version rows** in checklist / state-machine analysis — always use the
  most current integration-report analysis for that checklist (`is_current_machine = true`);
  older machine versions are superseded.

## Additional queries — decision matrix discovery

Recovers the *current* **policy matrix** from data (which `policy_matrix` is selected; cell →
outcome). This is **not** experiment discovery — for listing live experiment names/arms and the
analysis checklist, see
[`credit_experiments.md` → How to observe & query any experiment](credit_experiments.md#how-to-observe--query-any-experiment).

**M1** keeps `experiment_groups`, `city_group`, and `retenant_type` so you can see which inputs
selected which matrix (experiments and retenants pick different `policy_matrix` values). **M2**
grains only on `variant × policy_matrix × income × risk` → outcome. Always keep **`variant`**. On
M1, `experiment_groups` is a **MAP** — equatable (`GROUP BY` is fine) but **not orderable** on
Trino or Databricks; cast before `ORDER BY` (`json_format(CAST(... AS JSON))` on Trino; on
Databricks use `CAST(... AS STRING)` instead).

### Query M1 — matrix selection (which inputs pick which `policy_matrix`)

```sql
SELECT
    variant,
    json_format(CAST(experiment_groups AS JSON)) AS experiment_groups,
    city_group,
    retenant_type,
    policy_matrix,
    count(*) AS n
FROM datalake_sorting_hat.policy_report_credit_policy
WHERE external_source = 'PROPOSAL'
  AND ts_created >= TIMESTAMP '2026-07-01 00:00:00 UTC'
GROUP BY 1, 2, 3, 4, 5
ORDER BY 1, 2, 3, 4, 5;
```

### Query M2 — decision matrix (cell → outcome)

One outcome per `(variant × policy_matrix × income × risk band)` cell. `city_group` and
`retenant_type` only select which matrix runs (see M1) — do not re-grain on them here. Do **not**
drop `variant` or `policy_matrix` — same matrix *name* can differ across variants.

```sql
SELECT
    variant,
    policy_matrix,
    income_group,
    risk_category_range,
    analysis_category_name AS outcome,
    count(*) AS n
FROM datalake_sorting_hat.policy_report_credit_policy
WHERE external_source = 'PROPOSAL'
  AND ts_created >= TIMESTAMP '2026-07-01 00:00:00 UTC'
GROUP BY 1, 2, 3, 4, 5
ORDER BY 1, 2, 3, 4;
```

## Golden queries

Funnel queries → [`credit_analysis.md`](credit_analysis.md); experiments →
[`credit_experiments.md`](credit_experiments.md). Matrix discovery →
[Additional queries](#additional-queries--decision-matrix-discovery) (M1/M2).

### Query P1 — Decisions by variant

```sql
SELECT
    v.variant_name,
    f.guarantee_offered,
    count(*) AS proposals
FROM dw_credit.fact_proposal_credit_flows AS f
JOIN dw_credit.dim_variant AS v
    ON f.sk_last_variant_not_null = v.id_variant
WHERE f.is_last_credit_evaluation = true
  AND f.dt_last_credit_evaluation_init >= DATE '2025-01-01'
GROUP BY 1, 2
ORDER BY 3 DESC;
```

### Query P2 — Guarantee by risk band & income

```sql
SELECT
    pr.risk_category_range,
    pr.income_group,
    pr.analysis_category_name,
    count(*) AS credit_evaluations
FROM datalake_sorting_hat.policy_report_credit_policy AS pr
WHERE pr.external_source = 'PROPOSAL'
  AND pr.ts_created >= TIMESTAMP '2026-05-01 00:00:00 UTC'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 4 DESC;
```

### Query P3 — Guarantee vs current listing liquidity

```sql
SELECT
    CASE
        WHEN l.rent_liquidity_score IS NULL THEN 'unknown'
        WHEN l.rent_liquidity_score >= 0.5 THEN 'high (>=0.5)'
        ELSE 'low (<0.5)'
    END AS liquidity_band,
    f.guarantee_offered,
    count(*) AS proposals
FROM dw_credit.fact_proposal_credit_flows AS f
JOIN dw_liquidity.fact_house_listing_rent_liquidity AS l
    ON f.sk_house_listing = l.sk_house_listing
WHERE f.is_last_credit_evaluation = true
  AND f.ep_flag = 1
  AND f.dt_credit_evaluation_approved_date >= DATE '2025-01-01'
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
```

### Query P4 — Hard-stop rejection reasons

```sql
SELECT
    regexp_replace(sg.group_name, 'AUTOMATIC_DECISION_ELIGIBILITY_REJECTION_BY_', '') AS reason,
    count(DISTINCT f.sk_proposal) AS proposals
FROM datalake_sorting_hat_clean.analysis_state_group AS sg
JOIN datalake_sorting_hat_clean.analysis_machine AS m
    ON sg.id_machine = m.id AND m.is_current_machine = true
JOIN dw_credit.fact_proposal_credit_flows AS f
    ON f.sk_analysis_request = m.id_analysis_request
    AND f.is_last_credit_evaluation = true
WHERE sg.group_name LIKE 'AUTOMATIC_DECISION_ELIGIBILITY_REJECTION_BY_%'
  AND sg.result = 'SATISFIED'
  AND sg.ts_created >= TIMESTAMP '2026-06-01 00:00:00 UTC'
GROUP BY 1
ORDER BY 2 DESC;
```

### Query P5 — Disambiguate Sorting Hat `CLEAR_NO` (policy vs post-policy)

```sql
SELECT
    type AS documentation_policy,
    result,
    CASE
        WHEN category IS NULL THEN 'policy_or_pre_policy_clear_no'
        WHEN category = 0 THEN 'policy_free'
        WHEN category IN (25, 26, 55) THEN 'policy_paid'
        ELSE CAST(category AS VARCHAR)
    END AS credit_policy_category,
    reason,
    automatic_decision_reason,
    count(*) AS analyses
FROM datalake_sorting_hat_clean.credit_analysis
WHERE ts_created >= TIMESTAMP '2026-07-01 00:00:00 UTC'
GROUP BY 1, 2, 3, 4, 5
ORDER BY 1, 2, 3, 4, 5;
-- Pre-policy: category null + INSUFFICIENT_INCOME
-- Policy clear-no: category null + BAD_SCORE_ALL_PROPONENTS
-- Post-policy pre-docs: category set + CLEAR_NO + INSTABLE_INCOME / HIGH_DTI
-- Post-docs: reason AUTOMATIC_REJECTION_* (not CLEAR_NO)
```

## Known gaps & future work

- **QuintoCred / Neurotech B2B** — `dw_neurotech_quintocred.fact_credit_flow`, etc. (discontinued).
- **Delinquency "ever" labels** — `dw_credit_evers.fact_ever` / `fact_ever_full` (sparse metadata).
- **Credit-journey Amplitude** — `datalake_credit_journey_experience.*` (minimal metadata).
- **Per-prediction model I/O via Emlio** — only raw `datalake_emlio_clean.emlio_logs` for
  `alpha` / `income-verifier` / `tenant-screening`; no enrich table. The bureau **inputs** the
  models consumed *are* separately available (not the model output):
  `datalake_arquivo_confidencial_clean.integration_report` (Boa Vista, Serasa, TransUnion,
  BigDataCorp, …) + `datalake_arquivo_confidencial.scr` / `scr_pivot`, keyed by `cpf` (PII).

## DataHub catalog

- **Data Product:** published by CI (`credit_policy.md` → `credit-policy`).
- **Primary datasets:** `datalake_sorting_hat.policy_report_credit_policy`,
  `dw_credit_passport.fact_credit_evaluation`, `dw_liquidity.fact_house_rent_liquidity`,
  `dw_liquidity.fact_house_listing_rent_liquidity`, `dw_credit.fact_credit_engine_analysis_request`.
