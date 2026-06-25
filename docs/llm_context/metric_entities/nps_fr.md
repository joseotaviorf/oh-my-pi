# NPS FR

## Overview

**NPS FR** is the family of Net Promoter Score metrics for the For Rent product. The anchor
metric — **NPS True** — is a **weighted average** of the NPS computed independently for each
journey (onboarding, ongoing, offboarding), with quarterly weights defined by the CX team.
Pooling all answers into a single flat pool produces a **systematically incorrect** number
(per-journey volumes are very different, distorting the NPS by up to 5 points). The other
metrics in this file (per-journey components, PP Multi, SPOC, AS IS, and the interaction-type
ones — Seamless / Digital Sup / Human Support) use the **same engine**
(`% promoters − % detractors`) over different cuts of the same answer base.
**All are breakable by IQ / PP / Total.**

**This product exists exclusively for For Rent — there is no equivalent weighted NPS for FS
or other products.**

## Related Business Entities

- NPS

## Glossary and Synonyms

- **NPS FR**, **NPS True**, **official NPS**, **weighted NPS** → NPS True (weighted average of the journeys)
- **NPS Onboarding**, **NPS Ongoing**, **NPS Offboarding** → single-journey component (not weighted)
- **NPS PP Multi**, **NPS PPM**, **PP Multi (Up to 15 Properties)**, **N15** → NPS PP Multi
- **SPOC NPS**, **NPS SPOC** → offboarding NPS with `is_spoc_test = TRUE`
- **AS IS NPS**, **NPS AS IS**, **NPS BAU offboarding** → offboarding NPS with `is_spoc_test = FALSE`
- **NPS Offboarding cuts** (SPOC BAU/LAB, with/without Repairs, with Mediation, with Early Mediation, with Early Both Agree, with Repairs Contested PP/IQ, Ldt ≷ 15d, …) → sub-cuts of NPS Offboarding via `sandbox.nps_fr` flags (see Nuances)
- **NPS Seamless**, **NPS Seamless (Onb./Ong.)**, **self-service NPS** → pooled NPS of onboarding+ongoing with `seamless_ticket_type = 'seamless'`
- **NPS Digital Sup**, **NPS Digital Support (Onb./Ong.)** → pooled NPS of onboarding+ongoing with `seamless_ticket_type = 'digital_support'`
- **NPS Human Support**, **NPS Human Support (Onb./Ong.)**, **NPS tickets** → pooled NPS of onboarding+ongoing with `seamless_ticket_type = 'tickets'`
- **IQ** → tenant (`customer_type = 'IQ'`); **PP** → owner (`customer_type = 'PP'`); **Total** → IQ+PP pool

## Scope

**Included**: onboarding, ongoing, offboarding (NPS True and components); PP Multi journeys
(`onb_ppm`, `ong_ppm`, `off_ppm`); offboarding segmented by SPOC/AS IS and by the
**operational Ops cuts** (repairs, mediation, contestation, leadtime, etc. — see Nuances);
onboarding+ongoing segmented by interaction type (`seamless` / `digital_support` /
`tickets`) — IQ + PP, Brazil.

**Excluded (global, applies to all)**: lost, po, international campaigns (mexico, bo),
agents, brokers, test campaigns (`purpose = 'test'`).

**Per-metric exclusions** (on top of the global ones):

- **NPS True / components**: exclude `ppmulti` (all `*_ppm` campaigns and `currentpo`) —
  PP Multi is its own metric, computed separately; it does not enter the weighted number.
- **PP Multi**: excludes the legacy category `ppmulti_old` (`metric_group = 'currentpo'`); uses only
  `onbppm` / `ongppm` / `offppm`.

## Calculation

The anchor metric (**NPS True**) is the weighted average of the three journeys:

```
NPS_True = NPS_onboarding  × weight_onboarding
         + NPS_ongoing     × weight_ongoing
         + NPS_offboarding × weight_offboarding
```

where each `NPS_journey = (promoters − detractors) / total_journey × 100`, classifying by
`dim_nps_answer.score_category` (`promoter` 9–10, `passive` 7–8, `detractor` 0–6) and counting
only effective answers (`fact_nps_dispatches.is_answered = true`). The **components**
**NPS Onboarding / Ongoing / Offboarding** are exactly the `NPS_journey` above, reported
without weighting.

