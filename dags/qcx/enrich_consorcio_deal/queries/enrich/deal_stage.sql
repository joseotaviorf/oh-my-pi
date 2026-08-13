-- ================================================================
-- Consórcio deal stage visits (path grain)
-- One row per deal entering a pipeline stage (id_deal, id_stage, ts_entered).
-- Population is the deal master: INNER JOIN datalake_consorcio.deal.
-- Consórcio HubSpot pipeline only. Full rebuild so visits match deal.
-- ts_entered / ts_exited converted UTC -> America/Sao_Paulo (same clock as
-- deal and deal_milestone). Partitioned by local ts_entered.
-- ================================================================
WITH stage_visits AS (
  SELECT
    CAST(hubspot_deal_stage.id_deal AS STRING) AS id_deal,
    CAST(hubspot_deal_stage.id_pipeline AS STRING) AS id_pipeline,
    CAST(hubspot_deal_stage.id_stage AS STRING) AS id_stage,
    CAST(hubspot_deal_stage.id_user_updated_by AS STRING) AS id_actor,
    consorcio_deal.uuid_lead,
    hubspot_pipeline.label AS pipeline_name,
    hubspot_stage.label AS stage_name,
    hubspot_deal_stage.source_type AS change_source,
    FROM_UTC_TIMESTAMP(hubspot_deal_stage.ts_stage_started, 'America/Sao_Paulo') AS ts_entered,
    FROM_UTC_TIMESTAMP(hubspot_deal_stage.ts_stage_ended, 'America/Sao_Paulo') AS ts_exited
  FROM
    datalake_hubspot.deal_stage AS hubspot_deal_stage
  INNER JOIN
    datalake_consorcio.deal AS consorcio_deal
      ON CAST(consorcio_deal.id_deal AS STRING) = CAST(hubspot_deal_stage.id_deal AS STRING)
  LEFT JOIN
    datalake_hubspot.pipeline AS hubspot_pipeline
      ON hubspot_pipeline.id_pipeline = hubspot_deal_stage.id_pipeline
  LEFT JOIN
    datalake_hubspot.stage AS hubspot_stage
      ON hubspot_stage.id_stage = hubspot_deal_stage.id_stage
  WHERE
    hubspot_deal_stage.id_pipeline = 737631007
    AND hubspot_deal_stage.ts_stage_started IS NOT NULL
    AND hubspot_deal_stage.id_stage IS NOT NULL
)
SELECT
  stage_visits.id_deal,
  stage_visits.id_pipeline,
  stage_visits.id_stage,
  stage_visits.id_actor,
  stage_visits.uuid_lead,
  stage_visits.pipeline_name,
  stage_visits.stage_name,
  stage_visits.change_source,
  stage_visits.ts_entered,
  stage_visits.ts_exited,
  YEAR(stage_visits.ts_entered) AS year,
  MONTH(stage_visits.ts_entered) AS month,
  DAY(stage_visits.ts_entered) AS day
FROM
  stage_visits
