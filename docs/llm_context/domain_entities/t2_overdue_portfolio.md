# T2 Overdue Portfolio

## Ownership

**Data Owner:**
- maxsuel.alves@quintoandar.com.br

**Data Steward:**
- maxsuel.alves@quintoandar.com.br

## Overview

- **Objective:** Tracks the daily collections timeline for tenant (inquilino) overdue invoices under the "T2" methodology — payment status, negotiation/agreement context, risk/behavior segmentation, operational portfolio classification, eviction status, special-queue routing (ATPJ/AONB-XONB/OV15), and per-invoice last-contact/last-promise markers recorded before payment.
- **Asset status / lifecycle:** Production. `t2_fact_overdue_portfolio_timeline` is fully rebuilt every run (`CREATE OR REPLACE TABLE`). `t2_fact_overdue_data_with_last_occurrences` enriches the directly-collectable segment of that table with five sequential "last occurrence before payment" lookups (contact, call-specific contact, effort, own-advisory promise, other-advisory promise) and is also fully rebuilt every run.
- **Typical actions / events:** invoice becomes overdue → tracked daily until paid → a paid invoice remains visible through the end of its payment month (extended visibility) → resolved via one `recovery_method` category (Original Payment, Negotiation Oneshot/Card/Downpayment Payment, Written-down w/o Negotiation) or remains Open.
- **Common metrics:** Net Recovery / % Net Recovery (official — see Key Metrics below); recovery rate by aging bucket, `segmentation`, or `advisory`; wallet size by `portfolio` bucket; ATPJ/AONB/OV15 queue resolution rate; collection-activation funnel rates and conversion (% Acionado, % Alô, % CPC, % Promessa, % Acordo Pago, and "Spin" contact intensity) — see the **Ações de Cobrança** dashboard (Superset dashboard 2367), confirmed live in DataHub.
- **Source systems:** `dw_collections_segmentation` (invoice wallet timeline, contract features/wallet timelines), `datalake_cyber` (agency/queue timelines, collection action logs — also the source of the raw contact/effort logs behind the activation funnel), `dw_collection_recovery_quintoandar` (negotiation/debt/promise records, `creditor = 'IQ QuintoAndar'`), `sandbox.dw_evictions_cyber_legal` (eviction case windows).
- **Related entities:** For the full accounts-receivable ledger — including invoices this entity doesn't track (paid on time, not yet due, landlord-billed) — see **AR Portfolio** (`fact_ar_portfolio_timeline`), which inherits this entity's classification via a same-day join and depends on this table completing first in the execution order. For eviction *legal-process* tracking (case status, judicial procedure, office/agency assignment, procedural stages) see `pp_bi_timeline_evictions` / `pp_bi_timeline_stage_evictions` — confirmed via live DataHub schema check to be a **separate table family with a different grain** (one row per legal process/stage, not per invoice); not yet documented as its own domain entity in this project.

**Grain:**
- `t2_fact_overdue_portfolio_timeline` — one row per overdue invoice (`id_invoice`) per calendar reference date (`dt_reference`), from the day it becomes overdue until paid, extended through the end of the payment month.
- `t2_fact_overdue_data_with_last_occurrences` — one row per invoice (`id_invoice`) per contract (`sk_contract`) per `dt_reference`, restricted to the directly-collectable segment (`collectable_delinquent_portfolio = TRUE`) from `dt_reference >= 2025-01-01`.

## Glossary and Synonyms

- **T2 / metodologia T2** → the collections-tracking methodology this entity implements (as opposed to T1, an older/different methodology used elsewhere in Fintech reporting — e.g. a Superset chart named "Net Recovery Absolutes - T1 Delay" belongs to a **different** metric, not this entity).
- **Assessoria / advisory** → field `advisory` (the *valid* operational collection advisory attributed to the invoice). Observed values (snapshot 2026-09-13, non-exhaustive — a 13-month trend query also surfaced `LLC`, not present in the snapshot):
  - **External collection agencies:** `BULGARELLI`, `TRC`, `NOVAQUEST`, `PASCHOALOTTO`, `PLC`, `GONDIM`, `VZL`, `SLN`, `MEETCALL`, `ASL`, `PELLON`, `LLC`.
  - **Internal/administrative codes (not real agencies) — confirmed by the invoice-level advisory-selection rule, which explicitly excludes these from "valid" advisory attribution:** `COBRANÇA_INTERNA`, `PORTAL_QUINTOANDAR`, `PAUSA COBRANÇA CYBER`, `SERASA_DIGITAL`, `JUDICIAL INTERNO`, and blank/empty.
  - **Don't compare recovery performance across `advisory` without controlling for `segmentation`/aging** — see Dos and Don'ts.