**NPS PP Multi (Up to 15 Properties)** — weighted average of the three PP Multi journeys,
using the **same quarterly weights** as NPS True (`onb_ppm → onboarding`,
`ong_ppm → ongoing`, `off_ppm → offboarding`):

```
NPS_PPMulti = NPS(onb_ppm, cnt_15_seg='<= 15') × weight_onboarding
            + NPS(ong_ppm, cnt_15_seg='<= 15') × weight_ongoing
            + NPS(off_ppm)                      × weight_offboarding
```

Population: in `sandbox.nps_fr`, `campanha_nps = 'ppmulti'` and
`campanha_category IN ('onb_ppm','ong_ppm','off_ppm')` (excludes `currentpo`/`ppmulti_old`).
PP Multi is owner-exclusive → in practice `PP = Total` and `IQ` is empty.

**Rounding**: the team rounds each journey's NPS **to an integer** (`ROUND(…, 0)`) before
applying the weights — reproduce it this way to match the official gsheets number. (This
differs from NPS True, which rounds to 1 decimal.)

**SPOC NPS / AS IS NPS** — **offboarding** NPS (`campanha_nps = 'offboarding'` in
`sandbox.nps_fr`), **without weighting**, split by the `is_spoc_test` flag. The **only**
difference between the two is the flag; within SPOC, `spoc_team` distinguishes **SPOC BAU**
from **SPOC LAB**:

```
SPOC NPS  = offboarding NPS where is_spoc_test = TRUE
AS IS NPS = offboarding NPS where is_spoc_test = FALSE
```

**NPS by interaction type (Onb./Ong.)** — three sibling metrics with **identical
calculation**, differing **only** by the filtered `seamless_ticket_type` value:

- **NPS Seamless** → `seamless_ticket_type = 'seamless'`
- **NPS Digital Sup** → `seamless_ticket_type = 'digital_support'`
- **NPS Human Support** → `seamless_ticket_type = 'tickets'`

All are **pooled** (unweighted) NPS of onboarding + ongoing: each journey's numerator and
denominator are summed before dividing:

```
NPS = (num_onboarding + num_ongoing) / (den_onboarding + den_ongoing) × 100
```

where, over the answers of the chosen interaction type in each journey:
`num_journey = COUNT(DISTINCT CASE WHEN score_category = 'promoter' THEN sk_nps_answer END)
            − COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END)`
and `den_journey = COUNT(DISTINCT sk_nps_answer)`. Population: the onb/ong answers already
materialized in `sandbox.nps_onb_cohort` / `sandbox.nps_ong_cohort` (which internally scope
the onboarding/ongoing `metric_group` and compute `seamless_ticket_type`). Since it is a
direct pool, it is equivalent to the NPS over the union of that type's onb+ong answers
(without weights).

### Canonical Filter

Apply on `dim_nps_campaign` (alias `dnc`) when joining with `fact_nps_dispatches`. This is the
filter **for NPS True and the components only** (Onboarding / Ongoing / Offboarding):

```sql
business_context     = 'forRent'
AND customer_journey = 'true'   -- lowercase string, not boolean (≠ nps_target_share, which uses 'TRUE')
AND purpose          = 'main'
```

`customer_journey = 'true' AND purpose = 'main'` (always both together) selects exactly the
`onboarding` / `ongoing` / `offboarding` campaigns — the **same population** the team's
official dataset obtains via `metric_group IN ('iqonboarding','pponboarding','iqongoing',
'ppongoing','iqoffboarding','ppoffboarding')`. If there is any divergence, the `metric_group`
selection is the source of truth.

**Warning**: filtering only by `business_context = 'forRent'` without the other two fields
includes lost, ppm, po and other campaigns that do **not** compose the official NPS FR.

**Each metric uses a different selection** (all keep `business_context = 'forRent'`):

| Metric | Population selection |
| :---- | :---- |
| NPS True, Onboarding, Ongoing, Offboarding | `customer_journey = 'true'` AND `purpose = 'main'` |
| PP Multi | `sandbox.nps_fr`: `campanha_category IN ('onb_ppm','ong_ppm','off_ppm')` (+ `cnt_15_seg` in onb/ong) |
| SPOC / AS IS + Ops cuts | `sandbox.nps_fr`: `campanha_nps = 'offboarding'` + the cut's flag (`is_spoc_test`, `spoc_team`, `com_ou_sem_reparos`, …) |
| Seamless / Digital Sup / Human Support | materialized tables `sandbox.nps_onb_cohort` / `sandbox.nps_ong_cohort` |

