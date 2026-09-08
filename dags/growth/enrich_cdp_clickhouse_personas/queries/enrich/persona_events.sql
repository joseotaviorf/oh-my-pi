WITH persona_ranked AS (
    SELECT
        SHA2(
            CONCAT(
                CAST(id_user AS STRING),
                persona
            ),
            512
        ) AS id_persona_event,
        id_user,
        uuid_person,
        persona,
        journey_step AS last_journey_step,
        is_active,
        CAST(ts_first_event AS TIMESTAMP) AS ts_started,
        CAST(ts_last_event AS TIMESTAMP) AS ts_updated,
        CAST(NULL AS TIMESTAMP) AS ts_ended,
        YEAR(
            COALESCE(
                CAST(ts_last_event AS TIMESTAMP),
                CAST(ts_first_event AS TIMESTAMP)
            )
        ) AS year,
        MONTH(
            COALESCE(
                CAST(ts_last_event AS TIMESTAMP),
                CAST(ts_first_event AS TIMESTAMP)
            )
        ) AS month,
        DAY(
            COALESCE(
                CAST(ts_last_event AS TIMESTAMP),
                CAST(ts_first_event AS TIMESTAMP)
            )
        ) AS day,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_user,
                persona
            ORDER BY
                COALESCE(
                    CAST(ts_last_event AS TIMESTAMP),
                    CURRENT_TIMESTAMP()
                ) DESC
        ) AS row_number
    FROM
        datalake_cdp_personas.persona
),
persona_filtered AS (
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
        year,
        month,
        day
    FROM
        persona_ranked
    WHERE
        row_number = 1
),
persona_events_filtered AS (
    SELECT
        id_persona_event,
        id_user,
        uuid_person,
        persona,
        is_active,
        UPPER(last_journey_step) AS last_journey_step,
        ts_updated,
        year,
        month,
        day
    FROM
        datalake_cdp.stream_persona_events
    WHERE
        TO_DATE(ts_load)
        BETWEEN TO_DATE('{load_start_date}')
        AND TO_DATE('{load_end_date}')
),
persona_events_distinct AS (
    SELECT
        id_persona_event,
        id_user,
        uuid_person,
        persona,
        is_active,
        last_journey_step,
        MAX(ts_updated) AS ts_updated,
        year,
        month,
        day
    FROM
        persona_events_filtered
    GROUP BY
        id_persona_event,
        id_user,
        uuid_person,
        persona,
        is_active,
        last_journey_step,
        year,
        month,
        day
),
unified AS (
    SELECT
        COALESCE(
            persona_evt.id_persona_event,
            persona_hist.id_persona_event
        ) AS id_persona_event,
        COALESCE(
            persona_evt.id_user,
            persona_hist.id_user
        ) AS id_user,
        COALESCE(
            persona_evt.uuid_person,
            persona_hist.uuid_person
        ) AS uuid_person,
        COALESCE(
            persona_evt.persona,
            persona_hist.persona
        ) AS persona,
        CASE
            WHEN
                persona_hist.ts_updated IS NOT NULL
                AND persona_evt.ts_updated IS NOT NULL
                AND persona_hist.ts_updated >= persona_evt.ts_updated
                THEN persona_hist.last_journey_step
            WHEN
                persona_hist.ts_updated IS NOT NULL
                AND persona_evt.ts_updated IS NOT NULL
                AND persona_evt.ts_updated > persona_hist.ts_updated
                THEN persona_evt.last_journey_step
            WHEN
                persona_hist.ts_updated IS NULL
                AND persona_evt.ts_updated IS NOT NULL
                THEN persona_evt.last_journey_step
            WHEN
                persona_hist.ts_updated IS NOT NULL
                AND persona_evt.ts_updated IS NULL
                THEN persona_hist.last_journey_step
        END AS last_journey_step,
        COALESCE(
            persona_evt.is_active,
            persona_hist.is_active
        ) AS is_active,
        persona_hist.ts_started,
        COALESCE(
            CASE
                WHEN
                    persona_hist.ts_updated IS NOT NULL
                    AND persona_evt.ts_updated IS NOT NULL
                    AND persona_hist.ts_updated >= persona_evt.ts_updated
                    THEN persona_hist.ts_updated
                WHEN
                    persona_hist.ts_updated IS NOT NULL
                    AND persona_evt.ts_updated IS NOT NULL
                    AND persona_evt.ts_updated > persona_hist.ts_updated
                    THEN persona_evt.ts_updated
                WHEN
                    persona_hist.ts_updated IS NOT NULL
                    AND persona_evt.ts_updated IS NULL
                    THEN persona_hist.ts_updated
                WHEN
                    persona_evt.ts_updated IS NOT NULL
                    AND persona_hist.ts_updated IS NULL
                    THEN persona_evt.ts_updated
            END,
            persona_hist.ts_started
        ) AS ts_updated,
        persona_hist.ts_ended,
        CURRENT_TIMESTAMP() AS ts_load
    FROM
        persona_filtered AS persona_hist
    FULL OUTER JOIN
        persona_events_distinct AS persona_evt
            ON persona_hist.id_persona_event = persona_evt.id_persona_event
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
    YEAR(COALESCE(ts_updated, ts_started)) AS year,
    MONTH(COALESCE(ts_updated, ts_started)) AS month,
    DAY(COALESCE(ts_updated, ts_started)) AS day
FROM
    unified
WHERE
    id_persona_event IS NOT NULL
