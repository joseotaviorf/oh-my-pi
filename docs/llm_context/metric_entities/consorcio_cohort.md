# Consórcio Funnel — Cohort View

## Ownership

**Data Owner:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

**Data Steward:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

## Overview

**Consórcio Funnel — Cohort View** is the family of official **cohort** funnel metrics for Consórcio: conversions and cycle time anchored on the **lead creation date** and matured in **business days**. It is the canonical efficiency lens for the funnel (Daily, WBR, Fechamento Mensal, MBR). It differs from a naive read because every conversion is measured over the *cohort of leads that entered in a window* — not the volume that crossed a stage in the period (that is the Coincident View) — and maturation is counted in **business days**, not calendar days.

**Measured from `Lead` onward** — top-of-funnel conversions (PV2L, Sent → Page View) are out of scope.

**Maturation is materialized.** - `datalake_consorcio.deal_milestone` ships one `business_days_from_created_to_*` column per milestone. Stage-to-stage windows are **derived by subtracting two of those columns** — the rule is in [Calculation](#calculation).

## Related Domain Entities

- Consórcio

## Catalog

| Metric | Type |
| :---- | :---- |
| L2CD (Lead → Closed Deal) | OKR |
| L2SA (Lead → Simulation Accepted) | Health Metric |
| SA2CD (Simulation Accepted → Closed Deal) | Health Metric |
| SS2CD (Simulation Sent → Closed Deal) | Health Metric |
| L2SC (Lead → Successful Contact) | Health Metric |
| SC2SS (Successful Contact → Simulation Sent) | Health Metric |
| L2SS (Lead → Simulation Sent) | Health Metric |
| SS2SA (Simulation Sent → Simulation Accepted) | Health Metric |
| SA2OUN (Simulation Accepted → Offer Under Negotiation) | Health Metric |
| OUN2OA (Offer Under Negotiation → Offer Accepted) | Health Metric |
| OA2CC (Offer Accepted → Contract Created) | Health Metric |
| CC2CD (Contract Created → Closed Deal) | Health Metric |
| SC2SA (Successful Contact → Simulation Accepted) | Health Metric |
| SC2CD (Successful Contact → Closed Deal) | Health Metric |
| SA2OA (Simulation Accepted → Offer Accepted) | Health Metric |
| SA2CC (Simulation Accepted → Contract Created) | Health Metric |
| OUN2CD (Offer Under Negotiation → Closed Deal) | Health Metric |
| OA2CD (Offer Accepted → Closed Deal) | Health Metric |
| L2OUN / L2OA / L2CC (Lead → each late stage) | Health Metric |
| Any other stage pair (e.g. SC2CC, SS2OA) | Health Metric |

## Glossary and Synonyms

- **L2CD**, **Lead to Closed Deal**, **conversão lead→venda**, **eficiência do funil** → this metric family (Result)
- **L2SA**, **Lead to Simulation Accepted**, **conversão até o handoff** → L2SA
- **SA2CD**, **Simulation Accepted to Closed Deal**, **conversão da esteira comercial** → SA2CD
- **SS2CD**, **Simulation Sent to Closed Deal** → SS2CD
- **L2SC / SC2SS / L2SS / SS2SA** → top and middle of funnel (diagnostic)
- **SA2OUN / OUN2OA / OA2CC / CC2CD** → human journey (diagnostic)
- **SC2SA / SC2CD / SA2OA / SA2CC / OUN2CD / OA2CD** → intermediate conversions, same rule as the named ones
- **X2Y**, **conversão de \<etapa\> para \<etapa\>** → any stage pair; if it is not in the Catalog it is still computable — see *Any stage pair, on demand*
- **conversão cohort**, **eficiência da safra**, **cohort D+n** → cohort reading of any of the above
- **maturação**, **aging de conversão** → the business-day distance between two milestones
- **DU** (*dia útil*) → business day on the Brazilian calendar

## Scope

**Included**: the funnel **from `Lead` onward** (the pipeline scope is already applied upstream) — all origins (Meta, Google, YouTube/Paid Media, CRM, Direct, Internal, Imovelweb, Repescagem) and all tracks (`SDR IA`, `SIMULATOR IA`, `SDR Humano`).

**Excluded**: PV2L / Sent → Page View / Consentimento → Lead (top-of-funnel, CRM/web, out of the model). Test deals and duplicates are **already excluded upstream** by the `datalake_consorcio.deal` build — no filter needed here. Also excluded analytically: **OUN/CC-based conversions before 2026-07-20** (those stages did not exist) and **contact-initiation cuts before 2026-08-10**.

## Calculation

Every conversion is read in **cohort**: membership by lead creation period; maturation `D+n` in **business days** from the conversion's **start stage** to the end stage.

```
X2Y at D+n (cohort) = #(reached Y within n business days of reaching X) / #(reached X)
```

over the lead cohort. Value metrics: `GMV New = SUM(deal_amount)` over Closed Deals; `Avg Ticket = GMV New / #CD`; `R$/lead = GMV New / #Leads`.

### Maturation columns (materialized)

`datalake_consorcio.deal_milestone` carries the maturation of every milestone as a `bigint` column, **always measured from the deal creation date to that milestone, in Brazilian business days** (`dw_public.dim_date.is_brz_business_day`, counted inclusively minus 1 and floored at 0):

| Column | Milestone |
| :---- | :---- |
| `business_days_from_created_to_lead` | Lead |
| `business_days_from_created_to_contact_attempt` | Contact Attempt (TC) |
| `business_days_from_created_to_success_contact` | Successful Contact |
| `business_days_from_created_to_simulation_sent` | Simulation Sent |
| `business_days_from_created_to_simulation_accepted` | Simulation Accepted |
| `business_days_from_created_to_offer_under_negotiation` | Offer Under Negotiation |
| `business_days_from_created_to_offer_accepted` | Offer Accepted |
| `business_days_from_created_to_contract_created` | Contract Created |
| `business_days_from_created_to_closed_deal` | Closed Deal |
| `business_days_from_created_to_handoff` | Handoff |
| `business_days_from_created_to_discarded` | Discard |

Semantics that decide whether a formula is right:

- **Created is the lead anchor.** `business_days_from_created_to_lead` is `0` across the base (validated on the July 2026 cohort: 56,324 of 56,324 rows), so creation date and lead date are the same anchor. Every `L2*` metric therefore reads its column directly, with no offset.
- **`NULL`, never `0`, when the milestone was not reached** — or when its date falls outside the calendar window. `0` always means a genuine **same-day** transition. This is why the maturation column also gates the numerator: it is non-null exactly when the stage flag is `1` (validated on July 2026: 43,619 non-null SC maturations against 43,619 `is_success_contact = 1`, and 5,995 against 5,995 for SA — zero mismatches).
- **Immutable once reached.** A `business_days_*` value never changes after its milestone happens, so a cohort number computed today is reproducible tomorrow.
- **`aging_opened_leads` and `days_in_current_stage` are the exception** — both are relative to the **run date** and only valid as of the last rebuild. Never use them inside a historical cohort comparison.

### Stage-to-stage maturation (derived)

Only lead-anchored maturations are stored. Any other window — for example Successful Contact → Simulation Accepted — is derived by taking the maturation of the **more advanced** stage and subtracting the maturation of the **earlier** stage:

```sql
GREATEST(0,
    business_days_from_created_to_simulation_accepted
  - business_days_from_created_to_success_contact
) AS business_days_from_sc_to_sa
```

General form, where `Y` is the later stage and `X` the earlier one:

```sql
GREATEST(0, business_days_from_created_to_Y - business_days_from_created_to_X)
```

- **`GREATEST(0, ...)` is an exception guard, not a modelling choice.** A negative result has no business meaning, so it is floored at 0\. It is rare: on the July 2026 cohort exactly **1 of 5,995** SC → SA pairs was negative (minimum `-2`), around 0.02%.
- **Null propagates, which is correct.** If either stage was not reached the subtraction is `NULL`, so the deal is excluded from the numerator and the pair is never counted as a 0-day conversion.
- Use the same derivation for every intermediate pair: `sc→ss`, `sc-sa`, `ss→sa`, `sa→oun`, `oun→oa`, `oa→cc`, `cc→cd`, `ss→cd`, `sa→cd`, `handoff→cd`.
- **Although cohort membership is anchored on the lead creation date, conversions are not restricted to a lead anchor** — with this rule any `X2Y` can be matured from its own start stage `X`.

### Any stage pair, on demand

**The Catalog is not a closed list.** If someone asks for a conversion that is not named there — `SC2CC`, `SS2OA`, anything — it is still an official number, computed exactly like the named ones. Nothing new needs to be defined:

1. Take the two stages from the funnel definition in the **Consórcio** business entity, and their two `is_*` flags.
2. Denominator = `SUM(is_X)` — the deals that reached the start stage.
3. Numerator = deals that reached `Y` within `n` business days of `X`, using the subtraction rule above.
4. State the maturation used, since an unnamed pair has no canonical window — ask for `D+n`, or say which one you assumed.

```sql
-- SC2CC at D+14, as an example of a pair that is not in the Catalog
100e0 * SUM(CASE WHEN is_contract_created = 1
                  AND GREATEST(0, business_days_from_created_to_contract_created
                                - business_days_from_created_to_success_contact) <= 14
             THEN 1 END)
      / NULLIF(SUM(is_success_contact), 0) AS sc2cc_d14
```

The only pairs that are **not** valid are the ones the funnel does not order: `Contact Attempt` is a branch, not a cumulative stage, so a `TC2*` conversion has a smaller and differently-shaped population than an `L2*` one — say so when reporting it. And any pair involving `OUN` or `CC` is only valid for cohorts on or after 2026-07-20.

Metric hierarchy and canonical windows (from *\[Consórcio\] Novo Funil* — initial, to be calibrated):

| Level | Metric | Canonical window | Denominator |
| :---- | :---- | :---- | :---- |
| Result | L2CD | D14 | Leads |
| Health | L2SA | D0–D2 | Leads |
| Health | SA2CD / SS2CD | D7 / D14 | Reached SA / SS |
| Health | L2SC, SC2SS, SC2SA, L2SS, L2SA, SS2SA | D0–D1/D2 | Leads / reached start stage
| Health | SA2OUN, OUN2OA, OA2CC, CC2CD | D2 / D7 / D14 | Reached start stage |
| Health | SC2SA | D0–D2 | Reached SC |
| Health | SC2CD, SA2OA, SA2CC, OUN2CD, OA2CD | D7 / D14 | Reached start stage |


### Canonical Filter

The deal-grain base (`Funil Cohort - Não Agregado`) arrives **already filtered** — do not re-apply the domain filters:

```sql
-- No canonical WHERE clause is needed on the base dataset: the pipeline filter,
-- the one-row-per-deal dedup, and the test/duplicate exclusion are all applied
-- in the datalake_consorcio.deal build. Only add analytical scoping, e.g.:
year = 2026 AND month = 7          -- partition pruning
-- and, when the metric involves OUN/CC, restrict the cohort:
-- AND dt_created >= DATE '2026-07-20'
-- Cohort membership = dt_created (exposed as `date`); timestamps already in America/Sao_Paulo.
```

**Warning**: reading a conversion **coincident** (by each stage's own timestamp) instead of cohort inflates or deflates it versus the official number — "conversão" always means cohort here. Also, using calendar days instead of business days for `D+n` breaks comparability with the reported cuts, which is precisely what the materialized columns prevent.

### Nuances

- **Open vs closed cohort — always ask.** An **open cohort** counts all conversions to date (no cap); a **closed cohort** caps at a fixed `D+n`. Do not assume the window; if you must, state the maturation used. Some conversions mature very fast (near-fully matured by roughly D2).
- **Handoff (canonical):** `Simulação Aceita` (`SIMULATOR IA`), `Simulação Enviada` (`SDR IA`), `Lead` (`SDR Humano`). Not a headline conversion — use SS2CD / SA2CD.
- **GMV** is usually read coincident (see Coincident View); available in cohort via `deal_amount`.
- **Intermediate Conversions**: For all full and intermediate conversions from Lead to Simulation Accepted (`L2SC`, `L2SS`, `L2SA`, `SC2SS`, `SC2SA`, `SS2SA`) deals from the SDR Humano pipeline should be excluded from the calculation since these are conversions to understand the AI Agent performance.
- **Contact initiation / abandoned cart (from 2026-08-10 only)** — `is_abandoned_cart = 1` (an `integer` flag) means the user did not send the first WhatsApp message, we sent the abandoned-cart template and the card moved to **TC**; a reply then advances it to **SC**. `0` means the user sent the first message and the deal went **straight to SC**. Exposed as `contact_type` (`company_initiated` / `user_initiated`). It is `NULL` for earlier cohorts — never segment a cohort by it before that date, and never compare a pre/post-2026-08-10 series on it.
- **Timestamps are already in BRT.** Every `ts_*` column is already converted to `America/Sao_Paulo`, and `dt_created` / `date` is already the local calendar date. Do **not** apply `AT_TIMEZONE(...)` again — a second conversion shifts the cohort date and can move deals across day/week/month boundaries.
- **OUN and CC valid only from 2026-07-20** — restrict conversions involving them to cohorts on or after that date.
- **Analyst, role, supervisor and team are resolved as of the deal creation date**, from the Operação IS sheet, so a cohort split by supervisor reflects the operation as it was — not as it is today. Deals owned by an analyst who received leads after their end date carry supervisor `other`.
- **Use `100e0`, not `100.0`, in a conversion ratio.** In Trino `100.0` is a `decimal(4,1)`, so the whole expression stays at scale 1 and `ROUND(x, 3)` cannot recover the lost digits — an L2CD of `0.582%` prints as `0.6%`. Multiplying by the double literal `100e0` keeps the precision. This matters for the sub-1% conversions (L2CD, SS2CD), not for the mid-funnel ones.
- **Parity with the previous model.** Recomputing the June 2026 cohort from the materialized columns returns 257 closed deals over 44,121 leads \= **0.582% L2CD matured**, matching the number produced by the old inline `dim_date` computation and the WBR cut.
- **Renamed columns.** The base previously exposed inline `days_to_convert_from_*` columns. They are replaced by `business_days_from_created_to_*` plus the subtraction rule above; a saved query or chart still pointing at the old names must be remapped.

**Official source**: the base dataset is built from `datalake_consorcio.deal` \+ `datalake_consorcio.deal_milestone` — the funnel business rules (pipeline filter, dedup to latest stage, test/duplicate exclusion, origin/segment mapping, analyst attribution, qualifier explosion, contact initiation, simulation aggregates and the business-day maturations) are applied in the table build, not in the metric query. Flag names follow the table: `is_lead`, `is_contact_attempted`, `is_success_contact`, `is_simulation_sent`, `is_simulation_accepted`, `is_offer_under_negotiation`, `is_offer_accepted`, `is_contract_created`, `is_closed_deal`, `is_handoff`, `is_discarded`; the value field is `deal_amount`.

**Stage-visit detail**: `datalake_consorcio.deal_stage` holds the visit history for deep investigation only. It is **not** at deal grain (joining it fans out) and a skipped stage leaves no row there — the milestone corrections are applied when `deal_milestone` is built, so read stage passage from the `is_*` flags.

**Fallback**: a deal that never reached a stage has a `NULL` maturation for that conversion (excluded from the numerator); denominators use the cumulative flags.

## Dos and Don'ts

**Do:**

- Ask **open vs closed cohort (and days)** before answering; state the maturation if assumed.
- Read every conversion in **cohort** by lead creation date; mature in **business days**.
- Derive stage-to-stage windows with `GREATEST(0, business_days_from_created_to_Y - business_days_from_created_to_X)`.
- Answer **any** stage pair asked for, named in the Catalog or not — the derivation is the same; just state the maturation used.
- Separate **mix vs intra-channel vs journey** when the aggregate moves.

**Don't:**

- Don't default a bare "conversão" question to coincident — it is cohort.
- Don't recompute maturation against `dw_public.dim_date` — it is materialized; recomputing risks a different business-day convention.
- Don't read a `0` maturation as "did not reach the stage" — absence is `NULL`; `0` is a same-day conversion.
- Don't use `aging_opened_leads` or `days_in_current_stage` in a historical comparison — both are relative to the last rebuild.
- Don't present GMV/ticket/R$-per-lead as cohort without confirming the view (usually coincident).
- Don't analyze OUN/CC conversions before 2026-07-20; don't use a non-track-aware handoff.
- Don't include `SDR Humano` pipeline for any conversion between the stages of Lead and Simulation Accepted

## Golden Queries

### Query 1 — Headline cohort metrics per cohort week

Per cohort week, the headline cohort metrics plus GMV. Runs on the **Funil Cohort deal-grain base**, which carries the `is_*` flags, the materialized `business_days_from_created_to_*` columns, `origin`, track, `deal_amount` and `ts_deal_created`. The pattern generalizes to any `X2Y` at `D+n` by swapping the flag and the maturation expression.

```sql
-- Base = one row per deal (latest stage), from the OFFICIAL SOURCE
-- datalake_consorcio.deal + datalake_consorcio.deal_milestone (joined 1:1 on id_deal).
-- Lead-anchored windows read the column directly (created == lead anchor).
-- Stage-to-stage windows subtract two columns and floor at 0.
WITH funil AS (
    SELECT
        d.dt_created,
        dm.is_lead,
        dm.is_success_contact,
        dm.is_simulation_sent,
        dm.is_simulation_accepted,
        dm.is_offer_under_negotiation,
        dm.is_offer_accepted,
        dm.is_contract_created,
        dm.is_closed_deal,
        d.deal_amount,
        dm.business_days_from_created_to_closed_deal          AS bd_cd,
        dm.business_days_from_created_to_simulation_accepted  AS bd_sa,
        dm.business_days_from_created_to_simulation_sent      AS bd_ss,
        dm.business_days_from_created_to_success_contact      AS bd_sc,
        dm.business_days_from_created_to_offer_under_negotiation AS bd_oun,
        dm.business_days_from_created_to_offer_accepted       AS bd_oa,
        dm.business_days_from_created_to_contract_created     AS bd_cc
    FROM datalake_consorcio.deal d
    INNER JOIN datalake_consorcio.deal_milestone dm
      ON dm.id_deal = d.id_deal
    WHERE d.year = 2026 AND d.month = 7          -- analytical scoping only
)
SELECT
    date_trunc('week', dt_created) AS cohort_week,
    COUNT(*)                       AS leads,

    -- Windows below are ILLUSTRATIVE. Per question, pick OPEN cohort (matured / no cap)
    -- or CLOSED cohort at a fixed D+n. Ask the person; do not assume the canonical window.

    -- L2CD (Result) -- lead-anchored, column read directly
    ROUND(100e0*SUM(CASE WHEN is_closed_deal=1 AND bd_cd <= 2  THEN 1 END)/COUNT(*), 3) AS l2cd_d2,
    ROUND(100e0*SUM(CASE WHEN is_closed_deal=1 AND bd_cd <= 14 THEN 1 END)/COUNT(*), 3) AS l2cd_d14,
    ROUND(100e0*SUM(is_closed_deal)/COUNT(*), 3)                                        AS l2cd_matured,

    -- L2SA (Health) -- lead-anchored
    ROUND(100e0*SUM(CASE WHEN is_simulation_accepted=1 AND bd_sa <= 2 THEN 1 END)/COUNT(*), 3) AS l2sa_d2,

    -- SA2CD (Health) -- denominator = reached SA; window derived from SA
    ROUND(100e0*SUM(CASE WHEN is_closed_deal=1
                          AND GREATEST(0, bd_cd - bd_sa) <= 14 THEN 1 END)
          / NULLIF(SUM(is_simulation_accepted),0), 3)                                   AS sa2cd_d14,

    -- SS2CD -- denominator = reached SS; window derived from SS
    ROUND(100e0*SUM(CASE WHEN is_closed_deal=1
                          AND GREATEST(0, bd_cd - bd_ss) <= 14 THEN 1 END)
          / NULLIF(SUM(is_simulation_sent),0), 3)                                       AS ss2cd_d14,

    -- Diagnostic conversions -- windows ILLUSTRATIVE; denominator = reached start stage.
    -- The subtraction is NULL unless both stages were reached, so it gates the numerator.
    -- OUN/CC-based rows are valid only for cohorts on/after 2026-07-20.
    ROUND(100e0*SUM(CASE WHEN GREATEST(0, bd_ss  - bd_sc)  <= 1  THEN 1 END)/NULLIF(SUM(is_success_contact),0), 3)        AS sc2ss_d1,
    ROUND(100e0*SUM(CASE WHEN GREATEST(0, bd_sa  - bd_ss)  <= 1  THEN 1 END)/NULLIF(SUM(is_simulation_sent),0), 3)        AS ss2sa_d1,
    ROUND(100e0*SUM(CASE WHEN GREATEST(0, bd_oun - bd_sa)  <= 7  THEN 1 END)/NULLIF(SUM(is_simulation_accepted),0), 3)    AS sa2oun_d7,
    ROUND(100e0*SUM(CASE WHEN GREATEST(0, bd_oa  - bd_oun) <= 14 THEN 1 END)/NULLIF(SUM(is_offer_under_negotiation),0), 3) AS oun2oa_d14,
    ROUND(100e0*SUM(CASE WHEN GREATEST(0, bd_cc  - bd_oa)  <= 14 THEN 1 END)/NULLIF(SUM(is_offer_accepted),0), 3)         AS oa2cc_d14,
    ROUND(100e0*SUM(CASE WHEN GREATEST(0, bd_cd  - bd_cc)  <= 14 THEN 1 END)/NULLIF(SUM(is_contract_created),0), 3)       AS cc2cd_d14,

    -- Value (usually read COINCIDENT -- see Coincident View -- kept here for cohort GMV)
    SUM(CASE WHEN is_closed_deal=1 THEN deal_amount END)                               AS gmv_new,
    SUM(CASE WHEN is_closed_deal=1 THEN deal_amount END)/NULLIF(SUM(is_closed_deal),0)  AS avg_ticket,
    SUM(CASE WHEN is_closed_deal=1 THEN deal_amount END)/COUNT(*)                      AS rs_per_lead
FROM funil
GROUP BY 1
ORDER BY 1
```

### Query 2 — Maturation curve of a conversion

Distribution of a single conversion's maturation, to choose or defend a `D+n` cut. Shown for SC → SA using the subtraction rule; swap the two columns for any other pair.

```sql
WITH pairs AS (
    SELECT
        date_trunc('month', d.dt_created) AS cohort_month,
        dm.is_success_contact,
        GREATEST(0,
            dm.business_days_from_created_to_simulation_accepted
          - dm.business_days_from_created_to_success_contact
        ) AS bd_sc_to_sa
    FROM datalake_consorcio.deal d
    INNER JOIN datalake_consorcio.deal_milestone dm
      ON dm.id_deal = d.id_deal
    WHERE d.year = 2026 AND d.month IN (6, 7)
)
SELECT
    cohort_month,
    SUM(is_success_contact)                                              AS reached_sc,
    COUNT(bd_sc_to_sa)                                                   AS reached_sa,
    ROUND(100e0*SUM(CASE WHEN bd_sc_to_sa = 0  THEN 1 END)/NULLIF(SUM(is_success_contact),0), 2) AS sc2sa_same_day,
    ROUND(100e0*SUM(CASE WHEN bd_sc_to_sa <= 1 THEN 1 END)/NULLIF(SUM(is_success_contact),0), 2) AS sc2sa_d1,
    ROUND(100e0*SUM(CASE WHEN bd_sc_to_sa <= 2 THEN 1 END)/NULLIF(SUM(is_success_contact),0), 2) AS sc2sa_d2,
    ROUND(100e0*SUM(CASE WHEN bd_sc_to_sa <= 7 THEN 1 END)/NULLIF(SUM(is_success_contact),0), 2) AS sc2sa_d7,
    ROUND(100e0*COUNT(bd_sc_to_sa)/NULLIF(SUM(is_success_contact),0), 2)                         AS sc2sa_matured,
    APPROX_PERCENTILE(bd_sc_to_sa, 0.5)                                  AS p50_business_days,
    APPROX_PERCENTILE(bd_sc_to_sa, 0.9)                                  AS p90_business_days
FROM pairs
GROUP BY 1
ORDER BY 1
```

General pattern for any conversion `X2Y` at `D+n`:

```
-- lead-anchored (X = Lead)
100e0 * SUM(CASE WHEN is_Y = 1 AND business_days_from_created_to_Y <= n THEN 1 END)
      / COUNT(*)

-- stage-to-stage
100e0 * SUM(CASE WHEN is_Y = 1
                  AND GREATEST(0, business_days_from_created_to_Y
                                - business_days_from_created_to_X) <= n THEN 1 END)
      / NULLIF(SUM(is_X), 0)
```

## Superset Golden Assets

- **Funil Cohort \- Não Agregado \[Consorcio\]\[Fintech\]** — the canonical cohort deal-grain dataset analysts consume; materialized by the Consórcio business entity's golden query. (Add the Superset dataset URN when available.)
