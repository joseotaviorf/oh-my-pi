-- Per-turn schema verification detail: explodes schema_gate.tables (raw lake tables
-- Tars actually schema-checked before answering) from Vector turn_summary events.
-- Sourced from schema_gate_json, not schema_verified_tables_json (the latter is always
-- null on vector_logs today; the payload nests tables under schema_gate). Distinct from
-- DataHub asset usage: this is a raw catalog schema lookup, not a DataHub URN reference.
WITH turn_summaries AS (
    SELECT
        COALESCE(id_turn, CONCAT('turn_summary-', id_session, '-', CAST(UNIX_TIMESTAMP(ts_event) AS STRING))) AS id_turn,
        id_session,
        session_source,
        business_domain,
        CAST(GET_JSON_OBJECT(schema_gate_json, '$.passed') AS BOOLEAN) AS is_schema_gate_passed,
        FROM_JSON(
            GET_JSON_OBJECT(schema_gate_json, '$.tables'),
            'ARRAY<STRUCT<schema: STRING, table: STRING, columns: ARRAY<STRING>>>'
        ) AS verified_tables,
        ts_event,
        dt_event,
        year,
        month,
        day
    FROM
        datalake_tars_clean.vector_logs
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND event_type = 'turn_summary'
        AND schema_gate_json IS NOT NULL
),
exploded AS (
    SELECT
        turn_summaries.id_turn,
        turn_summaries.id_session,
        turn_summaries.session_source,
        turn_summaries.business_domain,
        turn_summaries.is_schema_gate_passed,
        verified_table.`schema` AS verified_schema,
        verified_table.`table` AS verified_table_name,
        verified_table.columns AS verified_columns,
        turn_summaries.ts_event,
        turn_summaries.dt_event,
        turn_summaries.year,
        turn_summaries.month,
        turn_summaries.day
    FROM
        turn_summaries
    LATERAL VIEW OUTER EXPLODE(turn_summaries.verified_tables) AS verified_table
    WHERE
        verified_table.`table` IS NOT NULL
)
SELECT
    id_turn,
    id_session,
    session_source,
    business_domain,
    is_schema_gate_passed,
    verified_schema,
    verified_table_name,
    verified_columns,
    ts_event AS ts_turn,
    dt_event AS dt_turn,
    year,
    month,
    day
FROM
    exploded
