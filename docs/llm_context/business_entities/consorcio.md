# Consórcio

## Ownership

**Data Owner:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

**Data Steward:**

- [conrado.fabri@quintoandar.com.br](mailto:conrado.fabri@quintoandar.com.br)

## Overview

Consórcio is QuintoAndar's *carta de crédito imobiliário* inside-sales funnel. Analysts use it to measure deal progression from Lead through Closed Deal, attribution, Conrado (AI) vs human tracks, and handoff-to-close performance. Data comes from HubSpot CRM (`datalake_hubspot.*`) plus Consórcio clean tables; the cohort consumption layer is the dataset **Funil Cohort \- Não Agregado \[Consorcio\]\[Fintech\]**.

**Grain:** one row per deal at its latest stage — enforce latest `ts_stage_started` (`rn = 1`) and `COALESCE(consorcio_deal_duplicado, 'unique') = 'unique'`.

**Mandatory domain filter:** `deal_stage.id_pipeline = 737631007`.

Funnel (from Lead onward; Page View → Lead / Consentimento → Lead are out of scope):

1. **Lead** — `is_lead` / `ts_lead`  
2. **Contact Attempt (TC)** — branch, not cumulative (`is_tc` / `ts_contact_attempt`)  
3. **Successful Contact (SC)** — `is_sc` / `ts_success_contact`  
4. **Simulation sent (SS)** — HubSpot label lowercased as `simulação` (`is_ss` / `ts_simulation_sent`)  
5. **Simulation accepted (SA)** — `is_sa` / `ts_simulation_accepted`  
6. **Offer under negotiation (OUN)** — `is_oun` / `ts_offer_under_negotiation`  
7. **Offer Accepted (OA)** — `is_oa` / `ts_offer_accepted`  
8. **Contract Created (CC)** — `is_cc` / `ts_contract_created`  
9. **Closed Deal (CD)** — `is_cd` / `ts_closed_deal`  
10. **Discard**— `is_discarted` / `ts_discarted` (not a conversion step)

Not all deals follow every step: TC is optional (Lead can go straight to SC); Conrado track (`SIMULATOR IA` / `SDR IA`) vs `SDR Humano` changes where handoff starts. Default analytical lens is **cohort by deal creation date** (`date = date(ts_deal_created)`). Timezone `America/Sao_Paulo`; exclude test deals (`deal_name NOT LIKE '%Teste%'` / `'%test%'`).

## Related Metric Entities

Official Consórcio metric formulas belong in metric-entity docs (not yet published under `docs/llm_context/metric_entities/`). Until those land, treat Key Metrics below as exploratory orientation only — do not invent official conversion formulas here.

- **Consórcio Cohort** — funnel conversion, cycle time, and volumes by deal creation date; reuses this doc's golden query / Funil Cohort dataset.  
- **Consórcio Coincident** — volume entering each stage by that stage's own timestamp (operational load; closed deals by close date). Not derivable from the cohort model.  
- **Consórcio Repescagem** — reactivation metrics on the discarded ↔ `origin = 'repescagem'` linkage dataset.

## Glossary and Synonyms

- **Consórcio** (*carta de crédito imobiliário*) → this entity; HubSpot pipeline `id_pipeline = 737631007`  
- **Conrado** → AI agent covering Lead → Simulação Aceita (`consorcio_inside_sales_pipeline = SIMULATOR IA`) and Lead → Simulação (`consorcio_inside_sales_pipeline = SDR IA`)  
- **SIMULATOR IA** → Conrado on Conversational Platform; handoff from Simulação Aceita  
- **SDR IA** → Conrado on Blip; handoff from Simulação; being discontinued  
- **SDR Humano** → human analyst; active for analyst-routed repescagem; handoff from Successful Contact  
- **Handoff** → Conrado → human analyst (`is_handoff` / `ts_handoff`)  
- **Repescagem** → reactivated lead after discard; new deal with `origin = 'repescagem'`  
- **Paid Media** → paid channel rollup: `origin IN ('meta', 'google', 'youtube')`  
- **TC** (*Tentativa de Contato*) → `is_tc` / `ts_contact_attempt` (branch, not cumulative)  
- **C2W** (*Click-to-WhatsApp*) → `consorcio_c2w_message` → `contact_type` (`user_initiated` vs `company_initiated`); does **not** mean TC passage. When null, company\_initiated the message → deal was moved to TC. When not null, user\_initiated.  
- **SC / SS / SA / OUN / OA / CC / CD** → Success Contact \= Contato com Sucesso / Simulation Sent \= Simulação \= Simulação Enviada / Simulation Accepted \= Simulação Aceita / Offer Under Negotiation \= Proposta em Negociação \= Oferta em Negociação / Offer Accepted \= Proposta Aceita \= Oferta Aceita / Contract Created \= Contrato Criado \= Contrato Emitido / Closed Deal \= Venda \= Venda Fechada  
- **Cohort** → metrics grouped by deal creation date (`date`)  
- **Coincident** → metrics grouped by each stage's own timestamp (separate dataset)  
- **Inside Sales** → operational sales team; usually coincident metrics

