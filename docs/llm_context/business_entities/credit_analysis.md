# Credit Analysis

## Ownership

**Data Owner:**
- marcus.silva@quintoandar.com.br

**Data Steward:**
- davi.figueiredo@quintoandar.com.br

## Overview

Credit Analysis is the **tenant credit-decisioning funnel** for QuintoAndar's *For Rent*
operation: eligibility check → offer → evaluation → guarantee product → signed contract,
including whether the decision was automatic or manual. **This doc is the funnel &
outcomes entry point.**

**Analytical home:** start in **`dw_credit`** (proposal-grain funnel) and
**`dw_credit_passport`** (discontinued passport funnel — historical only). Column
definitions, value enums, and join caveats live in **DataHub / governance metadata** —
do not duplicate them here. Decisioning internals (scores, policy, experiments) live in
[`credit_policy.md`](credit_policy.md) and [`credit_experiments.md`](credit_experiments.md).

## Related Business Entities

- [`credit_policy.md`](credit_policy.md) — scores, policy, models, rejection internals,
  rent-liquidity, credit-evaluation lifecycle.
- [`credit_experiments.md`](credit_experiments.md) — experiment registry & policy dimensions.
- [`payments.md`](payments.md) — the paid guarantee a tenant pays.
- [`losses.md`](losses.md) — post-contract delinquency of approved tenants.
- [`recovery_collections_fr_tenants.md`](recovery_collections_fr_tenants.md) — For-Rent collections.
- `dw_rent` (`dim_proposal` / `dim_contract` / `fact_listing_rent_flows`) — upstream listing/offer funnel.
- [`house_and_listing.md`](house_and_listing.md) — house / listing grain.

## Related Metric Entities

- [Credit Metrics](../metric_entities/credit_metrics.md) — official credit-policy monitoring toolkit (Evers, FPD, EC|ES2CS, OA2CA, volume, unpublishing, guarantee/risk mix).

## For-Rent credit funnel

Top to bottom = funnel order. Cumulative `*_flag` columns on
`dw_credit.fact_proposal_credit_flows` (`1` once the proposal reached or passed that stage):

