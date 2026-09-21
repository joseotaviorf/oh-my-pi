# NPS FR

## Ownership

**Data Owner:**
- samia.lauar@quintoandar.com.br
- felipe.abreu@quintoandar.com.br

**Data Steward:**
- victor.prado@quintoandar.com.br

## Description

**NPS FR** groups the Net Promoter Score metrics of the For Rent product, from the official
anchor (**NPS True**, a weighted average of the onboarding / ongoing / offboarding journeys)
down to the per-journey components and the operational cuts the CX team follows. Every metric
here runs the same engine — `% promoters − % detractors` over answered dispatches — applied to
a different population: a single journey, the PP Multi base, the SPOC experiment, or the
support-interaction type. What separates them is the population filter and, for the two
weighted metrics, the quarterly weights read from `nps_target_share`.

Offboarding NPS segmented by digital vs human support (U&J / Seamless ticket classification) is
defined in [`offboard_human_vs_digital_metrics.md`](offboard_human_vs_digital_metrics.md) — this
document does not redefine those cuts.

**This product exists exclusively for For Rent — there is no equivalent weighted NPS for For
Sale or any other product.**

## Domain

For Rent

## Related Domain Entities

- NPS

## Targets and OKRs

**NPS Onboarding / NPS Ongoing / NPS Offboarding — OKR** — monthly period goal per journey,
co-located with the official weights in the same GSheet table. Informational only: the target is
**never** an input to any calculation in this document.

- **Source table:** `datalake_gsheets_clean.target_service_kpis`
- **Filter key / metric name:** `NPS For Rent`, matching `campaign_group` to the journey
  (onboarding = `NPS Onboarding`, ongoing = `NPS Ongoing`, offboarding = `NPS Offboarding`)
- **Period grain:** month
- **Value column:** `target`
- **Aliases / search terms:** meta de NPS, target de NPS, meta NPS True, OKR NPS
- **Caveat:** never substitute a target for a computed NPS, and never report a target as if it
  were the realized number.

## Metrics

### NPS True

#### Slug

nps_true

#### Description

**NPS True** is the official For Rent NPS: the weighted average of the NPS computed
independently for the onboarding, ongoing and offboarding journeys, using quarterly weights set
by the CX team. It differs from the naive calculation in that pooling every answer into one flat
pool is **systematically wrong** — journey volumes are very different, and the flat pool distorts
the result by up to 5 points.

#### Also Known As

- **NPS FR**, **official NPS**, **weighted NPS**, **NPS ponderado**
- **QUBE NPS score breakdown** → near-miss — the `qube_metrics.nps_answer__score_breakdown__*`
  precompute counts answers across **all** NPS campaigns with no `business_context`,
  `customer_journey` or `purpose` filter and no journey weighting, so it never reproduces this
  number.

#### Rules