### Nuances

Mechanics shared by the metrics in this file. (Tables/columns and the generic component
calculation live in `business_entities/nps.md` — here, only what is specific to these
metrics.)

**Campaign taxonomy** — dictionary mapping `dnc.metric_group` (raw value in
`dim_nps_campaign`) to the **journey** label (`campanha_nps`) and the PP Multi
**sub-category** (`campanha_category`). These are the same labels the team uses as criteria in
the spreadsheet SUMIFS (columns A and B). The Golden Queries derive the journey inline from
`metric_group` (`CASE WHEN metric_group LIKE '%onboarding%' …`), so these two columns are not
materialized — use the table only as a reference for "which `metric_group` falls into which
journey":

| `metric_group` | journey (`campanha_nps`) | category (`campanha_category`) |
| :---- | :---- | :---- |
| `iqonboarding`, `pponboarding` | `onboarding` | — |
| `iqongoing`, `ppongoing` | `ongoing` | — |
| `iqoffboarding`, `ppoffboarding` | `offboarding` | — |
| `currentpo` | `ppmulti` | `ppmulti_old` (legacy, **outside** the current PP Multi) |
| `onbppm` / `ongppm` / `offppm` | `ppmulti` | `onb_ppm` / `ong_ppm` / `off_ppm` |

**IQ / PP / Total breakdown** — via `dnc.customer_type`: `'IQ'` = tenant, `'PP'` = owner.
IQ → `customer_type = 'IQ'`; PP → `customer_type = 'PP'`; **Total → pool of both populations in
the same denominator** (NOT the average of the IQ and PP NPS). In weighted metrics (NPS True,
PP Multi), compute each journey's NPS **per `customer_type`** before applying the weights.

**Quarterly weights** — read from `datalake_gsheets_clean.nps_target_share`; **never
hardcode**. The **same weights** serve NPS True and PP Multi.

| Column | Description |
| :---- | :---- |
| `campaign_group` | Journey: `onboarding`, `ongoing`, `offboarding` |
| `customer_journey` | Filter `= 'TRUE'` (UPPERCASE here — ≠ `dim_nps_campaign`, which uses lowercase `'true'`) for NPS FR weights |
| `share` | Weight (string `'25%'`) — parse: `CAST(REPLACE(share, '%', '') AS DOUBLE) / 100.0` |
| `dt_start`, `dt_end` | Quarterly validity |
| `target` | Period NPS target (informational, not used in the calculation) |

- **Join key**: `campaign_group` ↔ journey derived from `metric_group`.
- **Date join**: `CAST(ref_month AS DATE) BETWEEN dt_start AND dt_end`.
- **Fallback**: a month without a registered quarter uses the most recent weight per journey
  (`ROW_NUMBER() OVER (PARTITION BY journey ORDER BY dt_end DESC)`).

**`is_spoc_test` flag** (SPOC / AS IS) — **already available in `sandbox.nps_fr`** (alongside
`spoc_team` = `'BAU'`/`'LAB'`); consume the column directly. For reference, the derivation from
`dw_offboarding.fact_terminations` (by `sk_contract`, most recent termination) is:

```sql
CASE
    WHEN is_spoc_contract = true
     AND (is_spoc_control_group = false OR is_spoc_control_group IS NULL)
    THEN true ELSE false
END AS is_spoc_test
```

**"Up to 15 Properties" segment** (PP Multi) — **already available as `cnt_15_seg` in
`sandbox.nps_fr`** (values `'<= 15'` / `'> de 15'`); consume the column directly. For
reference, at the source it comes from `datalake_pp_multi.pp_multi_classification_history`,
`ACTIVE` records from **yesterday's snapshot** (partition `current_date - INTERVAL '1' day`),
joined via `id_owner = sk_user`. The filter `cnt_15_seg = '<= 15'` applies **only** to
`onb_ppm` and `ong_ppm`; `off_ppm` enters in full. Owners missing from the snapshot fall into
`> de 15` (excluded from onb/ong) — if yesterday's partition does not exist in the
materialization, onb/ong PP Multi goes to zero.

**`seamless_ticket_type` flag** (NPS Seamless / Digital Sup / Human Support) — classifies
each onb/ong answer by the **support interaction type** the customer had in the window
`(dt_start − 30 days) … nps_answer_date` (where `dt_start` is the contract start and
`nps_answer_date` is the answer date). It is a categorization of **4 mutually exclusive
values**, evaluated **in this precedence order**:

