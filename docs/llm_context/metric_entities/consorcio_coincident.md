# Consórcio Funnel — Coincident View

## Ownership

**Data Owner:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

**Data Steward:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

## Overview

**Consórcio Funnel — Coincident View** is the family of official **coincident** operational metrics for Consórcio: volumes and production counted by **each stage's own timestamp** (not by lead-creation cohort). It is the lens for Inside Sales / operations management — production, handoff, and per-analyst / per-supervisor throughput. It differs from the Cohort View because a Closed Deal counts in the period it was *closed*, a handoff in the period the handoff *happened*, etc. — answering "how much did the operation move this period", not "how efficient was this lead cohort".

## Related Business Entities

- Consórcio (Inside Sales Funnel)

## Catalog

| Metric | Type |
| :---- | :---- |
| Closed Deals (Production) | OKR |
| GMV New | OKR |
| Leads | Health Metric |
| Handoff (Handoff/DU, Handoff/Analyst/Day) | Health Metric |
| Avg Ticket | Health Metric |
| R$/Handoff | Health Metric |
| Leads/DU, CD/DU, R$/DU | Health Metric |
| Stage inventory — deals still parked in a stage (*estoque*) | Health Metric |
| Time in stage — entry → exit (*tempo na etapa*) | Health Metric |
| Handoff Rate — Handoff / Leads (*taxa de transbordo*) | Health Metric |

## Glossary and Synonyms

- **Produção**, **Closed Deals**, **vendas no período**, **CDs coincident** → Production (Closed Deals)  
- **GMV New**, **R$ vendido**, **produção em R$** → GMV New  
- **Handoff/analista**, **Handoff/dia**, **Handoff/DU**, **Handoff/Analyst/Day** → Handoff throughput  
- **Taxa de transbordo** → **Handoff ÷ Leads** (see Calculation below) — not to be confused with Handoff/Analyst/Day or Handoff→Closed Deal, which are different ratios  
- **R$/Handoff**, **quanto fechou por handoff** → R$/Handoff  
- **volume de leads na semana/dia**, **CDs na semana X** → coincident volumes  
- **Estoque**, **estoque em negociação**, **deal parado**, **envelhecimento na etapa** → deals still sitting in a stage (`ts_stage_exited IS NULL`) and how long they have been there
- **Tempo na etapa** → how long a deal that already left spent in a stage (entry → exit) — *not* estoque
- **por analista**, **por supervisor**, **painel gerencial**, **relatório de IS** → operational cuts

## Scope

**Included**: operational volumes and production for pipeline `737631007`, read **by each stage's own timestamp**, cut **by analyst and by supervisor** (also by origin / track), per Day / Week / Month, with `/DU` (per business day) variants.

**Excluded**: **Blip ticket / conversation data — we do not have it** (no ticket counts, conversation volumes, or Blip-sourced SLA on the SDR IA side); **cohort conversions** (those live in the Cohort View — a bare "conversão" question is cohort); reversed in-month closes (guarded by the dataset — see Known Data-Quality Issues below); duplicate stage-entry events for the same deal (see Known Data-Quality Issues below).

## Calculation

Every metric is counted by **the stage's own timestamp** (coincident) on the deal × stage base (`Funil Coincident - Não Agregado`):

- **Leads** — count of `leads` stage entries in the period; **Leads/DU** \= ÷ business days.  
- **Handoff** — count of handoff stage-entry events (track-aware): `Simulação` (`SDR IA`), `Simulação Aceita` (`SIMULATOR IA`), `Lead` (`SDR Humano`); **Handoff/DU**, **Handoff/Analyst/Day** (split SDR IA / Simulador / Repescagem). **Any handoff metric that involves a count/average of *analysts* (e.g. Handoff/Analyst/Day, "average handoff per analyst") must apply the Active Analyst Threshold and the Weekend Rule below — state both explicitly whenever a handoff-per-analyst question is answered.**  
- **Production — Closed Deals** — **one row per `id_deal`** (its **first** stage-entry into `venda fechada`), **only counted if the deal's current stage is still `venda fechada`** (excludes reversed and duplicated close events — see Canonical Filter and Known Data-Quality Issues below); **CD/DU**.  
- **Production — GMV New** — `SUM(amount)` over the same deduplicated `venda fechada` set, by close date; **R$/DU**.  
- **Avg Ticket** — `GMV New / #Closed Deals`, computed from the deduplicated Closed Deals base above (never from a raw `COUNT(*)` of `venda fechada` stage-entry rows).  
- **R$/Handoff** — `GMV closed / Handoff volume` (revenue per unit of handoff), using the track-aware handoff.  
- **Stage inventory** (*estoque*) — the deals **still parked** in a stage (`ts_stage_exited IS NULL`): how many there are and how many business days each has been sitting there. Read mainly on **`proposta em negociação` (OUN)**. A deal that already left the stage is **not** part of the inventory — that span is time in stage, a different metric (see the dedicated subsection).  
- **Handoff Rate** (*taxa de transbordo*) — `Handoff volume / Leads volume`, both coincident (each counted by its own stage-entry date, not a shared cohort) over the same period. This is a **volume ratio, not a cohort conversion rate** — it does not track the same leads from entry to handoff; it compares "how much handoff happened this period" to "how many leads entered this period." Do not apply the Active Analyst Threshold or Weekend Rule here — those apply only to Handoff/Analyst/Day, not to this ratio. **Ambiguity note:** when someone asks for "taxa de transbordo" they may instead mean Handoff ÷ Simulação/SC per track, or Handoff → Closed Deal — confirm which one is meant if it is not already established in the conversation.

