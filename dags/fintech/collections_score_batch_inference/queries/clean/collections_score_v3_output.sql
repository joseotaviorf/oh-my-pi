SELECT
  CAST(GET_JSON_OBJECT(output_data, '$.sk_contract') AS BIGINT) AS id_contract,
  model_name,
  model_version,
  CAST(GET_JSON_OBJECT(output_data, '$.payment_probability') AS DOUBLE) AS payment_probability,
  CAST(GET_JSON_OBJECT(output_data, '$.score') AS INT) AS score,
  'PROD' as flag_source,
  TO_DATE(FROM_UNIXTIME(CAST(GET_JSON_OBJECT(output_data, '$.dt_reference') AS BIGINT) / 1000)) AS dt_reference,
  TIMESTAMP(timestamp) as ts_inference,
  year,
  month,
  day
FROM datalake_collections_score_batch_inference_raw.collections_score_v3_output
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
