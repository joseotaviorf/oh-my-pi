# Consórcio

## Ownership

**Data Owner:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

**Data Steward:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

## Overview

Consórcio is QuintoAndar's *carta de crédito imobiliário* inside-sales funnel. Analysts use it to measure deal progression from Lead through Closed Deal, attribution, Conrado (AI) vs human tracks, and handoff-to-close performance. The **official source** is `datalake_consorcio.deal` \+ `datalake_consorcio.deal_milestone` (modelled tables where the funnel business rules are already applied), with `datalake_consorcio.deal_stage` as the stage-visit history for deep investigation. HubSpot (`datalake_hubspot.*`) and `datalake_consorcio_clean.*` are the upstream raw layers. Four team-maintained Google Sheets materialized in `datalake_gsheets_clean` drive the attribution lookups and the daily active-analyst headcount. The cohort consumption layer is the dataset **Funil Cohort \- Não Agregado \[Consorcio\]\[Fintech\]**.

**Grain:** one row per deal at its latest stage — **already enforced by `datalake_consorcio.deal`** (dedup, duplicate/test exclusion and the pipeline filter are applied in the table build, not in the query).

Funnel (from Lead onward; Page View → Lead / Consentimento → Lead are out of scope):

1. **Lead** — `is_lead` / `ts_lead`
2. **Contact Attempt (TC)** — branch, not cumulative (`is_contact_attempted` / `ts_contact_attempt`). Reached when the user does not send the first message and we send the abandoned-cart template (`is_abandoned_cart = 1`); a reply moves it to SC.
3. **Successful Contact (SC)** — `is_success_contact` / `ts_success_contact`
4. **Simulation sent (SS)** — HubSpot label lowercased as `simulação` (`is_simulation_sent` / `ts_simulation_sent`)
5. **Simulation accepted (SA)** — `is_simulation_accepted` / `ts_simulation_accepted`
6. **Offer under negotiation (OUN)** — `is_offer_under_negotiation` / `ts_offer_under_negotiation`
7. **Offer Accepted (OA)** — `is_offer_accepted` / `ts_offer_accepted`
8. **Contract Created (CC)** — `is_contract_created` / `ts_contract_created`
9. **Closed Deal (CD)** — `is_closed_deal` / `ts_closed_deal`
10. **Discard** — `is_discarded` / `ts_discarded` (not a conversion step)

Not all deals follow every step: TC is optional (Lead can go straight to SC); Conrado track (`SIMULATOR IA` / `SDR IA`) vs `SDR Humano` changes where handoff starts. Default analytical lens is **cohort by deal creation date** (`date` \= `dt_created`). All `ts_*` timestamps already arrive in `America/Sao_Paulo`, and test/duplicate deals are already excluded — both applied in the table build.

**Cycle time is now materialized.** `datalake_consorcio.deal_milestone` carries the business-day maturation of every milestone as `business_days_from_created_to_*` columns, plus `aging_opened_leads` and `days_in_current_stage`. Queries no longer compute cycle time against `dw_public.dim_date`. The full maturation semantics — including how to derive a stage-to-stage window from two lead-anchored columns — live in the **Consórcio Funnel — Cohort View** metric entity.

## Related Metric Entities

Official Consórcio metric formulas belong in metric-entity docs. Treat Key Metrics below as exploratory orientation only — do not invent official conversion formulas here.

- **Consórcio Funnel — Cohort View** — funnel conversion, cycle time and maturation rules by deal creation date; reuses this doc's golden query / Funil Cohort dataset.
- **Consórcio Funnel — Coincident View** — volume entering each stage by that stage's own timestamp (operational load; closed deals by close date). Not derivable from the cohort model.
- **Consórcio Repescagem** — reactivation metrics on the discarded ↔ `origin = 'repescagem'` linkage dataset; owns the `rehabilitation_*` fields.

## Glossary and Synonyms

