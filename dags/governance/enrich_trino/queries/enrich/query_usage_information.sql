WITH base AS (
  SELECT
    queryId AS id_query,
    query,
    fieldnames,
    warnings,
    number_stages,
    processed_input_data_bytes,
    resourceGroupId AS id_resource_group,
    GET(id_resource_group, 2) AS tool,
    GET(id_resource_group, 3) AS user,
    GET_JSON_OBJECT(session, '$.user') AS session_user,
    cast(
      nullif(
        regexp_extract(query, '"slice_id":\\s*(\\d+)'),
        ''
      ) AS INT
    ) AS superset_slice_id,
    cast(
      nullif(
        regexp_extract(query, '"dashboard_id":\\s*(\\d+)'),
        ''
      ) AS INT
    ) AS superset_dash_id,
    cast(
      nullif(regexp_extract(query, 'cardID: (\\d+)'), '') AS INT
    ) AS metabase_card_id,
    cast(
      nullif(regexp_extract(query, 'dashboardID: (\\d+)'), '') AS INT
    ) AS metabase_dash_id,
    referencedTables AS referenced_tables,
    array_size(
      array_remove(
        transform(
          referencedTables,
          x -> REGEXP_EXTRACT(x, '"schema":"(dw_|metric_)\\w*",', 1)
        ),
        ""
      )
    ) nr_dw_metric_tables,
    array_size(referencedTables) nr_tables,
    array_size(
      array_remove(
        transform(
          referencedTables,
          x -> REGEXP_EXTRACT(x, '"schema":"(dw_|metric_)\\w*",', 1)
        ),
        ""
      )
    ) = array_size(referencedTables) AS is_all_dw_metric_tables,
    if(lower(query) like '%row_number()%', true, false) AS has_row_number,
    state,
    peak_total_memory_reservation_bytes,
    execution_time,
    hour AS execution_hour,
    execution_start_time AS ts_execution_started,
    execution_end_time AS ts_execution_ended,
    ROW_NUMBER() OVER(PARTITION BY queryId ORDER BY MAKE_DATE(year, month, day) DESC) as last_event,
    year,
    month,
    day
  FROM
    data_platform_metrics.trino_query_log_events_metrics_clean_batch
  WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
    AND "{load_end_date}"
)
SELECT
  id_query,
  superset_slice_id AS id_slice_superset,
  superset_dash_id AS id_dash_superset,
  metabase_card_id AS id_metabase_card,
  metabase_dash_id AS id_dash_metabase,
  CASE
    WHEN tool = 'bi-metabase' THEN 'Metabase'
    WHEN tool = 'bi-looker' THEN 'Looker'
    WHEN tool = 'bi-superset' THEN 'Superset'
    WHEN tool = 'other'
    AND session_user LIKE 'trino_datahub%' THEN 'DataHub'
    ELSE tool
  END AS tool,
  query,
  referenced_tables,
  case
    when superset_dash_id is not null and superset_slice_id is not null then 'from dashboard'
    when superset_dash_id is not null and superset_slice_id is null then 'from filter'
    when superset_slice_id is not null then 'from chart'
    when metabase_dash_id is not null then 'from dashboard'
    when metabase_card_id is not null then 'from chart'
    when tool in ('bi-metabase', 'bi-superset') then 'exploratory'
    else 'other'
  end query_reason,
  user,
  state,
  if(array_size(warnings) = 0, false, true) AS has_warnings,
  has_row_number,
  is_all_dw_metric_tables,
  nr_dw_metric_tables,
  nr_tables,
  peak_total_memory_reservation_bytes,
  execution_time,
  execution_hour,
  MAKE_DATE(year, month, day) AS dt_extraction,
  ts_execution_started,
  ts_execution_ended,
  year,
  month,
  day
FROM base
WHERE last_event = 1
