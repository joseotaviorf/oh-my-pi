# Consórcio

## Ownership

**Data Owner:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

**Data Steward:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

## Overview

Consórcio is QuintoAndar's *carta de crédito imobiliário* inside-sales funnel. Analysts use it to measure deal progression from Lead through Closed Deal, attribution, Conrado (AI) vs human tracks, and handoff-to-close performance. The **official source** is `datalake_consorcio.deal` + `datalake_consorcio.deal_milestone` (modelled tables where the funnel business rules are already applied); HubSpot (`datalake_hubspot.*`) and the `datalake_consorcio_clean.*` tables are the upstream raw layers. The cohort consumption layer is the dataset **Funil Cohort - Não Agregado [Consorcio][Fintech]**.

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
10. **Discard**— `is_discarded` / `ts_discarded` (not a conversion step)

Not all deals follow every step: TC is optional (Lead can go straight to SC); Conrado track (`SIMULATOR IA` / `SDR IA`) vs `SDR Humano` changes where handoff starts. Default analytical lens is **cohort by deal creation date** (`date` = `dt_created`). All `ts_*` timestamps already arrive in `America/Sao_Paulo`, and test/duplicate deals are already excluded — both applied in the table build.

## Related Metric Entities

Official Consórcio metric formulas belong in metric-entity docs (not yet published under `docs/llm_context/metric_entities/`). Until those land, treat Key Metrics below as exploratory orientation only — do not invent official conversion formulas here.

- **Consórcio Cohort** — funnel conversion, cycle time, and volumes by deal creation date; reuses this doc's golden query / Funil Cohort dataset.  
- **Consórcio Coincident** — volume entering each stage by that stage's own timestamp (operational load; closed deals by close date). Not derivable from the cohort model.  
- **Consórcio Repescagem** — reactivation metrics on the discarded ↔ `origin = 'repescagem'` linkage dataset.

## Glossary and Synonyms

- **Consórcio** (*carta de crédito imobiliário*) → this entity; sourced from HubSpot pipeline `737631007` (filter already applied in `datalake_consorcio.deal`)  
- **Conrado** → AI agent covering Lead → Simulação Aceita (`consorcio_inside_sales_pipeline = SIMULATOR IA`) and Lead → Simulação (`consorcio_inside_sales_pipeline = SDR IA`)  
- **SIMULATOR IA** → Conrado on Conversational Platform; handoff from Simulação Aceita  
- **SDR IA** → Conrado on Blip; handoff from Simulação; being discontinued  
- **SDR Humano** → human analyst; active for analyst-routed repescagem; handoff from Successful Contact  
- **Handoff** → Conrado → human analyst (`is_handoff` / `ts_handoff`)  
- **Repescagem** → reactivated lead after discard; new deal with `origin = 'repescagem'`  
- **Paid Media** → paid channel rollup: `origin IN ('meta', 'google', 'youtube')`  
- **TC** (*Tentativa de Contato*) → `is_contact_attempted` / `ts_contact_attempt` (branch, not cumulative)  
- **Carrinho abandonado** (*abandoned cart — our nomenclature for the message, unrelated to the `carrinho abandonado` pipeline stage*) → the user did **not** send the first WhatsApp message, so we send the abandoned-cart template. `is_abandoned_cart = 1` ⇒ template sent and the card **moved to Tentativa de Contato (TC)**; if the user replies, it advances to **Contato com Sucesso (SC)**. `is_abandoned_cart = 0` ⇒ the user sent the first message and the deal goes **straight to SC** (no TC). The flag is an **`integer` (1/0)** — the raw string is `abandoned_cart_template_sent`. Surfaced as `contact_type` = `company_initiated` (true) / `user_initiated` (false). Valid from **2026-08-10**.  
- **SC / SS / SA / OUN / OA / CC / CD** → Success Contact = Contato com Sucesso / Simulation Sent = Simulação = Simulação Enviada / Simulation Accepted = Simulação Aceita / Offer Under Negotiation = Proposta em Negociação = Oferta em Negociação / Offer Accepted = Proposta Aceita = Oferta Aceita / Contract Created = Contrato Criado = Contrato Emitido / Closed Deal = Venda = Venda Fechada  
- **Cohort** → metrics grouped by deal creation date (`date` = `dt_created`, local BRT date)  
- **Coincident** → metrics grouped by each stage's own timestamp (separate dataset)  
- **Inside Sales** → operational sales team; usually coincident metrics

