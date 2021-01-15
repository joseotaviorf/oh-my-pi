WITH call_events AS (
    SELECT
        *
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
ringing_events AS (
    SELECT
        id_call,
        agent_email,
        ts_created
    FROM
        datalake_bigfone_twilio.agent_ringing_events
    WHERE
        dt_event >= DATE('2019-09-01')
    GROUP BY 1,2,3
),
agents_in_call AS (
    SELECT
        c.id_call,
        ring.agent_email,
        MAX(wait.id) AS id_call_queued
    FROM
        calls c
    INNER JOIN
        waiting_events wait
            ON c.id_call = wait.id_call
    INNER JOIN
        ringing_events ring
            ON c.id_call = ring.id_call
            AND wait.ts_created <= ring.ts_created
    GROUP BY 1,2
),
agent AS (
    SELECT
        id,
        ac.id_call,
        u.email,
        (u.id IS NULL) AS outsourcing_company
    FROM
        agents_in_call ac
    LEFT JOIN
        datalake_ebdb_clean.user u
            ON ac.agent_email = u.email
),
agent_entered_events AS (
	SELECT
        MIN(id) AS id,
        id_call,
        agent_email,
        extension_number,
        ts_created,
        ts_created_local
	FROM
        datalake_bigfone_twilio.agent_entered_events
	WHERE
        dt_event >= DATE('2019-09-01')
    GROUP BY 2,3,4,5,6
),
agent_left_events AS (
    SELECT
        id_call,
        agent_email,
        ts_created,
        ts_created_local
    FROM
        datalake_bigfone_twilio.agent_left_events
    WHERE
        dt_event >= DATE('2019-09-01')
    GROUP BY 1,2,3,4
),
talk_time AS (
    SELECT
        enter.id_call,
        enter.ts_created AS ts_created_entered_event,
        enter.ts_created_local AS ts_created_entered_event_local,
        enter.agent_email,
        enter.extension_number,
        MIN(lef.ts_created) AS ts_created_left_event,
        MIN(lef.ts_created_local) AS ts_created_left_event_local
    FROM
        agent_entered_events enter
    INNER JOIN
        agent_left_events lef
            ON enter.id_call = lef.id_call
            AND enter.agent_email = lef.agent_email
            AND lef.ts_created >= enter.ts_created
    GROUP BY 1,2,3,4,5
),
call_ring_events AS (
	SELECT
        MIN(id) AS id,
        id_call,
        agent_email,
        ts_created,
        ts_created_local
	FROM
        datalake_bigfone_twilio.agent_ringing_events
	WHERE
        dt_event >= DATE('2019-09-01')
    GROUP BY 2,3,4,5
),
/******************************
 retrieve the first AND last ring events for the call AND consider the next event after the last AS the stop
for the ring time
*******************************/
ring_summary AS (
    SELECT
        id_call,
        agent_email,
        ts_max,
        MIN(ts_min) AS ts_min,
        MIN(ts_min_local) AS ts_min_local
    FROM (
        SELECT
            ring.id_call,
            ring.agent_email,
            ring.ts_created AS ts_min,
            ring.ts_created_local AS ts_min_local,
            MIN(ae.id) AS enter_id,
            MIN(ae.ts_created) AS ts_max
        FROM
            call_ring_events ring
        INNER JOIN
            agent_entered_events ae
                ON ae.id_call = ring.id_call
                AND ae.ts_created > ring.ts_created
        GROUP BY 1,2,3,4
    )
    GROUP BY 1,2,3
),
ring_events_into_summary AS (
    SELECT
        ring.id_call,
        ring.agent_email AS agent_email,
        ring_summary.ts_min AS ts_created_ring_event,
        ring_summary.ts_min_local AS ts_created_ring_event_local,
        MAX(ring.ts_created) AS ts_created_last_ring_event,
        MAX(ring.id) AS last_ring_event_id
    FROM
        call_ring_events ring
    INNER JOIN
        ring_summary
            ON ring_summary.id_call = ring.id_call
            AND ring_summary.agent_email = ring.agent_email
            AND ring.ts_created >= ring_summary.ts_min
            AND ring.ts_created < ring_summary.ts_max
    GROUP BY 1,2,3,4
),
ring_time AS (
    SELECT
        ring.id_call,
        ring.ts_created_ring_event,
        ring.ts_created_ring_event_local,
        ring.agent_email,
        MIN(e.ts_created) AS ts_created_next_ring_event
    FROM
        call_events e
    INNER JOIN
        ring_events_into_summary ring
            ON ring.id_call = e.id_call
            AND ring.ts_created_last_ring_event <= e.ts_created
            AND e.id <> ring.last_ring_event_id
    GROUP BY 1,2,3,4
),
ring_talk_interaction AS (
    SELECT
        ring.id_call,
        ring.agent_email,
        ring.ts_created_ring_event,
        ring.ts_created_ring_event_local,
        ring.ts_created_next_ring_event,
        MIN(talk.ts_created_entered_event) AS ts_created_talk_event,
        MIN(talk.ts_created_entered_event_local) AS ts_created_talk_event_local
    FROM
        ring_time ring
    LEFT JOIN
        talk_time AS talk
            ON ring.id_call = talk.id_call
            AND ring.agent_email = talk.agent_email
            AND talk.ts_created_entered_event >= ring.ts_created_ring_event
    GROUP BY 1,2,3,4,5
)
SELECT
    re.id AS sk_call_agent_interaction,
    c.id_call AS sk_call,
    ac.agent_email AS sk_agent,
    ac.id_call_queued AS sk_call_queued,
    COALESCE (a.id, -1) AS sk_user,
    CAST(DATE_FORMAT(tt.ts_created_entered_event, 'yyyyMMdd') AS BIGINT) AS sk_agent_answered_date,
    CAST(DATE_FORMAT(tt.ts_created_entered_event_local, 'yyyyMMdd') AS BIGINT) AS sk_agent_answered_date_local,
    COALESCE(a.email, tt.agent_email) email_agent,
    tt.extension_number AS extension_number,
    UNIX_TIMESTAMP(rti.ts_created_next_ring_event) -  UNIX_TIMESTAMP(rti.ts_created_ring_event) AS seconds_call_ringing_time,
    UNIX_TIMESTAMP(tt.ts_created_left_event) -  UNIX_TIMESTAMP(tt.ts_created_entered_event) AS seconds_talk_time_agent,
    (tt.id_call IS NOT NULL) AS is_call_answered_by_agent,
    a.outsourcing_company AS is_call_answered_from_outsourcing_company,
    tt.ts_created_entered_event AS ts_agent_answered,
    tt.ts_created_entered_event_local AS ts_agent_answered_local,
    tt.ts_created_left_event AS ts_agent_hangup,
    tt.ts_created_left_event_local AS ts_agent_hangup_local,
    rti.ts_created_ring_event AS ts_agent_extension_rang,
    rti.ts_created_ring_event_local AS ts_agent_extension_rang_local,
    NOW() AS ts_load
FROM
    calls c
INNER JOIN
    agents_in_call ac
        ON c.id_call = ac.id_call
INNER JOIN
    agent a
        ON c.id_call = a.id_call
        AND ac.agent_email = a.email
INNER JOIN
    ring_talk_interaction rti
        ON rti.id_call = c.id_call
        AND rti.agent_email = ac.agent_email
INNER JOIN
    call_ring_events re
        ON re.id_call = rti.id_call
        AND re.agent_email = rti.agent_email
        AND re.ts_created = rti.ts_created_ring_event
LEFT JOIN
    talk_time tt
        ON rti.id_call = tt.id_call
        AND rti.agent_email = tt.agent_email
        AND tt.ts_created_entered_event = rti.ts_created_talk_event