| Value | Rule (in order) | Metric that uses it |
| :---- | :---- | :---- |
| `seamless` | no ticket **and** no chatbot **and** no walle | NPS Seamless |
| `tickets` | has a support ticket (specific categories) `> 0` | NPS Human Support |
| `digital_support` | no ticket, but with chatbot/walle `> 0` | NPS Digital Sup |
| `other` | none of the above | — |

Precedence matters: whoever has **a ticket and** chatbot falls into `tickets` (not
`digital_support`); `seamless` requires zero of all signals. (The exact ticket categories that
compose `tickets` differ slightly between onb and ong — see the definition of
`sandbox.nps_onb_cohort` / `sandbox.nps_ong_cohort`.)

> **Materialized in sandbox (official path — use it for the team's number).**
> `seamless_ticket_type` is materialized in **`sandbox.nps_onb_cohort`** (onboarding) and
> **`sandbox.nps_ong_cohort`** (ongoing), at `sk_nps_answer` grain, already with
> `customer_type`, `score_category`, `campanha_nps` and `data_resposta_nps`. **Consume these
> tables directly** (see **Query 5**); do **not** rebuild the flag from the raw tables — the
> exact `has_ticket` (ticket-category allowlist) only exists in the cohorts' logic. For
> reference, the flag sums these signals in the window `(dt_start − 30 days) …
> data_resposta_nps`, per `sk_user`:
>
> | Signal | Source | Rule (in the window, per `sk_user`) |
> | :---- | :---- | :---- |
> | `has_ticket` | `dw_customer_support.fact_tickets` (+ `dim_department`/`dim_taxonomy`) | sum of ticket categories (moving, repairs, payments, ongoing) `> 0` |
> | `has_chatbot_session` | `datalake_chatbot.sessions` | bot session without an associated ticket |
> | `has_walle_session` | `datalake_chatbot.sessions` (`bot = 'wall-e'`) | walle session without an associated ticket |

**Offboarding cuts (Ops)** — the operations team analyzes the Offboarding NPS by a series of
cuts, all available as **ready-made flags in `sandbox.nps_fr`** (`sk_nps_answer` grain). Always
filter `campanha_nps = 'offboarding'` and apply the cut's flag (combinable with the IQ/PP
breakdown via `customer_type` and crossable with one another):

| Cut | Column in `sandbox.nps_fr` | Filter |
| :---- | :---- | :---- |
| SPOC | `is_spoc_test` | `= true` |
| w/o SPOC | `is_spoc_test` | `= false` |
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
| Ldt > 15d / ≤ 15d | `leadtime_total` (= `DATE_DIFF('day', dt_termination, dt_tf)`) | `> 15` / `<= 15` |
| w/ Tkt Back | `ticket_off_escalado` | `= true` |

## Dos and Don'ts

**Do:**

- Classify by `score_category` (lowercase) and compute `% promoters − % detractors` over `is_answered = true`.
- **NPS True / components**: apply `business_context = 'forRent'` AND `customer_journey = 'true'` AND `purpose = 'main'`; compute each journey before weighting.
- **PP Multi**: in `sandbox.nps_fr`, select `campanha_category IN ('onb_ppm','ong_ppm','off_ppm')`; use the ready `cnt_15_seg` (`'<= 15'` only in onb/ong); round each journey to an integer; reuse the `nps_target_share` weights.
- **SPOC / AS IS**: in `sandbox.nps_fr`, filter `campanha_nps = 'offboarding'` and use the ready `is_spoc_test` / `spoc_team` (without re-joining `fact_terminations`).
- **Offboarding cuts (Ops)**: in `sandbox.nps_fr`, filter `campanha_nps = 'offboarding'` and apply the cut's flag (see the map in Nuances).
- **Seamless / Digital Sup / Human Support**: pool onboarding+ongoing (sum num/den before dividing) and filter the `seamless_ticket_type` value (`'seamless'` / `'digital_support'` / `'tickets'`); consume the flag directly from `sandbox.nps_onb_cohort` / `sandbox.nps_ong_cohort`.
- **IQ/PP**: filter `customer_type`; for **Total**, pool (not the average of IQ and PP).
- Read the weights from `nps_target_share` (`customer_journey = 'TRUE'`), use the fallback to the most recent quarter and deduplicate weights by `(ref_month, journey)`.