## Tables

| You need... | Use this table |
| :---- | :---- |
| **Deal master — official source** (business rules already resolved) | `datalake_consorcio.deal` — 1 row per deal; key `id_deal`; partitions `year` / `month` / `day` |
| **Funnel milestones + cumulative flags** | `datalake_consorcio.deal_milestone` — key `id_deal` (1:1 with `deal`); `is_*` flags and `ts_*` milestones |
| Blip id / external ids | `datalake_consorcio_clean.lead_external_data` — `id_crm = deal.id_deal`; `id_lead = lead.id_lead` |
| Lead detail (source of `uuid_lead`) | `datalake_consorcio_clean.lead` |
| Simulation detail (per-simulation rows) | `datalake_consorcio_clean.simulation` — only for raw rows; `deal` already carries `total_simulations`, `ts_first_simulated`, `ts_last_simulated` |
| Business-day calendar (cycle time / aging) | `dw_public.dim_date` — `is_brz_business_day` |

**Critical rules:**

- **`datalake_consorcio.deal` + `datalake_consorcio.deal_milestone` are the official source.** Join 1:1 on `id_deal`. Do **not** rebuild the funnel from `datalake_hubspot.*` — those are the upstream raw tables.
- **Already resolved in the tables — never re-implement in the query:** pipeline filter (`737631007`), dedup to one row per deal at its latest stage, test/duplicate exclusion, timezone conversion, `origin` / `segment` / `utm_*` mapping, `customer_journey`, the `qualifier_*` answers, `contact_type` / `is_abandoned_cart`, the feedback-survey fields, and the simulation aggregates.
- **All `ts_*` columns are already converted to `America/Sao_Paulo` (BRT)** in the table build — they are `timestamp(3) with time zone` in local time. Never wrap them in `AT_TIMEZONE(...)` again; doing so shifts them a second time. The `dt_*` / `date` columns are already the local calendar date.
- **Lead anchor:** all `days_to_convert_from_lead_to_*` measures start at **`ts_lead`** (the Lead milestone), not `ts_deal_created`. `aging_opened_leads` and `days_in_current_stage` are the exceptions by design — they run from `ts_deal_created` / `ts_current_stage_started` to *today*.
- **The only thing still computed in the query** is business-day cycle time / aging via `dw_public.dim_date`.
- **Analyst attribution comes from the table:** `deal.analyst_name`, `deal.analyst_role`, `deal.supervisor_name`. No inline roster CTE — the old `operational_data` map is gone.
- **Validity windows:** `OUN` / `CC` milestones only from **2026-07-20**; `contact_type` / `is_abandoned_cart` only from **2026-08-10** (NULL before).
- Contact fields arrive **already hashed** from the source — usable as join keys, no readable contact data. (Exception: `lead_external_data.id_bsp_contact` is **not** hashed.)
- ⚠️ **DataHub's column types for these two tables are stale** — it reports all fields as `VARCHAR`. The real Trino types are `integer` for the `is_*` flags and `deal_amount`, `bigint` for `id_deal` / `total_simulations`, `timestamp(3) with time zone` for `ts_*`, and `date` for `dt_*`. Trust the table, not the catalog metadata, until ingestion is refreshed.

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) when asking for an **official** conversion or reactivation number. Below is exploratory orientation only.

- **Funnel volumes** — deals per stage (`is_lead` … `is_closed_deal`)  
- **Conversion rates** — stage-to-stage ratios (Lead→SC, SS→CD, handoff→CD), usually cohort by `date`  
- **Cycle time (business days)** — `days_to_convert_from_*` via `dw_public.dim_date` (`is_brz_business_day`)  
- **Lead aging** — open business days since creation (`aging_opened_leads`)  
- **Simulation activity** — `total_simulations`, `ts_first_simulated` / `ts_last_simulated`  
- **Operational performance** — handoff → CD (SS→CD for SDR IA; SA→CD for SIMULATOR IA)  
- **Contact-initiation mix** — `contact_type` + `is_contact_attempted`  
- **Attribution mix** — `origin` / `segment/utm_*` ; Paid Media = Meta + Google + YouTube  
- **Repescagem** — reactivation metrics (separate dataset + metric entity)

