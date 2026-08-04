-- ================================================================
-- Consórcio chatbot offline-eval metrics (clean)
-- Grain: one row per (eval run × dataset item × agent run × metric)
-- Source: datalake_consorcio_raw.consorcio_chatbot_offline_eval
-- Window: ts_load >= {load_start_date} (rows raw-loaded since, so
-- late-arriving files of any eval date are indexed; insert-only
-- merge on the grain keys keeps re-runs idempotent)
-- ================================================================
WITH raw_in_window AS (
  SELECT
    raw_eval.s3_path,
    raw_eval.git_commit,
    raw_eval.ts_eval,
    raw_eval.result_json,
    raw_eval.dt_eval,
    raw_eval.ts_load
  FROM
    datalake_consorcio_raw.consorcio_chatbot_offline_eval AS raw_eval
  WHERE
    raw_eval.ts_load >= TIMESTAMP('{load_start_date}')
),
path_enriched AS (
  SELECT
    raw_in_window.s3_path,
    raw_in_window.git_commit,
    raw_in_window.ts_eval,
    raw_in_window.result_json,
    raw_in_window.dt_eval,
    raw_in_window.ts_load,
    REGEXP_EXTRACT(
      raw_in_window.s3_path,
      'chatbot/([^/]+)/atenas/([^/]+)/',
      1
    ) AS host_name,
    REGEXP_EXTRACT(
      raw_in_window.s3_path,
      'chatbot/([^/]+)/atenas/([^/]+)/',
      2
    ) AS suite_name,
    REGEXP_EXTRACT(raw_in_window.s3_path, '/([^/]+)\\.json$', 1) AS eval_run_stem
  FROM
    raw_in_window
),
with_run_id AS (
  SELECT
    path_enriched.s3_path,
    path_enriched.git_commit,
    path_enriched.ts_eval,
    path_enriched.result_json,
    path_enriched.dt_eval,
    path_enriched.ts_load,
    path_enriched.host_name,
    path_enriched.suite_name,
    CONCAT_WS(
      '/',
      path_enriched.host_name,
      'atenas',
      path_enriched.suite_name,
      CONCAT('date=', CAST(path_enriched.dt_eval AS STRING)),
      CONCAT('commit=', path_enriched.git_commit),
      path_enriched.eval_run_stem
    ) AS id_eval_run
  FROM
    path_enriched
  WHERE
    path_enriched.host_name != ''
    AND path_enriched.suite_name != ''
    AND path_enriched.eval_run_stem != ''
),
parsed AS (
  SELECT
    with_run_id.id_eval_run,
    with_run_id.host_name,
    with_run_id.suite_name,
    with_run_id.dt_eval,
    with_run_id.git_commit,
    with_run_id.ts_eval,
    with_run_id.s3_path,
    with_run_id.ts_load,
    -- Quote boolean scores so mixed bool/float score fields parse as STRING.
    FROM_JSON(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          with_run_id.result_json,
          '"score"\\s*:\\s*true',
          '"score":"true"'
        ),
        '"score"\\s*:\\s*false',
        '"score":"false"'
      ),
      'STRUCT<items:ARRAY<STRUCT<dataset_item:STRUCT<metadata:MAP<STRING,STRING>>,runs:ARRAY<STRUCT<agent_result:STRUCT<run:INT,duration_ms:DOUBLE,error:STRING>,metric_results:ARRAY<STRUCT<name:STRING,config_identifier:STRING,score:STRING,raw_score:DOUBLE,reason:STRING>>>>>>>'
    ) AS doc
  FROM
    with_run_id
),
items_exploded AS (
  SELECT
    parsed.id_eval_run,
    parsed.host_name,
    parsed.suite_name,
    parsed.dt_eval,
    parsed.git_commit,
    parsed.ts_eval,
    parsed.s3_path,
    parsed.ts_load,
    item_pos AS nr_dataset_item,
    item_row.dataset_item AS dataset_item,
    item_row.runs AS runs
  FROM
    parsed
  LATERAL VIEW OUTER POSEXPLODE(parsed.doc.items) AS item_pos, item_row
),
runs_exploded AS (
  SELECT
    items_exploded.id_eval_run,
    items_exploded.host_name,
    items_exploded.suite_name,
    items_exploded.dt_eval,
    items_exploded.git_commit,
    items_exploded.ts_eval,
    items_exploded.s3_path,
    items_exploded.ts_load,
    items_exploded.nr_dataset_item,
    COALESCE(
      items_exploded.dataset_item.metadata['id'],
      CONCAT('item_', CAST(items_exploded.nr_dataset_item AS STRING))
    ) AS id_dataset_item,
    items_exploded.dataset_item.metadata['label'] AS dataset_item_label,
    run_row.agent_result AS agent_result,
    run_row.metric_results AS metric_results
  FROM
    items_exploded
  LATERAL VIEW OUTER POSEXPLODE(items_exploded.runs) AS run_pos, run_row
),
metrics_exploded AS (
  SELECT
    runs_exploded.id_eval_run,
    runs_exploded.host_name,
    runs_exploded.suite_name,
    runs_exploded.dt_eval,
    runs_exploded.git_commit,
    runs_exploded.ts_eval,
    runs_exploded.s3_path,
    runs_exploded.id_dataset_item,
    runs_exploded.dataset_item_label,
    runs_exploded.agent_result.run AS nr_run,
    runs_exploded.agent_result.duration_ms AS agent_duration_ms,
    runs_exploded.agent_result.error AS agent_error,
    metric_row.name AS metric_name,
    metric_row.config_identifier AS metric_config_identifier,
    metric_row.score AS score_raw,
    metric_row.raw_score AS raw_score,
    metric_row.reason AS metric_reason,
    runs_exploded.ts_load
  FROM
    runs_exploded
  LATERAL VIEW OUTER EXPLODE(runs_exploded.metric_results) AS metric_row
)
SELECT
  metrics_exploded.id_eval_run,
  metrics_exploded.id_dataset_item,
  metrics_exploded.host_name,
  metrics_exploded.suite_name,
  metrics_exploded.dataset_item_label,
  metrics_exploded.nr_run,
  metrics_exploded.metric_name,
  metrics_exploded.metric_config_identifier,
  metrics_exploded.metric_reason,
  metrics_exploded.agent_error,
  metrics_exploded.git_commit,
  metrics_exploded.s3_path,
  CASE
    WHEN LOWER(metrics_exploded.score_raw) IN ('true', 'false')
      THEN CAST(LOWER(metrics_exploded.score_raw) = 'true' AS DOUBLE)
    ELSE CAST(metrics_exploded.score_raw AS DOUBLE)
  END AS score,
  metrics_exploded.raw_score,
  metrics_exploded.agent_duration_ms,
  CASE
    WHEN LOWER(metrics_exploded.score_raw) IN ('true', 'false')
      THEN LOWER(metrics_exploded.score_raw) = 'true'
    ELSE CAST(NULL AS BOOLEAN)
  END AS is_pass,
  metrics_exploded.agent_error IS NOT NULL AS has_agent_error,
  metrics_exploded.dt_eval,
  metrics_exploded.ts_eval,
  metrics_exploded.ts_load,
  YEAR(metrics_exploded.dt_eval) AS year,
  MONTH(metrics_exploded.dt_eval) AS month,
  DAY(metrics_exploded.dt_eval) AS day
FROM
  metrics_exploded
WHERE
  metrics_exploded.metric_name IS NOT NULL
