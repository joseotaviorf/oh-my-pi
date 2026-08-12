-- DataHub API tool-call latency/payload metrics from Vector datahub_probe + datahub_gql
-- events. Separates "DataHub was slow" from "LLM reasoning was slow" when investigating
-- turn_metrics.duration_ms outliers, and surfaces DataHub API error rates independently
-- of whether the turn eventually produced an answer.
SELECT
    COALESCE(id_turn, CONCAT(event_type, '-', id_session, '-', CAST(UNIX_TIMESTAMP(ts_event) AS STRING))) AS id_tool_call,
    id_session,
    event_type,
    session_source,
    status,
    error_class,
    query_preview,
    duration_ms,
    response_bytes,
    data_product_count,
    row_count,
    ts_event AS ts_tool_call,
    dt_event AS dt_tool_call,
    year,
    month,
    day
FROM
    datalake_tars_clean.vector_logs
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
    AND "{load_end_date}"
    AND event_type IN ('datahub_probe', 'datahub_gql')