- **Segmentação / segmentation** → field `segmentation` (contract risk/behavior segment, sourced from `fact_contract_features_timeline`). 32 observed values (snapshot 2026-09-13), grouped by prefix pattern: `active-new-defaulter-*` (high/medium/late-low/early-low/good-payers/first-payment-default/under-mob3-early/under-mob3-late), `active-stock-*` (risk-nodeal-low/high, risk-deal-new-monthly, risk-deal-unpaid, hold), `active-ongoing-deal`, `ended-new-defaulter-*` (low/high), `ended-ongoing-deal`, `ended-stock-*-{31-90,91-180,181-360,over1440}` each with `-low`/`-high`/`-repair` variants, `361-1440` (no variant observed), `evictions-*` (late, early-first-high, early-reincident-high, early-low). Segments ending in `-had-forgiveness` are documented as a special case (subdivided by `max_delay_contaminated_contract_t2` into aging bands) but were **not present** in the 2026-09-13 snapshot.
- **Portfolio (operacional) / portfolio** → field `portfolio`, an Ops-facing rollup of `segmentation` into 13 lettered buckets: `a) active-new-defaulter-first-payment-default`, `b) active-new-defaulter-under-mob3`, `c) active-new-defaulter`, `d) active-stock`, `e) active-ongoing-deal`, `f) ended-new-defaulter`, `g) ended-stock-31-90`, `h) ended-stock-91-180`, `i) ended-stock-181-360`, `j) ended-stock-361-1440`, `k) ended-stock-over1440`, `l) ended-ongoing-deal`, `m) evictions` (confirmed via live Trino query).
- **Colchão** → invoices generated by a negotiated installment (`negotiation_invoice_type = 'colchao em dia'` / `'colchao em atraso'`), as opposed to `'original'` invoices.
- **Recovery method categories** → `recovery_method`: Open, `b) Original Payment`, `c) Negotiation Oneshot Payment`, `d) Negotiation Card Payment`, `e) Negotiation Downpayment`, `f) Written-down w/o Negotiation`. Observed relationship (13-month trend, not causal): external agencies close predominantly via `c) Negotiation Oneshot Payment`; `COBRANÇA_INTERNA` and `PAUSA COBRANÇA CYBER` close more often via `b) Original Payment`.
- **Debtor type** → `debtor_type`: `Flow` (newly-delinquent this month) vs. `Stock` (delinquent carried over from prior months).
- **Status de despejo / eviction status** → `status_evic`: `EVICTION` vs. `EM COBRANCA` on this entity — do not confuse with `closing_month_evic_status` on AR Portfolio, which uses a different (fixed, non-`dt_reference`-driven) date basis.
- **Target mapping — `sandbox.planning_performance_fact_daily_targets`** → this shared target table carries daily rate targets (`decimal(18,6)`, e.g. `0.5511` = 55.11%) for several for-rent business lines at once (Collections IQ/tenant — this entity —, Collections PP/landlord, AR, Evictions), joined by `dt_reference`. The raw ETL that builds this table groups its own columns by code comment into two generations: **"COLLECTIONS QA NEW SEGMENTATION"** and **"COLLECTIONS QA OLD SEGMENTATION"** — the two generations largely represent the *same* business concepts under different column names, coexisting during a migration, not two different things to track in parallel.

  **Confirmed two ways** — by the requester, column by column, and independently by the actual production `CASE` logic in the official Collections IQ report tables (`rpt_collections_tenants_portfolio_timeline` and its contract-level variant `rpt_collections_tenants_portfolio_timeline_contracts`, schema not confirmed) — this is the mapping **currently in active use**, all drawn from the "NEW SEGMENTATION" column group:

  | Target column | T2 population it targets |
  |---|---|
  | `active_new_defaulter_first_payment_default_recovery` | `portfolio = 'a) active-new-defaulter-first-payment-default'` |
  | `active_new_defaulter_under_mob3_recovery` | `portfolio = 'b) active-new-defaulter-under-mob3'` |
  | `total_active_new_defaulter_recovery` | `portfolio = 'c) active-new-defaulter'` **alone** — despite the "total" prefix, this is not an aggregation of buckets `a`+`b`+`c`; it matches bucket `c` in isolation. Confirmed by the requester **and** by the production `CASE` statement. |
  | `bpo_active_new_defaulter_recovery` | Same population as `total_active_new_defaulter_recovery` (`portfolio = 'c) active-new-defaulter'`), restricted to external collection agencies (BPO) only. Not referenced in the production `CASE` (which only maps `portfolio` values, not the BPO cut), but confirmed by the requester as the correct population. |
  | `active_stock_recovery` | `portfolio = 'd) active-stock'` |
  | `ended_new_defaulter_recovery` | `portfolio = 'f) ended-new-defaulter'` |
  | `ended_stock_31_90_recovery` | `portfolio = 'g) ended-stock-31-90'` |
  | `ended_stock_91_180_recovery` | `portfolio = 'h) ended-stock-91-180'` |
  | `ended_stock_181_360_recovery` | `portfolio = 'i) ended-stock-181-360'` |
  | `ended_stock_361_1440_recovery` | `portfolio = 'j) ended-stock-361-1440'` |
  | `ended_stock_over1440_recovery` | `portfolio = 'k) ended-stock-over1440'` |
  | `active_effectiveness` | `contract_status = 'Active'` — aggregate KPI for the whole active population, no further cut. **Confirmed by the requester: this is the official target for the Colchão Effectiveness metric** (see `colchao_effectiveness_context.md`). Naming note: this column is grouped under "OLD SEGMENTATION" in the raw ETL's own build comment, yet it is the column the current production report actually uses — the "old" label does not match its real, current, confirmed usage; the comment label itself is stale, not the mapping. |
  | `ended_effectiveness` | `contract_status = 'Finished'` — same as `active_effectiveness` above: confirmed official target for Colchão Effectiveness, despite the stale "OLD SEGMENTATION" label in the build comment. |

  **`portfolio = 'e) active-ongoing-deal'` has no target column at all** — confirmed by the production `CASE`, which jumps directly from `d) active-stock` to `f) ended-new-defaulter` with no branch for `e`. Not an omission to fix in this documentation; the target-setting process simply does not set a target for that bucket.

  **Business rule confirmed by the requester:** when comparing Net Recovery results against targets, **default to the "new segmentation" mapping above**. Only pull a comparison against the "old segmentation" columns below when that is explicitly requested — don't surface both by default.

  **This target-comparison mechanism, and the `Δ% Target = (result / target) - 1` formula used to express variance, are not exclusive to Net Recovery — the same convention applies to Colchão Effectiveness** (via `active_effectiveness`/`ended_effectiveness`, cut by `contract_status` instead of `portfolio`). Both metric-level docs (`net_recovery_context.md`, `colchao_effectiveness_context.md`) carry the full Δ% formula, a Golden Query, and a worked numeric example — this table is the shared source of truth for which target column maps to which population; the metric docs are where the ready-to-run comparison queries live. When either metric is asked "vs. target," go to that metric's own doc first — do not ask the requester to supply the target.

  **Confirmed live in Trino (2026-09-18) — the new-segmentation columns only started being populated in August 2026; do not assume every recent month has a "new segmentation" target.** Checked `dt_reference = 2026-06-30 / 2026-07-31 / 2026-08-31`:
  - `total_active_new_defaulter_recovery`, `active_stock_recovery`, `ended_new_defaulter_recovery` (new segmentation): **null for June and July 2026**, populated starting **August 2026**.
  - `net_recovery_fpd`, `net_recovery_active_stock` (old segmentation equivalents of buckets `a` and `d`): still populated in June and July 2026, **null starting August 2026** — the migration crossover.
  - `total_net_recovery_active_flow` (old segmentation): already null by July 2026 — retired one month earlier than `net_recovery_fpd`/`net_recovery_active_stock`. Each old-segmentation column appears to retire on its own schedule, not all at once.
  - **Practical consequence:** a "Net Recovery vs. Target" request covering June or July 2026 returns a **null target** under the default new-segmentation mapping — this is expected (see the discontinued-target rule of thumb above), not a data quality gap. If a non-null target is needed for those two months, the old-segmentation equivalent must be pulled explicitly and the requester told which naming generation the number comes from.

  **Retired / "old segmentation" columns — not used by the current official Collections IQ report:**

  | Target column | T2 population it used to target |
  |---|---|
  | `total_net_recovery_active_flow` | `debtor_type = 'Flow'`, restricted to the **active** portfolio only (excludes ended/`portfolio` in the `f`–`k` range) |
  | `bpo_net_recovery_active_flow` | Same population as `total_net_recovery_active_flow`, external agencies only |
  | `net_recovery_active_stock` | Same population as `active_stock_recovery` (`portfolio = 'd) active-stock'`) — the "old segmentation" name for the same target now carried by `active_stock_recovery`. |
  | `net_recovery_atpj` | `is_atpj_portfolio = TRUE` |
  | `net_recovery_fpd` | Same population as `active_new_defaulter_first_payment_default_recovery` (`portfolio = 'a'`) — the "old segmentation" name for the same target now carried by `active_new_defaulter_first_payment_default_recovery`. |
  | `net_recovery_ended_1_90` | Ended population, aging **1–90 days only** (a coarser, `delay_contamined_range`-style cut, distinct from the `ended_stock_*`/`portfolio` buckets above) |
  | `net_recovery_ended_91_360` | Ended population, aging 91–360 days |
  | `net_recovery_ended_361_720` | Ended population, aging 361–720 days |
  | `net_recovery_ended_over_720` | Ended population, aging over 720 days |

  **Resolved (previously open):** `net_recovery_active_stock`/`active_stock_recovery` and `net_recovery_fpd`/`active_new_defaulter_first_payment_default_recovery` are not two independent targets accidentally duplicated — they are the same T2 population under the table's own "old" vs. "new segmentation" column-naming generations, confirmed by the raw ETL's own grouping comments. Per the business rule above, use the new-segmentation name (`active_stock_recovery`, `active_new_defaulter_first_payment_default_recovery`) by default.

  **Confirmed by the requester:** there was a **restructuring of the Collections target-setting concept during 2026** that discontinued several target lines that used to be tracked — e.g. `bpo_active_new_defaulter_recovery` (last populated 2026-08-31), `net_recovery_atpj` (last populated 2026-06-30). The column itself remains in the table schema after discontinuation; only its values stop being populated. **Rule of thumb to spot a discontinued target:** check whether the column is null for the most recent months while older months have values — that pattern signals a discontinued target line, not a data quality gap to investigate. The table also carries target columns for other business lines out of this entity's scope — AR (`ar_*`), Collections PP/landlord (`landlord_1_180`, `landlord_over_180`), Evictions (`resolution_rate_120`, `resolution_rate_120_240`, `resolution_rate_240_360`, `resolution_rate_over_360` — matching the `aging_stock` buckets on `pp_bi_timeline_evictions`), and `qc_recovery_*` / `signature_*` — per the requester, these last two groups belong to **Quinto Cred**, a separate business line entirely outside the scope of this project's entities; disregard them here.
