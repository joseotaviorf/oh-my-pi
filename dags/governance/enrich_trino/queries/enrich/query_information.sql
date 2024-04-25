WITH base AS (
    SELECT
        queryId AS id_query,
        resourceGroupId AS id_resource_group,
        referencedTables AS referenced_tables,
        state,
        execution_time, 
        execution_start_time AS ts_execution_started,
        execution_end_time AS ts_execution_ended,
        year,
        month,
        day
    FROM
        data_platform_metrics.trino_query_log_events_metrics_clean_batch
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
),
exploded_referenced_tables AS (
    SELECT
        id_query,
        EXPLODE(referenced_tables) AS referenced_table
    FROM
        base
),
extract_schema_and_table AS (
    SELECT
        id_query,
        REGEXP_EXTRACT(referenced_table, '"schema":"(\\w+)",') AS database_name,
        SPLIT(REGEXP_EXTRACT(referenced_table, '"table":"(\\w+(\\$)*\\w+)",'), '[\$]') [0] AS table_name
    FROM
        exploded_referenced_tables
),
tools AS (
    SELECT
        b.id_query,
        GET(b.id_resource_group, 2) AS tool,
        GET(b.id_resource_group, 3) AS user,
        b.state,
        b.execution_time,
        es.database_name,
        es.table_name,
        b.ts_execution_started,
        b.ts_execution_ended,
        b.year,
        b.month,
        b.day
    FROM
        base AS b
    JOIN
        extract_schema_and_table AS es
            ON es.id_query = b.id_query
)
SELECT
    id_query,
    CASE
        WHEN tool = 'bi-metabase' THEN 'Metabase'
        WHEN tool = 'bi-looker' THEN 'Looker'
        WHEN tool = 'bi-superset' THEN 'Superset'
        ELSE tool
    END AS tool,
    user,
    state,
    execution_time,
    database_name,
    table_name,
    MAKE_DATE(year, month, day) AS dt_extraction,
    ts_execution_started,
    ts_execution_ended,
    year,
    month,
    day
FROM
    tools