- **Canonical filter:** `dnc.business_context = 'forRent' AND dnc.customer_journey = 'true' AND
  dnc.purpose = 'main'`, over `fnd.is_answered = true`. The three predicates always travel
  together — they select exactly the `onboarding` / `ongoing` / `offboarding` campaigns, the same
  population the team's official dataset reaches via `metric_group IN ('iqonboarding',
  'pponboarding', 'iqongoing', 'ppongoing', 'iqoffboarding', 'ppoffboarding')`. On any divergence,
  the `metric_group` list is the source of truth.
- **Common mistake:** filtering only on `business_context = 'forRent'`. That pulls in lost, po,
  PP Multi, international and test campaigns and inflates the answer base well beyond the
  official NPS FR population.
- **Note on `customer_journey`:** in `dim_nps_campaign` it is the lowercase string `'true'`, not
  a boolean — and not the UPPERCASE `'TRUE'` used by `nps_target_share`.
- **Never pool the journeys:** compute each journey's NPS first, then weight. A direct pool is a
  different number, not an approximation of this one.
- **Excluded population:** lost, po, international campaigns (mexico, bo), agents, brokers,
  `purpose = 'test'`, and all of PP Multi (`*_ppm` campaigns and `currentpo`) — PP Multi is its
  own metric and does not enter the weighted number.
- **Parameters:** weights read from `datalake_gsheets_clean.nps_target_share`.`share`, filtered
  on `customer_journey = 'TRUE'` (UPPERCASE here) — never hardcoded. Parse as
  `CAST(REPLACE(share, '%', '') AS DOUBLE) / 100.0`; join `campaign_group` to the journey and
  `CAST(ref_month AS DATE) BETWEEN dt_start AND dt_end`.
- **Fallback:** a month with no registered quarter falls back to the most recent weight per
  journey (`ROW_NUMBER() OVER (PARTITION BY journey ORDER BY dt_end DESC)`). This is **designed
  behavior, not a data problem** — `weight_source = 'fallback'` is expected on its own and is
  never grounds to flag the number as incomplete or at risk, however old the fallback weight is.
  Do not escalate or draw attention to it. Aggregate the flag with `MIN`, never `MAX`, so
  `'fallback'` surfaces when any journey lacks an official weight.
- **Deduplication:** unique per `sk_nps_answer`; always count with
  `COUNT(DISTINCT sk_nps_answer)`, numerator and denominator alike.
- **Query-time breakdowns (not materialized):** IQ / PP via `dnc.customer_type` (`'IQ'` = tenant,
  `'PP'` = owner) — add it to the `journey_nps` grouping and to the final grouping. **Total is
  the pool of both populations in one denominator, never the average of the IQ and PP NPS.**

#### Type

OKR

#### Direction

Higher is better

#### Grain

monthly

#### Is Additive

false

#### MBR

Post Contract

#### Category

FR XP

#### Golden Query

Computes the monthly weighted NPS True, carrying the total answer volume and whether the weights
came from a registered quarter or from the fallback.

```sql
WITH journey_nps AS (
    SELECT
        date_trunc('month', CAST(dna.ts_answered AS TIMESTAMP)) AS ref_month,
        CASE
            WHEN dnc.metric_group LIKE '%onboarding%'  THEN 'onboarding'
            WHEN dnc.metric_group LIKE '%ongoing%'     THEN 'ongoing'
            WHEN dnc.metric_group LIKE '%offboarding%' THEN 'offboarding'
        END AS journey,
        COUNT(DISTINCT dna.sk_nps_answer) AS total_answers,
        ROUND(
            (CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'promoter'  THEN dna.sk_nps_answer END) AS DOUBLE)
           - CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'detractor' THEN dna.sk_nps_answer END) AS DOUBLE))
            / COUNT(DISTINCT dna.sk_nps_answer) * 100, 1
        ) AS nps_journey
    FROM dw_customer_satisfaction.fact_nps_dispatches AS fnd
    INNER JOIN dw_customer_satisfaction.dim_nps_answer AS dna
        ON fnd.sk_nps_answer = dna.sk_nps_answer
    INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc
        ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
    WHERE fnd.is_answered = true
      AND dnc.business_context = 'forRent'
      AND dnc.customer_journey = 'true'
      AND dnc.purpose = 'main'
      AND CAST(dna.ts_answered AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
      AND CAST(dna.ts_answered AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
    GROUP BY 1, 2
),
weights_raw AS (
    SELECT
        campaign_group AS journey,
        CAST(dt_start AS DATE) AS dt_start,
        CAST(dt_end AS DATE) AS dt_end,
        CAST(REPLACE(share, '%', '') AS DOUBLE) / 100.0 AS weight
    FROM datalake_gsheets_clean.nps_target_share
    WHERE customer_journey = 'TRUE'
      AND share IS NOT NULL
      AND share != ''
),
latest_weights AS (
    SELECT journey, weight
    FROM (
        SELECT
            journey,
            weight,
            ROW_NUMBER() OVER (PARTITION BY journey ORDER BY dt_end DESC) AS rn
        FROM weights_raw
    ) AS sub
    WHERE rn = 1
),
journey_with_weight AS (
    SELECT
        jn.ref_month,
        jn.journey,
        jn.nps_journey,
        jn.total_answers,
        w.weight,
        ROW_NUMBER() OVER (
            PARTITION BY jn.ref_month, jn.journey
            ORDER BY w.dt_start DESC, w.dt_end DESC
        ) AS rn
    FROM journey_nps AS jn
    LEFT JOIN weights_raw AS w
        ON jn.journey = w.journey
       AND CAST(jn.ref_month AS DATE) BETWEEN w.dt_start AND w.dt_end
)
SELECT
    d.ref_month,
    ROUND(SUM(d.nps_journey * COALESCE(d.weight, lw.weight)), 1) AS nps_true,
    SUM(d.total_answers) AS total_answers,
    MIN(CASE WHEN d.weight IS NULL THEN 'fallback' ELSE 'official' END) AS weight_source
FROM (SELECT * FROM journey_with_weight WHERE rn = 1) AS d
LEFT JOIN latest_weights AS lw
    ON d.journey = lw.journey
GROUP BY d.ref_month
ORDER BY d.ref_month
```

### NPS Onboarding

#### Slug

nps_onboarding

#### Description

**NPS Onboarding** is the NPS of the onboarding journey alone, reported **without** weighting. It
is one of the three components NPS True averages, so it is never the official For Rent number on
its own.

#### Also Known As

- **NPS de onboarding**, **NPS entrada**
- **NPS True** → near-miss — the weighted average of the three journeys, not this single
  component.

#### Rules

- **Canonical filter:** `dnc.business_context = 'forRent' AND dnc.customer_journey = 'true' AND
  dnc.purpose = 'main' AND dnc.metric_group IN ('iqonboarding', 'pponboarding')`, over
  `fnd.is_answered = true`.
- **Common mistake:** reporting this component as the official NPS FR. It carries no weight and
  answers a different question — the official number is NPS True.
- **Never weight it:** the quarterly `share` applies only when composing NPS True; the component
  is reported raw.
- **Classification:** `dim_nps_answer.score_category` — `promoter` (9–10), `passive` (7–8),
  `detractor` (0–6), always lowercase.
- **Deduplication:** unique per `sk_nps_answer`; count with `COUNT(DISTINCT sk_nps_answer)` in
  numerator and denominator.
- **Query-time breakdowns (not materialized):** IQ / PP via `dnc.customer_type`; **Total is the
  pool of both, never the average of the two NPS values.**

#### Type

Health Metric

#### Direction

Higher is better

#### Grain

monthly

#### Is Additive

false

#### MBR

Post Contract

#### Category

FR XP

#### Golden Query

Computes the monthly unweighted NPS of the onboarding journey, with the promoter, detractor and
total answer counts that make the rate re-aggregable over longer periods.

```sql
SELECT
    date_trunc('month', CAST(dna.ts_answered AS TIMESTAMP)) AS ref_month,
    COUNT(DISTINCT CASE WHEN dna.score_category = 'promoter'  THEN dna.sk_nps_answer END) AS promoters,
    COUNT(DISTINCT CASE WHEN dna.score_category = 'detractor' THEN dna.sk_nps_answer END) AS detractors,
    COUNT(DISTINCT dna.sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'promoter'  THEN dna.sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'detractor' THEN dna.sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT dna.sk_nps_answer) * 100, 1
    ) AS nps_onboarding