- **Near-miss — "Net Recovery" without qualifier** → could mean **Landlord (Proprietário) Net Recovery**, a different metric on a different table/domain, not covered by this entity or by `net_recovery_context.md`.
- **Near-miss — "AR Recovery" / "AR Portfolio"** → a separate, broader-population domain entity (see **AR Portfolio**), not this one.
- **Funil de Acionamentos / Ações de Cobrança (collection-activation funnel)** → not a persisted table — a Superset-side SQL construct (dashboard **Ações de Cobrança**, `urn:li:dashboard:(superset,dashboard.2367)`) built by joining the contract-level dedup of this entity's overdue data with raw collection contact logs (`datalake_cyber.collection`) and negotiation promises/agreements (`dw_collection_recovery_quintoandar.fact_negotiation`). Confirmed via live Trino validation. Funnel stages, in order: **Acionado** (`esforco > 0`, any contact attempt logged) → **Alô** (`alo > 0`, call answered) → **CPC** (`cpc > 0`, confirmed contact with the right person) → **Promessa** (a negotiation promise recorded, excluding same-day-cancelled promises and `origin_agreement = 'Boletagem'`) → **Acordo Pago** (`dt_down_payment IS NOT NULL` on the negotiation). Step-to-step conversion (e.g. "Alô → CPC") divides contracts reaching both steps by contracts reaching the first step only.
- **Spin** → a contact-intensity metric, distinct from the funnel activation rates above: `SUM(esforço) / COUNT(DISTINCT contract) / MAX(business_day elapsed)` — average number of contact attempts per contract per elapsed business day in the month. Can be sliced overall or restricted to phone-channel actions only ("Spin Ligação").
- **`action_description` (contact channel taxonomy)** → raw `datalake_cyber.collection.action` codes are mapped to channel labels: `AV`/`UR` → Telefone - URA/AGV; `AP` → Portal - Aplicativo; `CT` → Carta - Boleto; `DI` → Telefone - Discador Automático; `DM`/`HM` → Telefone - Discador Manual; `EM` → Email - Simples; `EB` → Email - Boleto; `HS`/`WH` → Whatsapp - Automático; `WM` → Whatsapp - Manual; `PO` → Portal - Web; `RC` → Mensagem de Texto - RCS; `SM` → Mensagem de Texto - SMS; `MI` → `-`; any other code falls back to the raw `action_description`. A coarser rollup groups these into `Ligação` / `Mensagem` / `E-mail` / `Offline` / `Outros Canais` in some funnel views.
- **Two different join-window patterns coexist across funnel charts on the same data** — see Dos and Don'ts.
- **Possible field-aliasing issue, unconfirmed:** one funnel query selects `is_aonb_portfolio AS is_first_payment_default` from this entity. That does not match this entity's own documented meaning of `is_aonb_portfolio` (AONB/XONB queue flag) — flagged here as a discrepancy to confirm with whoever built the funnel dataset, not silently treated as correct.