## Tables

| You need... | Use this table |
| :---- | :---- |
| Deal master \+ Consórcio HubSpot properties | `datalake_hubspot.deal` — `consorcio_*` fields; join key `id_deal` |
| Stage-transition history | `datalake_hubspot.deal_stage` — filter `id_pipeline = 737631007`; `ts_stage_started` / `ts_stage_ended` |
| Stage catalog (id → label) | `datalake_hubspot.stage` — `id_stage` → `label` |
| Lead enrichment (customer journey JSON) | `datalake_consorcio_clean.lead` — `lead.uuid = deal.consorcio_id_lead` |
| Simulations (N per lead) | `datalake_consorcio_clean.simulation` — pre-aggregate to lead grain; `simulation.id_lead = lead.id` |
| Analyst name | `datalake_hubspot_clean.owner` — dedup to 1:1 per `id_owner`; join `CAST(deal.id_hubspot_owner AS VARCHAR)` |
| Business-day calendar (cycle time / aging) | `dw_public.dim_date` — `is_brz_business_day` |

**Critical rules:**

- Always filter `datalake_hubspot.deal_stage.id_pipeline = 737631007`.  
- Deal grain: latest stage only (`ROW_NUMBER() … ORDER BY ts_stage_started DESC` → `rn = 1`) and `COALESCE(consorcio_deal_duplicado, 'unique') = 'unique'`.  
- Pre-aggregate `datalake_consorcio_clean.simulation` before join (N:1 to lead); never join raw.  
- Dedup `datalake_hubspot_clean.owner` to one row per `id_owner` (Consórcio team scope \+ non-null name) before join; CAST the join key.  
- Customer PII (`consorcio_email`, `consorcio_phone_number*`) is intentionally excluded — keep it out of outputs.  
- Inline maps `origin_mapping` / `segment_mapping` / `analyst_ops` are maintained by design in the golden query (no parameter table).

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) when asking for an **official** conversion or reactivation number. Below is exploratory orientation only.

- **Funnel volumes** — deals per stage (`is_lead` … `is_cd`)  
- **Conversion rates** — stage-to-stage ratios (Lead→SC, SS→CD, handoff→CD), usually cohort by `date`  
- **Cycle time (business days)** — `days_to_convert_from_*` via `dw_public.dim_date` (`is_brz_business_day`)  
- **Lead aging** — open business days since creation (`aging_lead`)  
- **Simulation activity** — `total_simulations`, `first_simulation_at` / `last_simulation_at`  
- **Operational performance** — handoff → CD (SS→CD for SDR IA; SA→CD for SIMULATOR IA)  
- **Contact-initiation mix** — `contact_type` \+ `is_tc`  
- **Attribution mix** — `origin` / `segment/utm_*` ; Paid Media \= Meta \+ Google \+ YouTube  
- **Repescagem** — reactivation metrics (separate dataset \+ metric entity)

**Cohort vs coincident:** cohort (this doc) anchors on deal creation date — right for conversion. Coincident counts by each stage's timestamp — right for operational load. Same metric name, different volumes (e.g. closed deals in July).

## Relationships with Other Entities

### Deal → Deal stage history (1:N)

- `datalake_hubspot.deal.id_deal = datalake_hubspot.deal_stage.id_deal`  
- Restrict stages with `deal_stage.id_pipeline = 737631007`, then collapse to deal grain (`rn = 1`).

### Deal → Lead (N:1)

- `datalake_consorcio_clean.lead.uuid = datalake_hubspot.deal.consorcio_id_lead`  
- Lead `metadata` JSON: `json_extract_scalar(metadata, '$.customerJourney')` → `customer_journey`.

### Lead → Simulation (1:N → aggregate to 1:1)

- `datalake_consorcio_clean.simulation.id_lead = datalake_consorcio_clean.lead.id`  
- Aggregate first: `MIN/MAX(ts_created)`, `COUNT(*)` as `total_simulations`. `0` simulations outside `SIMULATOR IA` is expected.

