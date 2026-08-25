# Consórcio Funnel — Cohort View

## Ownership

**Data Owner:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)  

**Data Steward:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

## Overview

**Consórcio Funnel — Cohort View** is the family of official **cohort** funnel metrics for Consórcio: conversions and cycle time anchored on the **Lead creation date** and matured in **business days**. It is the canonical efficiency lens for the funnel (Daily, WBR, Fechamento Mensal, MBR). It differs from a naive read because every conversion is measured over the *cohort of leads that entered in a window* — not the volume that crossed a stage in the period (that is the Coincident View) — and maturation is counted in **business days** from the conversion's start stage, not calendar days.

**Measured from `Lead` onward** — top-of-funnel conversions (PV2L, Sent → Page View) and Consentimento → Lead are out of scope.

## Related Domain Entities

- Consórcio (Inside Sales Funnel)

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


## Glossary and Synonyms

- **L2CD**, **Lead to Closed Deal**, **conversão lead→venda**, **eficiência do funil** → this metric family (Result)  
- **L2SA**, **Lead to Simulation Accepted**, **conversão até o handoff** → L2SA  
- **SA2CD**, **Simulation Accepted to Closed Deal**, **conversão da esteira comercial** → SA2CD  
- **SS2CD**, **Simulation Sent to Closed Deal** → SS2CD  
- **L2SC / SC2SS / L2SS / SS2SA** → topo/meio de funil (diagnóstico)  
- **SA2OUN / OUN2OA / OA2CC / CC2CD** → jornada humana (diagnóstico)  
- **conversão cohort**, **eficiência da safra**, **cohort D+n** → cohort reading of any of the above

## Scope

**Included**: the funnel **from `Lead` onward** (the pipeline scope is already applied upstream) — all origins (Meta, Google, YouTube/Paid Media, CRM, Direct, Internal, Imovelweb, Repescagem) and all tracks (`SDR IA`, `SIMULATOR IA`, `SDR Humano`).

**Excluded**: PV2L / Sent → Page View / Consentimento → Lead (top-of-funnel, CRM/web, out of the model). Test deals and duplicates are **already excluded upstream** by the `datalake_consorcio.deal` build — no filter needed here. Also excluded analytically: **OUN/CC-based conversions before 2026-07-20** (those stages did not exist) and **contact-initiation cuts before 2026-08-10**.

## Calculation

Every conversion is read in **cohort**: membership by lead creation period; maturation `D+n` in **business days** (`dw_public.dim_date.is_brz_business_day`) from the conversion's **start stage** to the end stage.

```
X2Y at D+n (cohort) = #(reached Y within n business days of reaching X) / #(reached X)
```

over the lead cohort. For `L2*` the start stage is `Lead`, so `D+n` is business days from **`ts_lead`** (the Lead milestone — the official anchor for every lead-anchored measure, not `ts_deal_created`). **Although cohort membership is anchored on the lead creation date, conversions are not restricted to a lead anchor:** the base model already carries the **stage-to-stage conversion aging** (`days_to_convert_from_X_to_Y` — both `lead→*` and the intermediate pairs `sc→ss`, `ss→sa`, `sa→oun`, `oun→oa`, `oa→cc`, `cc→cd`), so any conversion `X2Y` can be matured **from its own start stage `X`**, not only from Lead. Value metrics: `GMV New = SUM(deal_amount)` over Closed Deals; `Avg Ticket = GMV New / #CD`; `R$/lead = GMV New / #Leads`.

Metric hierarchy & canonical windows (from *[Consórcio] Novo Funil* — initial, to be calibrated):

| Level | Metric | Canonical window | Denominator |
| :---- | :---- | :---- | :---- |
| Result | L2CD | D14 | Leads |
| Health | L2SA | D0–D2 | Leads |
| Health | SA2CD / SS2CD | D7 / D14 | Reached SA / SS |
| Diagnostic | L2SC, SC2SS, L2SS, SS2SA | D0–D1/D2 | Leads / reached start stage |
| Diagnostic | SA2OUN, OUN2OA, OA2CC, CC2CD | D2 / D7 / D14 | Reached start stage |

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