| # | Stage | Flag | What happens |
|---|-------|------|----------------|
| EC | Early credit | `ec_flag` | Optional pre-proposal evaluation for a **specific property** (`id_house` set): bureau data is retrieved and the models produce a score. Most common evaluation type (`external_source = 'CREDIT_EVALUATION'`, `id_proposal` NULL). Distinct from discontinued **Credit Passport** (user-level, house-less). |
| OS | Offer submitted | `os_flag` | Tenant submits an offer. |
| OA | Offer approved | `oa_flag` | **Owner** approves the offer. |
| ES | Evaluation started | `es_flag` | The **actual proposal credit evaluation** runs — bureau data is retrieved and the models generate a score, feeding the policy decision at EP. An offer always generates its own ES event even if the tenant already did an early credit. |
| EP | Evaluation positive | `ep_flag` | Positive decision — either approved with **no paid guarantee** (`FREE`), or approved with a **paid guarantee the tenant accepted**. **Any evaluation auto-reject** (`result = REJECTED` with Sorting Hat `reason = CLEAR_NO`, including pre-policy / policy clear-no / post-policy `INSTABLE_INCOME`·`HIGH_DTI`) **never reaches EP** — funnel drop `ES2EP` (`es_flag = 1`, `ep_flag = 0`). Post-docs rejects (`reason = AUTOMATIC_REJECTION_*`) can have reached EP (and often DS) then fail before CA. Details: [`credit_policy.md`](credit_policy.md#disambiguating-reason--clear_no). |
| DS | Document sent | `ds_flag` | Tenant sends documents (paid guarantee must be accepted first; `FREE` skips that). |
| CA | Credit approved | `ca_flag` | Credit analysis approved (auto or analyst). |
| CS | Contract signed | `cs_flag` | End-of-funnel conversion. |

`funnel_step` = current/last step; `funnel_drop_step` = where the client dropped (categories in metadata).

> **Guarantee acceptance vs silent drop-off — and the `ep_flag` trap.** Handle `FREE` and
> **paid** (`PRO_GUARANTOR_*`) offers differently (verified on Trino, mid-2026):
> - **`FREE`** is auto-accepted → `NOT_ACCEPTED` = **0**. A `FREE` tenant who stalls just
>   **silently abandons after EP** (`ep_flag = 1`, no `ds_flag`; ~45% do). Measure that with
>   funnel flags / `funnel_drop_step`, not acceptance columns.
> - **Paid** offers are **not** mostly silent: **~39% are `NOT_ACCEPTED`** (explicit
>   non-acceptance). The DW **rewrites** a paid `NOT_ACCEPTED` drop from `EP2DS` to `ES2EP`,
>   which forces **`ep_flag = 0`** — so in the funnel model a paid non-acceptance is treated as
>   *"never reached EP."*
> - Because of that rewrite, do **not** filter `ep_flag = 1` when measuring paid acceptance or
>   `NOT_ACCEPTED`. Use `is_guarantee_accepted` / `guarantee_accepted` over **paid offers**
>   (`guarantee_offered LIKE 'PRO_GUARANTOR%'`) **without** pre-filtering `ep_flag`, and pick a
>   grain (Query 5). Never put `FREE` (auto-accepted) or `CLEAR_NO` (no offer) in an acceptance
>   rate.
> - **Caveat on the columns themselves:** `is_guarantee_accepted` / `guarantee_accepted` reflect the
>   **enum outcome** on the credit analysis (`NOT_ACCEPTED` / `CLEAR_NO` / NULL → false; any other
>   accepted paid/free value → true) — not whether a rental-guarantee record was later paid. For the
>   truly-paid population join `datalake_rental_guarantee.guarantee` (`guarantee_status`,
>   `cancellation_reason`).

### Time, funnel lag & right-censoring

The funnel takes **days**: EP today still needs DS → CA → CS. Recent days are
**right-censored** — naïve "EP→CA last 3 days" looks like conversion is falling when it
is mostly incomplete. Weekends add similar volume noise.

- **Censored (don't trust recent days):** EP→CA, DS→CA, EP→CS, CA→CS, contract counts.
  Worst in last ~3 days; largely settled by ~7 days.
- **Not censored:** the credit decision itself (`decision_type`, `CLEAR_NO` / approval at
  OA→EP, `policy_report.rejection_reason`, guarantee offered).

**Safe conversion analysis:** cohort by an *entry* date (e.g. EP =
`dt_credit_evaluation_approved_date`), compare equal maturation, exclude cohorts younger
than ~5–7 days, re-pull after maturity, and sanity-check against uncensored OA→EP /
`CLEAR_NO` — if the decision metric did not move, a downstream "drop" is likely lag.

> **Choose the conversion unit first.** Conversion can be measured on three concepts, which
> answer different questions and dedup differently:
> - **Event** — per `sk_proposal`; dedup multiple credit evaluations to the most recent
>   (`is_last_credit_evaluation = true`).
> - **User** — per `sk_client`; when a user has several proposals, keep the one that
>   progressed **furthest in the funnel within the observation window** (weekly/monthly).
> - **Listing** — per `sk_house_listing`; same furthest-progressed dedup as User.
>
> Elect one before computing rates; the Risk/MIS team's official numbers pick a specific concept.

## Data architecture

| System | Role | Lake / DW home |
|--------|------|----------------|
| **docx** | `CreditEvaluation` lifecycle | `datalake_docx` (enrich); lifecycle DW in `dw_credit_passport.fact_credit_evaluation` |
| **Sorting Hat** (*credito*) | Decision engine | `datalake_sorting_hat`, `datalake_credit_analysis` |
| **Credit Passport** | Discontinued pre-offer flow (early 2026) | `dw_credit_passport` |

**Layer preference:** DW default → enrich when no DW column (esp.
`policy_report_credit_policy`) → clean last resort.

## Glossary and Synonyms

- **Análise de crédito** → credit analysis (the decision)
- **Avaliação de crédito** → credit evaluation / `CreditEvaluation` (docx lifecycle)
- **Funil de crédito** → EC→…→CS; cumulative flags on `fpcf`
- **Garantia** → guarantee product — `guarantee_offered` on `fpcf` (`FREE`, `CLEAR_NO`, generic
  `PRO_GUARANTOR`, …). **Paid tier labels** (`PRO_GUARANTOR_50_PERC` / `_75_PERC` / `_100_PERC` =
  paid 4 / 6 / 8) are reliable on `policy_report_credit_policy.analysis_category_name`, not on
  `fpcf.guarantee_offered` (enrich collapses paid tiers to `PRO_GUARANTOR`).
- **Aceitação da garantia** → tenant accepting a **paid** guarantee — trivial for `FREE`; N/A for `CLEAR_NO`
- **Aceitação da oferta (owner)** → `oa_flag` (distinct from guarantee acceptance)
- **Conversão / contrato fechado** → `cs_flag`
- **Early credit / crédito antecipado** → pre-proposal, property-specific eligibility
- **Passaporte de crédito** → discontinued user/group pre-offer flow — `dw_credit_passport.*`
- **Sorting Hat / "credito"** → decision engine — internals in [`credit_policy.md`](credit_policy.md)
- **docx** → credit-evaluation lifecycle + documentation service
- **Bypass** → auto-decision short-circuit — reason enums in `dim_credit_analysis.bypass` metadata
- **AnalysisType / `documentation_policy` / Sorting Hat `type`** → configured docs depth
  (`LIGHT_APPROVAL` / `FLEX` / `FULL` / …). **Not** a funnel stage and **not** “approved light” —
  can sit on `REJECTED` rows; see [`credit_policy.md`](credit_policy.md#evaluation-sequence-on-sorting-hat-credit_analysis)
- **Sorting Hat `reason = CLEAR_NO`** → overloaded decision path (pre-policy / policy clear-no /
  post-policy pre-docs). Disambiguate with `category` + `automatic_decision_reason` — **not** the
  same as funnel `guarantee_offered = 'CLEAR_NO'` alone
  ([`credit_policy.md`](credit_policy.md#disambiguating-reason--clear_no))
- **Retenant** → returning tenant — `dim_credit_analysis_retenants`
- **DocPilot** → automated doc validation (`DOCPILOT_CLEAR_YES`)
- **Screening / score** → use `risk_category_canon` / `risk_category_range`; coarse `risk_category` (A–E) is **legacy**

## Tables

| You need… | Use this table |
|-----------|----------------|
| **Proposal credit funnel** (default) | `dw_credit.fact_proposal_credit_flows` (`fpcf`) — see metadata for grain, flags, dates, enums |
| **Credit Passport funnel** (historical) | `dw_credit_passport.fact_credit_passport_flows` — dedup `is_group_last_credit_evaluation` |
| **Decision detail per analysis** | `dw_credit.dim_credit_analysis` — prefer over enrich; enrich only for `liquidity` / `max_ca_category` |
| Early-credit results | `dw_credit.fact_early_credit`, `dw_credit.fact_offer_early_credit` |
| Per-proponent income | `dw_credit.fact_proponent_income_sources`, `dw_credit.dim_proponent_proposal_informed_incomes` |
| Guarantee category → product | `dw_credit.dim_guarantee_policy` |
| Model variant | `dw_credit.dim_variant` (`dim_experiment` is **deprecated/legacy** — don't use it; see [`credit_experiments.md`](credit_experiments.md)) |
| Retenant classification | `dw_credit.dim_credit_analysis_retenants` |
| DocPilot extraction | `dw_credit.dim_docpilot_proposal_extraction_results` |

**Critical rules:**

- Dedup proposals: `is_last_credit_evaluation = true`.
- Sentinel keys: `sk_* = -1` means absent — filter `<> -1` before joining.
- Date filters: stage date columns (no `year/month/day` partitions) — see metadata.
- Right-censoring: post-EP rates incomplete for recent cohorts (section above).
- Do not mix `fpcf` with passport flows without explicit intent.
- Scores / policy / granular rejection *why* → [`credit_policy.md`](credit_policy.md).
- Auto-reject taxonomy (`CLEAR_NO` vs `AUTOMATIC_REJECTION_*`, `automatic_decision_reason`) →
  [`credit_policy.md`](credit_policy.md#disambiguating-reason--clear_no); pre-docs auto-rejects
  stop at **ES→EP**.

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) for **official** credit-policy monitoring metrics. The bullets below are **component** funnel ratios on `fpcf` — suitable for ad-hoc exploration; EC|ES2CS and other official definitions live in the metric entity.

### Official metrics (metric entities)

| When you need… | Metric entity |
|----------------|---------------|
| Evers, FPD, EC\|ES2CS, OA2CA, volume, unpublishing, guarantee/risk mix | [Credit Metrics](../metric_entities/credit_metrics.md) |

### Component / exploratory metrics

All on `fpcf` with `is_last_credit_evaluation = true`. Stage ratio =
`SUM(later_flag) / SUM(earlier_flag)`. Past EP, exclude immature cohorts.

- **Offers submitted** — `SUM(os_flag)`
- **Approval rate (OS→CA)** — `SUM(ca_flag) / SUM(os_flag)`
- **Offer→contract (OS→CS)** — `SUM(cs_flag) / SUM(os_flag)` (censored when recent)
- **Credit-policy conversion (ES2CS / EC\|ES2CS)** — official definition in [Credit Metrics](../metric_entities/credit_metrics.md); do not use naive `ES→CS` alone for policy impact analysis
- **Intent rate (OA→ES)** — `SUM(es_flag) / SUM(oa_flag)` (not censored)
- **Evaluation-positive (OA→EP)** — `SUM(ep_flag) / SUM(oa_flag)` (not censored)
- **CLEAR_NO rate (funnel product)** — share of `guarantee_offered = 'CLEAR_NO'` among `es_flag`
  (typically `category` null). Does **not** include post-policy pre-docs rejects that kept a paid
  `category` / product on `guarantee_offered` while `result = REJECTED` — split those in
  [`credit_policy.md`](credit_policy.md#disambiguating-reason--clear_no)
- **Post-offer conversion (EP→CS)** — cohort by EP date; right-censored when recent
- **Guarantee mix** — `GROUP BY guarantee_offered` where `ep_flag = 1` on `fpcf` (coarse paid =
  `PRO_GUARANTOR`). For **tier-level** mix (paid 4/6/8), use `policy_report.analysis_category_name`
  ([`credit_policy.md`](credit_policy.md)).
- **Paid-guarantee acceptance** — `is_guarantee_accepted` among `guarantee_offered LIKE 'PRO_GUARANTOR%'`; **do not** pre-filter `ep_flag = 1` (see the acceptance note above); pick a grain — **user grain** ≈ Risk's official ~77% (Query 5)
- **Automatic vs manual** — `GROUP BY decision_type` (~99% automatic)

## Relationships with Other Entities

### For Rent listing / proposal (N:1)

- `fpcf.sk_proposal` → `dw_rent.dim_proposal`; `sk_contract` → `dw_rent.dim_contract`;
  `sk_house_listing` → `dw_rent.fact_listing_rent_flows`. House grain:
  [`house_and_listing.md`](house_and_listing.md).

### Credit analysis decision (N:1)

- `fpcf.sk_credit_analysis` → `dim_credit_analysis.id_credit_analysis` (where `<> -1`).

### Retenant / guarantee / variant

- `dim_credit_analysis_retenants.sk_credit_analysis` = `dim_credit_analysis.id_credit_analysis`.
- `fpcf.sk_guarantee_category` → `dim_guarantee_policy`.
- `fpcf.sk_first_variant` / `sk_last_variant_not_null` → `dim_variant` (its `id_experiment` →
  `dim_experiment` is **deprecated/legacy** — not for current analysis).
- Scores / `experiment_groups`: `policy_report_credit_policy` — [`credit_policy.md`](credit_policy.md).

### Credit Passport / identity

- Passport: `fact_credit_passport_flows.sk_credit_evaluation` → `fact_credit_evaluation`.
- `sk_client` / `sk_user` = **EBDB user id**, not CPF. CPF only on
  `fact_proponent_income_sources.proponent_cpf` (PII).

## Dos and don'ts

**Do:**

- Start from `dw_credit.fact_proposal_credit_flows` for funnel / conversion / guarantee questions.
- Deduplicate with `is_last_credit_evaluation = true`.
- Elect the conversion concept — Event (`sk_proposal`), User (`sk_client`), or Listing
  (`sk_house_listing`) — before computing conversion rates (see right-censoring section).
- Use cumulative `*_flag` / `funnel_step` for conversion rates.
- Filter on the **stage date** being measured; for decision mix / rejections use
  `dt_last_credit_evaluation_init` (not approval-only dates) — see column metadata.
- Prefer `dim_credit_analysis` over enrich; prefer name columns (`guarantee_offered`) over int codes.
- For **paid**-guarantee acceptance, use `is_guarantee_accepted` over `guarantee_offered LIKE
  'PRO_GUARANTOR%'` (pick a grain, don't filter `ep_flag`); for **FREE** post-EP drop-off, use
  funnel flags / `funnel_drop_step`.
- For scores / policy inputs / experiment arms / rejection taxonomy →
  [`credit_policy.md`](credit_policy.md).

**Don't:**

- Assume `guarantee_offered` / `decision_*` are filled before evaluation (often NULL).
- Infer “reached docs” or “light approval” from `documentation_policy` / `type = LIGHT_APPROVAL`
  alone — especially on `REJECTED` rows.
- Treat every Sorting Hat `reason = CLEAR_NO` as funnel policy clear-no — check `category` +
  `automatic_decision_reason` ([`credit_policy.md`](credit_policy.md#disambiguating-reason--clear_no)).
- Mix passport and proposal funnels; use `is_credit_passport` to flag passport-origin rows on `fpcf`.
- Read `sk_early_credit_analysis <> -1` as "early-credit result reused" — see column metadata.
- Measure guarantee acceptance **among `ep_flag = 1`** — paid `NOT_ACCEPTED` (~39%) is rewritten
  to `ES2EP` (`ep_flag = 0`), so an EP filter misses non-acceptance. Use **paid offers**
  (`guarantee_offered LIKE 'PRO_GUARANTOR%'`) without `ep_flag` (Query 5); never put `FREE`
  (auto-accepted) or `CLEAR_NO` (no offer) in an acceptance rate.
- Treat `is_guarantee_accepted = true` as "tenant accepted the offered guarantee enum" — not
  "guarantee paid/active"; for truly-paid use `datalake_rental_guarantee.guarantee`.
- Do not filter `fpcf.guarantee_offered = 'PRO_GUARANTOR_50_PERC'` (etc.) — tiers live on
  `policy_report.analysis_category_name`.
- Segment by legacy `risk_category` (A–E) — use `risk_category_canon` / `risk_category_range`.
- Trust recent post-EP conversion at face value (right-censoring).
- Expect this funnel to cover For-Sale or QuintoCred/Neurotech B2B credit
  ([`credit_policy.md` Known gaps](credit_policy.md#known-gaps-future-work)).

## Golden queries

Trino dialect. Decisioning / experiment queries live in sibling docs. `SELECT` lists are
illustrative — prefer explicit columns in production.

### Query 1 — Monthly funnel (offer → contract)

```sql
SELECT
    date_trunc('month', dt_offer_submitted_date) AS month,
    SUM(os_flag) AS offers_submitted,
    SUM(oa_flag) AS offers_approved,
    SUM(ep_flag) AS evaluation_positive,
    SUM(ca_flag) AS credit_approved,
    SUM(cs_flag) AS contracts_signed,
    CAST(SUM(ca_flag) AS DOUBLE) / NULLIF(SUM(os_flag), 0) AS approval_rate
FROM dw_credit.fact_proposal_credit_flows
WHERE is_last_credit_evaluation = true
  AND dt_offer_submitted_date >= DATE '2025-01-01'
GROUP BY 1
ORDER BY 1;
```

### Query 2 — Guarantee mix among EP

```sql
SELECT guarantee_offered, count(*) AS proposals
FROM dw_credit.fact_proposal_credit_flows
WHERE is_last_credit_evaluation = true
  AND ep_flag = 1
  AND dt_credit_evaluation_approved_date >= DATE '2025-01-01'
  AND guarantee_offered IS NOT NULL
GROUP BY 1
ORDER BY 2 DESC;
```

### Query 3 — Automatic vs manual (checklist decisions only)

Counts rows with a credit-engine `decision_type` (checklist path). Pre-policy / policy-level
auto-rejects that never reach the checklist (`INSUFFICIENT_INCOME`, score clear-no, pre-docs
`INSTABLE_INCOME` / `HIGH_DTI`) are **excluded** — use Query P5 in [`credit_policy.md`](credit_policy.md)
for the full rejection taxonomy.

```sql
SELECT decision_type, decision_reason, count(*) AS analyses
FROM dw_credit.fact_proposal_credit_flows
WHERE is_last_credit_evaluation = true
  AND decision_type IS NOT NULL
  AND dt_last_credit_evaluation_init >= DATE '2025-01-01'
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
```

### Query 4 — Funnel × risk band / score

```sql
SELECT
    f.sk_proposal,
    f.guarantee_offered,
    f.decision_type,
    d.risk_category_canon,
    d.internal_score,
    d.documentation_policy
FROM dw_credit.fact_proposal_credit_flows AS f
LEFT JOIN dw_credit.dim_credit_analysis AS d
    ON f.sk_credit_analysis = d.id_credit_analysis
WHERE f.is_last_credit_evaluation = true
  AND f.sk_credit_analysis <> -1
  AND f.dt_last_credit_evaluation_init >= DATE '2025-01-01';
```

### Censoring-aware EP→CA by maturation

```sql
SELECT
    date_diff('day', f.dt_credit_evaluation_approved_date, current_date) AS days_mature,
    count(*) AS reached_ep,
    CAST(SUM(ca_flag) AS DOUBLE) / NULLIF(count(*), 0) AS ep_to_ca
FROM dw_credit.fact_proposal_credit_flows AS f
WHERE f.is_last_credit_evaluation = true
  AND f.ep_flag = 1
  AND f.dt_credit_evaluation_approved_date >= current_date - INTERVAL '21' DAY
GROUP BY 1
ORDER BY 1;
```

### Query 5 — Paid-guarantee acceptance rate (Risk's "acceptance rate")

Acceptance is only meaningful for **paid** offers. Risk's official ~77% figure is the **user
grain** (`is_user_version`) for BR / QuintoAndar; **event** grain runs lower (~65%). Verified on
Trino: user grain May–Jun 2026 = **77.4%**. **Do not** add `ep_flag = 1` — paid `NOT_ACCEPTED` is
rewritten to ES→EP (`ep_flag = 0`); measure over paid offers without that filter (see acceptance
note above).

```sql
SELECT
    date_trunc('month', dt_reference) AS month,
    count(*) AS paid_offers,
    SUM(CASE WHEN is_guarantee_accepted THEN 1 ELSE 0 END) AS accepted,
    CAST(SUM(CASE WHEN is_guarantee_accepted THEN 1 ELSE 0 END) AS DOUBLE)
        / NULLIF(count(*), 0) AS acceptance_rate
FROM dw_credit.fact_proposal_credit_flows
WHERE is_last_credit_evaluation = true
  AND is_user_version = true                 -- User grain per Risk ~77%; drop for event grain
  AND guarantee_offered LIKE 'PRO_GUARANTOR%'
  AND country_code = 'BR'
  AND rental_administrator = 'QUINTOANDAR'
  AND dt_reference >= DATE '2026-05-01'
GROUP BY 1
ORDER BY 1;
-- Bucket on dt_reference (offer-submitted month) — matches is_user_version dedup axis.
-- "Accepted" = guarantee_accepted enum accepted (not NOT_ACCEPTED/CLEAR_NO/NULL).
-- For truly-paid, join datalake_rental_guarantee.guarantee (guarantee_status / cancellation_reason).
```

## DataHub catalog

- **Data Product:** published by CI from this Markdown (`credit_analysis.md` → `credit-analysis`).
- **Primary datasets:** `dw_credit.fact_proposal_credit_flows`, `dw_credit.dim_credit_analysis`,
  `dw_credit.dim_variant`, `dw_credit_passport.fact_credit_passport_flows`.
  (`dw_credit.dim_experiment` is **deprecated/legacy** — see [`credit_experiments.md`](credit_experiments.md).)