- **Consórcio** (*carta de crédito imobiliário*) → this entity; sourced from HubSpot pipeline `737631007` (filter already applied in `datalake_consorcio.deal`)
- **Conrado** → AI agent covering Lead → Simulação Aceita (`inside_sales_pipeline = SIMULATOR IA`) and Lead → Simulação (`inside_sales_pipeline = SDR IA`)
- **SIMULATOR IA** → Conrado on Conversational Platform; handoff from Simulação Aceita
- **SDR IA** → Conrado on Blip; handoff from Simulação; being discontinued
- **SDR Humano** → human analyst; active for analyst-routed repescagem; handoff from Successful Contact
- **Handoff** → Conrado → human analyst (`is_handoff` / `ts_handoff`)
- **Repescagem** → reactivated lead after discard; new deal with `origin = 'repescagem'`
- **Paid Media** → paid channel rollup: `origin IN ('meta', 'google', 'youtube')`
- **TC** (*Tentativa de Contato*) → `is_contact_attempted` / `ts_contact_attempt` (branch, not cumulative)
- **Carrinho abandonado** (*abandoned cart — our nomenclature for the message, unrelated to the `carrinho abandonado` pipeline stage*) → the user did **not** send the first WhatsApp message, so we send the abandoned-cart template. `is_abandoned_cart = 1` ⇒ template sent and the card **moved to Tentativa de Contato (TC)**; if the user replies, it advances to **Contato com Sucesso (SC)**. `is_abandoned_cart = 0` ⇒ the user sent the first message and the deal goes **straight to SC** (no TC). The flag is an **`integer` (1/0)**. Surfaced as `contact_type` \= `company_initiated` / `user_initiated`. Valid from **2026-08-10**.
- **SC / SS / SA / OUN / OA / CC / CD** → Success Contact \= Contato com Sucesso / Simulation Sent \= Simulação \= Simulação Enviada / Simulation Accepted \= Simulação Aceita / Offer Under Negotiation \= Proposta em Negociação \= Oferta em Negociação / Offer Accepted \= Proposta Aceita \= Oferta Aceita / Contract Created \= Contrato Criado \= Contrato Emitido / Closed Deal \= Venda \= Venda Fechada
- **Cohort** → metrics grouped by deal creation date (`date` \= `dt_created`, local BRT date)
- **Coincident** → metrics grouped by each stage's own timestamp (separate dataset)
- **Inside Sales** → operational sales team; usually coincident metrics
- **Growth Attribution** → the Google Sheet behind `origin` and `segment` (see Reference Sheets)
- **Operação IS** → the Google Sheet behind analyst, role, supervisor and team (see Reference Sheets)
- **Active Analysts** → the number of Inside Sales analysts working on a given day, maintained by the team in a sheet and materialized as `datalake_gsheets_clean.consorcio_daily_active_analysts`. It is the official denominator for any per-analyst metric — see the Coincident View metric entity
- **Conversations** → the WhatsApp message exchange between the customer and Conrado Agent or the customer and the human analyst, stored in `datalake_consorcio_clean.blip_messages`

## Tables

| You need... | Use this table |
| :---- | :---- |
| **Deal master — official source** (business rules already resolved) | `datalake_consorcio.deal` — 1 row per deal; key `id_deal`; partitions `year` / `month` / `day` |
| **Funnel milestones, cumulative flags and materialized cycle time** | `datalake_consorcio.deal_milestone` — key `id_deal` (1:1 with `deal`); `is_*` flags, `ts_*` milestones and `business_days_from_created_to_*` |
| Stage-visit history (deep investigation only) | `datalake_consorcio.deal_stage` — 1 row per (`id_deal`, `id_stage`, `ts_entered`); **N:1 with the deal — joining fans out** |
| `utm_source` → `origin` mapping | `datalake_gsheets_clean.consorcio_origin_mapping` |
| `utm_campaign` → `segment` mapping | `datalake_gsheets_clean.consorcio_segment_mapping` |
| Analyst → role / supervisor / team, with history | `datalake_gsheets_clean.consorcio_inside_sales_operation` |
| Active analysts per day (denominator of per-analyst metrics) | `datalake_gsheets_clean.consorcio_daily_active_analysts` — 1 row per calendar day |
| Conversation messages | `datalake_consorcio_clean.blip_messages` — 1 row per message; **N:1 with the deal — joining fans out** |
| Blip id / external ids | `datalake_consorcio_clean.lead_external_data` — `id_crm = deal.id_deal`; `id_lead = lead.id` |
| Lead detail (source of `uuid_lead`) | `datalake_consorcio_clean.lead` |
| Simulation detail (per-simulation rows) | `datalake_consorcio_clean.simulation` — simulations only done by the AI agent, the ones carried by the human analyst are not included here; only for raw rows; `deal` already carries `total_simulations` and the first / last / average simulation amounts |