**Cohort vs coincident:** cohort (this doc) anchors on deal creation date — right for conversion. Coincident counts by each stage's timestamp — right for operational load. Same metric name, different volumes (e.g. closed deals in July).

## Relationships with Other Entities

### Deal → Deal milestones (1:1)

- `datalake_consorcio.deal.id_deal = datalake_consorcio.deal_milestone.id_deal`  
- `deal` holds descriptive attributes; `deal_milestone` holds the funnel `is_*` flags and `ts_*` milestones. `INNER JOIN` — a deal always has a milestone row.

### Deal → Lead external data (1:1) — Blip id

- `datalake_consorcio_clean.lead_external_data.id_crm = CAST(datalake_consorcio.deal.id_deal AS VARCHAR)` — the HubSpot deal id is `id_crm` there. **`id_crm` is `varchar` while `deal.id_deal` is `bigint` — CAST or the join fails.** `id_crm` is also nullable (a lead may have no CRM deal yet).  
- `datalake_consorcio_clean.lead_external_data.id_lead = datalake_consorcio_clean.lead.id_lead` (both `bigint`).  
- **Blip ids:** `id_bsp_contact` (the Blip/WhatsApp contact) and `id_bsp_conversation` (the conversation). ⚠️ `id_bsp_contact` frequently carries the **raw phone number** (`55119…@wa.gw.msging.net`) — unhashed contact data, unlike the hashed `email`/`phone_number` fields. Keep it out of shared outputs.

### Deal → Lead (N:1)

- `datalake_consorcio_clean.lead.uuid = datalake_consorcio.deal.uuid_lead`  
- Only needed for lead attributes not already denormalized onto `deal` (`customer_journey` is already there).

### Lead → Simulation (1:N → aggregate to 1:1)

- `datalake_consorcio_clean.simulation.id_lead = datalake_consorcio_clean.lead.id`  
- Aggregate before joining. `deal` already exposes `total_simulations` / `ts_first_simulated` / `ts_last_simulated`, so go to `simulation` only for per-simulation detail.

### Deal milestones → dim_date (for cycle time)

- Compare milestone dates to `dw_public.dim_date.date` with `is_brz_business_day = TRUE` for business-day spans.

### Repescagem (out of scope here)

- Conversion of a repescagem deal through the funnel: this entity + the cohort metric entity.  
- Measurement that links a discarded deal to a later `origin = 'repescagem'` deal lives in the repescagem metric entity / dataset, not this cohort model.

## Dos and Don'ts

**Do:**

- Read from `datalake_consorcio.deal` joined 1:1 to `datalake_consorcio.deal_milestone` on `id_deal` — the pipeline filter, dedup and test/duplicate exclusion are already applied upstream.  
- Scope queries with the `year` / `month` / `day` partitions (or `dt_created`) — timezone conversion and test/duplicate exclusion are already done upstream.  
- Use `datalake_consorcio_clean.lead_external_data` (`id_crm = deal.id_deal`) to reach the Blip id.  
- Read TC passage from `is_contact_attempted` / `ts_contact_attempt` (the authoritative stage flag); read contact initiation from `is_abandoned_cart` / `contact_type` (valid from 2026-08-10 only).  
- Take analyst attribution from the table's own `analyst_name` / `analyst_role` / `supervisor_name`.  
- State cohort vs coincident explicitly when reporting volumes.

**Don't:**

- Treat `is_contact_attempted` as cumulative — TC is a branch; some deals go Lead → SC directly.  
- Infer TC passage from `contact_type` alone — it means who initiated contact, not stage passage.  
- Re-implement upstream rules (pipeline filter, dedup, origin/segment mapping, qualifier explosion) in the query — they are already in the table.  
- Treat `total_simulations = 0` outside `SIMULATOR IA` as missing data.  
- Derive a coincident view from this cohort model — use the coincident dataset/query.  
- Put repescagem linkage measurement or official conversion formulas in this doc — those belong in metric entities.

## Golden Queries

### Query 1 — Deal-grain cohort base (canonical)