### Deal → Owner / analyst ops (N:1)

- `CAST(deal.id_hubspot_owner AS VARCHAR) = owner.id_owner`  
- Owner has multiple rows / null names per `id_owner` — dedup before join. Role/supervisor (`analyst_ops`) is an inline VALUES map keyed by `id_owner`.

### Deal milestones → dim\_date (for cycle time)

- Compare milestone dates to `dw_public.dim_date.date` with `is_brz_business_day = TRUE` for business-day spans.

### Repescagem (out of scope here)

- For measurement of conversions from lead to closed deal, use this and the cohort metric entity.   
- Measurement that needs linking to a discarded deal to a later `origin = 'repescagem'` deal — lives in the repescagem metric entity / dataset, not this cohort model.

## Dos and Don'ts

**Do:**

- Filter `datalake_hubspot.deal_stage.id_pipeline = 737631007` on every Consórcio query.  
- Dedup to deal grain (`rn = 1` \+ `COALESCE(consorcio_deal_duplicado, 'unique') = 'unique'`).  
- Convert timestamps with `AT_TIMEZONE(..., 'America/Sao_Paulo')` and drop test deals (`deal_name NOT LIKE '%Teste%'` / `'%test%'`).  
- Pre-aggregate `datalake_consorcio_clean.simulation` to lead grain before joining.  
- Dedup `datalake_hubspot_clean.owner` to 1:1 and `CAST` the join to `id_hubspot_owner`.  
- Read TC passage from `is_tc` / `ts_contact_attempt`, not from `consorcio_c2w_message`.  
- Keep inline `origin_mapping`, `segment_mapping`, and `analyst_ops` current as campaigns/team change.  
- State cohort vs coincident explicitly when reporting volumes.

**Don't:**

- Treat `is_tc` as cumulative — TC is a branch; some deals go Lead → SC directly.  
- Infer TC passage from `consorcio_c2w_message` / `contact_type` alone (C2W \= who initiated contact).  
- Join raw `simulation` or undeduped `owner` (fans out deal grain).  
- Treat `total_simulations = 0` outside `SIMULATOR IA` as missing data.  
- Derive a coincident view from this cohort model — use the coincident dataset/query.  
- Put repescagem linkage measurement or official conversion formulas in this doc — those belong in metric entities.

## Golden Queries

### Query 1 — Deal-grain cohort base (canonical)

One row per Consórcio deal at its latest stage: milestones, cumulative stage flags (TC as branch), attribution, handoff, C2W, and simulation aggregates. Anchor analyses on `date` (deal creation). Expand business-day cycle-time measures with `dw_public.dim_date` as needed, or use the Consórcio Cohort metric entity when published.

Inline maps `segment_mapping` and `analyst_ops` are maintained by design (LEFT-joined — NULLs when unmapped). Adjust the creation-date filter for cheaper runs.

