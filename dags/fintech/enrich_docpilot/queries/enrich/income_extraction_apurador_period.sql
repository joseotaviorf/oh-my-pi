WITH batch_base AS (
  SELECT
    batch.id AS id_batch,
    CAST(batch.id_external AS BIGINT) AS id_external,
    batch.external_source,
    batch.status AS apurador_status,
    GET_JSON_OBJECT(batch.business_output, '$.extracted_income') AS apurador_extracted_income_json,
    GET_JSON_OBJECT(batch.business_output, '$.gross_income') AS apurador_gross_income_json,
    GET_JSON_OBJECT(batch.business_output, '$.committed_income') AS apurador_committed_income_json,
    GET_JSON_OBJECT(batch.pipeline_metadata, '$.handler_type') AS apurador_handler_type,
    batch.ts_created AS ts_batch_created
  FROM
    datalake_docpilot_clean.income_extraction_batch AS batch
),
apurador_extracted_periods AS (
  SELECT
    batch_base.id_batch,
    batch_base.id_external,
    batch_base.external_source,
    batch_base.apurador_status,
    batch_base.apurador_handler_type,
    batch_base.ts_batch_created,
    period_extracted.reference_period,
    CAST(period_extracted.apurador_extracted_income AS DECIMAL(18, 2)) AS apurador_extracted_income
  FROM
    batch_base
  LATERAL VIEW OUTER EXPLODE(
    FROM_JSON(batch_base.apurador_extracted_income_json, 'map<string,string>')
  ) period_extracted AS reference_period, apurador_extracted_income
),
apurador_gross_periods AS (
  SELECT
    batch_base.id_batch,
    period_gross.reference_period,
    CAST(period_gross.apurador_gross_income AS DECIMAL(18, 2)) AS apurador_gross_income
  FROM
    batch_base
  LATERAL VIEW OUTER EXPLODE(
    FROM_JSON(batch_base.apurador_gross_income_json, 'map<string,string>')
  ) period_gross AS reference_period, apurador_gross_income
),
apurador_committed_periods AS (
  SELECT
    batch_base.id_batch,
    period_committed.reference_period,
    CAST(period_committed.apurador_committed_income AS DECIMAL(18, 2)) AS apurador_committed_income
  FROM
    batch_base
  LATERAL VIEW OUTER EXPLODE(
    FROM_JSON(batch_base.apurador_committed_income_json, 'map<string,string>')
  ) period_committed AS reference_period, apurador_committed_income
),
apurador_periods AS (
  SELECT
    apurador_extracted_periods.id_batch,
    apurador_extracted_periods.id_external,
    apurador_extracted_periods.external_source,
    apurador_extracted_periods.apurador_status,
    apurador_extracted_periods.apurador_handler_type,
    apurador_extracted_periods.ts_batch_created,
    apurador_extracted_periods.reference_period,
    apurador_extracted_periods.apurador_extracted_income,
    apurador_gross_periods.apurador_gross_income,
    apurador_committed_periods.apurador_committed_income
  FROM
    apurador_extracted_periods
  LEFT JOIN
    apurador_gross_periods
      ON apurador_extracted_periods.id_batch = apurador_gross_periods.id_batch
      AND apurador_extracted_periods.reference_period = apurador_gross_periods.reference_period
  LEFT JOIN
    apurador_committed_periods
      ON apurador_extracted_periods.id_batch = apurador_committed_periods.id_batch
      AND apurador_extracted_periods.reference_period = apurador_committed_periods.reference_period
),
apurador_periods_ranked AS (
  SELECT
    apurador_periods.id_batch,
    apurador_periods.id_external,
    apurador_periods.external_source,
    apurador_periods.apurador_status,
    apurador_periods.apurador_handler_type,
    apurador_periods.ts_batch_created,
    apurador_periods.reference_period,
    apurador_periods.apurador_extracted_income,
    apurador_periods.apurador_gross_income,
    apurador_periods.apurador_committed_income,
    ROW_NUMBER() OVER (
      PARTITION BY apurador_periods.id_external, apurador_periods.external_source
      ORDER BY apurador_periods.ts_batch_created DESC
    ) AS rn
  FROM
    apurador_periods
),
legacy_latest AS (
  SELECT
    CAST(id_external AS BIGINT) AS id_external,
    legacy_external_source,
    GET_JSON_OBJECT(extracted_data, '$.extracted_income') AS legacy_extracted_income_json,
    GET_JSON_OBJECT(extracted_data, '$.gross_income') AS legacy_gross_income_json,
    GET_JSON_OBJECT(extracted_data, '$.committed_income') AS legacy_committed_income_json,
    processing_result AS legacy_processing_result
  FROM (
    SELECT
      id_external,
      external_source AS legacy_external_source,
      extracted_data,
      processing_result,
      ROW_NUMBER() OVER (
        PARTITION BY id_external, external_source
        ORDER BY ts_updated DESC, ts_created DESC
      ) AS rn
    FROM
      datalake_docpilot_clean.income_extraction
  ) AS ranked_legacy_extractions
  WHERE
    rn = 1
),
legacy_extracted_periods AS (
  SELECT
    legacy_latest.id_external,
    legacy_latest.legacy_external_source,
    legacy_latest.legacy_processing_result,
    period_extracted.reference_period,
    CAST(period_extracted.legacy_extracted_income AS DECIMAL(18, 2)) AS legacy_extracted_income
  FROM
    legacy_latest
  LATERAL VIEW OUTER EXPLODE(
    FROM_JSON(legacy_latest.legacy_extracted_income_json, 'map<string,string>')
  ) period_extracted AS reference_period, legacy_extracted_income
),
legacy_gross_periods AS (
  SELECT
    legacy_latest.id_external,
    legacy_latest.legacy_external_source,
    period_gross.reference_period,
    CAST(period_gross.legacy_gross_income AS DECIMAL(18, 2)) AS legacy_gross_income
  FROM
    legacy_latest
  LATERAL VIEW OUTER EXPLODE(
    FROM_JSON(legacy_latest.legacy_gross_income_json, 'map<string,string>')
  ) period_gross AS reference_period, legacy_gross_income
),
legacy_committed_periods AS (
  SELECT
    legacy_latest.id_external,
    legacy_latest.legacy_external_source,
    period_committed.reference_period,
    CAST(period_committed.legacy_committed_income AS DECIMAL(18, 2)) AS legacy_committed_income
  FROM
    legacy_latest
  LATERAL VIEW OUTER EXPLODE(
    FROM_JSON(legacy_latest.legacy_committed_income_json, 'map<string,string>')
  ) period_committed AS reference_period, legacy_committed_income
),
legacy_periods AS (
  SELECT
    legacy_extracted_periods.id_external,
    legacy_extracted_periods.legacy_external_source,
    legacy_extracted_periods.reference_period,
    legacy_extracted_periods.legacy_extracted_income,
    legacy_gross_periods.legacy_gross_income,
    legacy_committed_periods.legacy_committed_income,
    legacy_extracted_periods.legacy_processing_result
  FROM
    legacy_extracted_periods
  LEFT JOIN
    legacy_gross_periods
      ON legacy_extracted_periods.id_external = legacy_gross_periods.id_external
      AND legacy_extracted_periods.legacy_external_source = legacy_gross_periods.legacy_external_source
      AND legacy_extracted_periods.reference_period = legacy_gross_periods.reference_period
  LEFT JOIN
    legacy_committed_periods
      ON legacy_extracted_periods.id_external = legacy_committed_periods.id_external
      AND legacy_extracted_periods.legacy_external_source = legacy_committed_periods.legacy_external_source
      AND legacy_extracted_periods.reference_period = legacy_committed_periods.reference_period
)
SELECT
  COALESCE(
    apurador_periods_ranked.id_batch,
    CONCAT('legacy-only-', CAST(legacy_periods.id_external AS STRING))
  ) AS id_batch,
  COALESCE(apurador_periods_ranked.id_external, legacy_periods.id_external) AS id_external,
  COALESCE(apurador_periods_ranked.external_source, legacy_periods.legacy_external_source) AS external_source,
  COALESCE(apurador_periods_ranked.reference_period, legacy_periods.reference_period) AS reference_period,
  apurador_periods_ranked.apurador_status,
  apurador_periods_ranked.apurador_handler_type,
  legacy_periods.legacy_processing_result,
  apurador_periods_ranked.apurador_extracted_income,
  apurador_periods_ranked.apurador_gross_income,
  apurador_periods_ranked.apurador_committed_income,
  legacy_periods.legacy_extracted_income,
  legacy_periods.legacy_gross_income,
  legacy_periods.legacy_committed_income,
  CASE
    WHEN apurador_periods_ranked.apurador_extracted_income IS NOT NULL
      AND legacy_periods.legacy_extracted_income IS NOT NULL
    THEN ROUND(apurador_periods_ranked.apurador_extracted_income - legacy_periods.legacy_extracted_income, 2)
  END AS delta_extracted_income,
  CASE
    WHEN apurador_periods_ranked.apurador_extracted_income IS NOT NULL
      AND legacy_periods.legacy_extracted_income IS NOT NULL
    THEN ROUND(
      (apurador_periods_ranked.apurador_extracted_income - legacy_periods.legacy_extracted_income)
      / NULLIF(legacy_periods.legacy_extracted_income, 0) * 100,
      2
    )
  END AS delta_extracted_income_pct,
  apurador_periods_ranked.id_batch IS NOT NULL AS has_apurador_period,
  legacy_periods.legacy_extracted_income IS NOT NULL AS has_legacy_period,
  apurador_periods_ranked.rn = 1 AS is_latest_batch_for_external,
  apurador_periods_ranked.ts_batch_created,
  NOW() AS ts_load
FROM
  apurador_periods_ranked
FULL OUTER JOIN
  legacy_periods
    ON apurador_periods_ranked.id_external = legacy_periods.id_external
    AND apurador_periods_ranked.external_source = legacy_periods.legacy_external_source
    AND apurador_periods_ranked.reference_period = legacy_periods.reference_period