**Don't:**

- Don't filter only by `business_context = 'forRent'` in NPS True — it includes lost, ppm, po and others.
- Don't pool the journeys directly in NPS True / PP Multi — use the weighted calculation.
- Don't hardcode the weights (e.g. 25%, 53%, 22%) — always read from `nps_target_share`.
- Don't apply `cnt_15_seg = '<= 15'` to `off_ppm`.
- Don't confuse SPOC with AS IS — the only difference is `is_spoc_test` (TRUE vs FALSE), both in offboarding.
- Don't weight NPS Seamless / Digital Sup / Human Support — it is a direct pool of onb+ong (sum num/den), not a weighted average.
- Don't try to rebuild `seamless_ticket_type` from the raw tables — always consume from `sandbox.nps_onb_cohort` / `sandbox.nps_ong_cohort` (the exact `has_ticket` only exists in the cohorts' logic).
- Don't treat `tickets` and `digital_support` as overlapping — the categorization is exclusive and by precedence (`tickets` beats `digital_support`).
- Don't use `MAX` to aggregate the weight source — use `MIN`, so `'fallback'` shows up when any journey lacks an official weight.
- Don't treat **Total** as the average of the IQ and PP NPS — always pool the answers.

## Golden Queries

The per-journey NPS CTEs reproduce the component pattern already documented in
`business_entities/nps.md`; what is exclusive to these metrics is the weighting layer
(NPS True, PP Multi) and the cuts (`is_spoc_test`, `cnt_15_seg`, `customer_type`).

**Answer counting — always `COUNT(DISTINCT sk_nps_answer)`** (numerator and denominator),
across all sources. In the DW tables there is exactly 1 row per answer (1:1 join on
`sk_nps_answer`), so `DISTINCT` is identical to `COUNT(*)`. But `sandbox.nps_fr` and the
cohorts are built from **wide joins** (mediation, repairs, tickets, birdie…) and **may have
more than one row per `sk_nps_answer`** (fanout); there `COUNT(*)` would inflate the count.
Using `DISTINCT` everywhere keeps a single pattern and is always correct.

### Query 1 — NPS True (weighted)

For the **IQ/PP** breakdown, add `dnc.customer_type` to the `journey_nps` CTE `GROUP BY` and
propagate it to the final `SELECT` (grouping by `ref_month, customer_type`); for **Total**, run
it as is (IQ+PP pool).

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
    INNER JOIN dw_customer_satisfaction.dim_nps_answer   AS dna
        ON fnd.sk_nps_answer = dna.sk_nps_answer
    INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc
        ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
    WHERE fnd.is_answered = true
      AND dnc.business_context = 'forRent'
      AND dnc.customer_journey = 'true'
      AND dnc.purpose          = 'main'
      AND CAST(dna.ts_answered AS TIMESTAMP) >= CAST(date_add('month', -24, current_date) AS TIMESTAMP)
      AND CAST(dna.ts_answered AS TIMESTAMP) <  CAST(current_date AS TIMESTAMP)
    GROUP BY 1, 2
),
weights_raw AS (
    SELECT
        campaign_group                                   AS journey,
        CAST(dt_start AS DATE)                           AS dt_start,
        CAST(dt_end   AS DATE)                           AS dt_end,
        CAST(REPLACE(share, '%', '') AS DOUBLE) / 100.0  AS weight
    FROM datalake_gsheets_clean.nps_target_share
    WHERE customer_journey = 'TRUE'
      AND share IS NOT NULL
      AND share != ''
),
latest_weights AS (
    SELECT journey, weight
    FROM (
        SELECT journey, weight,
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
        ROW_NUMBER() OVER (PARTITION BY jn.ref_month, jn.journey ORDER BY w.dt_start DESC, w.dt_end DESC) AS rn
    FROM journey_nps AS jn
    LEFT JOIN weights_raw AS w ON jn.journey = w.journey
                               AND CAST(jn.ref_month AS DATE) BETWEEN w.dt_start AND w.dt_end
)
SELECT
    d.ref_month,
    ROUND(SUM(d.nps_journey * COALESCE(d.weight, lw.weight)), 1) AS nps_true,
    SUM(d.total_answers) AS total_answers,
    MAX(CASE WHEN d.journey = 'onboarding'  THEN d.nps_journey END) AS nps_onboarding,
    MAX(CASE WHEN d.journey = 'ongoing'     THEN d.nps_journey END) AS nps_ongoing,
    MAX(CASE WHEN d.journey = 'offboarding' THEN d.nps_journey END) AS nps_offboarding,
    MIN(CASE WHEN d.weight IS NULL THEN 'fallback' ELSE 'official' END) AS weight_source
FROM (SELECT * FROM journey_with_weight WHERE rn = 1) AS d
LEFT JOIN latest_weights AS lw ON d.journey = lw.journey
GROUP BY d.ref_month
ORDER BY d.ref_month
```

### Query 2 — Components by journey, by IQ/PP/Total

Component NPS (Onboarding/Ongoing/Offboarding) already broken down by `customer_type`. For the
**Total** per journey, aggregate IQ+PP in the same pool (or run without `customer_type` in the
`GROUP BY`).

```sql
SELECT
    date_trunc('month', CAST(dna.ts_answered AS TIMESTAMP)) AS ref_month,
    CASE
        WHEN dnc.metric_group LIKE '%onboarding%'  THEN 'onboarding'
        WHEN dnc.metric_group LIKE '%ongoing%'     THEN 'ongoing'
        WHEN dnc.metric_group LIKE '%offboarding%' THEN 'offboarding'
    END AS journey,
    dnc.customer_type,
    COUNT(DISTINCT dna.sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'promoter'  THEN dna.sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN dna.score_category = 'detractor' THEN dna.sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT dna.sk_nps_answer) * 100, 1
    ) AS nps_journey