## Tables

| You need… | Table | Grain | Mandatory filters/dedup |
|---|---|---|---|
| Daily collections timeline, wallet balance, negotiation/segmentation/portfolio classification, recovery outcome | `sandbox.t2_fact_overdue_portfolio_timeline` | One row per `id_invoice` per `dt_reference` | `collectable_delinquent_portfolio = TRUE` for the official metric universe; `is_last_business_days = TRUE` when comparing by `business_day` across months |
| Last collection contact / last negotiation promise recorded before an invoice was paid | `sandbox.t2_fact_overdue_data_with_last_occurrences` | One row per `id_invoice` per `sk_contract` per `dt_reference`, directly-collectable segment only | `last_*` fields are null for still-open invoices by design (join bound by `dt_invoice_paid`); fields are fixed per invoice, not evolving by `dt_reference` |
| Raw collection contact/effort logs (esforço, alô, CPC) by contract and channel — feeds the activation funnel | `datalake_cyber.collection` | One row per contact event (`id_contract_external`, `operator_agency`, `action`, `ts_occurrence`) | Filter `action_code_type = 'Ação'`; cast `id_contract_external` to `BIGINT` to match `sk_contract` |
| Negotiation promises and paid agreements — feeds the activation funnel's Promessa/Acordo Pago stages | `dw_collection_recovery_quintoandar.fact_negotiation` | One row per negotiation (`sk_negotiation`) | Exclude same-day-cancelled promises (`dt_promisse = dt_cancellation`) and `origin_agreement = 'Boletagem'` when counting a "promessa"; `dt_down_payment IS NOT NULL` marks a paid agreement |
| Net Recovery OKR/Health Metric targets by `portfolio`/`debtor_type`/aging cut — shared target table across multiple for-rent business lines (Collections IQ/tenant, Collections PP/landlord, AR, Evictions) | `sandbox.planning_performance_fact_daily_targets` | One row per `dt_reference` (rate columns, not amounts) | Confirmed by the requester: discontinued target columns (stopped being populated on a given date) remain in the table schema by design — a null after that date is expected, not a data quality issue. See the target mapping in Glossary and Synonyms. |
| Official Collections IQ production report — portfolio/segmentation/advisory cut, MTD/Fechamento/business-day `reference_view`, enriched with the confirmed target mapping (`portfolio_target`, `effectiveness_target`) | `rpt_collections_tenants_portfolio_timeline` (contract-level variant: `rpt_collections_tenants_portfolio_timeline_contracts`; schema not confirmed) | One row per dimensional cut (`portfolio`, `segmentation`, `advisory`, `recovery_channel`, etc.) per `dt_reference` per `reference_month`, fanned out up to 12 months back (`month_offset`) | Provided by the requester as the authoritative reference for which target columns are current — use this query's `CASE` logic over re-deriving the mapping from scratch |
| Official production report behind the collection-activation funnel (Ações de Cobrança) | `rpt_collections_tenants_collection_funnel_timeline` (schema not confirmed) | One row per contract-level cut (`portfolio`, `segmentation`, `advisory`, `contact_type`) per `dt_reference` per `reference_month`, same 12-month fan-out | Provided by the requester; confirms the funnel's join and dedup patterns already documented above |
| Official production report for negotiation promises | `rpt_collections_tenants_promisses_timeline` (schema not confirmed) | One row per negotiation (`id_negotiation`) per `dt_reference` per `reference_month`, same 12-month fan-out | Provided by the requester |

