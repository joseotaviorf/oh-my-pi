-- ================================================================
-- Labelled deal population for Consórcio Behavioral Lead Scoring
-- Grain: one row per deal (id_deal); one lead may have several deals
-- Partitioned by spec_version: each run writes one immutable population,
-- so several can coexist and an analysis can stay pinned to one of them
-- Scoped by floor_date, which is part of the population's identity
-- Entity comes from datalake_consorcio.deal. ts_handoff comes from
-- datalake_consorcio.deal_milestone (skip-stage COALESCE, pipeline CASE).
-- Null ts_handoff means the lead was with a human from the start.
-- Other first-hit timestamps come from datalake_consorcio.deal_stage
-- (already Sao Paulo). ts_lead_created comes from deal (already Sao Paulo).
-- Population grain matches deal (pipeline 737631007, tests and duplicates
-- already dropped).
-- ================================================================
WITH stage_events AS (
  SELECT
    CAST(deal_stage.id_deal AS BIGINT) AS id_deal,
    LOWER(deal_stage.stage_name) AS stage_name,
    deal_stage.ts_entered
  FROM
    datalake_consorcio.deal_stage AS deal_stage
),
raw_milestones AS (
  SELECT
    stage_events.id_deal,
    MIN(stage_events.ts_entered) AS ts_first_stage,
    MIN(
      CASE WHEN stage_events.stage_name = 'simulação' THEN stage_events.ts_entered END
    ) AS ts_simulation_sent,
    MIN(
      CASE WHEN stage_events.stage_name = 'venda fechada' THEN stage_events.ts_entered END
    ) AS ts_closed_deal,
    MIN(
      CASE WHEN stage_events.stage_name = 'descarte' THEN stage_events.ts_entered END
    ) AS ts_discarded_first,
    MAX(
      CASE WHEN stage_events.stage_name = 'descarte' THEN stage_events.ts_entered END
    ) AS ts_discarded_last
  FROM
    stage_events
  GROUP BY
    stage_events.id_deal
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
),
labelled AS (
  SELECT
    consorcio_deal.id_deal,
    -- The outcome is where the deal sits today; ts_closed_deal only distinguishes a
    -- discard that follows a sale from a plain loss. A deal that moved back into the
    -- funnel after reaching an outcome falls through to open, which is correct: it has
    -- no outcome right now.
    CASE
      WHEN raw_milestones.ts_closed_deal IS NOT NULL
        AND consorcio_deal.current_stage = 'descarte' THEN 'cancelled'
      WHEN consorcio_deal.current_stage = 'venda fechada' THEN 'won'
      WHEN consorcio_deal.current_stage = 'descarte' THEN 'lost'
      ELSE 'open'
    END AS outcome,
    -- Mirrors the branches above so that ts_outcome is null exactly when outcome is open
    CASE
      WHEN raw_milestones.ts_closed_deal IS NOT NULL
        AND consorcio_deal.current_stage = 'descarte' THEN raw_milestones.ts_discarded_last
      WHEN consorcio_deal.current_stage = 'venda fechada' THEN raw_milestones.ts_closed_deal
      WHEN consorcio_deal.current_stage = 'descarte' THEN raw_milestones.ts_discarded_first
    END AS ts_outcome
  FROM
    datalake_consorcio.deal AS consorcio_deal
  INNER JOIN
    raw_milestones
      ON raw_milestones.id_deal = consorcio_deal.id_deal
)
SELECT
  -- id_deal doubles as the bridge to the conversation tables: in
  -- datalake_consorcio_clean.blip_messages, id_crm is the HubSpot deal id.
  consorcio_deal.id_deal,
  consorcio_deal.uuid_lead,
  labelled.outcome,
  consorcio_deal.discard_reason,
  consorcio_deal.inside_sales_pipeline,
  consorcio_deal.utm_source,
  consorcio_deal.utm_campaign,
  CASE
    WHEN raw_milestones.ts_first_stage >= DATE('{platconv_start_date}') THEN 'platconv'
    ELSE 'blip'
  END AS host_name,
  COALESCE(deal_messages.number_of_messages, 0) AS number_of_messages,
  -- LIKE is case-sensitive on Spark, so both spellings are needed.
  -- datalake_consorcio.deal already drops test names, so this flag is false
  -- for every row in the current grain.
  (
    COALESCE(consorcio_deal.deal_name, '') LIKE '%Teste%'
    OR COALESCE(consorcio_deal.deal_name, '') LIKE '%test%'
  ) AS is_test_user,
  -- deal keeps unique deals only; flag kept for the ABT schema.
  FALSE AS is_duplicated,
  -- Maturity is measured from ts_lead_created, per the business definition of the
  -- journey start; ts_first_stage is kept for comparison.
  raw_milestones.ts_first_stage,
  consorcio_deal.ts_lead_created,
  -- Taken from the raw stage visit rather than the simulation record: the
  -- simulation table only resolves for ~2% of deals, while the stage covers ~30%.
  raw_milestones.ts_simulation_sent AS ts_simulated,
  -- Copied from deal_milestone: HubSpot skip-steps are filled forward, and a
  -- null means the lead was handled by a human from the beginning.
  deal_milestone.ts_handoff,
  labelled.ts_outcome,
  CURRENT_TIMESTAMP() AS ts_load,
  CAST({spec_version} AS INT) AS spec_version
FROM
  datalake_consorcio.deal AS consorcio_deal
INNER JOIN
  raw_milestones
    ON raw_milestones.id_deal = consorcio_deal.id_deal
INNER JOIN
  labelled
    ON labelled.id_deal = consorcio_deal.id_deal
INNER JOIN
  datalake_consorcio.deal_milestone AS deal_milestone
    ON deal_milestone.id_deal = consorcio_deal.id_deal
LEFT JOIN
  deal_messages
    ON deal_messages.id_deal = consorcio_deal.id_deal
WHERE
  raw_milestones.ts_first_stage >= DATE('{floor_date}')