FROM dw_customer_satisfaction.fact_nps_dispatches AS fnd
INNER JOIN dw_customer_satisfaction.dim_nps_answer   AS dna
    ON fnd.sk_nps_answer = dna.sk_nps_answer
INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc
    ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
WHERE fnd.is_answered = true
  AND dnc.business_context = 'forRent'
  AND dnc.customer_journey = 'true'   -- same canonical filter as Query 1: excludes purpose='test' and non-official campaigns
  AND dnc.purpose          = 'main'
  AND dnc.metric_group IN (
        'iqonboarding','pponboarding',
        'iqongoing','ppongoing',
        'iqoffboarding','ppoffboarding'
      )
  AND CAST(dna.ts_answered AS TIMESTAMP) >= CAST(date_add('month', -24, current_date) AS TIMESTAMP)
  AND CAST(dna.ts_answered AS TIMESTAMP) <  CAST(current_date AS TIMESTAMP)
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
```

### Query 3 — NPS PP Multi (Up to 15 Properties)

Reads directly from `sandbox.nps_fr` (which already brings `campanha_category` and `cnt_15_seg`
ready), mapping the PP Multi categories to journeys and reusing the same quarterly weights as
NPS True. Applies `cnt_15_seg = '<= 15'` only to onb_ppm and ong_ppm. **Each journey's NPS
rounded to an integer before weighting** (`ROUND(…, 0)`), as in the team's gsheets.

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
      AND campanha_category IN ('onb_ppm','ong_ppm','off_ppm')
      AND CAST(ts_answered AS TIMESTAMP) >= CAST(date_add('month', -24, current_date) AS TIMESTAMP)
      AND CAST(ts_answered AS TIMESTAMP) <  CAST(current_date AS TIMESTAMP)
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
    WHERE journey = 'offboarding'
       OR cnt_15_seg = '<= 15'
    GROUP BY 1, 2
),
weights_raw AS (
    SELECT
        campaign_group                                   AS journey,
        CAST(dt_start AS DATE)                           AS dt_start,
        CAST(dt_end   AS DATE)                           AS dt_end,
        CAST(REPLACE(share, '%', '') AS DOUBLE) / 100.0  AS weight
    FROM datalake_gsheets_clean.nps_target_share
    WHERE customer_journey = 'TRUE'
      AND share IS NOT NULL
      AND share != ''
),
latest_weights AS (
    SELECT journey, weight
    FROM (
        SELECT journey, weight,
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
        ROW_NUMBER() OVER (PARTITION BY jn.ref_month, jn.journey ORDER BY w.dt_start DESC, w.dt_end DESC) AS rn
    FROM journey_nps AS jn
    LEFT JOIN weights_raw AS w ON jn.journey = w.journey
                               AND CAST(jn.ref_month AS DATE) BETWEEN w.dt_start AND w.dt_end
)
SELECT
    d.ref_month,
    ROUND(SUM(d.nps_journey * COALESCE(d.weight, lw.weight)), 1) AS nps_pp_multi_n15,
    SUM(d.total_answers) AS total_answers,
    MAX(CASE WHEN d.journey = 'onboarding'  THEN d.nps_journey END) AS nps_onb_ppm,
    MAX(CASE WHEN d.journey = 'ongoing'     THEN d.nps_journey END) AS nps_ong_ppm,
    MAX(CASE WHEN d.journey = 'offboarding' THEN d.nps_journey END) AS nps_off_ppm,
    MIN(CASE WHEN d.weight IS NULL THEN 'fallback' ELSE 'official' END) AS weight_source
FROM (SELECT * FROM journey_with_weight WHERE rn = 1) AS d
LEFT JOIN latest_weights AS lw ON d.journey = lw.journey
GROUP BY d.ref_month
ORDER BY d.ref_month
```