**Warning**: reading a conversion **coincident** (by each stage's own timestamp) instead of cohort inflates/deflates it versus the official number — "conversão" always means cohort here. Also, using calendar days instead of business days for `D+n` breaks comparability with the reported cuts.

### Nuances

- **Open vs closed cohort — always ask.** An **open cohort** counts all conversions to date (no cap); a **closed cohort** caps at a fixed `D+n`. Do not assume the window; if you must, state the maturation used. Some conversions mature very fast (near-fully matured by ~D2).  
- **Handoff (canonical):** `Simulação Aceita` (`SIMULATOR IA`), `Simulação Enviada` (`SDR IA`), `Lead` (`SDR Humano`). Not a headline conversion — use SS2CD / SA2CD.  
- **GMV** is usually read coincident (see Coincident View); available in cohort via `deal_amount`.  
- **Contact initiation / abandoned cart (from 2026-08-10 only)** — `is_abandoned_cart = 1` (an `integer` flag, not a string) means the user did not send the first WhatsApp message, we sent the abandoned-cart template and the card moved to **TC**; a reply then advances it to **SC**. `0` means the user sent the first message and the deal went **straight to SC**. Exposed as `contact_type` (`company_initiated` / `user_initiated`). It is `NULL` for earlier cohorts — never segment a cohort by it before that date, and never compare a pre/post-2026-08-10 series on it. (The old `consorcio_c2w_message` no longer exists in the model.)
- **Timestamps are already in BRT.** Every `ts_*` column in the base dataset is already converted to `America/Sao_Paulo` (`timestamp(3) with time zone`), and `dt_created` / `date` is already the local calendar date. Do **not** apply `AT_TIMEZONE(...)` again — a second conversion shifts the cohort date and can move deals across day/week/month boundaries, silently changing `D+n` maturation.
- **OUN & CC valid only from 2026-07-20** — restrict conversions involving them to cohorts on/after that date.

**Official source**: the base dataset is built from `datalake_consorcio.deal` + `datalake_consorcio.deal_milestone` — the funnel business rules (pipeline filter, dedup to latest stage, test/duplicate exclusion, origin/segment mapping, qualifier explosion, contact initiation, simulation aggregates) are applied in the table build, not in the metric query. Flag names follow the table: `is_lead`, `is_contact_attempted`, `is_success_contact`, `is_simulation_sent`, `is_simulation_accepted`, `is_offer_under_negotiation`, `is_offer_accepted`, `is_contract_created`, `is_closed_deal`, `is_handoff`, `is_discarded`; the value field is `deal_amount`.

**Blip id**: reachable via `datalake_consorcio_clean.lead_external_data` — `id_crm = CAST(deal.id_deal AS VARCHAR)` (`id_crm` is varchar, `id_deal` is bigint) and `id_lead = lead.id_lead`; the Blip ids are `id_bsp_contact` / `id_bsp_conversation`.

**Join key**: base model already carries `is_*` flags and business-day `days_to_convert_from_*` columns per deal — no re-derivation needed.

**Fallback**: a deal that never reached a stage has `NULL` day-diff for that conversion (excluded from the numerator); denominators use the cumulative flags.

## Dos and Don'ts

**Do:**

- Ask **open vs closed cohort (and days)** before answering; state the maturation if assumed.  
- Read every conversion in **cohort** by lead creation date; mature in **business days**.  
- Separate **mix vs intra-channel vs journey** when the aggregate moves.

**Don't:**

- Don't default a bare "conversão" question to coincident — it is cohort.  
- Don't present GMV/ticket/R$-per-lead as cohort without confirming the view (usually coincident).  
- Don't analyze OUN/CC conversions before 2026-07-20; don't use a non-track-aware handoff.

## Golden Queries

Per cohort week, the headline cohort metrics + GMV. Runs on the **Funil Cohort deal-grain base** (`Funil Cohort - Não Agregado [Consorcio][Fintech]` / `consorcio_golden_query.sql`), which already carries `is_*` flags, business-day `days_to_convert_from_*` columns, `origin`, track, `deal_amount`, and `ts_deal_created`. The pattern generalizes to any `X2Y` at `D+n` by swapping the flag + day-diff column.

```sql
-- Base = one row per deal (latest stage), from the Funil Cohort dataset, which is built on the
-- OFFICIAL SOURCE datalake_consorcio.deal + datalake_consorcio.deal_milestone (joined on id_deal).
-- Columns used: ts_deal_created, is_lead, is_success_contact, is_simulation_sent, is_simulation_accepted, is_offer_under_negotiation, is_offer_accepted, is_contract_created, is_closed_deal, deal_amount,
--   days_to_convert_from_lead_to_cd, days_to_convert_from_lead_to_sa,
--   days_to_convert_from_ss_to_cd, days_to_convert_from_sa_to_cd (all BUSINESS days), and the
--   intermediate diffs: days_to_convert_from_{sc_to_ss, ss_to_sa, sa_to_oun, oun_to_oa, oa_to_cc, cc_to_cd}.
WITH funil AS (
    SELECT * FROM "Funil Cohort - Não Agregado [Consorcio][Fintech]"   -- or wrap consorcio_golden_query.sql
)
SELECT
    date_trunc('week', ts_deal_created) AS cohort_week,
    COUNT(*)                                                    AS leads,

    -- Windows below are ILLUSTRATIVE. Per question, pick OPEN cohort (matured / no cap, e.g. l2cd_matured)
    -- or CLOSED cohort at a fixed D+n (e.g. l2cd_d2). Ask the person; do not assume the canonical window.

    -- L2CD (Result) — from Lead
    ROUND(100.0*SUM(CASE WHEN is_closed_deal=1 AND days_to_convert_from_lead_to_cd <= 2  THEN 1 END)/COUNT(*), 3) AS l2cd_d2,
    ROUND(100.0*SUM(CASE WHEN is_closed_deal=1 AND days_to_convert_from_lead_to_cd <= 14 THEN 1 END)/COUNT(*), 3) AS l2cd_d14,
    ROUND(100.0*SUM(is_closed_deal)/COUNT(*), 3)                                                                  AS l2cd_matured,

    -- L2SA (Health) — from Lead
    ROUND(100.0*SUM(CASE WHEN is_simulation_accepted=1 AND days_to_convert_from_lead_to_sa <= 2 THEN 1 END)/COUNT(*), 3)  AS l2sa_d2,

    -- SA2CD (Health) — denominator = reached SA; window from SA
    ROUND(100.0*SUM(CASE WHEN is_closed_deal=1 AND is_simulation_accepted=1 AND days_to_convert_from_sa_to_cd <= 14 THEN 1 END)
          / NULLIF(SUM(is_simulation_accepted),0), 3)                                                                     AS sa2cd_d14,

    -- SS2CD (Simulation Sent → CD) — denominator = reached SS; window from SS
    ROUND(100.0*SUM(CASE WHEN is_closed_deal=1 AND is_simulation_sent=1 AND days_to_convert_from_ss_to_cd <= 14 THEN 1 END)
          / NULLIF(SUM(is_simulation_sent),0), 3)                                                                     AS ss2cd_d14,

    -- Diagnostic conversions (intermediate) — windows ILLUSTRATIVE (canonical shown); denominator = reached start stage.
    -- The day-diff column is non-null only when both stages were reached, so it also gates the numerator.
    -- OUN/CC-based rows are valid only for cohorts on/after 2026-07-20.
    ROUND(100.0*SUM(CASE WHEN days_to_convert_from_sc_to_ss  <= 1  THEN 1 END)/NULLIF(SUM(is_success_contact),0), 3)  AS sc2ss_d1,
    ROUND(100.0*SUM(CASE WHEN days_to_convert_from_ss_to_sa  <= 1  THEN 1 END)/NULLIF(SUM(is_simulation_sent),0), 3)  AS ss2sa_d1,
    ROUND(100.0*SUM(CASE WHEN days_to_convert_from_sa_to_oun <= 7  THEN 1 END)/NULLIF(SUM(is_simulation_accepted),0), 3)  AS sa2oun_d7,
    ROUND(100.0*SUM(CASE WHEN days_to_convert_from_oun_to_oa <= 14 THEN 1 END)/NULLIF(SUM(is_offer_under_negotiation),0), 3) AS oun2oa_d14,
    ROUND(100.0*SUM(CASE WHEN days_to_convert_from_oa_to_cc  <= 14 THEN 1 END)/NULLIF(SUM(is_offer_accepted),0), 3)  AS oa2cc_d14,
    ROUND(100.0*SUM(CASE WHEN days_to_convert_from_cc_to_cd  <= 14 THEN 1 END)/NULLIF(SUM(is_contract_created),0), 3)  AS cc2cd_d14,

    -- Value (usually read COINCIDENT — see Coincident entity — but kept here for cohort GMV / R$-per-lead)
    SUM(CASE WHEN is_closed_deal=1 THEN deal_amount END)                              AS gmv_new,
    SUM(CASE WHEN is_closed_deal=1 THEN deal_amount END)/NULLIF(SUM(is_closed_deal),0)         AS avg_ticket,
    SUM(CASE WHEN is_closed_deal=1 THEN deal_amount END)/COUNT(*)                     AS rs_per_lead
FROM funil
GROUP BY 1
ORDER BY 1
```

General pattern for any conversion `X2Y` at `D+n`:

```
100.0 * SUM(CASE WHEN is_Y = 1 AND days_to_convert_from_X_to_Y <= n THEN 1 END)
      / NULLIF(SUM(is_X), 0)
```

## Superset Golden Assets

- **Funil Cohort - Não Agregado [Consorcio][Fintech]** — the canonical cohort deal-grain dataset analysts consume; materialized by `consorcio_golden_query.sql`. (Add the Superset dataset URN when available.)