**Critical rules:**

- **`datalake_consorcio.deal` \+ `datalake_consorcio.deal_milestone` are the official source.** Join 1:1 on `id_deal`. Do **not** rebuild the funnel from `datalake_hubspot.*` — those are the upstream raw tables (`datalake_hubspot.deal_stage` is the raw stage feed, unpartitioned and in source timezone; the Consórcio-scoped, BRT-converted, partitioned version is `datalake_consorcio.deal_stage`).
- **Already resolved in the tables — never re-implement in the query:** pipeline filter (`737631007`), dedup to one row per deal at its latest stage, test/duplicate exclusion, timezone conversion, `origin` / `segment` / `utm_*` mapping, analyst / role / supervisor / team attribution, `customer_journey`, the `qualifier_*` answers, `contact_type` / `is_abandoned_cart`, the feedback-survey fields, the simulation aggregates, and **all business-day cycle times**.
- **All `ts_*` columns are already converted to `America/Sao_Paulo` (BRT)** in the table build — they are `timestamp(3) with time zone` in local time. Never wrap them in `AT_TIMEZONE(...)` again. The `dt_*` / `date` columns are already the local calendar date.
- **Maturation anchor:** every `business_days_from_created_to_*` column runs from the **deal creation date** to that milestone, in Brazilian business days. `business_days_from_created_to_lead` is `0` for the whole base (validated on the July 2026 cohort: 56,324 of 56,324 rows), so *created* and *lead* are the same anchor in practice. `aging_opened_leads` and `days_in_current_stage` are the exceptions by design — they run to *today* and are only valid as of the last rebuild.
- **Analyst attribution is history-aware.** `deal.analyst_name`, `analyst_role`, `supervisor_name` and `team` are resolved **as of each deal's creation date** from `consorcio_inside_sales_operation`, so a promotion or a supervisor change does not rewrite past deals. When an analyst who has left the operation still receives leads after their `dt_ended`, the supervisor is set to **`other`** so those deals stop landing on a former supervisor. Valid from **2026-08-01**.
- **Where to check a divergence:** for any doubt about `origin`, `segment`, or analyst / supervisor / role attribution, consult the two reference sheets below **plus** the SQL rule in `bi-etl-juice` that builds `datalake_consorcio.deal`. The sheets are the business input; the build SQL is how that input is applied.
- **The mapping sheets have no primary key** — each is deduped to one row per key before joining in the build. Do not assume uniqueness if you read them directly.
- **Validity windows:** `OUN` / `CC` milestones only from **2026-07-20**; `contact_type` / `is_abandoned_cart` only from **2026-08-10** (NULL before).
- The `Agendamento de pagamento` stage was retired and is no longer read;
- Contact fields arrive **already hashed** from the source — usable as join keys, no readable contact data. (Exception: `lead_external_data.id_bsp_contact` is **not** hashed.)
- ⚠️ **DataHub's column types for these tables are stale** — it reports fields as `VARCHAR`. The real Trino types are `integer` for the `is_*` flags / `deal_amount`, `bigint` for `id_deal` / `total_simulations` / every `business_days_*` column, `timestamp(3) with time zone` for `ts_*`, and `date` for `dt_created`. Trust the table, not the catalog metadata, until ingestion is refreshed.

## Reference Sheets

The business input behind attribution and headcount lives in three team-maintained Google Sheets, materialized daily into `datalake_gsheets_clean`. Editing the sheet changes the table on the next build — treat them as source of truth for the mapping, never as an ad-hoc scratchpad.