### Query 4 — SPOC NPS and AS IS NPS, by IQ/PP/Total

Both metrics side by side, reading the ready `is_spoc_test` and `spoc_team` from
`sandbox.nps_fr` — without re-joining `fact_terminations`. Already broken down by
`customer_type` and by `spoc_team` (`'BAU'`/`'LAB'` within SPOC). For **Total**, remove
`customer_type` from the `GROUP BY`; for SPOC/AS IS without the BAU/LAB breakdown, remove
`spoc_team`.

```sql
SELECT
    date_trunc('month', CAST(ts_answered AS TIMESTAMP)) AS ref_month,
    customer_type,
    CASE WHEN is_spoc_test THEN 'SPOC' ELSE 'AS IS' END AS spoc_group,
    spoc_team,   -- 'BAU' / 'LAB' when SPOC; NULL in AS IS
    COUNT(DISTINCT sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT sk_nps_answer) * 100, 1
    ) AS nps
FROM sandbox.nps_fr
WHERE campanha_nps = 'offboarding'
  AND CAST(ts_answered AS TIMESTAMP) >= CAST(date_add('month', -24, current_date) AS TIMESTAMP)
  AND CAST(ts_answered AS TIMESTAMP) <  CAST(current_date AS TIMESTAMP)
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4
```

### Query 5 — NPS by interaction type (Seamless / Digital Sup / Human Support), by IQ/PP/Total

**Canonical path** — reproduces the team's number. The cohorts are materialized in
`sandbox.nps_onb_cohort` and `sandbox.nps_ong_cohort` (`sk_nps_answer` grain), already with
`seamless_ticket_type` computed; just pool onb+ong and compute the NPS on top. Returns
**one row per `seamless_ticket_type`** — filter `'seamless'` (Seamless), `'tickets'`
(Human Support) or `'digital_support'` (Digital Sup). IQ/PP breakdown via `customer_type`; for
**Total**, remove `customer_type` from the `GROUP BY`. Queries 1–4 limit to 24 months; this one
covers the whole period present in the sandbox tables — uncomment the date filter to align the
window.

```sql
WITH seamless_base AS (
    SELECT sk_nps_answer, customer_type, score_category, seamless_ticket_type, data_resposta_nps
    FROM sandbox.nps_onb_cohort
    UNION ALL
    SELECT sk_nps_answer, customer_type, score_category, seamless_ticket_type, data_resposta_nps
    FROM sandbox.nps_ong_cohort
)
SELECT
    date_trunc('month', CAST(data_resposta_nps AS TIMESTAMP)) AS ref_month,
    customer_type,
    seamless_ticket_type,
    COUNT(DISTINCT sk_nps_answer) AS den_answers,
    COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END)
  - COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS net_num,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT sk_nps_answer) * 100, 1
    ) AS nps
FROM seamless_base
-- NPS Seamless → 'seamless'; NPS Human Support → 'tickets'; NPS Digital Sup → 'digital_support'
WHERE seamless_ticket_type IN ('seamless', 'tickets', 'digital_support')
  -- To align with the 24-month window of the other queries, uncomment:
  -- AND CAST(data_resposta_nps AS TIMESTAMP) >= CAST(date_add('month', -24, current_date) AS TIMESTAMP)
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
```

### Query 6 — Offboarding NPS by Ops cut, by IQ/PP/Total