```sql
-- ============================================================================
-- Consórcio — Golden Query (cohort model, deal grain)
-- One row per deal at its latest stage: milestones, cumulative stage flags,
-- attribution, ownership, C2W, qualifier answers, and business-day cycle time.
-- Catalog: delta. Cohort view (anchored on deal creation date `date`).
--
-- FULLY EXECUTABLE. Two maintained-by-design spots to keep current:
--   * segment_mapping  -> add new campaigns as they launch
--   * analyst_ops      -> role/supervisor per id_owner (take id_owner from owner_name)
-- Both are LEFT-joined, so the query runs even if a value is missing (NULL).
-- Tip: add a creation-date filter in stages_adjusted for cheaper runs.
-- ============================================================================

WITH origin_mapping AS (
    -- utm_source -> origin channel. Maintained manually inline (by design); unmapped -> Others/Direct.
    SELECT * FROM (VALUES
        ('newsletter','Internal'), ('none','Direct'), ('internal','Internal'),
        ('crm','CRM'), ('insidesales','Internal'), ('google','Google'),
        ('youtube','youtube'), ('referral','Internal'), ('fb','Meta'),
        ('ig','Meta'), ('{{site_source_name}}','Meta'), ('(none)','Direct'),
        ('instagram','Meta'), ('imovelweb','Imovelweb'), ('buzzlead','Others'),
        ('(Nenhum valor)','Direct'), ('TikTok','Others'), ('qa_consorcio_lp','C2W'),
        ('display','Meta'), ('repescagem','repescagem'), ('sfmc','crm')
    ) AS t(utm_source, origin)
),

segment_mapping AS (
    -- utm_campaign -> segment. Maintained manually inline (by design); add new campaigns here.
    SELECT * FROM (VALUES
        ('consorcio_launch___ED_Institucional_EX','Branded'),
        ('sitelinks_branded_consorcio','Branded'),
        ('comunicacao__lançamento','Branded'),
        ('consorcio_launch___ED_Institucional_FR','Branded'),
        ('RJ_BRANDED','Branded'), ('SP_BRANDED','Branded'),
        ('FLN_BRANDED','Branded'), ('POA_branded','Branded'),
        ('consorcio_launch___ED_Concorrentes_AM','Non-Branded'),
        ('consorcio_launch___ED_Consorcio_de_Casa_AM','Non-Branded'),
        ('consorcio_launch___ED_Carta_de_Credito_AM','Non-Branded'),
        ('consorcio_launch___ED_Consorcio_de_Imoveis_AM','Non-Branded'),
        ('consorcio_launch___ED_Consorcio_Imobiliario_AM','Non-Branded'),
        ('consorcio_launch___ED_Investimento_AM','Non-Branded'),
        ('consorcio_launch___ED_Planejamento_Financeiro_AM','Non-Branded'),
        ('consorcio_launch___ED_Taxa_de_Administracao_AM','Non-Branded'),
        ('[ED] Institucional_EX','Search Branded'),
        ('[ED] Institucional_FR','Search Branded'),
        ('[ED] Concorrentes_AM','Search Non Branded'),
        ('[ED] Carta de Crédito_AM','Search Non Branded'),
        ('[ED] Consórcio Imobiliário_AM','Search Non Branded'),
        ('[ED] Consórcio de Casa_AM','Search Non Branded'),
        ('[ED] Investimento_AM','Search Non Branded'),
        ('[ED] Consórcio de Imóveis_AM','Search Non Branded'),
        ('[ED] Planejamento Financeiro_AM','Search Non Branded'),
        ('[ED] Taxa de Administração_AM','Search Non Branded'),
        ('[ED] Consórcio+Valor_AM','Search Non Branded'),
        ('[ED] Concorrentes_EX','Search Non Branded'),
        ('[ED] PMáx - Consórcio','Google PMAX'),
        ('consorcio_launch___ED_PMáx_Consórcio','Google PMAX'),
        ('[ED] YouTube - Demand Gen - SP + PortoAlegre','YouTube'),
        ('[ED] display_aquisição_consorcio','Meta Ads'),
        ('[ED]ASC/amplo_consorcio_launch','Meta Ads'),
        ('[ED] display_remarketing_consorcio','Meta Ads')
    ) AS t(utm_campaign, segment)
),

-- Analyst name: DISTINCT + name filter + Consorcio-team scope, then GROUP BY id_owner
-- (MAX name) to force exactly 1 row per id_owner (historical name spellings otherwise fan out).
owner_name AS (
    SELECT id_owner, MAX(analyst_name) AS analyst_name
    FROM (
        SELECT DISTINCT
            id_owner,
            first_name || ' ' || last_name AS analyst_name
        FROM datalake_hubspot_clean.owner
        WHERE element_at(teams, 1).name LIKE '%Consorcio%'
          AND first_name IS NOT NULL
          AND first_name <> ''
    )
    GROUP BY id_owner
),

-- Role + supervisor, maintained MANUALLY inline (by design; no table), keyed by id_owner.
-- To onboard a new analyst: take their id_owner from owner_name's output and append a row.
analyst_ops AS (
    SELECT * FROM (VALUES
        ('83834497','Senior','Beatriz'),
        ('84909664','Pleno','Erick'),
        ('81197710','Junior','Bianca'),
        ('83834581','Senior','n/a'),
        ('84909665','Pleno','n/a'),
        ('84864479','Pleno','Bianca'),
        ('84050436','Senior','Erick'),
        ('84050487','Pleno','Erick'),
        ('83263494','Pleno','n/a'),
        ('82473891','Senior','Erick'),
        ('86362795','Pleno','Beatriz'),
        ('85434798','Senior','Bianca'),
        ('83834547','Senior','Erick'),
        ('85655480','Pleno','Erick'),
        ('83263457','Pleno','Beatriz'),
        ('83777915','Senior','n/a'),
        ('85321623','Pleno','Bianca'),
        ('84050586','Pleno','Erick'),
        ('81552418','Senior','Beatriz'),
        ('85180360','Pleno','n/a'),
        ('85180405','Senior','Bianca'),
        ('84050544','Senior','Erick'),
        ('85434858','Pleno','Beatriz'),
        ('80570949','Senior','n/a'),
        ('85325992','Pleno','Bianca'),
        ('85321594','Pleno','Beatriz'),
        ('82032559','Pleno','n/a'),
        ('83263567','Pleno','Beatriz'),
        ('82467411','Senior','Beatriz'),
        ('90624808','Senior','Erick'),
        ('90628391','Pleno','Bianca'),
        ('90728482','Pleno','Erick'),
        ('81556428','Senior','Bianca'),
        ('84306295','Senior','Bamaq'),
        ('85173258','Senior','Bamaq'),
        ('84306345','Senior','Bamaq'),
        ('92712595','Pleno','Bianca'),
        ('93485724','Pleno','Beatriz')
        -- add/update one row per id_owner as the team changes (id_owner from owner_name)
    ) AS t(id_owner, role, supervisor)
),

-- Collapse N simulations per lead to lead grain.
simulation_agg AS (
    SELECT
        id_lead,
        MIN(ts_created) AS first_simulation_at,
        MAX(ts_created) AS last_simulation_at,
        COUNT(*)        AS total_simulations
    FROM datalake_consorcio_clean.simulation
    GROUP BY 1
),

base_all AS (
    SELECT
        ds.id_deal, ds.id_stage, LOWER(s.label) AS stage_name, ds.id_pipeline,
        d.id_hubspot_owner, ds.source_type, ds.days_in_stage,
        AT_TIMEZONE(d.ts_created, 'America/Sao_Paulo')        AS ts_deal_created,
        AT_TIMEZONE(ds.ts_stage_started, 'America/Sao_Paulo') AS ts_stage_started,
        AT_TIMEZONE(ds.ts_stage_ended, 'America/Sao_Paulo')   AS ts_stage_ended,
        d.consorcio_id_lead AS id_lead, d.consorcio_id_device AS id_device,
        d.deal_name,
        d.consorcio_utm_source AS utm_source, d.consorcio_utm_medium AS utm_medium,
        d.consorcio_utm_campaign AS utm_campaign, d.consorcio_utm_content AS utm_content,
        d.consorcio_utm_term AS utm_term,
        d.consorcio_template_first_contact, d.consorcio_template_last_contact,
        d.consorcio_inside_sales_pipeline, d.consorcio_discard_reason,
        d.consorcio_forms_origin, d.consorcio_lead_priority,
        d.consorcio_quota_amount, d.consorcio_installment_type,
        d.consorcio_channel_origin, d.consorcio_deal_duplicado AS is_duplicated,
        d.consorcio_conrado_qualificador_responses, d.consorcio_c2w_message, d.amount,
        json_extract_scalar(l.metadata, '$.customerJourney') AS customer_journey,
        NULLIF(json_extract_scalar(d.consorcio_conrado_qualificador_responses, '$.goal'), '')           AS qualifier_goal,
        NULLIF(json_extract_scalar(d.consorcio_conrado_qualificador_responses, '$.investmentType'), '') AS qualifier_investment_type,
        NULLIF(json_extract_scalar(d.consorcio_conrado_qualificador_responses, '$.reason'), '')          AS qualifier_reason,
        NULLIF(json_extract_scalar(d.consorcio_conrado_qualificador_responses, '$.knowledge'), '')       AS qualifier_knowledge,
        NULLIF(json_extract_scalar(d.consorcio_conrado_qualificador_responses, '$.urgency'), '')         AS qualifier_urgency,
        sim.first_simulation_at,
        sim.last_simulation_at,
        COALESCE(sim.total_simulations, 0) AS total_simulations,
        -- customer PII (email, phone) intentionally omitted from the model.
        ROW_NUMBER() OVER (PARTITION BY ds.id_deal ORDER BY ds.ts_stage_started DESC) AS rn,
        LAG(LOWER(s.label)) OVER (PARTITION BY ds.id_deal ORDER BY ds.ts_stage_started) AS last_stage
    FROM datalake_hubspot.deal_stage ds
    INNER JOIN datalake_hubspot.stage s ON s.id_stage = ds.id_stage
    INNER JOIN datalake_hubspot.deal  d ON d.id_deal  = ds.id_deal
    LEFT JOIN datalake_consorcio_clean.lead l   ON l.uuid      = d.consorcio_id_lead
    LEFT JOIN simulation_agg                sim ON sim.id_lead = l.id
    WHERE ds.id_pipeline = 737631007
),

deal_milestones AS (
    SELECT
        id_deal,
        MIN(CASE WHEN stage_name = 'leads'                    THEN ts_stage_started END) AS ts_lead,
        MIN(CASE WHEN stage_name = 'tentativa de contato'     THEN ts_stage_started END) AS ts_contact_attempt,
        MIN(CASE WHEN stage_name = 'contato com sucesso'      THEN ts_stage_started END) AS ts_success_contact,
        MIN(CASE WHEN stage_name = 'simulação'                THEN ts_stage_started END) AS ts_simulation_sent,
        MIN(CASE WHEN stage_name = 'simulação aceita'         THEN ts_stage_started END) AS ts_simulation_accepted,
        MIN(CASE WHEN stage_name = 'proposta em negociação'   THEN ts_stage_started END) AS ts_offer_under_negotiation,
        MIN(CASE WHEN stage_name = 'proposta aceita'          THEN ts_stage_started END) AS ts_offer_accepted,
        MIN(CASE WHEN stage_name = 'agendamento de pagamento' THEN ts_stage_started END) AS ts_agendamento_started,
        MIN(CASE WHEN stage_name = 'contrato emitido'         THEN ts_stage_started END) AS ts_contract_created,
        MIN(CASE WHEN stage_name = 'venda fechada'            THEN ts_stage_started END) AS ts_closed_deal,
        MIN(CASE WHEN stage_name = 'descarte'                 THEN ts_stage_started END) AS ts_discarted
    FROM base_all
    GROUP BY 1
),

stages_adjusted AS (
    SELECT DISTINCT
        b.id_deal, b.id_lead, b.id_device, b.ts_deal_created,
        COALESCE(dm.ts_lead, dm.ts_success_contact, dm.ts_simulation_sent, dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) AS ts_lead,
        COALESCE(dm.ts_success_contact, dm.ts_simulation_sent, dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) AS ts_success_contact,
        COALESCE(dm.ts_simulation_sent, dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) AS ts_simulation_sent,
        COALESCE(dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) AS ts_simulation_accepted,
        COALESCE(dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) AS ts_offer_under_negotiation,
        COALESCE(dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) AS ts_offer_accepted,
        COALESCE(dm.ts_contract_created, dm.ts_closed_deal) AS ts_contract_created,
        dm.ts_contact_attempt, dm.ts_agendamento_started, dm.ts_closed_deal, dm.ts_discarted,
        CASE
          WHEN b.consorcio_inside_sales_pipeline = 'SDR IA'
               THEN COALESCE(dm.ts_simulation_sent, dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal)
          WHEN b.consorcio_inside_sales_pipeline = 'SIMULATOR IA'
               THEN COALESCE(dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal)
          WHEN b.consorcio_inside_sales_pipeline = 'SDR Humano'
               THEN coalesce(dm.ts_lead, dm.ts_success_contact)
        END AS ts_handoff,
        b.stage_name AS current_stage, b.ts_stage_started AS ts_current_stage_started,
        b.deal_name,
        LOWER(CASE
            WHEN b.utm_medium = 'blip_reply' THEN 'repescagem'
            WHEN o.origin IS NOT NULL THEN o.origin
            WHEN (b.consorcio_discard_reason IS NULL OR b.consorcio_quota_amount IS NULL) THEN 'DAG Fail - Properties Null'
            WHEN b.utm_source IS NOT NULL THEN 'Others'
            ELSE 'Direct'
        END) AS origin,
        LOWER(b.utm_medium) AS utm_medium, b.utm_campaign, b.utm_content, b.utm_term,
        CASE
            WHEN b.utm_source = 'crm' AND b.utm_campaign LIKE '%FR_Tenants%'  THEN 'Tenants'
            WHEN b.utm_source = 'crm' AND b.utm_campaign LIKE '%FS_ToF%'      THEN 'FS_ToF'
            WHEN b.utm_source = 'crm' AND b.utm_campaign LIKE '%FR_FS_Owners%' THEN 'Owners'
            WHEN b.utm_source = 'crm' AND b.utm_campaign LIKE '%FR_ToF%'      THEN 'FR_ToF'
            ELSE sm.segment
        END AS segment,
        b.consorcio_inside_sales_pipeline, b.consorcio_discard_reason,
        b.consorcio_forms_origin, b.consorcio_lead_priority,
        b.consorcio_quota_amount, b.consorcio_installment_type,
        b.consorcio_channel_origin, b.amount, b.id_hubspot_owner,
        b.customer_journey, b.first_simulation_at, b.last_simulation_at, b.total_simulations,
        b.qualifier_goal, b.qualifier_investment_type, b.qualifier_reason, b.qualifier_knowledge, b.qualifier_urgency,
        b.consorcio_c2w_message,
        CASE WHEN b.consorcio_c2w_message IS NOT NULL THEN 1 ELSE 0 END AS sent_c2w_message,
        CASE WHEN b.consorcio_c2w_message IS NOT NULL THEN 'user_initiated' ELSE 'company_initiated' END AS contact_type,
        on2.analyst_name, ao.role, ao.supervisor,
        CASE WHEN COALESCE(dm.ts_lead, dm.ts_success_contact, dm.ts_simulation_sent, dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) IS NOT NULL THEN 1 ELSE 0 END AS is_lead,
        CASE WHEN dm.ts_contact_attempt IS NOT NULL THEN 1 ELSE 0 END AS is_tc,
        CASE WHEN COALESCE(dm.ts_success_contact, dm.ts_simulation_sent, dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) IS NOT NULL AND b.stage_name NOT IN ('carrinho abandonado','lead','tentativa de contato') THEN 1 ELSE 0 END AS is_sc,
        CASE WHEN COALESCE(dm.ts_simulation_sent, dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) IS NOT NULL AND b.stage_name NOT IN ('carrinho abandonado','lead','tentativa de contato','contato com sucesso') THEN 1 ELSE 0 END AS is_ss,
        CASE WHEN COALESCE(dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) IS NOT NULL AND b.stage_name NOT IN ('carrinho abandonado','lead','tentativa de contato','contato com sucesso','simulação') THEN 1 ELSE 0 END AS is_sa,
        CASE WHEN COALESCE(dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) IS NOT NULL AND b.stage_name NOT IN ('carrinho abandonado','lead','tentativa de contato','contato com sucesso','simulação','simulação aceita') THEN 1 ELSE 0 END AS is_oun,
        CASE WHEN COALESCE(dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) IS NOT NULL AND b.stage_name NOT IN ('carrinho abandonado','lead','tentativa de contato','contato com sucesso','simulação','simulação aceita','proposta em negociação') THEN 1 ELSE 0 END AS is_oa,
        CASE WHEN COALESCE(dm.ts_contract_created, dm.ts_closed_deal) IS NOT NULL AND b.stage_name NOT IN ('carrinho abandonado','lead','tentativa de contato','contato com sucesso','simulação','simulação aceita','proposta em negociação','proposta aceita') THEN 1 ELSE 0 END AS is_cc,
        CASE WHEN dm.ts_closed_deal IS NOT NULL AND b.stage_name = 'venda fechada' THEN 1 ELSE 0 END AS is_cd,
        CASE
          WHEN b.consorcio_inside_sales_pipeline = 'SDR IA' AND COALESCE(dm.ts_simulation_sent, dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) IS NOT NULL AND b.stage_name NOT IN ('carrinho abandonado','lead','tentativa de contato','contato com sucesso') THEN 1
          WHEN b.consorcio_inside_sales_pipeline = 'SIMULATOR IA' AND COALESCE(dm.ts_simulation_accepted, dm.ts_offer_under_negotiation, dm.ts_offer_accepted, dm.ts_contract_created, dm.ts_agendamento_started, dm.ts_closed_deal) IS NOT NULL AND b.stage_name NOT IN ('carrinho abandonado','lead','tentativa de contato','contato com sucesso','simulação') THEN 1
          WHEN b.consorcio_inside_sales_pipeline = 'SDR Humano' THEN 1
          ELSE 0
        END AS is_handoff,
        CASE WHEN dm.ts_discarted IS NOT NULL AND b.stage_name = 'descarte' THEN 1 ELSE 0 END AS is_discarted,
        CASE WHEN b.stage_name = 'descarte' THEN b.last_stage ELSE NULL END AS discarted_in_which_stage,
        date_trunc('month', b.ts_deal_created) AS month_start,
        date_trunc('week',  b.ts_deal_created) AS week_start,
        date(b.ts_deal_created) AS date
    FROM base_all b
    LEFT JOIN deal_milestones dm ON b.id_deal = dm.id_deal
    LEFT JOIN origin_mapping   o  ON o.utm_source   = b.utm_source
    LEFT JOIN segment_mapping  sm ON sm.utm_campaign = b.utm_campaign
    LEFT JOIN owner_name  on2 ON on2.id_owner = CAST(b.id_hubspot_owner AS VARCHAR)
    LEFT JOIN analyst_ops ao  ON ao.id_owner = CAST(b.id_hubspot_owner AS VARCHAR)
    WHERE DATE(b.ts_deal_created) >= DATE('2025-08-01')   -- adjust cohort window as needed
      AND b.deal_name NOT LIKE '%Teste%'
      AND b.deal_name NOT LIKE '%test%'
      AND b.rn = 1
      AND COALESCE(b.is_duplicated, 'unique') = 'unique'
)

SELECT
    sa.*,
    -- Business-day durations vs. dw_public.dim_date (is_brz_business_day). All measures fully expanded.
    CASE WHEN sa.is_lead = 1 AND sa.current_stage NOT IN ('venda fechada','descarte','carrinho_abandonado') THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_deal_created AS DATE) AND c.date <= CAST(CURRENT_DATE - INTERVAL '1' DAY AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS aging_lead,
    GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_current_stage_started AS DATE) AND c.date <= CAST(CURRENT_DATE - INTERVAL '1' DAY AS DATE) AND c.is_brz_business_day = TRUE) - 1) AS days_in_current_stage,
    CASE WHEN sa.is_lead = 1 AND sa.is_sc = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_lead AS DATE) AND c.date <= CAST(sa.ts_success_contact AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_lead_to_sc,
    CASE WHEN sa.is_lead = 1 AND sa.is_ss = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_lead AS DATE) AND c.date <= CAST(sa.ts_simulation_sent AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_lead_to_ss,
    CASE WHEN sa.is_lead = 1 AND sa.is_sa = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_lead AS DATE) AND c.date <= CAST(sa.ts_simulation_accepted AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_lead_to_sa,
    CASE WHEN sa.is_lead = 1 AND sa.is_oun = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_lead AS DATE) AND c.date <= CAST(sa.ts_offer_under_negotiation AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_lead_to_oun,
    CASE WHEN sa.is_lead = 1 AND sa.is_oa = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_lead AS DATE) AND c.date <= CAST(sa.ts_offer_accepted AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_lead_to_oa,
    CASE WHEN sa.is_lead = 1 AND sa.is_cc = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_lead AS DATE) AND c.date <= CAST(sa.ts_contract_created AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_lead_to_cc,
    CASE WHEN sa.is_lead = 1 AND sa.is_cd = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_lead AS DATE) AND c.date <= CAST(sa.ts_closed_deal AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_lead_to_cd,
    CASE WHEN sa.is_ss = 1 AND sa.is_cd = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_simulation_sent AS DATE) AND c.date <= CAST(sa.ts_closed_deal AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_ss_to_cd,
    CASE WHEN sa.is_sa = 1 AND sa.is_cd = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_simulation_accepted AS DATE) AND c.date <= CAST(sa.ts_closed_deal AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_sa_to_cd,
    CASE WHEN sa.is_sa = 1 AND sa.is_oun = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_simulation_accepted AS DATE) AND c.date <= CAST(sa.ts_offer_under_negotiation AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_sa_to_oun,
    CASE WHEN sa.is_oun = 1 AND sa.is_oa = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_offer_under_negotiation AS DATE) AND c.date <= CAST(sa.ts_offer_accepted AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_oun_to_oa,
    CASE WHEN sa.is_oa = 1 AND sa.is_cc = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_offer_accepted AS DATE) AND c.date <= CAST(sa.ts_contract_created AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_oa_to_cc,
    CASE WHEN sa.is_cc = 1 AND sa.is_cd = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_contract_created AS DATE) AND c.date <= CAST(sa.ts_closed_deal AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_cc_to_cd,
    CASE WHEN sa.is_sa = 1 AND sa.is_oa = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_simulation_accepted AS DATE) AND c.date <= CAST(sa.ts_offer_accepted AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_sa_to_oa,
    CASE WHEN sa.is_oa = 1 AND sa.is_cd = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_offer_accepted AS DATE) AND c.date <= CAST(sa.ts_closed_deal AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_oa_to_cd,
    CASE WHEN sa.is_handoff = 1 AND sa.is_cd = 1 THEN
        GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_handoff AS DATE) AND c.date <= CAST(sa.ts_closed_deal AS DATE) AND c.is_brz_business_day = TRUE) - 1)
    END AS days_to_convert_from_handoff_to_cd,
    GREATEST(0, (SELECT COUNT(*) FROM dw_public.dim_date c WHERE c.date >= CAST(sa.ts_deal_created AS DATE) AND c.date <= CAST(sa.ts_current_stage_started AS DATE) AND c.is_brz_business_day = TRUE) - 1) AS days_from_creation_to_current_stage
FROM stages_adjusted sa
```

