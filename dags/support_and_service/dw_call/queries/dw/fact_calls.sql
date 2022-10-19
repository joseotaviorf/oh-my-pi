WITH ivr_calls AS (
    SELECT
        id_call,
        customer_phone,
        MIN(id_task) AS id_task, -- workaround to filter 1 instance with duplicity
        MIN(ts_created_local_unix) AS ts_first_event_local_unix,
        MAX(ts_created_local_unix) AS ts_last_event_local_unix
    FROM
        datalake_bigfone_twilio.call_ivr_events
    GROUP BY 1,2
),
initial_ivr_events AS (
    SELECT
        cie.id_task,
        cie.id_call,
        UNIX_TIMESTAMP(MAX(ts_created)) - UNIX_TIMESTAMP(MIN(ts_created)) AS initial_ivr_time
    FROM
      datalake_bigfone_twilio.call_ivr_paths cip
    JOIN
        datalake_bigfone_twilio.call_ivr_events cie
            ON cie.id = cip.id
    GROUP BY 1,2
),
flex_calls AS (
    SELECT
        cfe.id_call,
        cfe.id_task,
        cfe.customer_phone,
        cfe.is_scheduled,
        cfe.id_conversation,
        MAX(cfe.ts_wrapup_event_local_unix) AS ts_wrapup_event_local_unix,
        MIN(cfe.ts_created_local_unix) AS ts_first_event_local_unix,
        MAX(cfe.ts_created_local_unix) AS ts_last_event_local_unix
    FROM
        datalake_bigfone_twilio.call_flex_events cfe
    WHERE
        event_type != 'task.updated'
    GROUP BY 1,2,3,4,5
),
call_metrics AS (
    SELECT
        id_task,
        id_call,
        COUNT(id_reservation) AS reservations,
        COUNT(
            CASE
                WHEN is_answered THEN id_reservation
            END
        ) AS reservations_accepted,
        SUM(seconds_wait_time) AS wait_time_flex,
        SUM(seconds_talk_time) AS talk_time,
        MIN(ts_created) AS ts_first_reservation,
        MAX(ts_created) AS ts_last_reservation
    FROM
        datalake_bigfone_twilio.call_flex_reservations
    GROUP BY 1,2
),
last_reservation AS (
    SELECT
        cfr.id_task,
        cfr.queue_name AS last_queue_name
    FROM
        datalake_bigfone_twilio.call_flex_reservations cfr
    JOIN
        call_metrics cm
            ON cfr.id_task = cm.id_task
            AND cfr.ts_created = cm.ts_last_reservation
),
first_reservation AS (
    SELECT
        cfr.id_task,
        cfr.queue_name AS first_queue_name,
        cfr.seconds_wait_time AS first_wait_time,
        UNIX_TIMESTAMP(cfr.ts_created_local) AS ts_first_reservation_local_unix
    FROM
        datalake_bigfone_twilio.call_flex_reservations cfr
    JOIN
        call_metrics cm
            ON cfr.id_task = cm.id_task
            AND cfr.ts_created = cm.ts_first_reservation
),
csat_events AS (
    SELECT
        id_call,
        id_task,
        MAX(csat_1) AS csat_1,
        MAX(csat_2) AS csat_2
    FROM
        datalake_bigfone_twilio.call_ivr_events
    WHERE
        COALESCE(csat_1, csat_2) IS NOT NULL
    GROUP BY 1,2
),
customer_identification AS (
    SELECT
        REGEXP_REPLACE(customer_contact,'(^\\+?55)|(\\D*)','') AS formatted_phone,
        MAX(id_user) AS id_user,
        MAX(cpf) AS cpf
    FROM
        datalake_ebdb_customer_contact_identification.customer_contact_identification
    WHERE
        channel = 'phone'
    GROUP BY 1
)
SELECT
    COALESCE(ic.id_call, fc.id_call, fc.id_conversation, fc.id_task) AS sk_call, -- only inbound calls have id_call, but all calls have id_task
    ci.id_user AS sk_user,
    ci.cpf AS sk_personal_document,
    CAST(FROM_UNIXTIME(COALESCE(ic.ts_first_event_local_unix,fc.ts_first_event_local_unix), 'yyyyMMdd') AS BIGINT) AS sk_call_date,
    lr.last_queue_name,
    cm.reservations IS NULL AS has_ended_in_ura,
    cm.reservations_accepted > 0 AS is_answered,
    cm.reservations > 1 AS is_transfered,
    ce.csat_2 IS NOT NULL AS is_csat_answered,
    ce.csat_1 = 1 AS is_solved,
    cm.reservations AS tasks,
    cm.reservations_accepted AS answered_tasks,
    fr.first_wait_time AS seconds_first_answer,
    ie.initial_ivr_time AS seconds_ivr_time,
    cm.wait_time_flex AS seconds_total_wait_time,
    cm.talk_time AS seconds_total_talk_time,
    fc.ts_last_event_local_unix - fc.ts_wrapup_event_local_unix AS seconds_wrapup_time,
    fc.ts_last_event_local_unix - fr.ts_first_reservation_local_unix AS seconds_aht,
    GREATEST(ic.ts_last_event_local_unix,fc.ts_last_event_local_unix) - COALESCE(ic.ts_first_event_local_unix,fc.ts_first_event_local_unix) AS seconds_duration,
    ce.csat_2 AS csat_rating,
    fc.is_scheduled,
    NOW() AS ts_load
FROM
    ivr_calls ic
FULL JOIN
    flex_calls fc
        ON fc.id_call = ic.id_call
LEFT JOIN
    initial_ivr_events ie
        ON ie.id_call = ic.id_call
LEFT JOIN
    csat_events ce
        ON ce.id_call = ic.id_call
LEFT JOIN
    call_metrics cm
        ON cm.id_task = fc.id_task
LEFT JOIN
    first_reservation fr
        ON fr.id_task = fc.id_task
LEFT JOIN
    last_reservation lr
        ON lr.id_task = fc.id_task
LEFT JOIN
    customer_identification ci
        ON ci.formatted_phone = COALESCE(ic.customer_phone,fc.customer_phone)