`DU = dia útil` (business day) via `dw_public.dim_date.is_brz_business_day`. GMV field \= `amount`.

### Active Analyst Threshold

For **any handoff metric expressed per analyst** (Handoff/Analyst/Day, average handoff per active analyst, analyst headcount used as a denominator, etc.), an analyst only counts as **"ativo" (active)** on a given day if they had **≥ 10 handoffs that day**. An analyst with 1–9 handoffs on a day is **not** counted in the active-analyst denominator for that day (their handoff volume still counts in the numerator/total, only the analyst headcount is affected).

- Applies to: Handoff/Analyst/Day, any "average handoff per analyst" read, and any other handoff metric where the denominator is a count of analysts.  
- Does **not** apply to: raw Handoff volume/count, Handoff/DU, R$/Handoff (none of these divide by a count of analysts).  
- **State this rule explicitly** in the response whenever a handoff-per-analyst question is answered — do not let it stay an implicit assumption.

### Weekend Rule 

Monday–Friday are always included in Handoff/Analyst/Day. Saturday and Sunday are **never included by default** — **always ask the requester whether the weekend should be considered** before computing a Handoff/Analyst/Day figure for a period that includes one. Do not assume either way.

**If the requester says no** → exclude Saturday and Sunday entirely from the calculation (no contribution to numerator or denominator).

**If the requester says yes**, Saturday and Sunday are handled differently, because they are operationally different days:

- **Sunday** — Inside Sales **never** runs a shift on Sunday, so there is no need to check: **the denominator contribution from Sunday is always 0\.** However, leads and simulations still flow through the funnel on Sundays (bot-driven tracks keep operating), so Sunday's handoff volume is real and **is included in the numerator** whenever the requester opts to consider the weekend.  
- **Saturday** — Inside Sales *sometimes* runs a **reduced** Saturday shift with fewer analysts, so this must be checked per Saturday, not assumed: does at least one analyst meet the Active Analyst Threshold (≥10 handoffs) that Saturday?  
  - **Yes, operation occurred** → treat that Saturday like a normal weekday: its handoff volume goes into the numerator **and** its active-analyst count goes into the denominator.  
  - **No operation occurred** (i.e. genuinely 0 analysts met the threshold that Saturday) → its handoff volume still goes into the numerator (same as Sunday), but its denominator contribution is 0 — there is no staffed capacity that day to attribute a per-analyst rate to.  
  - **Always compute this by query (per-analyst, ≥10 threshold), never by inference from the day's total volume alone.** 2026-08-01 is a documented edge case: the ≥10-threshold query found 6 analysts crossing it, but Inside Sales confirms there was **no real staffed operation** that Saturday — the 6 are most likely residual/misattributed handoff events, not a genuine reduced shift. Where the automated threshold check and known ground-truth staffing disagree, **ground truth wins for the final number**, but **always show the calculation** (numerator, denominator, and which rule/branch was applied per day) so the reader can see exactly how it was built and override it themselves if their own operational knowledge differs. Transparency of the formula matters more than forcing every edge case to reconcile automatically.

**Summary table (when the requester opts to include the weekend):**

| Day | Numerator (handoff volume) | Denominator (active analysts) |
| :---- | :---- | :---- |
| Mon–Fri | Always included | Per Active Analyst Threshold, as normal |
| Saturday | Always included | Only if that Saturday had a real operation (≥1 analyst over the threshold **and** not contradicted by known staffing); otherwise 0 |
| Sunday | Always included | Always 0 (no shift ever runs) |

- **State this explicitly** alongside the Active Analyst Threshold whenever a handoff-per-analyst question is answered: whether the weekend was asked about and included, and — if Saturday was included — whether operation was detected that day.  
- This is distinct from `/DU` (business-day count from `dw_public.dim_date.is_brz_business_day`), which is used for Leads/DU, CD/DU, R$/DU — those are **not** affected by this rule, only handoff-per-analyst metrics are.

### Handoff (business days) vs. Handoff (full week) — two different numbers by design

**Handoff (business days)** is the sum of handoff volume across Monday–Friday only, **before** any weekend days the requester may have opted to add per the Weekend Rule above — this is the default numerator base for **Handoff/Analyst/Day**. When the requester opts to include the weekend, report the resulting number as *handoff over business days plus the weekend*, rather than silently folding it back into the business-day figure.

