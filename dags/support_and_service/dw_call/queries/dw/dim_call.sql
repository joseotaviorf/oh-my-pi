WITH ivr_events AS (
    SELECT
        id_call,
        from_number,
        to_number,
        MIN(id_task) AS id_task, -- workaround to filter 1 instance with duplicity
        MIN(ts_created_local) AS ts_first_event,
        MAX(ts_created_local) AS ts_last_event
    FROM
        datalake_bigfone_twilio.call_ivr_events
    GROUP BY 1,2,3
),
flex_events AS (
    SELECT
        id_task,
        id_call,
        id_conversation,
        from_number,
        to_number,
        direction,
        scheduling_source,
        MIN(ts_created_local) AS ts_first_event,
        MAX(ts_created_local) AS ts_last_event
    FROM
        datalake_bigfone_twilio.call_flex_events
    GROUP BY 1,2,3,4,5,6,7
),
call_locations AS (
    SELECT
        id_call,
        from_city,
        from_state,
        from_country
    FROM
        datalake_bigfone_twilio.inbound_call_locations
    GROUP BY 1,2,3,4
),
csat_events AS (
    SELECT
        id_call,
        MIN(ts_created_local) AS ts_csat
    FROM
        datalake_bigfone_twilio.call_ivr_events
    WHERE
        csat_2 IS NOT NULL
    GROUP BY 1
)
SELECT
    COALESCE(ie.id_call, fe.id_call, fe.id_conversation, fe.id_task) AS sk_call, -- only inbound calls have id_call, but all calls have id_task
    COALESCE(ie.from_number,fe.from_number) AS from_phone_number,
    COALESCE(ie.to_number,fe.to_number) AS to_phone_number,
    fe.direction,
    cl.from_city,
    cl.from_state,
    cl.from_country,
    fe.scheduling_source,
    COALESCE(ie.ts_first_event,fe.ts_first_event) AS ts_started,
    ce.ts_csat AS ts_csat_answered,
    GREATEST(ie.ts_last_event,fe.ts_last_event) AS ts_ended,
    NOW() AS ts_load
FROM
    ivr_events ie
FULL JOIN
    flex_events fe
        ON fe.id_call = ie.id_call
LEFT JOIN
    csat_events ce
        ON ce.id_call = ie.id_call
LEFT JOIN
    call_locations cl
        ON cl.id_call = ie.id_call