WITH queues AS (
    SELECT
        *
    FROM
        datalake_teravoz_clean.queues
    WHERE
        DATE(
            CONCAT(
                CAST(YEAR AS VARCHAR(4)), '-',
                CAST(MONTH AS VARCHAR(2)), '-',
                CAST(DAY AS VARCHAR(2))
            )
        ) >= DATE('2019-09-01')
),
-- the queues are replicated daily, so the last load contains the more recent data.
queues_last_update AS (
    SELECT
        number,
        MAX(ts_load) AS max_ts_load
    FROM
        queues
    GROUP BY 1
),
queues_name AS (
    SELECT
        q.number,
        q.name
    FROM
        queues q
    INNER JOIN
        queues_last_update ql
            ON q.number=ql.number
            AND q.ts_load=ql.max_ts_load
    GROUP BY 1,2
),
call_events AS (
    SELECT *
    FROM
        datalake_bigfone_events.events
    WHERE
        DATE(
            CONCAT(
                CAST(YEAR AS VARCHAR(4)), '-',
                CAST(MONTH AS VARCHAR(2)), '-',
                CAST(DAY AS VARCHAR(2))
            )
        ) >= DATE('2019-09-01')
),
calls AS (
    SELECT DISTINCT
        id_call
    FROM
        call_events
),
waiting_events AS (
    SELECT
        MIN(id) AS id,
        id_call,
        queue_number,
        ts_created,
        ts_created_local
    FROM
        datalake_bigfone_twilio.call_waiting_events
    WHERE
        dt_event >= DATE('2019-09-01')
    GROUP BY 2,3,4,5
),
waiting_next_events AS (
    SELECT
        MIN(id) AS id,
        id_call,
        ts_created,
        ts_created_local
    FROM
        datalake_bigfone_twilio.call_waiting_next_events
    WHERE
        dt_event >= DATE('2019-09-01')
    GROUP BY 2,3,4
),
/*
    wait_time_interactions = time diff between the next riging, queue-abandon or finished event immediately after 'call_waiting' event AND 'call_waiting' event
    A call can have multiple call_waiting event. So we find the pair (call_waiting, next_event) WHEN:
    1. the events compared are different
    2. MIN(ts_next_event) >= ts_call_waiting, AND ts_call_ringing is the closest to ts_call_waiting
    3. id_call is the same
*/
wait_time_interactions AS (
    SELECT
        wait.id,
        wait.id_call,
        wait.queue_number,
        wait.ts_created AS ts_created_wait_event,
        wait.ts_created_local AS ts_created_wait_event_local,
        MIN(wait_next.id) AS next_event_id,
        MIN(wait_next.ts_created) AS ts_created_next_wait_event,
        MIN(wait_next.ts_created_local) AS ts_created_next_wait_event_local
    FROM
        waiting_events wait
    LEFT JOIN
        waiting_next_events wait_next
            ON wait.id_call = wait_next.id_call
            AND wait.ts_created <= wait_next.ts_created
    GROUP BY 1,2,3,4,5
),
/*
    same_queue_transferred = it must find out if the queue has been transferred to the same queue number:
    So we must find the previous waiting event (queue event) to queue event we are analyzing:
    1. In the first waiting event has no queue transfer in call yet.
    2. MIN(ts_waiting_event) > ts_previous_waiting_event
    3. queue_number must be the same.
*/
same_queue_transferred AS (
    SELECT DISTINCT
        prev.id
    FROM
        wait_time_interactions prev
    INNER JOIN
        wait_time_interactions next
            ON prev.id <> next.id
            AND prev.ts_created_wait_event > next.ts_created_wait_event
            AND prev.queue_number = next.queue_number
            AND prev.id_call = next.id_call
),
/* blind_transfer is a event that occurres before waiting event.
    The metric logic is the same AS wait_time_interactions, just inverted MIN to MAX.
*/
blind_transfer AS (
    SELECT
        wti.id,
        MAX(bt.ts_created) AS ts_created,
        MAX(bt.ts_created_local) AS ts_created_local
    FROM
        datalake_bigfone_twilio.called_blind_transfer_events bt
    INNER JOIN
        wait_time_interactions wti
            ON wti.id_call = bt.id_call
            AND wti.queue_number = destination_called_number
            AND bt.ts_created <= wti.ts_created_wait_event
    WHERE
        dt_event >= DATE('2019-09-01')
    GROUP BY 1
),
abandoned_queue AS (
    SELECT
        id_call,
        queue_number,
        ts_created,
        ts_created_local
    FROM
        datalake_bigfone_twilio.call_queue_abandon_events
    WHERE
        dt_event >= DATE('2019-09-01')
    GROUP BY 1,2,3,4
),
call_finished AS (
    SELECT
        MIN(id) AS id,
        id_call,
        ts_created,
        ts_created_local
    FROM
        datalake_bigfone_twilio.call_finished_events
    WHERE
        dt_event >= DATE('2019-09-01')
    GROUP BY 2,3,4
),
outside_user_phone AS (
    SELECT
        id_user,
        id_call
    FROM
        datalake_user_phone.incoming_user_phone
    WHERE
        DATE(
            CONCAT(
                CAST(YEAR AS VARCHAR(4)), '-',
                CAST(MONTH AS VARCHAR(2)), '-',
                CAST(DAY AS VARCHAR(2))
            )
        ) >= DATE('2019-09-01')
    GROUP BY 1,2
),
dialed_user_phone AS (
    SELECT
        id_user,
        id_call
    FROM
        datalake_user_phone.dialed_user_phone
    WHERE
        DATE(
            CONCAT(
                CAST(YEAR AS VARCHAR(4)), '-',
                CAST(MONTH AS VARCHAR(2)), '-',
                CAST(DAY AS VARCHAR(2))
            )
        ) >= DATE('2019-09-01')
    GROUP BY 1,2
)
SELECT
    wti.id AS sk_call_queued,
    c.id_call AS sk_call,
    wti.queue_number AS sk_queue,
    COALESCE(outside.id_user, dial.id_user) AS sk_user,
    CAST(DATE_FORMAT(wti.ts_created_wait_event, "yyyyMMdd") AS BIGINT) AS sk_call_date,
    CAST(DATE_FORMAT(wti.ts_created_wait_event_local, "yyyyMMdd") AS BIGINT) AS sk_call_date_local,
    wti.queue_number,
    qn.name AS queue_name,
    unix_timestamp(wti.ts_created_next_wait_event) - unix_timestamp(wti.ts_created_wait_event) AS seconds_queue_waiting_duration,
    (transf.id IS NOT NULL) AS is_same_queue_transferred,
    (bt.id IS NOT NULL) AS is_blind_transfer,
    (aq.id_call IS NOT NULL) AS is_call_abandoned_in_queue,
    wti.ts_created_wait_event AS ts_queue_joined,
    wti.ts_created_wait_event_local AS ts_queue_joined_local,
    bt.ts_created AS ts_blinded_transfer,
    bt.ts_created_local AS ts_blinded_transfer_local,
    COALESCE(aq.ts_created, cf.ts_created) AS ts_call_abandoned_in_queue,
    COALESCE(aq.ts_created_local, cf.ts_created_local) AS ts_call_abandoned_in_queue_local,
    wti.ts_created_next_wait_event AS ts_queue_left,
    wti.ts_created_next_wait_event_local AS ts_queue_left_local,
    NOW() AS ts_load
FROM
    calls c
INNER JOIN
    wait_time_interactions wti
        ON c.id_call=wti.id_call
LEFT JOIN
    outside_user_phone outside
        ON c.id_call=outside.id_call
LEFT JOIN
    dialed_user_phone dial
        ON c.id_call=dial.id_call
INNER JOIN
    queues_name qn
        ON wti.queue_number = qn.number
LEFT JOIN
    same_queue_transferred transf
        ON wti.id=transf.id
LEFT JOIN
    blind_transfer bt
        ON wti.id = bt.id
LEFT JOIN
    abandoned_queue aq
        ON wti.id_call = aq.id_call
        AND wti.queue_number = aq.queue_number
LEFT JOIN
    call_finished cf
        ON wti.id_call = cf.id_call
        AND wti.next_event_id = cf.id