**Handoff (full week)** is the sum of handoff volume across all 7 days of the week, with no exclusions — used for raw volume reporting, track segmentation (SDR Humano / SDR IA / SIMULATOR IA), and any other handoff read that is not per analyst.

**These two numbers will differ whenever there is Saturday/Sunday handoff activity, and that is expected, not an error.** When reporting either one, name it explicitly — in Portuguese answers use the labels `Handoff (dias úteis)` and `Handoff (semana total)` — so the two are never confused or silently swapped.

### Handoff/Analyst/Day — Official Formula

**Handoff/Analyst/Day is a weekly (or longer-period) figure, computed as a pooled rate — not an average of daily ratios:**

```
Handoff/Analyst/Day (period) = SUM(daily handoff volume, over the included days)
                                 / SUM(daily active-analyst count, over the included days)
```

- **Included days** = Monday–Friday always; Saturday and Sunday only if the requester opts in per the Weekend Rule decision path above. That is the business-day figure vs. the business-day-plus-weekend figure defined above — neither is automatically the raw 7-day weekly total.  
- **Numerator:** sum of handoff volume across the included days. Both Saturday and Sunday, when opted in, always contribute their full handoff volume to the numerator — this holds even when Saturday had no detected operation, and always for Sunday.  
- **Denominator:** sum, across the included days, of the count of analysts who were "active" that day (≥10 handoffs — Active Analyst Threshold). This is a sum of daily headcounts, **not** a distinct-analyst count for the period (the same analyst active on 5 weekdays contributes 5 to this sum). Sunday always contributes 0 to this sum (no shift ever runs). Saturday contributes 0 unless that specific Saturday had a real operation — ≥1 analyst over the threshold **and** no ground-truth staffing information contradicting it (see the Weekend Rule; 2026-08-01 is the documented case where it does).  
- **Do not** compute this as `AVG(daily_handoff / daily_active_analysts)` (average of daily ratios) — that method under-weights high-volume days and was explicitly rejected in favor of the pooled/summed formula above. If both are ever shown side by side for context, always label which is which; only the pooled formula is the official Handoff/Analyst/Day.  
- **Worked example (week of 2026-07-27, weekend excluded per requester's answer):** 3,715 weekday handoffs ÷ 117 analyst-active-days = **31.8** Handoff/Analyst/Day.
  Had the requester opted to include the weekend, this same week shows why the ground-truth override matters. Saturday (01/08) had 195 handoffs and the ≥10-threshold query returned 6 analysts, **but Inside Sales confirmed there was no staffed operation that day** — so, per the Weekend Rule, ground truth wins and Saturday contributes **0** to the denominator (its 195 handoffs still count in the numerator). Sunday (02/08) had 237 handoffs and always contributes 0 to the denominator.
  Numerator = 3,715 + 195 + 237 = 4,147; denominator = 117 + 0 (Saturday, no real operation) + 0 (Sunday, forced) = 117 → **4,147 ÷ 117 = 35.4**.
  Always show this breakdown — the numerator, the denominator, and which branch was applied per day — so the reader can see that Saturday's 6 threshold-crossing analysts were deliberately excluded.

### Stage inventory (*estoque*) — deals still parked in a stage

**Stage inventory (*estoque*) is the set of deals that are still sitting in a stage right now** — rows with `ts_stage_entered` filled and **`ts_stage_exited IS NULL`**. That NULL is the definition: once a deal leaves the stage, `ts_stage_exited` is filled and **the deal is no longer part of the inventory**. Read mainly on **`proposta em negociação` (OUN)**.

Stage inventory answers two questions, both restricted to open rows:

1. **How many deals are parked** in the stage — `COUNT(*) WHERE ts_stage_exited IS NULL`.
2. **How long each one has been parked** — business days from `ts_stage_entered` to today.

```sql
-- Stage inventory: open rows only
WHERE ts_stage_exited IS NULL

-- Days parked (business days, entry -> today)
GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date dd
             WHERE dd.date >= CAST(ts_stage_entered AS DATE)
               AND dd.date <= CURRENT_DATE
               AND dd.is_brz_business_day = TRUE) - 1)
```

**Not inventory — time in stage (*tempo na etapa*).** When a deal has already left (`ts_stage_exited` filled), the span between entry and exit is how long it *spent* in that stage. That is a legitimate and useful measure — e.g. how long deals historically sat in OUN before advancing — but it is **a different metric**: it describes deals that moved on, not inventory sitting there now. Never mix the two in one number: adding closed spans to the inventory inflates it with deals that are no longer parked.

| | Stage inventory | Time in stage |
| :-- | :-- | :-- |
| Population | `ts_stage_exited IS NULL` (still there) | `ts_stage_exited` filled (already left) |
| Clock | entry → **today** | entry → **exit** |
| Answers | "what is stuck right now" | "how long it took to move" |

Common inventory readings, all on the open population:

- **Deals in inventory** — count of parked deals, by stage / analyst / supervisor / origin.
- **Average inventory age** — average business days parked.
- **Aging buckets** — distribution by bucket (0–2, 3–7, 8–14, 15+ business days), which is what flags stalled negotiations.
- **Value in inventory** — `SUM(deal_amount)` over the parked deals.

**Point-in-time caveat:** inventory is measured *as of now* — the same question on another day returns different numbers for the same deals. Always state the reference date.

### Canonical Filter

The base is built on `datalake_consorcio.deal_stage` + `datalake_consorcio.deal`, so the pipeline filter and the test/duplicate exclusion are **already applied upstream** — do not re-add them:

```sql
-- Grain: one row per (deal, stage) at FIRST entry into that stage
--   ROW_NUMBER() OVER (PARTITION BY id_deal, stage_name ORDER BY ts_entered) = 1
-- Closed-deal guard (kept in the join): drop a 'venda fechada' entry when the deal has
--   since moved away AND the reversal happened in the same month:
--   NOT ((stage_name = 'venda fechada' AND current_stage != 'venda fechada')
--        AND month_start = date_trunc('month', ts_stage_entered))
-- Join: CAST(deal.id_deal AS VARCHAR) = deal_stage.id_deal   (bigint vs varchar)
-- Scope a query with the deal_stage partitions: year / month / day
```

**Warning**: anchoring a coincident metric on lead creation (cohort) instead of the stage's own timestamp produces the wrong period attribution — production must be counted by close date, handoff by handoff date.

### Known Data-Quality Issues (confirmed 2026-08-10)

Reconciliation surfaced two distinct failure modes on `venda fechada` stage-entry rows in the raw stage history (originally found on `datalake_hubspot.deal_stage`; the same shapes carry into `datalake_consorcio.deal_stage`). Both **inflate** Closed Deals / GMV New / distort Avg Ticket if not filtered:

1. **Reversed-in-month closes.** A deal enters `venda fechada`, is later moved back to an earlier stage (e.g. `Simulação`) within the same month. The stage-entry row for the original close still exists in `deal_stage` history, so a naive count double-attributes it as a real close. **Confirmed case:** one deal closed and reverted to `Simulação` on the same day, inflating that day's count from 15 to 16 and GMV by R$ 400k.  
   - **Fix:** require the deal's *current* stage (`datalake_consorcio.deal.current_stage`) to still be `venda fechada` at query time — this is the guard already applied in the golden query's join.  
2. **Duplicate stage-entry events.** The same `id_deal` gets two `venda fechada` stage-entry rows fired seconds-to-minutes apart (same `amount`, no intervening stage change) — most likely a duplicate webhook/event fire in the HubSpot integration, not two separate sales. **Confirmed cases:** two separate days each had one deal with a duplicate close event (44 seconds apart in one case), inflating each day's count by 1 and GMV by the deal's `amount`.  
   - **Fix:** dedupe to one row per `id_deal` — the first `venda fechada` entry, ordered by `ts_entered` ascending (the `rn = 1` window in the golden query).

Both fixes are combined into a single filter (see Canonical Filter above): **first stage-entry per `id_deal` into `venda fechada`, AND current stage still `venda fechada`.** This has been validated against the official base for three separate days in the 2026-07-27 → 2026-08-08 window with a full match after the fix.

**Not yet investigated:** whether the same duplicate-event pattern affects other stages (`leads`, `simulação`, `simulação aceita`, handoff stage-entries) — if so, **Leads**, **Handoff**, and **R$/Handoff** may need the same per-deal-per-stage dedup. Flag this to the Data Owner / Inside Sales before treating those metrics as clean.

### Nuances

- **No Blip ticket data** — state this whenever a ticket/conversation/Blip-SLA read is requested.  
- **Conversion defaults to Cohort** — only compute a coincident conversion when explicitly asked as coincident, or when the ask is volumes per day/week.  
- **Handoff is track-aware** (same rule as the domain entity) — reported as `SDR IA/Analyst/Day`, `Simulador/Analyst/Day`, `Repescagem/Analyst/Day`, summing to `Handoff/Analyst/Day`.  
- **Closed Deals / GMV New / Avg Ticket are deal-deduplicated, not row-counted** — see Known Data-Quality Issues. Never `COUNT(*)` or `SUM(amount)` directly over raw `venda fechada` stage-entry rows without the per-deal dedup \+ current-stage check.  
- **Handoff/Analyst/Day (and any handoff-per-analyst read) applies the Active Analyst Threshold (≥10 handoffs/day to count as active) and the Weekend Rule (Sat/Sun always read as 0\)** — see the two subsections above. State both rules explicitly in the answer, every time.

**Join key**: `CAST(deal.id_deal AS VARCHAR) = deal_stage.id_deal`. The base carries `analyst_name` / `analyst_role` / `supervisor_name` (straight from `deal`, no inline roster), `origin`, `segment`, `inside_sales_pipeline`, `deal_amount`, `stage_name`, `dt_stage_entered` / `dt_stage_exited`, and `ts_stage_entered` / `ts_stage_exited` (the stage-inventory inputs).

**Fallback**: `/DU` divides by the count of `is_brz_business_day = TRUE` dates in the period.

## Dos and Don'ts

**Do:**

- Count each metric by its **own stage timestamp** (production by close date, handoff by handoff-stage entry).  
- Use the **track-aware handoff** for Handoff and R$/Handoff; divide by **business days** for `/DU`.  
- Read operational metrics **by analyst and by supervisor**; route **conversion** to the Cohort View unless coincident/volume-per-period is explicitly asked.  
- For **Closed Deals / GMV New / Avg Ticket**, dedupe to one row per `id_deal` (first `venda fechada` entry) **and** require the deal's current stage to still be `venda fechada` before counting it.  
- For **any handoff-per-analyst metric**, apply the **Active Analyst Threshold** (≥10 handoffs/day to count as active) and the **Weekend Rule** — Sunday's denominator is always 0 (but its volume counts if the weekend is opted in); Saturday's denominator depends on whether operation was detected that specific day — and say so explicitly in the answer.  
- **Ask the requester whether to include the weekend** every time a Handoff/Analyst/Day period spans a Saturday or Sunday — never assume yes or no.  
- For **stage inventory**, filter `ts_stage_exited IS NULL`, state the **reference date** (it is point-in-time), and say whether you are reporting the **count of parked deals**, the **average days parked**, or the **aging distribution**.  
- Label handoff totals explicitly — business days, business days plus weekend (both Handoff/Analyst/Day numerators), or full week (raw volume across all 7 days, no analyst denominator). In Portuguese answers these map to `Handoff (dias úteis)`, `Handoff (dias úteis + fim de semana)` and `Handoff (semana total)`. Never present one number without saying which it is.

**Don't:**

- Don't anchor coincident metrics on lead-creation cohort; don't use a non-track-aware handoff.  
- Don't attempt Blip-ticket/conversation metrics (no data); don't count reversed in-month closes (already guarded).  
- Don't default a bare "conversão" to coincident — that's cohort.  
- Don't count a deal that already left the stage as inventory — `ts_stage_exited` filled means it is out. Mixing closed spans into the inventory inflates it with deals that are no longer parked; report those separately as time in stage.  
- Don't join a `date_trunc('day', ts_*)` expression to `dim_date.date` — `date_trunc` returns a timestamp, not a date, so it matches nothing; `CAST(... AS DATE)` is required.  
- Don't `COUNT(*)` the coincident base for volumes — the calendar `LEFT JOIN` leaves NULL-padded rows for days with no events; count `id_deal` instead.  
- Don't `COUNT(*)` or `SUM(amount)` raw `venda fechada` stage-entry rows for Closed Deals/GMV/Avg Ticket — duplicate close events and reversed closes will inflate the numbers (see Known Data-Quality Issues).  
- Don't count an analyst with fewer than 10 handoffs on a day as "active" for Handoff/Analyst/Day or similar.  
- Don't attribute a per-analyst rate to **Sunday**, or to a **Saturday with no confirmed operation** — those days contribute **0 to the denominator** (their handoff volume still counts in the numerator when the weekend is opted in). What is always zero is the *denominator contribution of those specific days*, **not** the metric: a weekend-inclusive period figure is non-zero and legitimate.  
- Don't silently apply the Active Analyst Threshold / Weekend Rule without mentioning them — they change the reported number and must be visible to whoever asked.

## Golden Queries

### Query 1 — Coincident base (canonical)

One row per (deal, stage) at its **first entry** into that stage, joined to the calendar so every event is counted by **its own date** (`dt_stage_entered`). Built on the official source `datalake_consorcio.deal_stage` + `datalake_consorcio.deal`; materializes the Superset dataset **`Funil Coincident - Não Agregado [Consorcio][Fintech]`**.

Two things to know before aggregating it:

- **The date key must be `CAST(ts_entered AS DATE)`, not `date_trunc('day', ts_entered)`.** `date_trunc` returns a timestamp, not a date, so it does not compare equal to `dim_date.date` — the join then matches nothing and every calendar row comes back NULL-padded (verified: 31 July dates, 0 matches). With the cast the same window returns **208,941 rows, 0 NULL-padded, 254 closed deals and R$ 98.73M GMV — an exact match to the July figures reported in the Daily Digest**.
- The calendar is `LEFT JOIN`ed, so dates with no qualifying stage event still produce a row with all `ds.*` columns NULL. Use `COUNT(ds.id_deal)` or `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` for volumes — a bare `COUNT(*)` would count those empty days too.
- `ts_stage_exited` is `NULL` while the deal is **still in the stage** — that is what makes the stage-inventory measure possible.

```sql
-- ============================================================================
-- Consórcio — Coincident golden query (deal × stage grain)
-- OFFICIAL SOURCE: datalake_consorcio.deal_stage (ds) + datalake_consorcio.deal (d).
-- One row per (deal, stage) at FIRST entry into that stage (rn = 1), joined to the
-- calendar so every stage event is counted by ITS OWN date (dt_stage_entered).
--
-- Already resolved UPSTREAM in `deal` (do NOT re-implement): pipeline filter,
-- test/duplicate exclusion,
-- origin / segment / utm_* mapping, qualifier_*, contact_type / is_abandoned_cart,
-- feedback survey, simulation aggregates, analyst_name / analyst_role / supervisor_name.
--
-- JOIN NOTE: ds.id_deal is varchar and d.id_deal is bigint -> CAST is required.
--
-- DATE KEY: use CAST(... AS DATE) for the dim_date join -- date_trunc returns a timestamp,
--   not a date, so it never equals dim_date.date and silently matches nothing.
-- CLOSED-DEAL GUARD: a `venda fechada` entry is dropped when the deal has since moved
-- away AND the reversal happened in the same month (reversed-in-month close).
--
-- Materializes the Superset dataset "Funil Coincident - Não Agregado [Consorcio][Fintech]".
-- ============================================================================

with
deal_stage as (SELECT
  ds.id_deal,
  ds.id_stage,
  lower(ds.stage_name) as stage_name,
  ds.id_actor,
  ds.change_source,
  ds.ts_entered as ts_stage_entered,
  ds.ts_exited  as ts_stage_exited,
  -- CAST(... AS DATE), not date_trunc: date_trunc returns a timestamp, which never
  -- equals dim_date.date and silently yields zero matches.
  CAST(ds.ts_entered AS DATE) as dt_stage_entered,
  CAST(ds.ts_exited  AS DATE) as dt_stage_exited,
  d.id_hubspot_owner,
  d.id_device,
  d.uuid_lead,
  d.deal_name,
  d.current_stage,
  d.origin,
  d.utm_source,
  d.utm_medium,
  d.utm_campaign,
  d.utm_content,
  d.utm_term,
  d.segment,
  d.inside_sales_pipeline,
  d.discard_reason,
  d.forms_origin,
  d.lead_priority,
  d.quota_amount,
  d.installment_type,
  d.channel_origin,
  d.deal_amount,
  d.customer_journey,
  d.qualifier_goal,
  d.qualifier_investment_type,
  d.qualifier_reason,
  d.qualifier_knowledge,
  d.qualifier_urgency,
  d.abandoned_cart_template_sent,
  d.contact_type,
  d.negotiation_value,
  d.bamaq_proposal_codes,
  d.feedback_benefits,
  d.feedback_comment,
  d.analyst_name,
  d.analyst_role,
  d.supervisor_name,
  d.feedback_score,
  d.total_simulations,
  d.is_abandoned_cart,
  d.has_blip_agent_inactivity,
  d.is_feedback_contact_allowed,
  d.dt_created,
  row_number() over (partition by ds.id_deal, ds.stage_name order by ds.ts_entered) as rn
from datalake_consorcio.deal_stage ds
inner join datalake_consorcio.deal d
  on cast(d.id_deal as varchar) = ds.id_deal
),
dim_date AS (
    SELECT
        date,
        month_start,
        week_start,
        weekday_name AS day_of_week,
        day_of_month(date) AS day_of_month,
        is_brz_business_day
    FROM dw_public.dim_date
    WHERE date BETWEEN date('2025-08-01') AND date(current_date)
)
SELECT *
FROM dim_date dd
LEFT JOIN deal_stage ds
  ON ds.dt_stage_entered = dd.date
  AND ds.rn = 1
  AND NOT (
            (ds.stage_name = 'venda fechada' AND ds.current_stage != 'venda fechada')
            AND dd.month_start = date(date_trunc('month', ds.ts_stage_entered))
          )
```

### Query 2 — Operational metrics (per week × supervisor × analyst)

Self-contained: the coincident base is inlined, so this runs directly against `datalake_consorcio.*` without going through the Superset dataset. Drop the supervisor/analyst grouping for the global view; group by `origin` or `inside_sales_pipeline` for those cuts. Uncomment the partition filter in `deal_stage` to scope the scan.

```sql
-- Coincident base, inlined (same logic as Query 1; only the columns these metrics need.
-- See Query 1 for the full column list).
WITH deal_stage AS (
    SELECT
        ds.id_deal,
        lower(ds.stage_name)        AS stage_name,
        ds.ts_entered               AS ts_stage_entered,
        ds.ts_exited                AS ts_stage_exited,
        CAST(ds.ts_entered AS DATE) AS dt_stage_entered,
        d.current_stage,
        d.origin,
        d.inside_sales_pipeline,
        d.deal_amount,
        d.analyst_name,
        d.analyst_role,
        d.supervisor_name,
        row_number() over (partition by ds.id_deal, ds.stage_name order by ds.ts_entered) AS rn
    FROM datalake_consorcio.deal_stage ds
    INNER JOIN datalake_consorcio.deal d
        ON cast(d.id_deal AS varchar) = ds.id_deal
    -- WHERE ds.year = 2026 AND ds.month = 7        -- always scope the partitions
),
dim_date AS (
    SELECT date, month_start, week_start, is_brz_business_day
    FROM dw_public.dim_date
    WHERE date BETWEEN date('2025-08-01') AND date(current_date)
),
coincident AS (
    SELECT
        dd.date, dd.month_start, dd.week_start, dd.is_brz_business_day,
        ds.id_deal, ds.stage_name, ds.ts_stage_entered, ds.ts_stage_exited,
        ds.origin, ds.inside_sales_pipeline, ds.deal_amount,
        ds.analyst_name, ds.analyst_role, ds.supervisor_name
    FROM dim_date dd
    LEFT JOIN deal_stage ds
      ON ds.dt_stage_entered = dd.date
      AND ds.rn = 1
      AND NOT (
                (ds.stage_name = 'venda fechada' AND ds.current_stage != 'venda fechada')
                AND dd.month_start = date(date_trunc('month', ds.ts_stage_entered))
              )
),
-- Business days per period (for /DU)
du AS (
    SELECT week_start, COUNT(*) AS business_days
    FROM (SELECT DISTINCT date, week_start, is_brz_business_day FROM coincident)
    WHERE is_brz_business_day = TRUE
    GROUP BY week_start
)
SELECT
    c.week_start,
    c.supervisor_name,
    c.analyst_name,

    -- Production (coincident): closed deals + GMV, by close date.
    -- The base already applies the first-entry dedup and the reversed-in-month guard.
    SUM(CASE WHEN c.stage_name = 'venda fechada' THEN 1 ELSE 0 END)                     AS closed_deals,
    SUM(CASE WHEN c.stage_name = 'venda fechada' THEN c.deal_amount END)                AS gmv_new,

    -- Leads volume (by lead-stage date)
    SUM(CASE WHEN c.stage_name = 'leads' THEN 1 ELSE 0 END)                             AS leads,

    -- Handoff volume (track-aware): stage-entry events that constitute a handoff
    SUM(CASE
          WHEN c.inside_sales_pipeline = 'SDR IA'       AND c.stage_name = 'simulação'        THEN 1
          WHEN c.inside_sales_pipeline = 'SIMULATOR IA' AND c.stage_name = 'simulação aceita' THEN 1
          WHEN c.inside_sales_pipeline = 'SDR Humano'   AND c.stage_name = 'leads'            THEN 1
          ELSE 0 END)                                                                   AS handoff,

    -- Per business day (/DU)
    1.0 * SUM(CASE WHEN c.stage_name = 'leads' THEN 1 ELSE 0 END) / NULLIF(d.business_days,0)          AS leads_du,
    1.0 * SUM(CASE WHEN c.stage_name = 'venda fechada' THEN 1 ELSE 0 END) / NULLIF(d.business_days,0)  AS cd_du,

    -- Efficiency: R$ per handoff
    SUM(CASE WHEN c.stage_name = 'venda fechada' THEN c.deal_amount END)
      / NULLIF(SUM(CASE
          WHEN c.inside_sales_pipeline = 'SDR IA'       AND c.stage_name = 'simulação'        THEN 1
          WHEN c.inside_sales_pipeline = 'SIMULATOR IA' AND c.stage_name = 'simulação aceita' THEN 1
          WHEN c.inside_sales_pipeline = 'SDR Humano'   AND c.stage_name = 'leads'            THEN 1
          ELSE 0 END),0)                                                                AS rs_per_handoff
FROM coincident c
LEFT JOIN du d ON d.week_start = c.week_start
WHERE c.id_deal IS NOT NULL          -- drop the empty-calendar rows from the LEFT JOIN
GROUP BY c.week_start, c.supervisor_name, c.analyst_name, d.business_days
ORDER BY c.week_start, c.supervisor_name, c.analyst_name
```

### Query 3 — Stage inventory in negotiation (deals still parked in OUN)

Stage inventory as of today for `proposta em negociação` — **open rows only** (`ts_stage_exited IS NULL`): how many deals are parked, how long they have been there (business days), the value sitting there, and the aging distribution. Swap the stage to read inventory anywhere else. The coincident base is inlined here too, so it runs directly against `datalake_consorcio.*`.

```sql
-- Coincident base, inlined (same logic as Query 1; only the columns these metrics need.
-- See Query 1 for the full column list).
WITH deal_stage AS (
    SELECT
        ds.id_deal,
        lower(ds.stage_name)        AS stage_name,
        ds.ts_entered               AS ts_stage_entered,
        ds.ts_exited                AS ts_stage_exited,
        CAST(ds.ts_entered AS DATE) AS dt_stage_entered,
        d.current_stage,
        d.origin,
        d.inside_sales_pipeline,
        d.deal_amount,
        d.analyst_name,
        d.analyst_role,
        d.supervisor_name,
        row_number() over (partition by ds.id_deal, ds.stage_name order by ds.ts_entered) AS rn
    FROM datalake_consorcio.deal_stage ds
    INNER JOIN datalake_consorcio.deal d
        ON cast(d.id_deal AS varchar) = ds.id_deal
    -- WHERE ds.year = 2026 AND ds.month = 7        -- always scope the partitions
),
dim_date AS (
    SELECT date, month_start, week_start, is_brz_business_day
    FROM dw_public.dim_date
    WHERE date BETWEEN date('2025-08-01') AND date(current_date)
),
coincident AS (
    SELECT
        dd.date, dd.month_start, dd.week_start, dd.is_brz_business_day,
        ds.id_deal, ds.stage_name, ds.ts_stage_entered, ds.ts_stage_exited,
        ds.origin, ds.inside_sales_pipeline, ds.deal_amount,
        ds.analyst_name, ds.analyst_role, ds.supervisor_name
    FROM dim_date dd
    LEFT JOIN deal_stage ds
      ON ds.dt_stage_entered = dd.date
      AND ds.rn = 1
      AND NOT (
                (ds.stage_name = 'venda fechada' AND ds.current_stage != 'venda fechada')
                AND dd.month_start = date(date_trunc('month', ds.ts_stage_entered))
              )
),
open_stage AS (
    SELECT
        c.id_deal,
        c.supervisor_name,
        c.analyst_name,
        c.origin,
        c.deal_amount,
        c.ts_stage_entered,
        -- business days parked, from stage entry to today
        GREATEST(0, (
            SELECT COUNT(*) FROM dw_public.dim_date dd
            WHERE dd.date >= CAST(c.ts_stage_entered AS DATE)
              AND dd.date <= CAST(CURRENT_DATE AS DATE)
              AND dd.is_brz_business_day = TRUE) - 1)                AS inventory_business_days
    FROM coincident c
    WHERE c.id_deal IS NOT NULL
      AND c.stage_name = 'proposta em negociação'
      AND c.ts_stage_exited IS NULL          -- still sitting in the stage
)
SELECT
    supervisor_name,
    analyst_name,
    COUNT(*)                                                              AS deals_in_inventory,
    ROUND(AVG(inventory_business_days), 1)                                     AS avg_inventory_business_days,
    approx_percentile(inventory_business_days, 0.5)                            AS median_inventory_business_days,
    SUM(deal_amount)                                                      AS value_in_inventory,
    SUM(CASE WHEN inventory_business_days BETWEEN 0 AND 2  THEN 1 ELSE 0 END)  AS bucket_0_2,
    SUM(CASE WHEN inventory_business_days BETWEEN 3 AND 7  THEN 1 ELSE 0 END)  AS bucket_3_7,
    SUM(CASE WHEN inventory_business_days BETWEEN 8 AND 14 THEN 1 ELSE 0 END)  AS bucket_8_14,
    SUM(CASE WHEN inventory_business_days > 14 THEN 1 ELSE 0 END)              AS bucket_15_plus
FROM open_stage
GROUP BY supervisor_name, analyst_name
ORDER BY deals_in_inventory DESC
```

### Reference — Closed Deals / GMV New / Avg Ticket directly from Trino

Production computed straight from the official source, with the dedup + reversal guard made explicit (useful when not going through the Superset dataset):

```sql
WITH closed AS (
    SELECT
        ds.id_deal,
        ds.ts_entered AS ts_closed,
        d.deal_amount,
        ROW_NUMBER() OVER (PARTITION BY ds.id_deal ORDER BY ds.ts_entered ASC) AS rn_first_close
    FROM datalake_consorcio.deal_stage ds
    INNER JOIN datalake_consorcio.deal d
        ON CAST(d.id_deal AS VARCHAR) = ds.id_deal
    WHERE LOWER(ds.stage_name) = 'venda fechada'
      AND d.current_stage = 'venda fechada'     -- excludes reversed-away deals
      AND ds.year = 2026 AND ds.month = 7       -- always scope the partitions
)
SELECT
    CAST(ts_closed AS DATE)                     AS close_date,
    COUNT(*)                                    AS closed_deals,
    SUM(deal_amount)                            AS gmv_new,
    1.0 * SUM(deal_amount) / NULLIF(COUNT(*),0) AS avg_ticket
FROM closed
WHERE rn_first_close = 1                        -- one row per deal: first close event
GROUP BY CAST(ts_closed AS DATE)
ORDER BY close_date
```