**Common join key:** `id_invoice` + `dt_reference` between the two T2 fact tables; `sk_contract` (cast `datalake_cyber.collection.id_contract_external` to `BIGINT`) to bring in contact logs and negotiation data at contract grain.

## Key Metrics

Use [Official metrics (metric entities)](#official-metrics-metric-entities) below for official Net Recovery, Collections Actions Funnel, and Colchão Effectiveness numbers — do not compute an official OKR/Health Metric directly from these tables.

### Official metrics (metric entities)

| When you need… | Metric entity |
|---|---|
| Net Recovery, % Net Recovery | `net_recovery_context.md` |
| Spin, % Alô, % CPC, % Promessa, % Acordo (activation funnel) | `collections_actions_funnel_context.md` |
| Colchão Effectiveness, % Colchão Effectiveness (negotiated-portfolio recovery) | `colchao_effectiveness_context.md` |

### Component / exploratory metrics

- **Wallet size by aging bucket** — `SUM(due_amount)` grouped by `delay_contamined_range`.
- **Wallet and recovery rate by individual `portfolio` bucket** — `SUM(due_amount)`, `SUM(net_recovered_amount)`, `SUM(net_recovered_amount)/SUM(due_amount)` filtered to one single lettered bucket at a time. Confirmed with the requester: business indicators named **"% Rec - Active New Defaulter"** and **"% Rec - Active Stock"** refer to `portfolio = 'c) active-new-defaulter'` and `portfolio = 'd) active-stock'` **each in isolation**, and this matches the `total_active_new_defaulter_recovery` / `active_stock_recovery` target columns directly — despite the "total" prefix, `total_active_new_defaulter_recovery` targets bucket `c` alone, not an `a`+`b`+`c` aggregate (see the target mapping table above).
- **Recovery rate by advisory** — `SUM(net_recovered_amount)/SUM(due_amount)` grouped by `advisory`; **must** control for `segmentation`/aging first (see Dos and Don'ts) or the ranking reflects each advisory's portfolio mix, not performance.
- **Recovery rate by segmentation** — same ratio grouped by `segmentation`; the finer-grained, statistically safer cut for advisory comparisons.
- **Special-queue resolution rate** — `is_atpj_portfolio` / `is_aonb_portfolio` / `is_ov15_portfolio` combined with the respective `*_resolution` field.
- **Recovery-method share** — `SUM(net_recovered_amount)` grouped by `recovery_method`, decomposing % Net Recovery by payment channel.
- **Funnel step conversion** (exploratory variant of the official Collections Actions Funnel metrics) — Actioned→Contacted, Contacted→CPC, CPC→Promessa, Promessa→Negotiation: contracts reaching both steps ÷ contracts reaching the first step. Real observed range (trailing 7 months, MTD snapshot): Contacted→CPC conversion ≈25–34%, Promessa→Negotiation ≈70–84% — cite as an order-of-magnitude reference, not a target.

Spin, % Alô, % CPC, % Promessa, and % Acordo are **official** Health Metrics — see `collections_actions_funnel_context.md`, not this section. Colchão Effectiveness / % Colchão Effectiveness are likewise official — see `colchao_effectiveness_context.md`.

## Relationships with other entities

- **`t2_fact_overdue_portfolio_timeline` ↔ `t2_fact_overdue_data_with_last_occurrences`** (1:1 per invoice per date, directly-collectable segment): join on `id_invoice` + `dt_reference` (or `sk_contract` for contract-level rollups). The last-occurrence table inherits `portfolio`, `advisory`, `agreement_advisory`, `recovery_method`, `business_day`, and ATPJ fields directly from the base table.
- **T2 Overdue Portfolio → AR Portfolio** (`fact_ar_portfolio_timeline`, N:1 per invoice per date): AR Portfolio's `portfolio`, `debtor_type`, `advisory`, `contract_status`, `delay_contamined_range` are inherited via a same-`dt_reference` `LEFT JOIN` from this entity, only for invoices under active collection tracking. Execution order dependency: `t2_fact_overdue_portfolio_timeline` must complete before `fact_ar_portfolio_timeline` runs.
- **T2 Overdue Portfolio → Eviction Process Timeline** (`sandbox.dw_evictions_cyber_legal`, referenced not joined-in-full): this entity's `status_evic` field checks whether `dt_reference` falls inside an active eviction case window from this source. The broader legal-process timelines (`pp_bi_timeline_evictions`, `pp_bi_timeline_stage_evictions`) are a separate table family — not yet cross-documented here.
- **T2 Overdue Portfolio → Collection-Activation Funnel** (`datalake_cyber.collection`, `dw_collection_recovery_quintoandar.fact_negotiation`, N:1 per contract per month): the contract-level dedup of this entity (one row per `sk_contract` per `dt_reference`, prioritizing still-open invoices) is `CROSS JOIN`ed against the distinct contact-channel list, then `LEFT JOIN`ed to contact logs and negotiation promises/agreements — both **cumulative within the month up to `dt_reference`** (`dt_occurrence <= dt_reference` AND same `dt_month_occurrence`). Confirmed via live Trino validation.
- **T2 Overdue Portfolio → Daily Targets** (`sandbox.planning_performance_fact_daily_targets`, 1:1 per `dt_reference`): joined by `dt_reference` (and `business_day` for MTD-locked comparisons, same convention as AR Portfolio) to compare Net Recovery against a rate target cut by `portfolio`/`debtor_type`/aging. See the full column mapping in Glossary and Synonyms. This target table is shared across multiple for-rent business lines — most of its columns are out of this entity's scope.

## Dos and don'ts

**Do:**
- Apply `collectable_delinquent_portfolio = TRUE` **and** `portfolio NOT LIKE '%eviction%'` for any analysis meant to match the official Net Recovery universe — neither flag excludes `portfolio = 'm) evictions'` on its own, confirmed live in Trino (2026-09-18) against the production report `rpt_collections_tenants_portfolio_timeline`. Skipping it materially distorts rates that don't already isolate `portfolio` as a `GROUP BY` key (~0.4 points found on one test month for overall Net Recovery) — see `net_recovery_context.md` for the confirmed magnitude.
- For **Colchão Effectiveness**, apply `actionable_regularized_portfolio = TRUE` **and** `status_evic = 'EM COBRANCA'` — confirmed against the live official production chart (Superset slice 63832, shared directly by the requester on 2026-09-18). Note this is `status_evic`, **not** `portfolio NOT LIKE '%eviction%'` — the two conditions are close but not identical (a small set of invoices carry `status_evic = 'EVICTION'` while classified outside the `m) evictions` portfolio bucket, and vice versa); only `status_evic` matches the real production chart. Skipping either exclusion entirely understated the metric by up to ~20 percentage points on one test month — see `colchao_effectiveness_context.md` for the confirmed magnitude.
- Apply `is_last_business_days = TRUE` whenever grouping or comparing by `business_day` across months.
- Control for `segmentation` (or at minimum `delay_contamined_range`) before comparing recovery rate across `advisory`, channel, or any other cut — portfolio mix is not randomly assigned, and an uncontrolled comparison can invert the real ranking (Simpson's paradox).
- Treat `COBRANÇA_INTERNA`, `PORTAL_QUINTOANDAR`, `PAUSA COBRANÇA CYBER`, `SERASA_DIGITAL`, `JUDICIAL INTERNO`, and blank `advisory` as internal/administrative codes, not real collection agencies, when ranking agency performance.
- Use `id_invoice` + `dt_reference` as the join key between `t2_fact_overdue_portfolio_timeline` and `t2_fact_overdue_data_with_last_occurrences`.
- Cast `datalake_cyber.collection.id_contract_external` to `BIGINT` before joining on `sk_contract`.
- Deduplicate `t2_fact_overdue_portfolio_timeline` from invoice grain to **contract** grain before joining to the activation funnel — `ROW_NUMBER() OVER (PARTITION BY sk_contract, dt_reference ORDER BY CASE WHEN dt_invoice_paid IS NULL THEN 1 ELSE 2 END, dt_invoice_paid DESC)` (prioritizes a still-open invoice, else the most recently paid one) is the pattern used in production.
- Note which join-window pattern a funnel query uses before reading its numbers: **cumulative-to-date** (`dt_occurrence <= dt_reference`, same `dt_month_occurrence` — used by most funnel charts, gives month-to-date totals) vs. **discrete-daily** (log's own business-day equals the contract's `business_day` — used by at least one chart, "Collections Daily CPC over Open Contracts") produce very different numbers from the same base data.

**Don't:**
- Don't sum `due_amount` / `net_recovered_amount` across multiple `dt_reference` values, or group by `business_day`, without first collapsing the daily fan-out — it double- or triple-counts the same invoice.
- Don't treat `last_*` fields on `t2_fact_overdue_data_with_last_occurrences` as varying by `dt_reference` — they are fixed per invoice (computed once, relative to `dt_invoice_paid`) and will be null for any invoice still open.
- Don't confuse `status_evic` (this entity, driven by `dt_reference`) with `closing_month_evic_status` (AR Portfolio, driven by a fixed `dt_closing`) — they use different date bases and can disagree for the same invoice.
- Don't rank `advisory` performance without a `segmentation`/aging control.
- Don't assume `is_aonb_portfolio` means "first payment default" just because one funnel query aliases it `AS is_first_payment_default` — that aliasing is unconfirmed and contradicts this entity's own documented meaning of the field.
- Don't mix the cumulative-to-date and discrete-daily funnel join patterns when comparing two charts — confirm which one each was built with first.
- Don't treat a null value in a `planning_performance_fact_daily_targets` column as a data quality problem before checking whether that target line was simply discontinued — several were, and the column is kept in the schema regardless (confirmed by the requester).
- Don't use the "old segmentation" target columns (`total_net_recovery_active_flow`, `bpo_net_recovery_active_flow`, `net_recovery_active_stock`, `net_recovery_atpj`, `net_recovery_fpd`, `net_recovery_ended_*`) by default — they are the same T2 populations as the "new segmentation" columns under older names. Use them only when an old-segmentation comparison is explicitly requested.
- Don't trust the target table's own "NEW SEGMENTATION" / "OLD SEGMENTATION" build comments as the final word on which columns are actually current — `active_effectiveness` / `ended_effectiveness` are labeled "old" in that comment but are the columns the official production report actually uses today. Validate against the real production query logic (`rpt_collections_tenants_portfolio_timeline`), not just the comment label.

## Golden Queries

**% Net Recovery by `advisory`, month over month**, trailing 13 months, month-end snapshot. Validated in Trino (dry run).

```sql
SELECT
    advisory,
    date_trunc('month', dt_month_end) AS mes,
    SUM(net_recovered_amount) * 1.0000 / SUM(due_amount) AS pct_net_recovery
FROM sandbox.t2_fact_overdue_portfolio_timeline
WHERE is_last_business_days = TRUE
  AND collectable_delinquent_portfolio = TRUE
  AND dt_reference = dt_month_end
  AND dt_reference >= date_add('month', -13, date_trunc('month', current_date))
GROUP BY advisory, date_trunc('month', dt_month_end)
ORDER BY mes DESC, pct_net_recovery DESC
```

**% Net Recovery by `segmentation`, month over month**, trailing 13 months, month-end snapshot. Validated in Trino (dry run).

```sql
SELECT
    segmentation,
    date_trunc('month', dt_month_end) AS mes,
    SUM(net_recovered_amount) * 1.0000 / SUM(due_amount) AS pct_net_recovery
FROM sandbox.t2_fact_overdue_portfolio_timeline
WHERE is_last_business_days = TRUE
  AND collectable_delinquent_portfolio = TRUE
  AND dt_reference = dt_month_end
  AND dt_reference >= date_add('month', -13, date_trunc('month', current_date))
GROUP BY segmentation, date_trunc('month', dt_month_end)
ORDER BY mes DESC, pct_net_recovery DESC
```

**Last collection contact before payment**, joined at the correct grain (reference pattern for `t2_fact_overdue_data_with_last_occurrences`):

```sql
SELECT
    t2.id_invoice,
    t2.dt_reference,
    t2.advisory,
    t2.recovery_method,
    lo.last_general_cpc_action_category,
    lo.last_general_cpc_dt_occurrence,
    lo.last_dt_promise
FROM sandbox.t2_fact_overdue_portfolio_timeline AS t2
LEFT JOIN sandbox.t2_fact_overdue_data_with_last_occurrences AS lo
    ON t2.id_invoice = lo.id_invoice
   AND t2.dt_reference = lo.dt_reference
WHERE t2.collectable_delinquent_portfolio = TRUE
  AND t2.dt_invoice_paid IS NOT NULL
  AND t2.dt_reference = DATE '2026-09-07' -- replace with the desired reference date
```

**Collection-activation funnel conversion, by business day, trailing 7 months** (Acionado → Alô → CPC → Promessa → Acordo Pago). Validated in Trino (dry run). Simplified from the production Superset query behind dashboard **Ações de Cobrança** (see Superset Golden Assets) — the production version also carries `portfolio`/`advisory`/`status_evic` passthrough columns, omitted here for readability.

```sql
SELECT
    date_trunc('day', CAST(dt_month_end AS TIMESTAMP)) AS dt_month_end,
    business_day,
    COUNT(DISTINCT sk_contract) AS qt_contratos,
    COUNT(DISTINCT CASE WHEN total_esforco > 0 AND total_alo > 0 THEN sk_contract END) * 1.0000
        / COUNT(DISTINCT CASE WHEN total_esforco > 0 THEN sk_contract END) AS "Acionado -> Alo",
    COUNT(DISTINCT CASE WHEN total_alo > 0 AND total_cpc > 0 THEN sk_contract END) * 1.0000
        / COUNT(DISTINCT CASE WHEN total_alo > 0 THEN sk_contract END) AS "Alo -> CPC",
    COUNT(DISTINCT CASE WHEN total_cpc > 0 AND total_promessa > 0 THEN sk_contract END) * 1.0000
        / COUNT(DISTINCT CASE WHEN total_cpc > 0 THEN sk_contract END) AS "CPC -> Promessa",
    COUNT(DISTINCT CASE WHEN total_promessa > 0 AND total_acordo > 0 THEN sk_contract END) * 1.0000
        / COUNT(DISTINCT CASE WHEN total_promessa > 0 THEN sk_contract END) AS "Promessa -> Acordo Pago"
FROM (
    WITH logs_data AS (
        SELECT
            CAST(id_contract_external AS BIGINT) AS sk_contract,
            CASE
                WHEN action IN ('AV', 'UR') THEN 'Telefone - URA/AGV'
                WHEN action = 'AP' THEN 'Portal - Aplicativo'
                WHEN action = 'DI' THEN 'Telefone - Discador Automático'
                WHEN action IN ('DM', 'HM') THEN 'Telefone - Discador Manual'
                WHEN action IN ('HS', 'WH') THEN 'Whatsapp - Automático'
                WHEN action = 'WM' THEN 'Whatsapp - Manual'
                ELSE action_description
            END AS action_description,
            CAST(esforco AS BIGINT) AS esforco,
            CAST(alo AS BIGINT) AS alo,
            CAST(cpc AS BIGINT) AS cpc,
            DATE(ts_occurrence) AS dt_occurrence,
            DATE(DATE_TRUNC('MONTH', ts_occurrence)) AS dt_month_occurrence
        FROM datalake_cyber.collection
        WHERE action_code_type = 'Ação'
          AND DATE(DATE_TRUNC('MONTH', ts_occurrence)) > date_add('month', -7, current_date)
    ),
    fact_negotiation_data AS (
        SELECT CAST(sk_contract AS BIGINT) AS sk_contract, origin_agreement, dt_promisse, dt_down_payment, dt_cancellation
        FROM dw_collection_recovery_quintoandar.fact_negotiation
    ),
    negotiation_flags AS (
        SELECT sk_contract, 1 AS promessa, 0 AS acordo, DATE(dt_promisse) AS dt_occurrence, DATE(DATE_TRUNC('MONTH', dt_promisse)) AS dt_month_occurrence
        FROM fact_negotiation_data
        WHERE (DATE(dt_promisse) <> DATE(dt_cancellation) OR dt_cancellation IS NULL) AND (origin_agreement <> 'Boletagem' OR origin_agreement IS NULL)
        UNION ALL
        SELECT sk_contract, 0 AS promessa, 1 AS acordo, DATE(dt_down_payment), DATE(DATE_TRUNC('MONTH', dt_down_payment))
        FROM fact_negotiation_data
        WHERE dt_down_payment IS NOT NULL
    ),
    logs_totals AS (
        SELECT sk_contract, action_description, SUM(esforco) AS total_esforco, SUM(alo) AS total_alo, SUM(cpc) AS total_cpc, dt_occurrence, dt_month_occurrence
        FROM logs_data GROUP BY 1, 2, 6, 7
    ),
    negotiation_totals AS (
        SELECT sk_contract, SUM(promessa) AS total_promessa, SUM(acordo) AS total_acordo, dt_occurrence, dt_month_occurrence
        FROM negotiation_flags GROUP BY 1, 4, 5
    ),
    action_category AS (SELECT DISTINCT action_description FROM logs_totals),
    contract_dedup AS (
        SELECT sk_contract, business_day, dt_reference, dt_month_start, dt_month_end,
            ROW_NUMBER() OVER (PARTITION BY sk_contract, dt_reference ORDER BY CASE WHEN dt_invoice_paid IS NULL THEN 1 ELSE 2 END, dt_invoice_paid DESC) AS rn
        FROM sandbox.t2_fact_overdue_portfolio_timeline
        WHERE collectable_delinquent_portfolio = TRUE
          AND is_last_business_days = TRUE
          AND dt_month_start > date_add('month', -7, current_date)
    ),
    contract_base AS (SELECT sk_contract, business_day, dt_reference, dt_month_start, dt_month_end FROM contract_dedup WHERE rn = 1),
    contract_x_channel AS (SELECT * FROM contract_base CROSS JOIN action_category),
    contract_x_negotiation AS (
        SELECT c.*, COALESCE(SUM(n.total_promessa), 0) AS total_promessa, COALESCE(SUM(n.total_acordo), 0) AS total_acordo
        FROM contract_x_channel AS c
        LEFT JOIN negotiation_totals AS n ON c.sk_contract = n.sk_contract AND n.dt_month_occurrence = c.dt_month_start AND n.dt_occurrence <= c.dt_reference
        GROUP BY 1, 2, 3, 4, 5, 6
    )
    SELECT c.sk_contract, c.business_day, c.dt_month_end, c.total_promessa, c.total_acordo,
        COALESCE(SUM(l.total_esforco), 0) AS total_esforco, COALESCE(SUM(l.total_alo), 0) AS total_alo, COALESCE(SUM(l.total_cpc), 0) AS total_cpc
    FROM contract_x_negotiation AS c
    LEFT JOIN logs_totals AS l ON c.sk_contract = l.sk_contract AND l.dt_month_occurrence = c.dt_month_start AND l.dt_occurrence <= c.dt_reference AND c.action_description = l.action_description
    GROUP BY 1, 2, 3, 4, 5
) AS funnel_base
GROUP BY date_trunc('day', CAST(dt_month_end AS TIMESTAMP)), business_day
ORDER BY dt_month_end DESC
```

## Superset Golden Assets (project extension — not part of the standard domain template)

> **Note:** this section is not part of the official `CREATE_DOMAIN_ENTITY_CONTEXT.md` template — it is a project-specific extension, kept intentionally because Superset chart/dashboard routing is directly useful for whoever works on this entity.

Confirmed live via DataHub — all charts belong to dashboard **Ações de Cobrança** `[Fintech][P&P]` (`urn:li:dashboard:(superset,dashboard.2367)`, https://superset.apps.data-prd.habitat.zone/superset/dashboard/2367):

- **Successful Contacted Contracts per Business Day (%)** — https://superset.data.quintoandar.com.br/explore/?slice_id=32244 — URN: `urn:li:chart:(superset,chart.32244)`
- **Contacted to CPC Conversion Rate (%)** — https://superset.data.quintoandar.com.br/explore/?slice_id=32303 — URN: `urn:li:chart:(superset,chart.32303)`
- **Successful Payment Negotiation per Business Day (%)** — https://superset.data.quintoandar.com.br/explore/?slice_id=32247 — URN: `urn:li:chart:(superset,chart.32247)`
- **Collections Daily CPC over Open Contracts** — https://superset.data.quintoandar.com.br/explore/?slice_id=33575 — URN: `urn:li:chart:(superset,chart.33575)` (uses the **discrete-daily** join pattern, not cumulative-to-date — see Dos and Don'ts)
- **Accumulated Advisory Spin per Business Day** — https://superset.apps.data-prd.habitat.zone/explore/?slice_id=33745 — URN: `urn:li:chart:(superset,chart.33745)`. **Flagged for confirmation:** this slice ID was provided alongside two different SQL examples during analysis (an advisory-level % Acionado/Alô/CPC/Promessa/Acordo breakdown, and a "Spin médio" query) — only the second matches this chart's actual title; likely a copy/paste mismatch on the first, not treated as this chart's real query here.
