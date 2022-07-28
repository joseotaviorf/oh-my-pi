WITH exploded_stages AS (
    SELECT
        id_ticket::BIGINT,
        EXPLODE(id_stage_history) AS stage_struct
    FROM
        datalake_hubspot.ticket
),
exploded_pipelines AS (
    SELECT
        id_ticket::BIGINT,
        EXPLODE(id_pipeline_history) AS pipeline_struct
    FROM
        datalake_hubspot.ticket
),
united_ticket_stage_pipeline AS (
    SELECT
        s.id_ticket,
        s.stage_struct.value ::BIGINT AS id_stage,
        LAST(p.pipeline_struct.value::BIGINT, TRUE) OVER (PARTITION BY s.id_ticket ORDER BY s.stage_struct.timestamp) AS id_pipeline,
        s.stage_struct.timestamp AS ts_stage_started
    FROM
        exploded_stages AS s
    LEFT JOIN
        exploded_pipelines AS p
            ON s.id_ticket = p.id_ticket
            AND s.stage_struct.timestamp = p.pipeline_struct.timestamp
),
calculated_end_timestamps AS (
    SELECT *,
        LEAD(ts_stage_started) OVER (PARTITION BY id_ticket ORDER BY ts_stage_started) AS ts_stage_ended
    FROM
        united_ticket_stage_pipeline
)
SELECT
    id_ticket,
    id_stage,
    id_pipeline,
    DATEDIFF(COALESCE(ts_stage_ended, NOW()), ts_stage_started) AS days_in_stage,
    ts_stage_started,
    ts_stage_ended
FROM
    calculated_end_timestamps