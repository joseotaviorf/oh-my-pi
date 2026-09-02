WITH events_incremental AS (
    SELECT
        id_persona_event,
        id_user,
        uuid_person,
        persona,
        last_journey_step,
        is_active,
        ts_updated,
        year,
        month,
        day
    FROM
        datalake_cdp.stream_persona_events
    WHERE
        ts_ingested_at >= TIMESTAMP('{load_start_date}')
        AND ts_ingested_at <= TIMESTAMP('{load_end_date}')
),
batch_ranked AS (
    SELECT
        events.id_persona_event,
        events.id_user,
        COALESCE(events.uuid_person, batch.uuid_person) AS uuid_person,
        events.persona,
        events.last_journey_step AS event_last_journey_step,
        events.is_active AS event_is_active,
        events.ts_updated AS event_ts_updated,
        events.year,
        events.month,
        events.day,
        batch.journey_step AS batch_last_journey_step,
        batch.is_active AS batch_is_active,
        CAST(batch.ts_first_event AS TIMESTAMP) AS batch_ts_started,
        CAST(batch.ts_last_event AS TIMESTAMP) AS batch_ts_updated,
        ROW_NUMBER() OVER (
            PARTITION BY events.id_persona_event
            ORDER BY
                COALESCE(
                    CAST(batch.ts_last_event AS TIMESTAMP),
                    CURRENT_TIMESTAMP()
                ) DESC,
                CAST(batch.ts_first_event AS TIMESTAMP) DESC
        ) AS row_number
    FROM
        events_incremental AS events
    LEFT JOIN
        datalake_cdp_personas.persona AS batch
            ON batch.id_user = events.id_user
            AND batch.persona = events.persona
),
reconciled AS (
    SELECT
        id_persona_event,
        id_user,
        uuid_person,
        persona,
        CASE
            WHEN
                event_ts_updated IS NOT NULL
                AND (
                    batch_ts_updated IS NULL
                    OR event_ts_updated > batch_ts_updated
                )
                THEN UPPER(event_last_journey_step)
            ELSE UPPER(batch_last_journey_step)
        END AS last_journey_step,
        CASE
            WHEN
                event_ts_updated IS NOT NULL
                AND (
                    batch_ts_updated IS NULL
                    OR event_ts_updated > batch_ts_updated
                )
                THEN event_is_active
            ELSE batch_is_active
        END AS is_active,
        batch_ts_started AS ts_started,
        COALESCE(
            CASE
                WHEN
                    batch_ts_updated IS NOT NULL
                    AND event_ts_updated IS NOT NULL
                    AND batch_ts_updated >= event_ts_updated
                    THEN batch_ts_updated
                WHEN
                    batch_ts_updated IS NOT NULL
                    AND event_ts_updated IS NOT NULL
                    AND event_ts_updated > batch_ts_updated
                    THEN event_ts_updated
                WHEN
                    batch_ts_updated IS NOT NULL
                    AND event_ts_updated IS NULL
                    THEN batch_ts_updated
                WHEN
                    event_ts_updated IS NOT NULL
                    AND batch_ts_updated IS NULL
                    THEN event_ts_updated
            END,
            batch_ts_started
        ) AS ts_updated,
        CAST(NULL AS TIMESTAMP) AS ts_ended,
        CURRENT_TIMESTAMP() AS ts_load,
        COALESCE(year, YEAR(batch_ts_updated), YEAR(CURRENT_DATE())) AS year,
        COALESCE(month, MONTH(batch_ts_updated), MONTH(CURRENT_DATE())) AS month,
        COALESCE(day, DAY(batch_ts_updated), DAY(CURRENT_DATE())) AS day
    FROM
        batch_ranked
    WHERE
        row_number = 1
        AND id_persona_event IS NOT NULL
)
SELECT
    id_persona_event,
    id_user,
    uuid_person,
    persona,
    last_journey_step,
    is_active,
    ts_started,
    ts_updated,
    ts_ended,
    ts_load,
    year,
    month,
    day
FROM
    reconciled
WHERE
    is_active = true
