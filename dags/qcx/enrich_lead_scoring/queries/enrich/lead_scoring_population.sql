-- ================================================================
-- Labelled deal population for Consórcio Behavioral Lead Scoring
-- Grain: one row per deal (id_deal); one lead may have several deals
-- Partitioned by spec_version: each run writes one immutable population,
-- so several can coexist and an analysis can stay pinned to one of them
-- Scoped by floor_date, which is part of the population's identity
-- Milestones read raw (no COALESCE backfill) to keep ts_handoff free of
-- outcome leakage; a missing handoff milestone yields NULL and drops the
-- deal out of the population
-- ================================================================
WITH deal_milestones AS (
  SELECT
    deal_stage.id_deal,
    MIN(deal_stage.ts_stage_started) AS ts_first_stage,
    MIN(
      CASE WHEN LOWER(stage.label) = 'leads' THEN deal_stage.ts_stage_started END
    ) AS ts_lead,
    MIN(
      CASE WHEN LOWER(stage.label) = 'simulação' THEN deal_stage.ts_stage_started END
    ) AS ts_simulation_sent,
    MIN(
      CASE WHEN LOWER(stage.label) = 'simulação aceita' THEN deal_stage.ts_stage_started END
    ) AS ts_simulation_accepted,
    MIN(
      CASE WHEN LOWER(stage.label) = 'venda fechada' THEN deal_stage.ts_stage_started END
    ) AS ts_closed_deal,
    MIN(
      CASE WHEN LOWER(stage.label) = 'descarte' THEN deal_stage.ts_stage_started END
    ) AS ts_discarded
  FROM
    datalake_hubspot.deal_stage AS deal_stage
  INNER JOIN
    datalake_hubspot.stage AS stage
      ON stage.id_stage = deal_stage.id_stage
  WHERE
    deal_stage.id_pipeline = {id_pipeline}
  GROUP BY
    deal_stage.id_deal
),
-- Lead creation timestamp, carried alongside ts_first_stage so that the choice of
-- journey start stays a read-time decision while the business definition is open.
-- Aggregated by uuid so the join can never fan out and break the deal grain.
lead_created AS (
  SELECT
    consorcio_lead.uuid AS uuid_lead,
    MIN(consorcio_lead.ts_created) AS ts_lead_created
  FROM
    datalake_consorcio_clean.lead AS consorcio_lead
  WHERE
    consorcio_lead.uuid IS NOT NULL
  GROUP BY
    consorcio_lead.uuid
),
-- Conversation link indicator. Sourced from the clean layer, where id_crm is
-- already resolved to the HubSpot deal id, so no raw access is required.
-- Counts every linked message; the per-feature temporal cutoff is applied
-- downstream, in the feature table.
deal_messages AS (
  SELECT
    -- id_crm is a varchar in the clean layer while id_deal is a bigint, so the
    -- join key has to be cast. Every distinct id_crm is numeric, so the cast is
    -- lossless; a non-numeric value would become NULL and simply not match.
    CAST(blip_messages.id_crm AS BIGINT) AS id_deal,
    COUNT(DISTINCT blip_messages.id_message) AS number_of_messages
  FROM
    datalake_consorcio_clean.blip_messages AS blip_messages
  WHERE
    blip_messages.id_crm IS NOT NULL
  GROUP BY
    CAST(blip_messages.id_crm AS BIGINT)
)
SELECT
  -- id_deal doubles as the bridge to the conversation tables: in
  -- datalake_consorcio_clean.blip_messages, id_crm is the HubSpot deal id.
  hubspot_deal.id_deal,
  hubspot_deal.consorcio_id_lead AS uuid_lead,
  CASE
    WHEN deal_milestones.ts_closed_deal IS NOT NULL THEN 'won'
    WHEN deal_milestones.ts_discarded IS NOT NULL THEN 'lost'
    ELSE 'open'
  END AS outcome,
  hubspot_deal.consorcio_discard_reason AS discard_reason,
  hubspot_deal.consorcio_inside_sales_pipeline AS inside_sales_pipeline,
  CASE
    WHEN deal_milestones.ts_first_stage >= DATE('{platconv_start_date}') THEN 'platconv'
    ELSE 'blip'
  END AS host_name,
  COALESCE(deal_messages.number_of_messages, 0) AS number_of_messages,
  -- LIKE is case-sensitive on Spark, so both spellings are needed
  (
    COALESCE(hubspot_deal.deal_name, '') LIKE '%Teste%'
    OR COALESCE(hubspot_deal.deal_name, '') LIKE '%test%'
  ) AS is_test_user,
  COALESCE(hubspot_deal.consorcio_deal_duplicado, 'unique') <> 'unique' AS is_duplicated,
  -- Maturity is measured from here; the P95 = 34 days cycle was computed on this
  -- same definition. Whether the journey should instead start at lead creation in
  -- consorcio-api is an open business question.
  deal_milestones.ts_first_stage,
  lead_created.ts_lead_created,
  -- Taken from the funnel milestone rather than the simulation record: the
  -- simulation table only resolves for ~2% of deals, while the stage covers ~30%,
  -- and using the same source as ts_handoff keeps the post-simulation window
  -- internally consistent.
  deal_milestones.ts_simulation_sent AS ts_simulated,
  CASE
    WHEN hubspot_deal.consorcio_inside_sales_pipeline = 'SDR IA'
      THEN deal_milestones.ts_simulation_sent
    WHEN hubspot_deal.consorcio_inside_sales_pipeline = 'SIMULATOR IA'
      THEN deal_milestones.ts_simulation_accepted
    WHEN hubspot_deal.consorcio_inside_sales_pipeline = 'SDR Humano'
      THEN deal_milestones.ts_lead
  END AS ts_handoff,
  COALESCE(deal_milestones.ts_closed_deal, deal_milestones.ts_discarded) AS ts_outcome,
  CURRENT_TIMESTAMP() AS ts_load,
  CAST({spec_version} AS INT) AS spec_version
FROM
  deal_milestones
INNER JOIN
  datalake_hubspot.deal AS hubspot_deal
    ON hubspot_deal.id_deal = deal_milestones.id_deal
LEFT JOIN
  lead_created
    ON lead_created.uuid_lead = hubspot_deal.consorcio_id_lead
LEFT JOIN
  deal_messages
    ON deal_messages.id_deal = deal_milestones.id_deal
WHERE
  deal_milestones.ts_first_stage >= DATE('{floor_date}')
