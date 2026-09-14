# Consórcio Funnel — Coincident View

## Ownership

**Data Owner:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

**Data Steward:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

## Overview

**Consórcio Funnel — Coincident View** is the family of official **coincident** operational metrics for Consórcio: volumes and production counted by **each stage's own timestamp** (not by lead-creation cohort). It is the lens for Inside Sales / operations management — production, handoff, and per-analyst / per-supervisor throughput. It differs from the Cohort View because a Closed Deal counts in the period it was *closed*, a handoff in the period the handoff *happened*, etc. — answering "how much did the operation move this period", not "how efficient was this lead cohort".

It also owns **stage inventory (*estoque*)**, which has its own daily-snapshot base: one row per (snapshot date, deal, stage, entry), with begin/end-of-day inventory flags and same-day entry/exit flags. See [Stage inventory](#stage-inventory-estoque--daily-snapshot-base).

## Related Domain Entities

- Consórcio

## Catalog

| Metric | Type |
| :---- | :---- |
| Closed Deals (Production) | OKR |
| GMV New | OKR |
| Leads | Health Metric |
| Handoff (Handoff/DU, Handoff/Analyst/Day, by track) | Health Metric |
| Active analysts per day (denominator of per-analyst metrics) | Health Metric |
| Avg Ticket | Health Metric |
| R$/Handoff | Health Metric |
| Leads/DU, CD/DU, R$/DU | Health Metric |
| Stage inventory — deals still parked in a stage (*estoque*) | Health Metric |
| Stage flow — entries, exits and exit reason per day (*movimentação*) | Health Metric |
| Time in stage — entry → exit (*tempo na etapa*) | Health Metric |
| Handoff Rate — Handoff / Leads (*taxa de transbordo*) | Health Metric |

## Glossary and Synonyms

- **Produção**, **Closed Deals**, **vendas no período**, **CDs coincident** → Production (Closed Deals)
- **GMV New**, **R$ vendido**, **produção em R$** → GMV New
- **Handoff/analista**, **Handoff/dia**, **Handoff/DU**, **Handoff/Analyst/Day** → Handoff throughput
- **Analistas ativos**, **analistas escalados**, **headcount do dia** → `datalake_gsheets_clean.consorcio_daily_active_analysts`, the official denominator of every per-analyst metric
- **Taxa de transbordo** → **Handoff ÷ Leads** (see Calculation below) — not to be confused with Handoff/Analyst/Day or Handoff→Closed Deal, which are different ratios
- **R$/Handoff**, **quanto fechou por handoff** → R$/Handoff
- **volume de leads na semana/dia**, **CDs na semana X** → coincident volumes
- **Estoque**, **estoque em negociação**, **deal parado**, **envelhecimento na etapa** → deals still sitting in a stage on a given snapshot date
- **Movimentação**, **entradas e saídas do dia** → stage flow: `is_entry` / `is_exit` on the inventory base
- **Tempo na etapa** → how long a deal that already left spent in a stage (entry → exit) — *not* estoque
- **Credit value** (`credit_value`) → the deal's potential credit amount, taken from the most advanced value the funnel has filled in (see [Credit value](#credit-value-and-value_source))
- **Spell**, **entry\_seq** → one continuous stay of a deal in a stage; `entry_seq` numbers re-entries into the same stage
- **por analista**, **por supervisor**, **painel gerencial**, **relatório de IS** → operational cuts

## Scope

**Included**: operational volumes and production for pipeline `737631007`, read **by each stage's own timestamp**, cut **by analyst, supervisor and team** (also by origin / track), per Day / Week / Month, with `/DU` (per business day) variants; plus daily stage inventory and stage flow.

**Excluded**: **Blip ticket / conversation data — we do not have it** (no ticket counts, conversation volumes, or Blip-sourced SLA on the SDR IA side); **cohort conversions** (those live in the Cohort View — a bare "conversão" question is cohort); reversed in-month closes (guarded by the dataset — see Known Data-Quality Issues below); duplicate stage-entry events for the same deal (see Known Data-Quality Issues below).

## Calculation

Every metric is counted by **the stage's own timestamp** (coincident) on the deal × stage base (`Funil Coincident - Não Agregado`):

- **Leads** — count of `leads` stage entries in the period; **Leads/DU** \= ÷ business days.
- **Handoff** — count of deals that reached their track's handoff milestone, counted on that milestone's own date: **Lead** (`SDR Humano`), **Simulação** (`SDR IA`), **Simulação Aceita** (`SIMULATOR IA`); **Handoff/DU** and **Handoff/Analyst/Day**, normally split by track. Every per-analyst metric divides by the active-analyst headcount from `datalake_gsheets_clean.consorcio_daily_active_analysts` — see the two sections below.
- **Production — Closed Deals** — **one row per `id_deal`** (its **first** stage-entry into `venda fechada`), **only counted if the deal's current stage is still `venda fechada`** (excludes reversed and duplicated close events — see Canonical Filter and Known Data-Quality Issues below); **CD/DU**.
- **Production — GMV New** — `SUM(deal_amount)` over the same deduplicated `venda fechada` set, by close date; **R$/DU**.
- **Avg Ticket** — `GMV New / #Closed Deals`, computed from the deduplicated Closed Deals base above (never from a raw `COUNT(*)` of `venda fechada` stage-entry rows).
- **R$/Handoff** — `GMV closed / Handoff volume` (revenue per unit of handoff), using the track-aware handoff.
- **Stage inventory** (*estoque*) — the deals **still sitting** in a stage on a given snapshot date, and how many business days they have been there. Available for **every** stage in scope, not only `proposta em negociação`. See the dedicated section.
- **Stage flow** (*movimentação*) — entries and exits of a stage on a given day, with the exit classified by where the deal went (`exit_type`). Same base as inventory.
- **Handoff Rate** (*taxa de transbordo*) — `Handoff volume / Leads volume`, both coincident (each counted by its own stage-entry date, not a shared cohort) over the same period. This is a **volume ratio, not a cohort conversion rate** — it does not track the same leads from entry to handoff; it compares "how much handoff happened this period" to "how many leads entered this period." Do not bring the active-analyst headcount into this ratio — it belongs only to per-analyst metrics. **Ambiguity note:** when someone asks for "taxa de transbordo" they may instead mean Handoff ÷ Simulação/SC per track, or Handoff → Closed Deal — confirm which one is meant if it is not already established in the conversation.

`DU = dia útil` (business day) via `dw_public.dim_date.is_brz_business_day`. GMV field \= `deal_amount`.

**Attribution is history-aware.** `analyst_name`, `analyst_role`, `supervisor_name` and `team` come from `datalake_consorcio.deal`, resolved **as of each deal's creation date** from the `[Consórcio] Operação IS` sheet — so an operational cut reflects the team as it was when the deal was created, not as it is today. A deal owned by an analyst who kept receiving leads after their end date carries supervisor `other`. `origin` and `segment` come from the `[Consorcio] Growth Attribution` sheets. All of this is applied upstream in the `deal` build; never rebuild it in a query. See the Consórcio business entity for the sheets and the rules.

### Active analysts — the official denominator

**The number of analysts working on a given day comes from a table, not from a heuristic.** `datalake_gsheets_clean.consorcio_daily_active_analysts` holds one row per calendar day, maintained by Inside Sales in the *\[Consórcio\] Analistas Ativos* sheet (tab **consolidado**):

| Column | Meaning | Type trap |
| :---- | :---- | :---- |
| `data` | the calendar day | **`varchar`** — `CAST(data AS DATE)` |
| `qtd_analistas` | how many analysts were active that day | **`varchar`** — `CAST(qtd_analistas AS INTEGER)` |

Everything a per-analyst metric needs is in those two columns:

- **Join on the day being measured**, never on the deal creation date.
- **Weekends and holidays are already in the data.** Sunday is `0` on every Sunday; Saturday is `0` on most Saturdays and carries a real reduced headcount (~6 analysts) when there is a shift; weekday zeros are holidays. **There is no weekend rule to apply and nothing to ask the requester** — a day with no operation contributes 0 to the denominator because the sheet says so.
- **The sheet runs ahead of today** (planned staffing for future dates). Scope any per-analyst metric to closed days, or the denominator mixes fact with plan.
- Verified on 2026-09-09: 395 rows, one per day, no duplicates, covering 2025-09-01 to 2026-09-30.

### Handoff — what counts as a handoff, per track

Handoff is where Conrado hands the deal to a human analyst, and **the milestone that marks it is different in each track**:

| Track | Handoff happens when the deal reaches | Counted on |
| :---- | :---- | :---- |
| `SDR Humano` | **Lead** — there is no AI stage before it, so having a deal created is already a handoff | `ts_deal_created` |
| `SDR IA` | **Simulação** (Simulation Sent) | `ts_simulation_sent` |
| `SIMULATOR IA` | **Simulação Aceita** (Simulation Accepted) | `ts_simulation_accepted` |

- Coincident, so each deal is counted **on the date of its own handoff milestone**, not on the cohort date.
- A deal that never reached its track's milestone is not a handoff — it is still with Conrado.
- Handoff is normally reported **split by track**, most often `SDR Humano` vs `SIMULATOR IA` (`SDR IA` is discontinued and its volume is residual).
- `deal_milestone` also carries `is_handoff` / `ts_handoff`, which already encode this rule. Use them when the base is at deal grain; use the per-track expression above when you need the split explicit in the query.

### Handoff/Analyst/Day — Official Formula

**A pooled rate over the period — not an average of daily ratios:**

```
Handoff/Analyst/Day (period) = SUM(handoffs in the period)
                                 / SUM(active analysts on each day of the period)
```

- **Numerator:** all handoffs whose milestone date falls in the period, per the per-track table above. Every day in the range contributes its volume, weekend included — bot-driven tracks keep producing handoff on Saturday and Sunday.
- **Denominator:** the sum of `qtd_analistas` across the days of the period. This is a **sum of daily headcounts**, not a distinct-analyst count: an analyst working 5 days contributes 5. Days with no operation contribute 0 on their own.
- **Do not** compute it as `AVG(daily_handoff / daily_active_analysts)` — the average of daily ratios under-weights high-volume days. Only the pooled formula is official.
- The same formula works for a single day, a week, a month or any date range: sum both sides over the range and divide.

### Handoff (business days) vs. Handoff (full week)

Handoff volume is produced every day of the week, including weekends, because the bot-driven tracks never stop. When reporting **raw handoff volume**, say which window it covers — `Handoff (dias úteis)` for Monday to Friday, `Handoff (semana total)` for all 7 days — so two reports of the same week are never compared across different windows.

This distinction does **not** change Handoff/Analyst/Day: that metric sums both sides over whatever range was asked, and days with no staffed operation already contribute 0 to the denominator through the sheet.

### Stage inventory (*estoque*) — daily snapshot base

**Stage inventory is the set of deals sitting in a stage on a given day.** It is no longer a single-stage, as-of-today read: the base is a **daily snapshot grid** covering every stage in scope, so the same query answers inventory, aging, and daily flow for any stage.

**Grain: one row per (`snapshot_date`, `id_deal`, `id_stage`, `entry_seq`).** One row means "this deal, in this stage, on this day, in this stay". A deal that leaves a stage and later comes back produces a second stay — `entry_seq` numbers them.

Each row carries `date_entered`, `date_exited` (NULL while the deal is still there), `business_days_in_stage`, an `aging_band`, `credit_value`, and four boolean flags:

| Flag | Meaning |
| :---- | :---- |
| `is_stock_bod` | the deal was already in the stage at the **start** of the day |
| `is_stock_eod` | the deal was still in the stage at the **end** of the day — this is the inventory measure |
| `is_entry` | the deal **entered** the stage that day |
| `is_exit` | the deal **left** the stage that day |

**The flags satisfy an identity that is worth checking whenever the numbers look wrong:**

```
estoque_eod = estoque_bod + entradas - saidas
```

A deal that enters and leaves on the same day counts on both ends, which is what keeps the identity exact. (Verified on the `proposta em negociação` snapshot grid: the identity holds for every day in the window.)

**Reading the inventory:**

- The usual question — "what is the inventory right now" — is **the latest snapshot date, normally D-1**: filter `snapshot_date = <last closed day>` and `is_stock_eod`. Do not aggregate `is_stock_eod` across several days and call it inventory: that sums the same deal once per day it sat there.
- On the most recent snapshot, `date_exited IS NULL` means the deal has not left the stage at all.
- **Always state the snapshot date** — inventory is point-in-time and the same question on another day returns different numbers for the same deals.
- Aging is measured in **business days since entering the stage**, bucketed by `aging_band`: `1) 0-2`, `2) 3-5`, `3) 6-11`, `4) 12+` business days. The bands are what flag stalled deals.
- Value sitting in the stage is `SUM(credit_value)` over the `is_stock_eod` rows.

**Stages in scope.** Three stages are excluded **as the origin of a stay**, but kept **as a destination** when classifying an exit:

| Stage | Why excluded as origin |
| :---- | :---- |
| `Descarte` | terminal — a deal that enters never leaves, so "inventory" becomes a cumulative backlog and the aging bands lose meaning |
| `Venda fechada` | terminal, same reason |
| `Carrinho Abandonado` | outside the operational scope of the report |

`Deseja abordagem futura` **is** in scope as an origin (it has real movement), but deliberately has **no funnel order**: a deal can enter it from any point, so "advance" vs "return" is not determinable for it.

**Exit classification (`exit_type`)** is derived from the funnel order of the next stage, so it works for any origin stage: `Convertida (CD)`, `Perdida / descartada`, `Saída para abordagem futura`, `Avanço para outra etapa`, `Retorno a etapa anterior`, `Reentrada na mesma etapa`, plus the residual `Saída sem próximo estágio` / `Saída para etapa sem ordem definida` / `Saída de abordagem futura`.

**Why `deal_stage` and not `deal_milestone`.** `deal_milestone` stores the **first** `ts_*` per stage at deal grain — it cannot reconstruct re-entries, and inventory depends on the current stay, not the first one. Inventory is therefore built on `datalake_consorcio.deal_stage`, whose grain is the stage visit.

### Credit value and `value_source`

`credit_value` is the deal's potential credit amount, taken from the **most advanced value the funnel has filled in**, because different stages populate different fields:

1. `deal_amount` — filled by the analyst at `Proposta Aceita` / `Contrato Emitido` (mandatory only at `Contrato Emitido`).
2. `negotiation_value` — filled by the analyst when the deal moves to `Proposta em Negociação`.
3. `last_simulation_amount` — the last simulated amount in Conrado; only populated from `Simulação` onward.
4. `0` when none of the three is filled.

```sql
COALESCE(NULLIF(deal_amount, 0),
         NULLIF(negotiation_value, 0),
         CAST(last_simulation_amount AS DOUBLE),
         0)
```

`value_source` labels which branch was taken: `negociado` (`deal_amount` **or** `negotiation_value`), `simulacao` (`last_simulation_amount`), `sem valor`. Note that `negociado` deliberately covers the first two branches, so it does not separate a filled contract amount from a negotiation amount — read `deal_amount` directly if that distinction matters. `sem valor` is expected and common for stages before `Simulação`.

### Time in stage (*tempo na etapa*) — not inventory

When a deal has already left (`is_exit`, `date_exited` filled), the span between entry and exit is how long it *spent* in that stage. That is a legitimate and useful measure — e.g. how long deals historically sat in `Proposta em Negociação` before advancing — but it is **a different metric**: it describes deals that moved on, not inventory sitting there now. Never mix the two in one number.

|  | Stage inventory | Time in stage |
| :---- | :---- | :---- |
| Population | `is_stock_eod` on the snapshot date | `is_exit` rows (`date_exited` filled) |
| Clock | entry → snapshot date | entry → exit |
| Answers | "what is parked right now" | "how long it took to move" |

### Canonical Filter

The base is built on `datalake_consorcio.deal_stage` \+ `datalake_consorcio.deal`, so the pipeline filter and the test/duplicate exclusion are **already applied upstream** — do not re-add them:

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

The **inventory base is different on purpose**: it keeps every stay (no `rn = 1` dedup), because re-entries are part of the measure. It applies its own dedup — one row per (`id_deal`, `id_stage`, `ts_entered`) — to drop repeated CDC rows.

**Warning**: anchoring a coincident metric on lead creation (cohort) instead of the stage's own timestamp produces the wrong period attribution — production must be counted by close date, handoff by handoff date.

### Known Data-Quality Issues (confirmed 2026-08-10)

Reconciliation surfaced two distinct failure modes on `venda fechada` stage-entry rows in the raw stage history (originally found on `datalake_hubspot.deal_stage`; the same shapes carry into `datalake_consorcio.deal_stage`). Both **inflate** Closed Deals / GMV New / distort Avg Ticket if not filtered:

1. **Reversed-in-month closes.** A deal enters `venda fechada`, is later moved back to an earlier stage (e.g. `Simulação`) within the same month. The stage-entry row for the original close still exists in `deal_stage` history, so a naive count double-attributes it as a real close. **Confirmed case:** one deal closed and reverted to `Simulação` on the same day, inflating that day's count from 15 to 16 and GMV by R$ 400k.
   - **Fix:** require the deal's *current* stage (`datalake_consorcio.deal.current_stage`) to still be `venda fechada` at query time — this is the guard already applied in the golden query's join.
2. **Duplicate stage-entry events.** The same `id_deal` gets two `venda fechada` stage-entry rows fired seconds-to-minutes apart (same amount, no intervening stage change) — most likely a duplicate webhook/event fire in the HubSpot integration, not two separate sales. **Confirmed cases:** two separate days each had one deal with a duplicate close event (44 seconds apart in one case), inflating each day's count by 1 and GMV by the deal's `deal_amount`.
   - **Fix:** dedupe to one row per `id_deal` — the first `venda fechada` entry, ordered by `ts_entered` ascending (the `rn = 1` window in the golden query).

Both fixes are combined into a single filter (see Canonical Filter above): **first stage-entry per `id_deal` into `venda fechada`, AND current stage still `venda fechada`.** This has been validated against the official base for three separate days in the 2026-07-27 → 2026-08-08 window with a full match after the fix.

The same duplicate-event pattern affects other stages, mostly stages after handoff for `SIMULATOR IA` or the whole funnel for `SDR Humano` because the cards are moved manually by the analyst, therefore, **Leads**, **Handoff**, and **R$/Handoff** need the same per-deal-per-stage dedup.

### Nuances

- **No Blip ticket data** — state this whenever a ticket/conversation/Blip-SLA read is requested.
- **Conversion defaults to Cohort** — only compute a coincident conversion when explicitly asked as coincident, or when the ask is volumes per day/week.
- **Handoff is track-aware** (same rule as the domain entity) — reported as `SDR IA/Analyst/Day`, `Simulador/Analyst/Day`, `SDR Humano/Analyst/Day`, summing to `Handoff/Analyst/Day`.
- **Closed Deals / GMV New / Avg Ticket are deal-deduplicated, not row-counted** — see Known Data-Quality Issues. Never `COUNT(*)` or `SUM(deal_amount)` directly over raw `venda fechada` stage-entry rows without the per-deal dedup and current-stage check.
- **Handoff/Analyst/Day divides by the headcount table**, not by a heuristic — and the table already resolves weekends and holidays. State the period, the numerator and the denominator in the answer, every time.
- **Inventory needs a single snapshot date** — normally D-1. Summing `is_stock_eod` over a range counts the same deal repeatedly.
- **Inventory drops deals with no supervisor.** The inventory base requires `supervisor_name IS NOT NULL` and not `'n/a'`, because the report is an operational cut. This is a small exclusion (165 of 61,975 deals created in August 2026\) but it means inventory totals will not match an unfiltered stage count exactly.
- **Cycle time is materialized in the cohort model, not here.** `datalake_consorcio.deal_milestone` now carries `business_days_from_created_to_*`; those are lead-anchored, first-hit measures and belong to the Cohort View. Coincident aging is computed on the stage visit (`business_days_in_stage`), which is a different clock.

**Join key**: `CAST(deal.id_deal AS VARCHAR) = deal_stage.id_deal`. The base carries `analyst_name` / `analyst_role` / `supervisor_name` / `team` (straight from `deal`, resolved as of the deal creation date — no inline roster), `origin`, `segment`, `inside_sales_pipeline`, `deal_amount`, `negotiation_value`, `last_simulation_amount`, `stage_name`, `dt_stage_entered` / `dt_stage_exited`, and `ts_stage_entered` / `ts_stage_exited`.

**Fallback**: `/DU` divides by the count of `is_brz_business_day = TRUE` dates in the period.

## Dos and Don'ts

**Do:**

- Count each metric by its **own stage timestamp** (production by close date, handoff by handoff-stage entry).
- Use the **track-aware handoff** for Handoff and R$/Handoff; divide by **business days** for `/DU`.
- Read operational metrics **by analyst, supervisor and team**; route **conversion** to the Cohort View unless coincident/volume-per-period is explicitly asked.
- For **Closed Deals / GMV New / Avg Ticket**, dedupe to one row per `id_deal` (first `venda fechada` entry) **and** require the deal's current stage to still be `venda fechada` before counting it.
- For **any handoff-per-analyst metric**, take the denominator from `consorcio_daily_active_analysts` (casting `data` and `qtd_analistas`) and show numerator, denominator and period in the answer.
- Use the **per-track handoff milestone** — Lead for `SDR Humano`, Simulação for `SDR IA`, Simulação Aceita for `SIMULATOR IA` — and report handoff split by track.
- Restrict per-analyst metrics to **closed days**: the headcount sheet also carries planned future dates.
- For **stage inventory**, pick **one snapshot date** (normally D-1), filter `is_stock_eod`, name the **stage**, state the snapshot date, and say whether you are reporting the count of parked deals, the aging distribution, or the value in inventory.
- Check the identity `estoque_eod = estoque_bod + entradas - saidas` when an inventory or flow number looks off.
- Label handoff totals explicitly — business days, business days plus weekend (both Handoff/Analyst/Day numerators), or full week (raw volume across all 7 days, no analyst denominator). In Portuguese answers these map to `Handoff (dias úteis)`, `Handoff (dias úteis + fim de semana)` and `Handoff (semana total)`. Never present one number without saying which it is.

**Don't:**

- Don't anchor coincident metrics on lead-creation cohort; don't use a non-track-aware handoff.
- Don't attempt Blip-ticket/conversation metrics (no data); don't count reversed in-month closes (already guarded).
- Don't default a bare "conversão" to coincident — that's cohort.
- Don't sum `is_stock_eod` across multiple snapshot dates and call it inventory — that counts the same deal once per day it was parked.
- Don't report inventory for `Descarte`, `Venda fechada` or `Carrinho Abandonado` — they are excluded as origin stages by design (terminal or out of scope).
- Don't count a deal that already left the stage as inventory — report those separately as time in stage.
- Don't read `value_source = 'negociado'` as "the contract amount is filled" — it also covers `negotiation_value`.
- Don't join a `date_trunc('day', ts_*)` expression to `dim_date.date` — `date_trunc` returns a timestamp, not a date, so it matches nothing; `CAST(... AS DATE)` is required.
- Don't `COUNT(*)` the coincident base for volumes — the calendar `LEFT JOIN` leaves NULL-padded rows for days with no events; count `id_deal` instead.
- Don't `COUNT(*)` or `SUM(deal_amount)` raw `venda fechada` stage-entry rows for Closed Deals/GMV/Avg Ticket — duplicate close events and reversed closes will inflate the numbers (see Known Data-Quality Issues).
- Don't use the retired ≥10-handoffs heuristic to decide who was active — read the headcount table.
- Don't count a `SIMULATOR IA` deal as handoff before Simulação Aceita, or an `SDR IA` deal before Simulação — the milestone differs per track.
- Don't drop weekend handoff volume from the numerator — the bot keeps producing handoff on Saturday and Sunday, and the denominator already handles the missing shift by being 0 on those days.
- Don't compute Handoff/Analyst/Day as an average of daily ratios; it is a pooled sum over sum.

## Golden Queries

### Query 1 — Coincident base (canonical)

One row per (deal, stage) at its **first entry** into that stage, joined to the calendar so every event is counted by **its own date** (`dt_stage_entered`). Built on the official source `datalake_consorcio.deal_stage` \+ `datalake_consorcio.deal`; materializes the Superset dataset **`Funil Coincident - Não Agregado [Consorcio][Fintech]`**.

Two things to know before aggregating it:

- **The date key must be `CAST(ts_entered AS DATE)`, not `date_trunc('day', ts_entered)`.** `date_trunc` returns a timestamp, not a date, so it does not compare equal to `dim_date.date` — the join then matches nothing and every calendar row comes back NULL-padded (verified: 31 July dates, 0 matches). With the cast the same window returns **208,941 rows, 0 NULL-padded, 254 closed deals and R$ 98.73M GMV — an exact match to the July figures reported in the Daily Digest**.
- The calendar is `LEFT JOIN`ed, so dates with no qualifying stage event still produce a row with all `ds.*` columns NULL. Use `COUNT(ds.id_deal)` or `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` for volumes — a bare `COUNT(*)` would count those empty days too.
- `ts_stage_exited` is `NULL` while the deal is **still in the stage**. This base keeps only the first entry per stage, so for inventory and flow use Query 3 instead, which keeps every stay.

```sql
-- ============================================================================
-- Consórcio — Coincident golden query (deal × stage grain)
-- OFFICIAL SOURCE: datalake_consorcio.deal_stage (ds) + datalake_consorcio.deal (d).
-- One row per (deal, stage) at FIRST entry into that stage (rn = 1), joined to the
-- calendar so every stage event is counted by ITS OWN date (dt_stage_entered).
--
-- Already resolved UPSTREAM in `deal` (do NOT re-implement): pipeline filter,
-- test/duplicate exclusion, origin / segment / utm_* mapping (Growth Attribution sheets),
-- analyst / role / supervisor / team as of the deal creation date (Operação IS sheet),
-- qualifier_*, contact_type / is_abandoned_cart, feedback survey, simulation aggregates.
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
  d.negotiation_value,
  d.last_simulation_amount,
  d.customer_journey,
  d.qualifier_goal,
  d.qualifier_investment_type,
  d.qualifier_reason,
  d.qualifier_knowledge,
  d.qualifier_urgency,
  d.abandoned_cart_template_sent,
  d.contact_type,
  d.bamaq_proposal_codes,
  d.feedback_benefits,
  d.feedback_comment,
  d.analyst_name,
  d.analyst_role,
  d.supervisor_name,
  d.team,
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

Self-contained: the coincident base is inlined, so this runs directly against `datalake_consorcio.*` without going through the Superset dataset. Drop the supervisor/analyst grouping for the global view; group by `team`, `origin` or `inside_sales_pipeline` for those cuts. Uncomment the partition filter in `deal_stage` to scope the scan.

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
        d.team,
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
        ds.analyst_name, ds.analyst_role, ds.supervisor_name, ds.team
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

### Query 3 — Daily stage inventory and flow

The inventory base. One row per (`snapshot_date`, `id_deal`, `id_stage`, `entry_seq`), with the four stock/flow flags, `business_days_in_stage`, `aging_band` and `credit_value`. Set `filter_id_stage` in the `params` CTE to read a single stage (pushes the filter down early); leave it `NULL` to produce every stage and filter at consumption time.

```sql
WITH params AS (
    SELECT
        CAST(NULL AS VARCHAR) AS filter_id_stage,   -- NULL = every stage; e.g. '1398904650'
        90                    AS janela_dias        -- reporting window (calendar days)
),
-- Stages out of scope as the ORIGIN of a stay, kept as a DESTINATION in exit_type.
excluded_stages AS (
    SELECT *
    FROM (VALUES
        ('1073555315'),   -- Descarte             (terminal)
        ('1073555314'),   -- Venda fechada        (terminal)
        ('1179036774')    -- Carrinho Abandonado  (out of operational scope)
    ) AS t(id_stage)
),
-- 1. Funnel order. This is what allows classifying "advance" vs "return" for ANY stage.
--    datalake_consorcio.deal_stage has no display_order -- the order below follows the
--    funnel documented in the Consórcio Data Product. Terminal / out-of-flow stages keep
--    a NULL order on purpose.
stage_order AS (
    SELECT *
    FROM (VALUES
        ('1179036774', 'Carrinho Abandonado',    0),   -- destination only
        ('1073602594', 'Leads',                  1),
        ('1091695644', 'Tentativa de Contato',   2),
        ('1073555311', 'Contato com Sucesso',    3),
        ('1073555312', 'Simulação',              4),
        ('1129719733', 'Simulação Aceita',       5),
        ('1398904650', 'Proposta em Negociação', 6),
        ('1073555313', 'Proposta Aceita',        7),
        ('1268779444', 'Contrato Emitido',       8),
        ('1073555314', 'Venda fechada',          9),   -- destination only
        ('1073555315', 'Descarte',            NULL),   -- terminal, destination only
        ('1317298291', 'Deseja abordagem futura', NULL) -- no order: entered from any point
    ) AS t(id_stage, stage_label, funnel_order)
),
-- 2. FULL stage history.
--    LEAD runs BEFORE any stage filter -- otherwise "next stage" would only see rows
--    from the same stage.
--    The inner ROW_NUMBER drops repeated CDC rows.
deal_stage_seq AS (
    SELECT
        id_deal,
        id_stage,
        stage_name,
        ts_entered,
        ts_exited,
        LEAD(id_stage) OVER (
            PARTITION BY id_deal ORDER BY ts_entered, id_stage
        ) AS next_id_stage
    FROM (
        SELECT
            id_deal,
            id_stage,
            stage_name,
            ts_entered,
            ts_exited,
            ROW_NUMBER() OVER (
                PARTITION BY id_deal, id_stage, ts_entered
                ORDER BY ts_exited DESC
            ) AS rn_dedup
        FROM datalake_consorcio.deal_stage
        WHERE id_pipeline = '737631007'
    )
    WHERE rn_dedup = 1
),
-- 3. Spells (stays) per (deal, stage). entry_seq numbers re-entries into the same stage.
stage_spells AS (
    SELECT
        s.id_deal,
        s.id_stage,
        s.stage_name,
        s.ts_entered,
        s.ts_exited,
        s.next_id_stage,
        s.ts_exited IS NULL AS is_open,
        ROW_NUMBER() OVER (
            PARTITION BY s.id_deal, s.id_stage ORDER BY s.ts_entered
        ) AS entry_seq
    FROM deal_stage_seq s
    CROSS JOIN params p
    WHERE s.id_stage NOT IN (SELECT id_stage FROM excluded_stages)
      AND (p.filter_id_stage IS NULL OR s.id_stage = p.filter_id_stage)
),
-- 4. Enriched spells: stage, owner, seniority, potential credit value and exit type
spells AS (
    SELECT
        d.id_deal,
        s.id_stage,
        COALESCE(so.stage_label, s.stage_name) AS stage_name,
        so.funnel_order,
        s.entry_seq,
        s.is_open,
        CAST(s.ts_entered AS DATE) AS date_entered,
        CAST(s.ts_exited  AS DATE) AS date_exited,   -- NULL while still in the stage
        d.analyst_name,
        d.analyst_role    AS "role",
        d.supervisor_name AS supervisor,
        -- Most advanced value the funnel has filled in: contract/proposal amount,
        -- else negotiated value, else the last simulated amount.
        CAST(COALESCE(NULLIF(d.deal_amount, 0),
            NULLIF(d.negotiation_value, 0),
            CAST(d.last_simulation_amount AS DOUBLE),
            0
        ) AS DOUBLE) AS credit_value,
        CASE
            WHEN COALESCE(NULLIF(d.deal_amount, 0), 0)       > 0 THEN 'negociado'
            WHEN COALESCE(NULLIF(d.negotiation_value, 0), 0) > 0 THEN 'negociado'
            WHEN COALESCE(CAST(d.last_simulation_amount AS DOUBLE), 0) > 0 THEN 'simulacao'
            ELSE 'sem valor'
        END AS value_source,
        nx.stage_label AS next_stage_name,
        -- Exit classification -- generic, driven by funnel ORDER rather than a fixed list
        -- of labels, so it works for any origin stage.
        CASE
            WHEN s.is_open                      THEN NULL
            WHEN s.next_id_stage IS NULL        THEN 'Saída sem próximo estágio'
            WHEN nx.id_stage = '1073555314'     THEN 'Convertida (CD)'
            WHEN nx.id_stage = '1073555315'     THEN 'Perdida / descartada'
            WHEN nx.id_stage = '1317298291'     THEN 'Saída para abordagem futura'
            WHEN nx.funnel_order IS NULL        THEN 'Saída para etapa sem ordem definida'
            -- Origin without order (abordagem futura): the deal may have entered from any
            -- point of the funnel, so advance vs return is not determinable.
            WHEN so.funnel_order IS NULL        THEN 'Saída de abordagem futura'
            WHEN nx.funnel_order < so.funnel_order THEN 'Retorno a etapa anterior'
            WHEN nx.funnel_order > so.funnel_order THEN 'Avanço para outra etapa'
            ELSE 'Reentrada na mesma etapa'
        END AS exit_type
    FROM stage_spells s
    JOIN datalake_consorcio.deal d
        ON CAST(d.id_deal AS VARCHAR) = s.id_deal
    LEFT JOIN stage_order so
        ON so.id_stage = s.id_stage
    LEFT JOIN stage_order nx
        ON nx.id_stage = s.next_id_stage
    -- Operational cut: deals with no supervisor are out of the report.
    WHERE d.supervisor_name IS NOT NULL
      AND lower(d.supervisor_name) <> 'n/a'
),
-- 5. Calendar with a CONTINUOUS business-day index.
--    The floor comes from the spells themselves, so no old entry is dropped by the
--    aging join.
calendar AS (
    SELECT
        dd.date,
        dd.is_brz_business_day,
        SUM(CASE WHEN dd.is_brz_business_day THEN 1 ELSE 0 END)
            OVER (ORDER BY dd.date ROWS UNBOUNDED PRECEDING) AS bd_seq
    FROM dw_public.dim_date dd
    WHERE dd.date >= (SELECT MIN(date_entered) FROM spells)
      AND dd.date <= CURRENT_DATE
)
-- 6. Daily grid with stock and flow flags
SELECT
    c.date AS snapshot_date,
    sp.id_stage,
    sp.stage_name,
    sp.funnel_order,
    sp.id_deal,
    sp.entry_seq,
    sp.analyst_name,
    sp."role",
    sp.supervisor,
    sp.date_entered,
    sp.date_exited,
    sp.credit_value,
    sp.next_stage_name,
    sp.exit_type,
    -- Business days elapsed up to (exclusive) the snapshot day
    (c.bd_seq  - CASE WHEN c.is_brz_business_day  THEN 1 ELSE 0 END)
  - (ce.bd_seq - CASE WHEN ce.is_brz_business_day THEN 1 ELSE 0 END) AS business_days_in_stage,
    CASE
        WHEN (c.bd_seq  - CASE WHEN c.is_brz_business_day  THEN 1 ELSE 0 END)
           - (ce.bd_seq - CASE WHEN ce.is_brz_business_day THEN 1 ELSE 0 END) <= 2  THEN '1. 0-2 dias uteis'
        WHEN (c.bd_seq  - CASE WHEN c.is_brz_business_day  THEN 1 ELSE 0 END)
           - (ce.bd_seq - CASE WHEN ce.is_brz_business_day THEN 1 ELSE 0 END) <= 5  THEN '2. 3-5 dias uteis'
        WHEN (c.bd_seq  - CASE WHEN c.is_brz_business_day  THEN 1 ELSE 0 END)
           - (ce.bd_seq - CASE WHEN ce.is_brz_business_day THEN 1 ELSE 0 END) <= 11 THEN '3. 6-11 dias uteis'
        ELSE '4. 12+ dias uteis'
    END AS aging_band,
    -- FLAGS. A deal that enters AND leaves on the same day counts on BOTH ends.
    -- Guaranteed identity: estoque_eod = estoque_bod + entradas - saidas
    sp.date_entered < c.date
        AND (sp.is_open OR sp.date_exited >= c.date)  AS is_stock_bod,   -- stock at start of day
    sp.date_entered <= c.date
        AND (sp.is_open OR sp.date_exited >  c.date)  AS is_stock_eod,   -- stock at end of day (V1)
    sp.date_entered = c.date                          AS is_entry,       -- entered that day (V2)
    sp.date_exited  = c.date                          AS is_exit,        -- left that day (V2 and V3)
    sp.value_source
FROM spells sp
CROSS JOIN params p
JOIN calendar ce
    ON ce.date = sp.date_entered
JOIN calendar c
    ON c.date >= sp.date_entered
   AND c.date <= COALESCE(sp.date_exited, CURRENT_DATE)
-- Reporting window: applied HERE, after the aging computation (so it does not truncate it)
WHERE c.date >= CURRENT_DATE - (p.janela_dias * INTERVAL '1' DAY)
  AND c.date <= CURRENT_DATE
ORDER BY snapshot_date DESC, sp.funnel_order, analyst_name, id_deal
-- =====================================================================================
-- CONSUMPTION (filter the stage here, at the end)
--
-- V1 -- balance by aging band, one stage:
--   WHERE is_stock_eod AND id_stage = '1398904650'
--   GROUP BY snapshot_date, aging_band
--   -> COUNT(DISTINCT id_deal), SUM(credit_value)
--
-- V1 -- balance for EVERY stage side by side:
--   WHERE is_stock_eod
--   GROUP BY snapshot_date, funnel_order, stage_name, aging_band
--
-- V2 -- daily flow, per stage:
--   GROUP BY snapshot_date, funnel_order, stage_name
--   -> SUM(IF(is_stock_bod,1,0))                                     AS estoque_inicial
--      SUM(IF(is_entry,1,0))                                         AS entradas
--      SUM(IF(is_exit AND exit_type='Convertida (CD)',1,0))          AS saidas_cd
--      SUM(IF(is_exit AND exit_type='Perdida / descartada',1,0))     AS saidas_perdidas
--      SUM(IF(is_exit AND exit_type='Retorno a etapa anterior',1,0)) AS saidas_retorno
--      SUM(IF(is_stock_eod,1,0))                                     AS estoque_final
--
-- R1/R2 -- same base + GROUP BY analyst_name / supervisor / "role"
-- R3    -- conversion by aging band: numerator = is_exit AND exit_type='Convertida (CD)'
--
-- MAINTENANCE -- run when the funnel changes, to review the stage_order CTE:
--   SELECT id_stage, stage_name, COUNT(*) AS visitas
--   FROM datalake_consorcio.deal_stage
--   WHERE id_pipeline = '737631007'
--   GROUP BY id_stage, stage_name
--   ORDER BY visitas DESC
-- =====================================================================================
```

**Reference numbers (snapshot 2026-08-31, `is_stock_eod`):** `Contato com Sucesso` 8,146 deals; `Simulação` 6,082 (R$ 656.7M); `Simulação Aceita` 4,837 (R$ 886.1M); `Proposta em Negociação` 139 (R$ 68.7M); `Proposta Aceita` 35 (R$ 16.7M); `Contrato Emitido` 48 (R$ 21.2M); `Deseja abordagem futura` 168 (R$ 260.0M). Use these to sanity-check a rewrite of the query, not as a reported figure.


### Query 4 — Handoff/Analyst/Day

```sql
-- Handoff/Analyst/Day for any date range, total and by track.
WITH handoff AS (
    SELECT
        CASE
            WHEN d.inside_sales_pipeline = 'SDR Humano'   AND m.is_lead = 1                THEN CAST(m.ts_lead AS DATE)
            WHEN d.inside_sales_pipeline = 'SDR IA'       AND m.is_simulation_sent = 1     THEN CAST(m.ts_simulation_sent AS DATE)
            WHEN d.inside_sales_pipeline = 'SIMULATOR IA' AND m.is_simulation_accepted = 1 THEN CAST(m.ts_simulation_accepted AS DATE)
        END AS dt_handoff,
        d.inside_sales_pipeline AS track
    FROM datalake_consorcio.deal d
    JOIN datalake_consorcio.deal_milestone m ON m.id_deal = d.id_deal
    WHERE YEAR(ts_handoff) = 2026 AND MONTH(ts_handoff) IN (7, 8)
),
h AS (
    SELECT track, COUNT(*) AS handoffs
    FROM handoff
    WHERE dt_handoff BETWEEN DATE '2026-08-04' AND DATE '2026-08-10'
    GROUP BY track
),
a AS (
    SELECT SUM(CAST(qtd_analistas AS INTEGER)) AS analyst_days
    FROM datalake_gsheets_clean.consorcio_daily_active_analysts
    WHERE CAST(data AS DATE) BETWEEN DATE '2026-08-04' AND DATE '2026-08-10'
)
SELECT
    (SELECT SUM(handoffs) FROM h)                                        AS handoff_total,
    (SELECT SUM(handoffs) FROM h WHERE track = 'SIMULATOR IA')           AS handoff_simulator_ia,
    (SELECT SUM(handoffs) FROM h WHERE track = 'SDR Humano')             AS handoff_sdr_humano,
    (SELECT analyst_days FROM a)                                         AS analyst_days,
    ROUND(1e0 * (SELECT SUM(handoffs) FROM h) / (SELECT analyst_days FROM a), 1) AS handoff_per_analyst_day
```

**Worked example — week of 2026-08-04 to 2026-08-10:** 3,265 handoffs (2,109 `SIMULATOR IA`, 1,121 `SDR Humano`, 35 `SDR IA`) over 97 analyst-days — 5 days with operation, Saturday and Sunday at 0 in the sheet. **3,265 ÷ 97 = 33.7** handoffs per analyst per day. Always show the numerator, the denominator and the period, so the reader can rebuild the number.

### Reference — Closed Deals / GMV New / Avg Ticket directly from Trino

Production computed straight from the official source, with the dedup \+ reversal guard made explicit (useful when not going through the Superset dataset):

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

## Superset Golden Assets

- **Funil Coincident \- Não Agregado \[Consorcio\]\[Fintech\]** — the canonical coincident deal × stage dataset (Query 1).
- **Estoque \[Consorcio\]\[Fintech\]** — the stock reference dataset (Query 3)
