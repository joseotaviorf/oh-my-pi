WITH base AS (
    SELECT
        queryId AS id_query,
        resourceGroupId AS id_resource_group,
        GET_JSON_OBJECT(session, '$.user') AS session_user,
        regexp_extract(query, '"slice_id":\\s*(\\d+)') AS superset_slice_id,
        regexp_extract(query, 'cardID: (\\d+)') AS metabase_card_id,
        referencedTables AS referenced_tables,
        state,
        execution_time, 
        hour AS execution_hour,
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
        b.session_user,
        b.superset_slice_id,
        b.metabase_card_id,
        b.state,
        b.execution_time,
        b.execution_hour,
        NULLIF(es.database_name, '') AS database_name,
        NULLIF(es.table_name, '') AS table_name,
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
    CONCAT(database_name, '.', table_name) AS id_table,
    CASE
        WHEN tool = 'bi-metabase' THEN 'Metabase'
        WHEN tool = 'bi-looker' THEN 'Looker'
        WHEN tool = 'bi-superset' THEN 'Superset'
        WHEN tool = 'other' AND session_user LIKE 'trino_datahub%' THEN 'DataHub'
        ELSE tool
    END AS tool,
    superset_slice_id AS id_slice_superset,
    metabase_card_id AS id_metabase_card,
    user,
    state,
    execution_time,
    database_name,
    table_name,
    execution_hour,
    MAKE_DATE(year, month, day) AS dt_extraction,
    ts_execution_started,
    ts_execution_ended,
    year,
    month,
    day
FROM
    tools