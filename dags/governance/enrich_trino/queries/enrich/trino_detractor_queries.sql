WITH users AS (
    SELECT
        p.work_email,
        p.cost_center,
        cd.line
    FROM
        datalake_gsheets_clean.cost_center_person AS p
    LEFT JOIN
        datalake_gsheets_clean.cost_center_directory AS cd
            ON p.cost_center = cd.cost_center
),
query_metrics AS (
    SELECT
        queryId AS id_query,
        CAST(get_json_object(session, '$.user') AS STRING) AS user,
        CAST(get_json_object(session, '$.source') AS STRING) AS source,
        CAST(
            get_json_object(
                regexp_extract(query, '--\\s*(\\{.*\\})', 1),
                '$.slice_id'
            ) AS INT)
        AS id_superset_slice,
        CAST(
            get_json_object(
                regexp_extract(query, '--\\s*(\\{.*\\})', 1),
                '$.dashboard_id'
            ) AS INT)
        AS id_superset_dashboard,
        internal_network_input_data_size_bytes / 1073741824 AS internal_network_input_data_size_GB,
        execution_time,
        execution_time_unit,
        total_cpu_time,
        total_cpu_time_unit,
        processed_input_data_bytes,
        peak_total_memory_reservation_bytes,
        number_stages,
        (dayofweek(created_time) = 7) as is_saturday,
        created_time AS ts_created,
        execution_start_time AS ts_execution_start,
        execution_end_time AS ts_execution_end,
        year,
        month,
        day
    FROM
        data_platform_metrics.trino_query_log_events_metrics_clean_batch
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
        AND CAST(get_json_object(session, '$.source') AS STRING) = 'Apache Superset'
        AND query LIKE '%-- {%'
        AND errorcode IS NULL
),
enrich_base AS (
    SELECT
        qm.id_superset_dashboard,
        qm.id_superset_slice,
        -- mb_queries.context,
        sl.slice_name,
        sl.last_owner,
        sl.company_line AS line,
        qm.source,
        qm.id_query,
        qm.internal_network_input_data_size_GB,
        CASE
            qm.total_cpu_time_unit
            WHEN 'd' THEN qm.total_cpu_time * 86400
            WHEN 'h' THEN qm.total_cpu_time * 3600
            WHEN 'm' THEN qm.total_cpu_time * 60
            WHEN 's' THEN qm.total_cpu_time
            WHEN 'ms' THEN qm.total_cpu_time / 1000
            WHEN 'ns' THEN qm.total_cpu_time / 1000000000
            ELSE NULL
        END AS cpu_time_sec,
        CASE
            qm.execution_time_unit
            WHEN 'd' THEN qm.execution_time * 86400
            WHEN 'h' THEN qm.execution_time * 3600
            WHEN 'm' THEN qm.execution_time * 60
            WHEN 's' THEN qm.execution_time
            WHEN 'ms' THEN qm.execution_time / 1000
            WHEN 'ns' THEN qm.execution_time / 1000000000
            ELSE NULL
        END AS execution_time_sec,
        qm.processed_input_data_bytes / power(1024, 3) AS input_data_gb,
        qm.peak_total_memory_reservation_bytes / power(1024, 3) AS peak_total_memory_gb,
        qm.number_stages,
        is_saturday,
        qm.ts_execution_start,
        qm.ts_execution_end,
        year,
        month,
        day
    FROM
      query_metrics AS qm
    LEFT JOIN
      datalake_superset.slices AS sl
        ON sl.id = qm.id_superset_slice
    LEFT JOIN
      users AS us
        ON us.work_email = sl.last_owner
)
SELECT
    base.id_superset_dashboard,
    base.id_superset_slice,
    base.slice_name,
    base.last_owner,
    base.line,
    base.source,
    execution_week_start.week_start,
    base.internal_network_input_data_size_GB,
    base.execution_time_sec,
    base.input_data_gb,
    base.peak_total_memory_gb,
    base.number_stages,
    CASE WHEN (cpu_time_sec >= "{cpu_threshold}") THEN TRUE ELSE FALSE END AS cpu_time_sec_threshold_active,
    CASE WHEN (input_data_gb >= "{input_data_threshold}") THEN TRUE ELSE FALSE END AS input_data_gb_threshold_active,
    CASE WHEN (number_stages >= "{stages_threshold}") THEN TRUE ELSE FALSE END AS stages_threshold_active,
    CASE WHEN (execution_time_sec >= "{execution_time_cpu_threshold}") THEN TRUE ELSE FALSE END AS execution_time_sec_threshold_active,
    ts_execution_start,
    ts_execution_end,
    base.year,
    base.month,
    base.day
FROM
    enrich_base AS base
LEFT JOIN
    dw_public.dim_date AS execution_week_start
        ON DATE(base.ts_execution_start) = execution_week_start.`date`
WHERE
    id_superset_slice IS NOT NULL
    AND (
        COALESCE(cpu_time_sec, 0) >= "{cpu_threshold}"
        OR COALESCE(input_data_gb, 0) >= "{input_data_threshold}"
        OR COALESCE(number_stages, 0) >= "{stages_threshold}"
        OR COALESCE(execution_time_sec, 0) >= "{execution_time_cpu_threshold}"
    )
