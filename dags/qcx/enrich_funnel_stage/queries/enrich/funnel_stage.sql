-- ================================================================
-- Consórcio funnel stage façade
-- Grain: one row per deal × stage visit (id_deal, id_stage, ts_entered)
-- Source: HubSpot deal_stage + stage + pipeline + deal (consorcio_id_lead)
-- Window: {load_start_date}..{load_end_date} on ts_stage_started OR
--         ts_stage_ended so late exits still re-merge and refresh ts_exited
-- ================================================================
WITH consorcio_deals AS (
  SELECT
    CAST(hubspot_deal.id_deal AS STRING) AS id_deal,
    CAST(hubspot_deal.consorcio_id_lead AS STRING) AS uuid_lead
  FROM
    datalake_hubspot.deal AS hubspot_deal
  WHERE
    hubspot_deal.consorcio_id_lead IS NOT NULL
),
stage_visits AS (
  SELECT
    consorcio_deals.uuid_lead,
    CAST(deal_stage.id_deal AS STRING) AS id_deal,
    CAST(deal_stage.id_pipeline AS STRING) AS id_pipeline,
    CAST(deal_stage.id_stage AS STRING) AS id_stage,
    deal_stage.ts_stage_started AS ts_entered,
    deal_stage.ts_stage_ended AS ts_exited,
    CAST(deal_stage.id_user_updated_by AS STRING) AS id_actor,
    deal_stage.source_type AS change_source
  FROM
    datalake_hubspot.deal_stage AS deal_stage
  INNER JOIN
    consorcio_deals
      ON consorcio_deals.id_deal = CAST(deal_stage.id_deal AS STRING)
  WHERE
    (
      deal_stage.ts_stage_started >= DATE('{load_start_date}')
      AND deal_stage.ts_stage_started < DATE_ADD(DATE('{load_end_date}'), 1)
    )
    OR (
      deal_stage.ts_stage_ended >= DATE('{load_start_date}')
      AND deal_stage.ts_stage_ended < DATE_ADD(DATE('{load_end_date}'), 1)
    )
)
SELECT
  stage_visits.id_deal,
  stage_visits.id_pipeline,
  stage_visits.id_stage,
  stage_visits.id_actor,
  stage_visits.uuid_lead,
  hubspot_pipeline.label AS pipeline_name,
  hubspot_stage.label AS stage_name,
  stage_visits.change_source,
  stage_visits.ts_entered,
  stage_visits.ts_exited,
  YEAR(stage_visits.ts_entered) AS year,
  MONTH(stage_visits.ts_entered) AS month,
  DAY(stage_visits.ts_entered) AS day
FROM
  stage_visits
LEFT JOIN
  datalake_hubspot.pipeline AS hubspot_pipeline
    ON CAST(hubspot_pipeline.id_pipeline AS STRING) = stage_visits.id_pipeline
LEFT JOIN
  datalake_hubspot.stage AS hubspot_stage
    ON CAST(hubspot_stage.id_stage AS STRING) = stage_visits.id_stage
WHERE
  stage_visits.uuid_lead IS NOT NULL
  AND stage_visits.id_deal IS NOT NULL
  AND stage_visits.id_stage IS NOT NULL
  AND stage_visits.ts_entered IS NOT NULL