Template for any operational cut of the Offboarding NPS (see the **Offboarding cuts** map in
Nuances). Reads everything from `sandbox.nps_fr` filtering `campanha_nps = 'offboarding'` and
the cut's flag. Here the cut appears as a **dimension** (`ops_cut`) to compare side by side; to
isolate a single value, replace it with a `WHERE` on the flag. IQ/PP breakdown via
`customer_type`; for **Total**, remove `customer_type` from the `GROUP BY`.

```sql
SELECT
    date_trunc('month', CAST(ts_answered AS TIMESTAMP)) AS ref_month,
    customer_type,
    -- choose the cut to analyze (one at a time). Examples:
    CASE WHEN com_ou_sem_reparos THEN 'w/ Repairs' ELSE 'w/o Repairs' END AS ops_cut,
    -- SPOC BAU/LAB:        CASE WHEN is_spoc_test THEN spoc_team ELSE 'AS IS' END
    -- w/ Mediation:        CASE WHEN intermed = 1 THEN 'w/ Mediation' ELSE 'w/o Mediation' END
    -- w/ Early Mediation:  CASE WHEN has_early_mediation THEN 'w/ Early Mediation' ELSE 'w/o Early Mediation' END
    -- w/ Early Both Agree: CASE WHEN is_early_both_agree THEN 'w/ Early Both Agree' ELSE 'w/o Early Both Agree' END
    -- Repairs Contested:   CASE WHEN total_repair_contested = 1 THEN 'w/ Contested' ELSE 'w/o Contested' END
    --   ... PP / IQ:       contest_owner = 1 / contest_tenant = 1
    -- w/ Tkt Back:         CASE WHEN ticket_off_escalado THEN 'w/ Tkt Back' ELSE 'w/o Tkt Back' END
    -- Ldt:                 CASE WHEN leadtime_total > 15 THEN '> 15d' ELSE '<= 15d' END
    COUNT(DISTINCT sk_nps_answer) AS total_answers,
    ROUND(
        (CAST(COUNT(DISTINCT CASE WHEN score_category = 'promoter'  THEN sk_nps_answer END) AS DOUBLE)
       - CAST(COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END) AS DOUBLE))
        / COUNT(DISTINCT sk_nps_answer) * 100, 1
    ) AS nps
FROM sandbox.nps_fr
WHERE campanha_nps = 'offboarding'
  AND CAST(ts_answered AS TIMESTAMP) >= CAST(date_add('month', -24, current_date) AS TIMESTAMP)
  AND CAST(ts_answered AS TIMESTAMP) <  CAST(current_date AS TIMESTAMP)
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
```

## Superset Golden Assets

The three datasets below were born as **virtual datasets** (Superset) and **have already been
materialized into sandbox tables** (`sk_nps_answer` grain) — **consume the tables directly**;
the Superset URN remains only as the origin/documentation of the logic (the SQL is exposed in
DataHub).

- **NPS For Rent Post Contract [Perf.] [Support and Services]** — canonical post-contract NPS base (all journeys + offboarding flags, `is_spoc_test`, `spoc_team`, `cnt_15_seg`, etc.). **Materialized in `sandbox.nps_fr`** (`sk_nps_answer` grain) — consume the table directly for PP Multi, SPOC/AS IS and the Offboarding cuts. URN (origin): `urn:li:dataset:(urn:li:dataPlatform:superset,16266,PROD)` ([link](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:%28urn:li:dataPlatform:superset,16266,PROD%29/Columns)).
- **NPS ONB Cohort [Support and Services][VoC]** — origin of the `seamless_ticket_type` logic for the **onboarding** journey (`sk_nps_answer` grain). **Materialized in `sandbox.nps_onb_cohort`** — consume the table directly. URN (origin): `urn:li:dataset:(urn:li:dataPlatform:superset,15745,PROD)` ([link](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:%28urn:li:dataPlatform:superset,15745,PROD%29/Columns)).
- **NPS ONG Cohort [Support and Services][VoC]** — equivalent for the **ongoing** journey (`sk_nps_answer` grain). **Materialized in `sandbox.nps_ong_cohort`** — consume the table directly. URN (origin): `urn:li:dataset:(urn:li:dataPlatform:superset,15749,PROD)` ([link](https://datahub.apps.data-prd.habitat.zone/dataset/urn:li:dataset:%28urn:li:dataPlatform:superset,15749,PROD%29/Columns)).