One row per Consórcio deal at its latest stage, read from the **official source** `datalake_consorcio.deal` + `datalake_consorcio.deal_milestone`: descriptive attributes, funnel milestones, cumulative stage flags (TC as a branch), attribution, contact initiation, feedback survey, simulation aggregates — plus the business-day cycle-time measures computed here. Anchor cohort analyses on `date` (= `dt_created`). Materializes the Superset dataset **`Funil Cohort - Não Agregado [Consorcio][Fintech]`**.

Business rules that used to live in this query now live in the table build — the query is much thinner as a result. Analyst attribution comes straight from `deal.analyst_name` / `analyst_role` / `supervisor_name`, so no inline roster is needed.

**Lead anchor (official definition):** every `days_to_convert_from_lead_to_*` measure — including `days_to_convert_from_lead_to_sc` — is anchored on **`ts_lead`** (the Lead milestone in `deal_milestone`), never on `ts_deal_created`. The two coincide in practice (validated on the July 2026 cohort: 43,592 deals with SC, 100% with the same calendar date and no null `ts_lead`), but `ts_lead` is the milestone that defines the stage, so it is the single anchor for all lead-anchored cycle-time measures.

```sql
-- ============================================================================
-- Consórcio — Golden Query (cohort model, deal grain)
-- OFFICIAL SOURCE: datalake_consorcio.deal (d) + datalake_consorcio.deal_milestone (dm),
-- joined 1:1 on id_deal. Catalog: delta. Cohort view (anchor on `date` = dt_created).
--
-- Already resolved UPSTREAM in the tables (do NOT re-implement here):
--   pipeline filter, dedup to latest stage, test/duplicate exclusion, timezone,
--   origin / segment / utm_* mapping, customer_journey, qualifier_* answers,
--   contact_type + is_abandoned_cart, feedback survey fields, simulation aggregates.
-- The ONLY thing computed here is business-day cycle time / aging via dw_public.dim_date.
--
-- Analyst attribution (analyst_name / analyst_role / supervisor_name) comes from the table --
-- no inline roster CTE needed.
--
-- Materializes the Superset dataset "Funil Cohort - Não Agregado [Consorcio][Fintech]".
-- ============================================================================

with
deals as (SELECT
    d.id_deal,
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
  d.ts_deal_created,
  d.dt_created as date,
  d.dt_month_start as month_start,
  d.dt_week_start as week_start,
  d.year,
  d.month,
  d.day,
  d.ts_current_stage_started,
  d.ts_first_simulated,
  d.ts_last_simulated,
  dm.discarded_from_stage,
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
  dm.ts_handoff
FROM datalake_consorcio.deal d
inner join datalake_consorcio.deal_milestone dm
  on dm.id_deal = d.id_deal
)
Select
  *,
  CASE
    WHEN d.is_lead = 1 AND d.current_stage NOT IN ('venda fechada','descarte','carrinho_abandonado') THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_deal_created AS DATE)
          AND c.date <= CAST(CURRENT_DATE - INTERVAL '1' DAY AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS aging_opened_leads,
  GREATEST(0, (
    SELECT COUNT(*)
    FROM dw_public.dim_date c
    WHERE c.date >= CAST(d.ts_current_stage_started AS DATE)
      AND c.date <= CAST(CURRENT_DATE - INTERVAL '1' DAY AS DATE)
      AND c.is_brz_business_day = TRUE) - 1)
  AS days_in_current_stage,
  -- Lead anchor is ts_lead for every lead-anchored measure (official definition).
  CASE
    WHEN d.is_lead = 1 AND d.is_success_contact = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_lead AS DATE)
          AND c.date <= CAST(d.ts_success_contact AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_lead_to_sc,
  CASE
    WHEN d.is_lead = 1 AND d.is_simulation_sent = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_lead AS DATE)
          AND c.date <= CAST(d.ts_simulation_sent AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_lead_to_ss,
  CASE
    WHEN d.is_lead = 1 AND d.is_simulation_accepted = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_lead AS DATE)
          AND c.date <= CAST(d.ts_simulation_accepted AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_lead_to_sa,
  CASE
    WHEN d.is_lead = 1 AND d.is_offer_under_negotiation = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_lead AS DATE)
          AND c.date <= CAST(d.ts_offer_under_negotiation AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_lead_to_oun,
  CASE
    WHEN d.is_lead = 1 AND d.is_offer_accepted = 1 THEN
      GREATEST(0, (
      SELECT COUNT(*)
      FROM dw_public.dim_date c
      WHERE c.date >= CAST(d.ts_lead AS DATE)
        AND c.date <= CAST(d.ts_offer_accepted AS DATE)
        AND c.is_brz_business_day = TRUE)
    - 1)
  END AS days_to_convert_from_lead_to_oa,
  CASE
    WHEN d.is_lead = 1 AND d.is_contract_created = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_lead AS DATE)
          AND c.date <= CAST(d.ts_contract_created AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_lead_to_cc,
  CASE
    WHEN d.is_lead = 1 AND d.is_closed_deal = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_lead AS DATE)
          AND c.date <= CAST(d.ts_closed_deal AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_lead_to_cd,
  CASE
    WHEN d.is_lead = 1 AND d.is_handoff = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_lead AS DATE)
          AND c.date <= CAST(d.ts_handoff AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_lead_to_handoff,
  CASE
    WHEN d.is_simulation_sent = 1 AND d.is_closed_deal = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_simulation_sent AS DATE)
          AND c.date <= CAST(d.ts_closed_deal AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_ss_to_cd,
  CASE
    WHEN d.is_simulation_accepted = 1 AND d.is_closed_deal = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_simulation_accepted AS DATE)
          AND c.date <= CAST(d.ts_closed_deal AS DATE)
          AND c.is_brz_business_day = TRUE)
    - 1)
  END AS days_to_convert_from_sa_to_cd,
  CASE
    WHEN d.is_simulation_accepted = 1 AND d.is_offer_under_negotiation = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_simulation_accepted AS DATE)
          AND c.date <= CAST(d.ts_offer_under_negotiation AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_sa_to_oun,
  CASE
    WHEN d.is_offer_under_negotiation = 1 AND d.is_offer_accepted = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_offer_under_negotiation AS DATE)
          AND c.date <= CAST(d.ts_offer_accepted AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_oun_to_oa,
  CASE
    WHEN d.is_offer_accepted = 1 AND d.is_contract_created = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_offer_accepted AS DATE)
          AND c.date <= CAST(d.ts_contract_created AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_oa_to_cc,
  CASE
    WHEN d.is_contract_created = 1 AND d.is_closed_deal = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_contract_created AS DATE)
          AND c.date <= CAST(d.ts_closed_deal AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_cc_to_cd,
  CASE
    WHEN d.is_simulation_accepted = 1 AND d.is_offer_accepted = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_simulation_accepted AS DATE)
          AND c.date <= CAST(d.ts_offer_accepted AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_sa_to_oa,
  CASE
    WHEN d.is_offer_accepted = 1 AND d.is_closed_deal = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_offer_accepted AS DATE)
          AND c.date <= CAST(d.ts_closed_deal AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
  END AS days_to_convert_from_oa_to_cd,
  CASE
    WHEN d.is_handoff = 1 AND d.is_closed_deal = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_handoff AS DATE)
          AND c.date <= CAST(d.ts_closed_deal AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_handoff_to_cd,
  CASE
    WHEN d.is_simulation_sent = 1 AND d.is_simulation_accepted = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_simulation_sent AS DATE)
          AND c.date <= CAST(d.ts_simulation_accepted AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_ss_to_sa,
  CASE
    WHEN d.is_success_contact = 1 and d.is_simulation_sent = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_success_contact AS DATE)
          AND c.date <= CAST(d.ts_simulation_sent AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_sc_to_ss,
  CASE
    WHEN d.is_success_contact = 1 and d.is_offer_accepted = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_success_contact AS DATE)
          AND c.date <= CAST(d.ts_offer_accepted AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_sc_to_oa,
  CASE
    WHEN d.is_success_contact = 1 and d.is_closed_deal = 1 THEN
      GREATEST(0, (
        SELECT COUNT(*)
        FROM dw_public.dim_date c
        WHERE c.date >= CAST(d.ts_success_contact AS DATE)
          AND c.date <= CAST(d.ts_closed_deal AS DATE)
          AND c.is_brz_business_day = TRUE)
      - 1)
    ELSE NULL
  END AS days_to_convert_from_sc_to_cd
from deals d
```