| Sheet | Materialized as | Drives |
| :---- | :---- | :---- |
| **\[Consorcio\] Growth Attribution** — [link](https://docs.google.com/spreadsheets/d/1k1_AnI0qbJ6-2txg0qB_HX1o_GeEFFOGlMMs9JwAZ9w/edit?gid=0#gid=0) | `consorcio_origin_mapping` (`utm_source` → `origin`), `consorcio_segment_mapping` (`utm_campaign` → `segment`) | `deal.origin`, `deal.segment` |
| **\[Consórcio\] Operação IS** — [link](https://docs.google.com/spreadsheets/d/1B088r-Hsan7-ZQAxX_VpIllfFO_za9avRSm8GUtpb8A/edit?gid=1239496841#gid=1239496841) | `consorcio_inside_sales_operation` (one row per analyst relationship) | `deal.analyst_name`, `analyst_role`, `supervisor_name`, `team` |
| **\[Consórcio\] Analistas Ativos** — [link](https://docs.google.com/spreadsheets/d/1EPqja9mUgAn6ftY9NzS9fIzDGxExvCytiAZUeicHm0A/edit?gid=12732683#gid=12732683) (tab **consolidado**) | `consorcio_daily_active_analysts` (one row per calendar day) | the denominator of every per-analyst metric |

`consorcio_daily_active_analysts` is the headcount table: one row per calendar day, columns `data` and `qtd_analistas`. **Both arrive as `varchar`** — `CAST(data AS DATE)` and `CAST(qtd_analistas AS INTEGER)` before using them. Verified on 2026-09-09: 395 rows, one per day, no duplicates, covering 2025-09-01 to 2026-09-30. Two properties matter analytically:

- **The sheet already answers the weekend question.** Sunday is `0` on every Sunday in the window; Saturday is `0` on 9 of 14 Saturdays and averages ~6 analysts when there is a shift. Weekday zeros are holidays. No heuristic and no assumption is needed — read the day.
- **It runs ahead of today.** The sheet carries future dates (planned staffing), so a join on a date in the future returns a plan, not a fact. Scope any per-analyst metric to closed days.

`consorcio_inside_sales_operation` is a slowly-changing relationship table: one row per `id_hubspot_owner` × relationship, with `dt_created` (start) and `dt_ended` (end, empty while active). A promotion or supervisor change closes the current row with a `dt_ended` and inserts a new row starting on the change date. This replaced a hard-coded CTE that overwrote the entire history on every change, which made past deals inconsistent with the operation as it actually was.

Deals whose owner received leads **after** their `dt_ended` are attributed to supervisor `other` in `deal` by the build rule, so they will not appear inside any relationship window here — that gap is the expected signal, not a data error.

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) when asking for an **official** conversion or reactivation number. Below is exploratory orientation only.

- **Funnel volumes** — deals per stage (`is_lead` … `is_closed_deal`)
- **Conversion rates** — stage-to-stage ratios (Lead→SC, SS→CD, SA→CD), usually cohort by `date`
- **Cycle time (business days)** — the materialized `business_days_from_created_to_*` columns
- **Lead aging** — open business days since creation (`aging_opened_leads`)
- **Simulation activity** — `total_simulations`, first / last / average simulation amount, `ts_first_simulated` / `ts_last_simulated`
- **Operational performance** — handoff → CD (SS→CD for SDR IA; SA→CD for SIMULATOR IA)
- **Contact-initiation mix** — `contact_type` \+ `is_contact_attempted`
- **Attribution mix** — `origin` / `segment` / `utm_*`; Paid Media \= Meta \+ Google \+ YouTube
- **Team performance** — by `analyst_name`, `analyst_role`, `supervisor_name`, `team`
- **Repescagem** — reactivation metrics (separate dataset \+ metric entity)

**Cohort vs coincident:** cohort (this doc) anchors on deal creation date — right for conversion. Coincident counts by each stage's timestamp — right for operational load. Same metric name, different volumes (e.g. closed deals in July).

## Relationships with Other Entities

### Deal → Deal milestones (1:1)

- `datalake_consorcio.deal.id_deal = datalake_consorcio.deal_milestone.id_deal`
- `deal` holds descriptive attributes; `deal_milestone` holds the funnel `is_*` flags, `ts_*` milestones and the materialized `business_days_from_created_to_*` cycle times. `INNER JOIN` — a deal always has a milestone row.

### Deal → Deal stage visits (1:N — fans out)

- `datalake_consorcio.deal_stage.id_deal` is `varchar` while `deal.id_deal` is `bigint` — CAST or the join fails.
- **This table is for deep investigation only.** It is not at deal grain, so joining it multiplies `id_deal` rows. Never use it to count deals.
- **A skipped stage leaves no visit row**, and stage skipping is frequent. The milestone corrections for skipped stages are applied when `deal_milestone` is built — so `deal_milestone` is the correct place to read whether a stage was reached, and `deal_stage` only shows the visits that physically happened.

### Deal → Attribution sheets (N:1, as of creation date)

- `deal.utm_source = consorcio_origin_mapping.utm_source` → `origin`
- `deal.utm_campaign = consorcio_segment_mapping.utm_campaign` → `segment`
- `CAST(deal.id_hubspot_owner AS VARCHAR) = consorcio_inside_sales_operation.id_hubspot_owner` (the sheet column is `varchar`, `deal.id_hubspot_owner` is `bigint`), restricted to the relationship whose `dt_created` / `dt_ended` window contains `deal.dt_created`.
- All three joins are **already applied in the build**. Read them directly only to audit the mapping itself.

### Deal → Lead external data (1:1) — Blip id

- `datalake_consorcio_clean.lead_external_data.id_crm = CAST(datalake_consorcio.deal.id_deal AS VARCHAR)` — the HubSpot deal id is `id_crm` there. **`id_crm` is `varchar` while `deal.id_deal` is `bigint` — CAST or the join fails.** `id_crm` is also nullable (a lead may have no CRM deal yet).
- `datalake_consorcio_clean.lead_external_data.id_lead = datalake_consorcio_clean.lead.id` (both `bigint`).
- **Blip ids:** `id_bsp_contact` (the Blip/WhatsApp contact) and `id_bsp_conversation` (the conversation). ⚠️ `id_bsp_contact` frequently carries the **raw phone number** (`55119…@wa.gw.msging.net`) — unhashed contact data, unlike the hashed `phone_number` field. Keep it out of shared outputs.

### Lead → Blip messages (1:N — fans out) — conversations history

- `datalake_consorcio_clean.blip_messages.id_lead = datalake_consorcio_clean.lead.id` (both `bigint`).
- **Shortcut to the deal:** `blip_messages.id_crm = CAST(datalake_consorcio.deal.id_deal AS VARCHAR)` — the table already carries the HubSpot deal id, so reaching a conversation does not require going through `lead_external_data`. `id_crm` is `varchar` and nullable.
- **One row per message exchanged**, in either direction, between the customer and Conrado on the Conversational Platform or the analyst. `role` says who sent it, `content` is the message text and `ts_created` is when it was sent. Partitioned by `year` / `month` / `day`.
- ⚠️ **Joining this table multiplies deals.** Measured on August 2026: 8.1 messages per deal on average, median 4, maximum 271. Never count deals, leads or conversions over a join with `blip_messages` — aggregate to one row per deal first.
- **`role` observed values are `ai`, `human` and `attendant`.** `ai` is Conrado. `attendant` is the human analyst after handoff: it appears in 68% of handed-off `SIMULATOR IA` deals (6,475 of 9,513) against 1.6% of the non-handed-off ones (763 of 46,237), which leaves `human` as the customer.
- **Coverage is for the whole funnel.** For `SIMULATOR IA` from `Lead` to `Simulation` the conversation is between `ai` and `human` and after `Simulation` between `attendant` and `human` whereas `SDR Humano` is between `attendant` and `human`.
- **`content` carries the customer's own words** — treat it as sensitive text. Keep it out of shared outputs and never paste message bodies into a report.

### Deal → Active analysts per day (N:1 on the calendar date)

- `CAST(datalake_gsheets_clean.consorcio_daily_active_analysts.data AS DATE) = <the metric's own date>` — join on the day being measured, not on the deal creation date.
- This is the **official denominator for any per-analyst metric**. The formula and the per-track handoff definition live in the Coincident View metric entity; do not reimplement them here.

### Deal → Lead (N:1)

- `datalake_consorcio_clean.lead.uuid = datalake_consorcio.deal.uuid_lead`
- Only needed for lead attributes not already denormalized onto `deal` (`customer_journey` is already there).

### Lead → Simulation (1:N → aggregate to 1:1)

- `datalake_consorcio_clean.simulation.id_lead = datalake_consorcio_clean.lead.id`
- Aggregate before joining. `deal` already exposes `total_simulations`, `ts_first_simulated` / `ts_last_simulated` and the first / last / average simulation amounts, so go to `simulation` only for per-simulation detail.

### Repescagem (out of scope here)

- Conversion of a repescagem deal through the funnel: this entity \+ the cohort metric entity.
- Measurement that links a discarded deal to a later `origin = 'repescagem'` deal — and the `rehabilitation_*` fields on `deal` — live in the repescagem metric entity / dataset, not here.

## Dos and Don'ts

**Do:**

- Read from `datalake_consorcio.deal` joined 1:1 to `datalake_consorcio.deal_milestone` on `id_deal` — the pipeline filter, dedup and test/duplicate exclusion are already applied upstream.
- Scope queries with the `year` / `month` / `day` partitions (or `dt_created`).
- Take cycle time from the materialized `business_days_from_created_to_*` columns; see the cohort metric entity for the stage-to-stage derivation rule.
- Take analyst attribution from the table's own `analyst_name` / `analyst_role` / `supervisor_name` / `team`.
- Take the active-analyst headcount from `consorcio_daily_active_analysts`, casting `data` and `qtd_analistas`, and restrict to closed days.
- Send `origin`, `segment` or analyst-attribution divergences to the two reference sheets plus the `bi-etl-juice` build SQL.
- Read TC passage from `is_contact_attempted` / `ts_contact_attempt`; read contact initiation from `is_abandoned_cart` / `contact_type` (valid from 2026-08-10 only).
- State cohort vs coincident explicitly when reporting volumes.
- Ask which stages of the funnel and which `role` before analysing conversations.

**Don't:**

- Don't join `datalake_consorcio.deal_stage` to count deals — it fans out, and a skipped stage has no row there at all.
- Don't join `datalake_consorcio_clean.blip_messages` to count deals or leads — it is at message grain and multiplies rows ~8x on average.
- Don't assume `blip_messages` only covers `SIMULATOR IA` — `SDR Humano` deals also have conversations. Filter the track explicitly.
- Don't estimate active analysts from deal volume — read `consorcio_daily_active_analysts`.
- Don't recompute cycle time against `dw_public.dim_date` — it is materialized, and recomputing risks a different business-day convention.
- Don't treat `is_contact_attempted` as cumulative — TC is a branch; some deals go Lead → SC directly.
- Don't infer TC passage from `contact_type` alone — it means who initiated contact, not stage passage.
- Don't re-implement upstream rules (pipeline filter, dedup, origin/segment mapping, analyst attribution, qualifier explosion) in the query.
- Don't hard-code an analyst → supervisor map in a query; it loses the history and reintroduces the problem the sheet solved.
- Don't treat `total_simulations = 0` outside `SIMULATOR IA` as missing data.
- Don't derive a coincident view from this cohort model — use the coincident dataset/query.
- Don't put repescagem linkage measurement or official conversion formulas in this doc — those belong in metric entities.

## Golden Queries

### Query 1 — Deal-grain cohort base (canonical)

One row per Consórcio deal at its latest stage, read from the **official source** `datalake_consorcio.deal` \+ `datalake_consorcio.deal_milestone`: descriptive attributes, funnel milestones, cumulative stage flags (TC as a branch), attribution, contact initiation, feedback survey, simulation aggregates and the **materialized business-day cycle times**. Anchor cohort analyses on `date` (= `dt_created`). Materializes the Superset dataset **`Funil Cohort \- Não Agregado \[Consorcio\]\[Fintech\]`**.

The query is now a projection: every business rule — including cycle time — lives in the table build. Nothing is computed here.

**Consumer note:** the cycle-time columns changed name and anchor. The old query exposed `days_to_convert_from_lead_to_*` (and stage-pair columns) computed inline; the base now exposes `business_days_from_created_to_*` from the table. Any chart or saved query still referencing a `days_to_convert_from_*` column must be remapped — see the cohort metric entity for the stage-to-stage equivalent.

```sql
-- ============================================================================
-- Consórcio — Golden Query (cohort model, deal grain)
-- OFFICIAL SOURCE: datalake_consorcio.deal (d) + datalake_consorcio.deal_milestone (dm),
-- joined 1:1 on id_deal. Catalog: delta. Cohort view (anchor on `date` = dt_created).
--
-- Already resolved UPSTREAM in the tables (do NOT re-implement here):
--   pipeline filter, dedup to latest stage, test/duplicate exclusion, timezone,
--   origin / segment / utm_* mapping (consorcio_origin_mapping, consorcio_segment_mapping),
--   analyst / role / supervisor / team as of the deal creation date
--   (consorcio_inside_sales_operation), customer_journey, qualifier_* answers,
--   contact_type + is_abandoned_cart, feedback survey fields, simulation aggregates,
--   and ALL business-day cycle times (business_days_from_created_to_*).
--
-- Materializes the Superset dataset "Funil Cohort - Não Agregado [Consorcio][Fintech]".
-- ============================================================================

SELECT
  -- identity
  d.id_deal,
  d.id_hubspot_owner,
  d.id_device,
  d.uuid_lead,
  d.deal_name,
  d.current_stage,

  -- attribution (from the Growth Attribution sheet)
  d.origin,
  d.utm_source,
  d.utm_medium,
  d.utm_campaign,
  d.utm_content,
  d.utm_term,
  d.segment,
  d.channel_origin,
  d.forms_origin,
  d.customer_journey,

  -- track and ownership (from the Operação IS sheet, as of dt_created)
  d.inside_sales_pipeline,
  d.analyst_name,
  d.analyst_role,
  d.supervisor_name,
  d.team,

  -- deal attributes
  d.lead_priority,
  d.discard_reason,
  d.quota_amount,
  d.installment_type,
  d.deal_amount,
  d.negotiation_value,
  d.bamaq_proposal_codes,

  -- Conrado qualifier answers
  d.qualifier_goal,
  d.qualifier_investment_type,
  d.qualifier_reason,
  d.qualifier_knowledge,
  d.qualifier_urgency,

  -- contact initiation (valid from 2026-08-10)
  d.is_abandoned_cart,
  d.contact_type,
  d.has_blip_agent_inactivity,

  -- discard survey
  d.feedback_score,
  d.feedback_benefits,
  d.feedback_comment,
  d.is_feedback_contact_allowed,

  -- simulation aggregates
  d.total_simulations,
  d.first_simulation_amount,
  d.last_simulation_amount,
  d.avg_simulation_amount,
  d.ts_first_simulated,
  d.ts_last_simulated,

  -- cohort calendar
  d.ts_deal_created,
  d.ts_current_stage_started,
  d.dt_created  AS date,
  d.dt_month_start AS month_start,
  d.dt_week_start  AS week_start,
  d.year,
  d.month,
  d.day,

  -- funnel position (cumulative flags; TC is a branch)
  dm.is_lead,
  dm.is_contact_attempted,
  dm.is_success_contact,
  dm.is_simulation_sent,
  dm.is_simulation_accepted,
  dm.is_offer_under_negotiation,
  dm.is_offer_accepted,
  dm.is_contract_created,
  dm.is_closed_deal,
  dm.is_handoff,
  dm.is_discarded,
  dm.discarded_from_stage,

  -- milestone timestamps (already BRT)
  dm.ts_lead,
  dm.ts_contact_attempt,
  dm.ts_success_contact,
  dm.ts_simulation_sent,
  dm.ts_simulation_accepted,
  dm.ts_offer_under_negotiation,
  dm.ts_offer_accepted,
  dm.ts_contract_created,
  dm.ts_closed_deal,
  dm.ts_discarded,
  dm.ts_handoff,

  -- materialized cycle time: business days from deal creation to each milestone.
  -- NULL (never 0) when the milestone was not reached; 0 means a same-day transition.
  -- For a stage-to-stage window, subtract two of these columns -- see the cohort metric entity.
  dm.business_days_from_created_to_lead,
  dm.business_days_from_created_to_contact_attempt,
  dm.business_days_from_created_to_success_contact,
  dm.business_days_from_created_to_simulation_sent,
  dm.business_days_from_created_to_simulation_accepted,
  dm.business_days_from_created_to_offer_under_negotiation,
  dm.business_days_from_created_to_offer_accepted,
  dm.business_days_from_created_to_contract_created,
  dm.business_days_from_created_to_closed_deal,
  dm.business_days_from_created_to_handoff,
  dm.business_days_from_created_to_discarded,

  -- run-date relative: valid only as of the last rebuild
  dm.aging_opened_leads,
  dm.days_in_current_stage

FROM datalake_consorcio.deal d
INNER JOIN datalake_consorcio.deal_milestone dm
  ON dm.id_deal = d.id_deal
```