FROM dw_customer_satisfaction.fact_nps_dispatches AS fnd
INNER JOIN dw_customer_satisfaction.dim_nps_answer AS dna
    ON fnd.sk_nps_answer = dna.sk_nps_answer
INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc
    ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
WHERE fnd.is_answered = true
  AND dnc.business_context = 'forRent'
  AND dnc.customer_journey = 'true'
  AND dnc.purpose = 'main'
  AND dnc.metric_group IN ('iqonboarding', 'pponboarding')
  AND CAST(dna.ts_answered AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
  AND CAST(dna.ts_answered AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
GROUP BY 1
ORDER BY 1
```

### NPS Ongoing

#### Slug

nps_ongoing

#### Description

**NPS Ongoing** is the NPS of the ongoing journey alone — the tenancy period between move-in and
termination — reported **without** weighting. It is one of the three components NPS True
averages.

#### Also Known As

- **NPS de ongoing**, **NPS durante a locação**
- **NPS True** → near-miss — the weighted average of the three journeys, not this single
  component.

#### Rules

- **Canonical filter:** `dnc.business_context = 'forRent' AND dnc.customer_journey = 'true' AND
  dnc.purpose = 'main' AND dnc.metric_group IN ('iqongoing', 'ppongoing')`, over
  `fnd.is_answered = true`.
- **Common mistake:** reporting this component as the official NPS FR. It carries no weight; the
  official number is NPS True.
- **Never weight it:** the quarterly `share` applies only when composing NPS True.
- **Classification:** `dim_nps_answer.score_category` — `promoter` (9–10), `passive` (7–8),
  `detractor` (0–6), always lowercase.
- **Deduplication:** unique per `sk_nps_answer`; count with `COUNT(DISTINCT sk_nps_answer)` in
  numerator and denominator.
- **Query-time breakdowns (not materialized):** IQ / PP via `dnc.customer_type`; **Total is the
  pool of both, never the average of the two NPS values.**

#### Type

Health Metric

#### Direction

Higher is better

#### Grain

monthly

#### Is Additive

false

#### MBR

Post Contract

#### Category

FR XP

#### Golden Query

Computes the monthly unweighted NPS of the ongoing journey, with the promoter, detractor and
total answer counts that make the rate re-aggregable over longer periods.

```sql
SELECT
    date_trunc('month', CAST(dna.ts_answered AS TIMESTAMP)) AS ref_month,
    COUNT(DISTINCT CASE WHEN dna.score_category = 'promoter'  THEN dna.sk_nps_answer END) AS promoters,
    COUNT(DISTINCT CASE WHEN dna.score_category = 'detractor' THEN dna.sk_nps_answer END) AS detractors,
    COUNT(DISTINCT dna.sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'promoter'  THEN dna.sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'detractor' THEN dna.sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT dna.sk_nps_answer) * 100, 1
    ) AS nps_ongoing
FROM dw_customer_satisfaction.fact_nps_dispatches AS fnd
INNER JOIN dw_customer_satisfaction.dim_nps_answer AS dna
    ON fnd.sk_nps_answer = dna.sk_nps_answer
INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc
    ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
WHERE fnd.is_answered = true
  AND dnc.business_context = 'forRent'
  AND dnc.customer_journey = 'true'
  AND dnc.purpose = 'main'
  AND dnc.metric_group IN ('iqongoing', 'ppongoing')
  AND CAST(dna.ts_answered AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
  AND CAST(dna.ts_answered AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
GROUP BY 1
ORDER BY 1
```

### NPS Offboarding

#### Slug

nps_offboarding

#### Description

**NPS Offboarding** is the NPS of the offboarding journey alone — the termination and move-out
experience — reported **without** weighting. It is the component with the richest set of
operational cuts, and the base from which SPOC NPS and AS IS NPS are split.

#### Also Known As

- **NPS de offboarding**, **NPS de saída**, **NPS de rescisão**
- **NPS True** → near-miss — the weighted average of the three journeys, not this single
  component.

#### Rules

- **Canonical filter:** `dnc.business_context = 'forRent' AND dnc.customer_journey = 'true' AND
  dnc.purpose = 'main' AND dnc.metric_group IN ('iqoffboarding', 'ppoffboarding')`, over
  `fnd.is_answered = true`. The equivalent population in `sandbox.nps_fr` is
  `campanha_nps = 'offboarding'`.
- **Common mistake:** reporting this component as the official NPS FR. It carries no weight; the
  official number is NPS True.
- **Never weight it:** the quarterly `share` applies only when composing NPS True.
- **Deduplication:** unique per `sk_nps_answer`; count with `COUNT(DISTINCT sk_nps_answer)` in
  numerator and denominator. This matters more here than elsewhere: `sandbox.nps_fr` is built
  from wide joins (mediation, repairs, tickets, birdie) and **can carry more than one row per
  `sk_nps_answer`**, so `COUNT(*)` would inflate the count.
- **Query-time breakdowns (not materialized):** IQ / PP via `customer_type`, with **Total as the
  pool, never the average**; plus the operational cuts below, all available as ready-made flags
  in `sandbox.nps_fr` at `sk_nps_answer` grain. Always keep `campanha_nps = 'offboarding'` and
  add the cut's predicate — the cuts combine with IQ/PP and with each other.

  | Cut | Column in `sandbox.nps_fr` | Predicate |
  | :---- | :---- | :---- |
  | SPOC | `is_spoc_test` | `= true` |
  | AS IS (não-SPOC) | `is_spoc_test` | `= false` |
  | SPOC BAU | `is_spoc_test` + `spoc_team` | `is_spoc_test AND spoc_team = 'BAU'` |
  | SPOC LAB | `is_spoc_test` + `spoc_team` | `is_spoc_test AND spoc_team = 'LAB'` |
  | w/ Repairs | `com_ou_sem_reparos` | `= true` |
  | w/o Repairs | `com_ou_sem_reparos` | `= false` |
  | w/ Mediation | `intermed` | `= 1` |
  | w/ Early Mediation | `has_early_mediation` | `= true` |
  | w/ Early Both Agree | `is_early_both_agree` | `= true` |
  | w/ Repairs Contested | `total_repair_contested` | `= 1` |
  | w/ Repairs Contested PP | `contest_owner` | `= 1` |
  | w/ Repairs Contested IQ | `contest_tenant` | `= 1` |
  | Ldt > 15d / <= 15d | `leadtime_total` | `> 15` / `<= 15` |
  | w/ Tkt Back | `ticket_off_escalado` | `= true` |

#### Type

Health Metric

#### Direction

Higher is better

#### Grain

monthly

#### Is Additive

false

#### MBR

Post Contract

#### Category

FR XP

#### Golden Query

Computes the monthly unweighted NPS of the offboarding journey, with the promoter, detractor and
total answer counts that make the rate re-aggregable over longer periods.

```sql
SELECT
    date_trunc('month', CAST(dna.ts_answered AS TIMESTAMP)) AS ref_month,
    COUNT(DISTINCT CASE WHEN dna.score_category = 'promoter'  THEN dna.sk_nps_answer END) AS promoters,
    COUNT(DISTINCT CASE WHEN dna.score_category = 'detractor' THEN dna.sk_nps_answer END) AS detractors,
    COUNT(DISTINCT dna.sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'promoter'  THEN dna.sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'detractor' THEN dna.sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT dna.sk_nps_answer) * 100, 1
    ) AS nps_offboarding
FROM dw_customer_satisfaction.fact_nps_dispatches AS fnd
INNER JOIN dw_customer_satisfaction.dim_nps_answer AS dna
    ON fnd.sk_nps_answer = dna.sk_nps_answer
INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc
    ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
WHERE fnd.is_answered = true
  AND dnc.business_context = 'forRent'
  AND dnc.customer_journey = 'true'
  AND dnc.purpose = 'main'
  AND dnc.metric_group IN ('iqoffboarding', 'ppoffboarding')
  AND CAST(dna.ts_answered AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
  AND CAST(dna.ts_answered AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
GROUP BY 1
ORDER BY 1
```

### NPS PP Multi (Up to 15 Properties)

#### Slug

nps_pp_multi

#### Description

**NPS PP Multi (Up to 15 Properties)** is the weighted NPS of owners holding at most 15
properties, computed over the three PP Multi journeys (`onb_ppm`, `ong_ppm`, `off_ppm`) with the
**same quarterly weights** as NPS True. It sits outside NPS True — PP Multi answers never enter
the official weighted number — and it rounds each journey differently, to an integer rather than
one decimal.

#### Also Known As

- **NPS PPM**, **PP Multi (Up to 15 Properties)**, **N15**
- **NPS True** → near-miss — the official For Rent NPS, which **excludes** every PP Multi
  campaign.

#### Rules

- **Canonical filter:** in `sandbox.nps_fr`, `campanha_nps = 'ppmulti' AND campanha_category IN
  ('onb_ppm', 'ong_ppm', 'off_ppm')`, then `cnt_15_seg = '<= 15'`.
- **Common mistake:** skipping `cnt_15_seg = '<= 15'` on `off_ppm`. The exception that let
  offboarding bypass the segment filter was a bug, not intended behavior — the filter applies to
  **all three** journeys, consistent with the metric's own name.
- **Excluded population:** the legacy category `ppmulti_old` (`metric_group = 'currentpo'`) is
  not part of the current PP Multi.
- **Rounding:** each journey's NPS is rounded to an **integer** (`ROUND(…, 0)`) *before* the
  weights are applied — this is what matches the team's gsheets, and it is the one place this
  metric diverges from NPS True, which rounds to one decimal.
- **Parameters:** the same weights as NPS True, from
  `datalake_gsheets_clean.nps_target_share`.`share` with `customer_journey = 'TRUE'` — never
  hardcoded. Map `onb_ppm → onboarding`, `ong_ppm → ongoing`, `off_ppm → offboarding`.
- **Fallback:** identical to NPS True — most recent weight per journey when the month has no
  registered quarter; `weight_source = 'fallback'` is expected behavior and not a reason to flag
  the number. Aggregate with `MIN`, never `MAX`.
- **Segment source:** `cnt_15_seg` is already materialized in `sandbox.nps_fr` (values `'<= 15'`
  / `'> de 15'`) — consume it directly. At origin it comes from
  `datalake_pp_multi.pp_multi_classification_history`, `ACTIVE` records of the previous day's
  snapshot, joined `id_owner = sk_user`. Owners absent from the snapshot fall into `'> de 15'`
  and drop out of all three journeys, so a missing partition sends PP Multi to zero.
- **Deduplication:** unique per `sk_nps_answer`; `COUNT(DISTINCT sk_nps_answer)` everywhere —
  `sandbox.nps_fr` can fan out.
- **Query-time breakdowns (not materialized):** IQ / PP via `customer_type`, though PP Multi is
  owner-exclusive in practice, so `PP = Total` and `IQ` is empty.

#### Type

Health Metric

#### Direction

Higher is better

#### Grain

monthly

#### Is Additive

false

#### MBR

Post Contract

#### Category

FR XP

#### Golden Query

Computes the monthly weighted PP Multi NPS restricted to owners with at most 15 properties,
rounding each journey to an integer before weighting.

```sql
WITH ppmulti_answers AS (
    SELECT
        sk_nps_answer,
        date_trunc('month', CAST(ts_answered AS TIMESTAMP)) AS ref_month,
        CASE campanha_category
            WHEN 'onb_ppm' THEN 'onboarding'
            WHEN 'ong_ppm' THEN 'ongoing'
            WHEN 'off_ppm' THEN 'offboarding'
        END AS journey,
        score_category,
        cnt_15_seg
    FROM sandbox.nps_fr
    WHERE campanha_nps = 'ppmulti'
      AND campanha_category IN ('onb_ppm', 'ong_ppm', 'off_ppm')
      AND CAST(ts_answered AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
      AND CAST(ts_answered AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
),
journey_nps AS (
    SELECT
        ref_month,
        journey,
        ROUND(
            (CAST(COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS DOUBLE)
           - CAST(COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS DOUBLE))
            / COUNT(DISTINCT sk_nps_answer) * 100, 0
        ) AS nps_journey,
        COUNT(DISTINCT sk_nps_answer) AS total_answers
    FROM ppmulti_answers
    WHERE cnt_15_seg = '<= 15'
    GROUP BY 1, 2
),
weights_raw AS (
    SELECT
        campaign_group AS journey,
        CAST(dt_start AS DATE) AS dt_start,
        CAST(dt_end AS DATE) AS dt_end,
        CAST(REPLACE(share, '%', '') AS DOUBLE) / 100.0 AS weight
    FROM datalake_gsheets_clean.nps_target_share
    WHERE customer_journey = 'TRUE'
      AND share IS NOT NULL
      AND share != ''
),
latest_weights AS (
    SELECT journey, weight
    FROM (
        SELECT
            journey,
            weight,
            ROW_NUMBER() OVER (PARTITION BY journey ORDER BY dt_end DESC) AS rn
        FROM weights_raw
    ) AS sub
    WHERE rn = 1
),
journey_with_weight AS (
    SELECT
        jn.ref_month,
        jn.journey,
        jn.nps_journey,
        jn.total_answers,
        w.weight,
        ROW_NUMBER() OVER (
            PARTITION BY jn.ref_month, jn.journey
            ORDER BY w.dt_start DESC, w.dt_end DESC
        ) AS rn
    FROM journey_nps AS jn
    LEFT JOIN weights_raw AS w
        ON jn.journey = w.journey
       AND CAST(jn.ref_month AS DATE) BETWEEN w.dt_start AND w.dt_end
)
SELECT
    d.ref_month,
    ROUND(SUM(d.nps_journey * COALESCE(d.weight, lw.weight)), 1) AS nps_pp_multi,
    SUM(d.total_answers) AS total_answers,
    MIN(CASE WHEN d.weight IS NULL THEN 'fallback' ELSE 'official' END) AS weight_source
FROM (SELECT * FROM journey_with_weight WHERE rn = 1) AS d
LEFT JOIN latest_weights AS lw
    ON d.journey = lw.journey
GROUP BY d.ref_month
ORDER BY d.ref_month
```

### SPOC NPS

#### Slug

spoc_nps

#### Description

**SPOC NPS** is the offboarding NPS restricted to contracts in the SPOC experiment
(`is_spoc_test = true`), reported **without** weighting. It is the treatment side of the SPOC
comparison; the control side is AS IS NPS, and the two differ by nothing but that flag.

#### Also Known As

- **NPS SPOC**, **NPS do SPOC**
- **AS IS NPS** → near-miss — the complementary bucket, `is_spoc_test = false`, not this metric.

#### Rules

- **Canonical filter:** in `sandbox.nps_fr`, `campanha_nps = 'offboarding' AND
  is_spoc_test = true`.
- **Common mistake:** forgetting `campanha_nps = 'offboarding'`. The SPOC flag exists on rows of
  other journeys too, and without the journey predicate the population stops being comparable to
  AS IS NPS.
- **Never weight it:** SPOC and AS IS are single-journey metrics; the `nps_target_share` weights
  do not apply.
- **Flag source:** `is_spoc_test` is already materialized in `sandbox.nps_fr`, alongside
  `spoc_team` (`'BAU'` / `'LAB'`) — consume the column directly, do not re-derive it by joining
  `dw_offboarding.fact_terminations`.
- **Deduplication:** unique per `sk_nps_answer`; `COUNT(DISTINCT sk_nps_answer)` everywhere —
  `sandbox.nps_fr` can fan out.
- **Query-time breakdowns (not materialized):** `spoc_team` splits SPOC into BAU and LAB; IQ / PP
  via `customer_type`, with **Total as the pool, never the average**.

#### Type

Health Metric

#### Direction

Higher is better

#### Grain

monthly

#### Is Additive

false

#### MBR

Post Contract

#### Category

FR XP

#### Golden Query

Computes the monthly unweighted offboarding NPS for the SPOC test group, with the counts that
make the rate re-aggregable over longer periods.

```sql
SELECT
    date_trunc('month', CAST(ts_answered AS TIMESTAMP)) AS ref_month,
    COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS promoters,
    COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS detractors,
    COUNT(DISTINCT sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT sk_nps_answer) * 100, 1
    ) AS spoc_nps
FROM sandbox.nps_fr
WHERE campanha_nps = 'offboarding'
  AND is_spoc_test = true
  AND CAST(ts_answered AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
  AND CAST(ts_answered AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
GROUP BY 1
ORDER BY 1
```

### AS IS NPS

#### Slug

as_is_nps

#### Description

**AS IS NPS** is the offboarding NPS of contracts **outside** the SPOC experiment
(`is_spoc_test = false`), reported **without** weighting. "AS IS" is the team's label for the
control bucket; não-SPOC, no-spoc and sem SPOC all name this same metric.

#### Also Known As

- **NPS AS IS**, **NPS BAU offboarding**, **NPS não SPOC**, **NPS no-spoc**, **NPS sem SPOC**
- **SPOC NPS** → near-miss — the complementary bucket, `is_spoc_test = true`, not this metric.
- **SPOC BAU** → near-miss — a subdivision *inside* SPOC (`spoc_team = 'BAU'`), despite the "BAU"
  wording; it is not the AS IS bucket.

#### Rules

- **Canonical filter:** in `sandbox.nps_fr`, `campanha_nps = 'offboarding' AND
  is_spoc_test = false`.
- **Common mistake:** conflating AS IS with SPOC BAU. `spoc_team = 'BAU'` lives *inside*
  `is_spoc_test = true`; AS IS is the complement of the whole experiment.
- **Watch the NULLs:** `is_spoc_test = false` is not the same as `NOT is_spoc_test` when the
  column is nullable — keep the explicit equality so the population matches SPOC NPS's exact
  complement.
- **Never weight it:** SPOC and AS IS are single-journey metrics; the `nps_target_share` weights
  do not apply.
- **Flag source:** `is_spoc_test` is already materialized in `sandbox.nps_fr` — consume it
  directly, do not re-derive it from `dw_offboarding.fact_terminations`.
- **Deduplication:** unique per `sk_nps_answer`; `COUNT(DISTINCT sk_nps_answer)` everywhere.
- **Query-time breakdowns (not materialized):** IQ / PP via `customer_type`, with **Total as the
  pool, never the average**.

#### Type

Health Metric

#### Direction

Higher is better

#### Grain

monthly

#### Is Additive

false

#### MBR

Post Contract

#### Category

FR XP

#### Golden Query

Computes the monthly unweighted offboarding NPS for the non-SPOC control group, with the counts
that make the rate re-aggregable over longer periods.

```sql
SELECT
    date_trunc('month', CAST(ts_answered AS TIMESTAMP)) AS ref_month,
    COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS promoters,
    COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS detractors,
    COUNT(DISTINCT sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT sk_nps_answer) * 100, 1
    ) AS as_is_nps
FROM sandbox.nps_fr
WHERE campanha_nps = 'offboarding'
  AND is_spoc_test = false
  AND CAST(ts_answered AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
  AND CAST(ts_answered AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
GROUP BY 1
ORDER BY 1
```

### NPS Seamless

#### Slug

nps_seamless

#### Description

**NPS Seamless** is the pooled onboarding + ongoing NPS of customers who needed **no support at
all** in the observation window — no ticket, no chatbot, no walle. It is a direct pool, not a
weighted average: the two journeys' numerators and denominators are summed before dividing.

#### Also Known As

- **NPS Seamless (Onb./Ong.)**, **self-service NPS**, **NPS sem suporte**
- **NPS Digital Sup** → near-miss — customers who used chatbot or walle, which is the opposite of
  seamless.

#### Rules

- **Canonical filter:** `seamless_ticket_type = 'seamless'` over the union of
  `sandbox.nps_onb_cohort` and `sandbox.nps_ong_cohort`.
- **Common mistake:** weighting the two journeys. This metric is a **pool** —
  `(num_onb + num_ong) / (den_onb + den_ong) × 100`. Applying the `nps_target_share` weights
  produces a different number that no one reports.
- **Do not rebuild the flag:** `seamless_ticket_type` is already computed inside the cohort
  tables, which also scope the onboarding / ongoing `metric_group`. The exact ticket-category
  allowlist behind `has_ticket` exists only in the cohorts' logic, so deriving the flag from
  `dw_customer_support.fact_tickets` and `datalake_chatbot.sessions` will not reproduce it.
- **Mutually exclusive categorization, evaluated by precedence:** `seamless` requires zero of all
  signals; `tickets` wins over `digital_support` for anyone who has both a ticket and a chatbot
  session. The four values never overlap.

  | Value | Rule (in order) | Metric |
  | :---- | :---- | :---- |
  | `seamless` | no ticket **and** no chatbot **and** no walle | NPS Seamless |
  | `tickets` | has a support ticket in the allowed categories `> 0` | NPS Human Support |
  | `digital_support` | no ticket, but chatbot or walle `> 0` | NPS Digital Sup |
  | `other` | none of the above | — |

- **Observation window of the flag:** `(dt_start − 30 days) … nps_answer_date`, per `sk_user`,
  where `dt_start` is the contract start.
- **Date column:** the cohorts expose the answer date as `data_resposta_nps`, not `ts_answered`.
- **Deduplication:** unique per `sk_nps_answer`; the cohorts are built from wide joins and can
  fan out, so `COUNT(DISTINCT sk_nps_answer)` is required in numerator and denominator.
- **Query-time breakdowns (not materialized):** IQ / PP via `customer_type`, with **Total as the
  pool, never the average**; `campanha_nps` splits the pool back into onboarding and ongoing.

#### Type

Health Metric

#### Direction

Higher is better

#### Grain

monthly

#### Is Additive

false

#### MBR

Post Contract

#### Category

FR XP

#### Golden Query

Computes the monthly pooled onboarding + ongoing NPS of answers classified as seamless, with the
counts that make the rate re-aggregable over longer periods.

```sql
WITH seamless_base AS (
    SELECT sk_nps_answer, score_category, seamless_ticket_type, data_resposta_nps
    FROM sandbox.nps_onb_cohort
    UNION ALL
    SELECT sk_nps_answer, score_category, seamless_ticket_type, data_resposta_nps
    FROM sandbox.nps_ong_cohort
)
SELECT
    date_trunc('month', CAST(data_resposta_nps AS TIMESTAMP)) AS ref_month,
    COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS promoters,
    COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS detractors,
    COUNT(DISTINCT sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT sk_nps_answer) * 100, 1
    ) AS nps_seamless
FROM seamless_base
WHERE seamless_ticket_type = 'seamless'
  AND CAST(data_resposta_nps AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
  AND CAST(data_resposta_nps AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
GROUP BY 1
ORDER BY 1
```

### NPS Digital Sup

#### Slug

nps_digital_sup

#### Description

**NPS Digital Sup** is the pooled onboarding + ongoing NPS of customers who resolved their need
through **digital channels only** — chatbot or walle, with no support ticket. It uses the same
pooled engine as NPS Seamless and NPS Human Support, differing only in the
`seamless_ticket_type` value it filters.

#### Also Known As

- **NPS Digital Support (Onb./Ong.)**, **NPS suporte digital**
- **NPS Human Support** → near-miss — customers who opened a ticket; the ticket takes precedence
  over the digital signal, so the two populations never overlap.

#### Rules

- **Canonical filter:** `seamless_ticket_type = 'digital_support'` over the union of
  `sandbox.nps_onb_cohort` and `sandbox.nps_ong_cohort`.
- **Common mistake:** treating `digital_support` and `tickets` as overlapping sets and adding
  them up. The categorization is exclusive and resolved by precedence — a customer with both a
  ticket and a chatbot session is classified as `tickets`, never counted here.
- **Never weight it:** this is a direct pool of the two journeys —
  `(num_onb + num_ong) / (den_onb + den_ong) × 100`.
- **Do not rebuild the flag:** consume `seamless_ticket_type` from the cohort tables; the
  ticket-category allowlist behind `has_ticket` exists only in their logic.
- **Observation window of the flag:** `(dt_start − 30 days) … nps_answer_date`, per `sk_user`.
- **Date column:** the cohorts expose the answer date as `data_resposta_nps`, not `ts_answered`.
- **Deduplication:** unique per `sk_nps_answer`; the cohorts can fan out, so
  `COUNT(DISTINCT sk_nps_answer)` is required.
- **Query-time breakdowns (not materialized):** IQ / PP via `customer_type`, with **Total as the
  pool, never the average**; `campanha_nps` splits the pool back into onboarding and ongoing.

#### Type

Health Metric

#### Direction

Higher is better

#### Grain

monthly

#### Is Additive

false

#### MBR

Post Contract

#### Category

FR XP

#### Golden Query

Computes the monthly pooled onboarding + ongoing NPS of answers classified as digital support,
with the counts that make the rate re-aggregable over longer periods.

```sql
WITH seamless_base AS (
    SELECT sk_nps_answer, score_category, seamless_ticket_type, data_resposta_nps
    FROM sandbox.nps_onb_cohort
    UNION ALL
    SELECT sk_nps_answer, score_category, seamless_ticket_type, data_resposta_nps
    FROM sandbox.nps_ong_cohort
)
SELECT
    date_trunc('month', CAST(data_resposta_nps AS TIMESTAMP)) AS ref_month,
    COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS promoters,
    COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS detractors,
    COUNT(DISTINCT sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT sk_nps_answer) * 100, 1
    ) AS nps_digital_sup
FROM seamless_base
WHERE seamless_ticket_type = 'digital_support'
  AND CAST(data_resposta_nps AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
  AND CAST(data_resposta_nps AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
GROUP BY 1
ORDER BY 1
```

### NPS Human Support

#### Slug

nps_human_support

#### Description

**NPS Human Support** is the pooled onboarding + ongoing NPS of customers who opened a **support
ticket** in the observation window. It uses the same pooled engine as NPS Seamless and NPS
Digital Sup, differing only in the `seamless_ticket_type` value it filters — and it takes
precedence over the digital classification whenever both signals are present.

#### Also Known As

- **NPS Human Support (Onb./Ong.)**, **NPS tickets**, **NPS suporte humano**
- **NPS Digital Sup** → near-miss — chatbot or walle **without** a ticket; a customer with both
  is counted here, not there.

#### Rules

- **Canonical filter:** `seamless_ticket_type = 'tickets'` over the union of
  `sandbox.nps_onb_cohort` and `sandbox.nps_ong_cohort`. Note the value is the plural `'tickets'`,
  not `'ticket'` or `'human_support'`.
- **Common mistake:** assuming the population is "everyone who contacted support". Only ticket
  categories in the cohorts' allowlist (moving, repairs, payments, ongoing) count; the exact list
  differs slightly between the onboarding and ongoing cohorts.
- **Never weight it:** this is a direct pool of the two journeys —
  `(num_onb + num_ong) / (den_onb + den_ong) × 100`.
- **Do not rebuild the flag:** consume `seamless_ticket_type` from the cohort tables; the
  ticket-category allowlist behind `has_ticket` exists only in their logic.
- **Observation window of the flag:** `(dt_start − 30 days) … nps_answer_date`, per `sk_user`.
- **Date column:** the cohorts expose the answer date as `data_resposta_nps`, not `ts_answered`.
- **Deduplication:** unique per `sk_nps_answer`; the cohorts can fan out, so
  `COUNT(DISTINCT sk_nps_answer)` is required.
- **Query-time breakdowns (not materialized):** IQ / PP via `customer_type`, with **Total as the
  pool, never the average**; `campanha_nps` splits the pool back into onboarding and ongoing.

#### Type

Health Metric

#### Direction

Higher is better

#### Grain

monthly

#### Is Additive

false

#### MBR

Post Contract

#### Category

FR XP

#### Golden Query

Computes the monthly pooled onboarding + ongoing NPS of answers classified as human support, with
the counts that make the rate re-aggregable over longer periods.

```sql
WITH seamless_base AS (
    SELECT sk_nps_answer, score_category, seamless_ticket_type, data_resposta_nps
    FROM sandbox.nps_onb_cohort
    UNION ALL
    SELECT sk_nps_answer, score_category, seamless_ticket_type, data_resposta_nps
    FROM sandbox.nps_ong_cohort
)
SELECT
    date_trunc('month', CAST(data_resposta_nps AS TIMESTAMP)) AS ref_month,
    COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS promoters,
    COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS detractors,
    COUNT(DISTINCT sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT sk_nps_answer) * 100, 1
    ) AS nps_human_support
FROM seamless_base
WHERE seamless_ticket_type = 'tickets'
  AND CAST(data_resposta_nps AS TIMESTAMP) >= CAST(current_date - INTERVAL '24' MONTH AS TIMESTAMP)
  AND CAST(data_resposta_nps AS TIMESTAMP) < CAST(current_date AS TIMESTAMP)
GROUP BY 1
ORDER BY 1
```
