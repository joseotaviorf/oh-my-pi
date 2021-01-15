WITH
    call_events AS (
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
        SELECT
            id_call,
            MIN(ts_created) AS ts_created_min,
            MIN(ts_created_local) AS ts_created_min_local,
            MAX(ts_created) AS ts_created_max,
            MAX(ts_created_local) AS ts_created_max_local
        FROM
            call_events
        GROUP BY 1
    ),
    -- Each Teravoz call generates a ticket ON Zendesk, if the integration was stable FROM Semptember 2019,
    -- we can filter Zendesk tickets FROM that DATE.
    zendesk_integration AS (
        SELECT
            id_ticket,
            -- the value "360020220412" correspond to column id that contains the id_call value.
            get_json_object(custom_fields, '$.360020220412') AS id_call,
            ts_updated
        FROM
            datalake_clean.zendesk_custom_fields
        WHERE
            ts_updated >= '2019-09-01'
            AND get_json_object(custom_fields, '$.360020220412') <> ''
    ),
    -- The table called zendesk_tickets repeats the same ticket for different dates.
    -- But the last update = MAX(ts_updated) contains the latest values.
    last_updated_tickets AS (
        SELECT
            zt.id_ticket,
            zt.id_call
        FROM (
            SELECT
                id_ticket,
                MAX(ts_updated) AS ts_last_updated
            FROM
                zendesk_integration
            GROUP BY 1
        ) last_zt
        INNER JOIN
            zendesk_integration zt
                ON last_zt.id_ticket=zt.id_ticket
                AND last_zt.ts_last_updated=zt.ts_updated
    ),
    zendesk_tickets_custom_fields AS (
        SELECT
            MIN(id_ticket) AS id_ticket,
            id_call
        FROM
            last_updated_tickets
        GROUP BY 2
    ),
    incoming_user_phone AS (
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
    ),
    agent_entered_events AS (
        SELECT
            MIN(id) AS id,
            id_call,
            agent_email,
            ts_created,
            ts_created_local
        FROM
            datalake_bigfone_twilio.agent_entered_events
        WHERE
            dt_event >= DATE('2019-09-01')
        GROUP BY 2,3,4,5
    ),
    agent_left_events AS (
        SELECT
            id_call,
            agent_email,
            ts_created
        FROM
            datalake_bigfone_twilio.agent_left_events
        WHERE
            dt_event >= DATE('2019-09-01')
        GROUP BY 1,2,3
    ),
    -- talk_time_interactions = time diff between the 'agent_left' event AND 'agent_entered' event
    -- A call can have multiple agent_entered AND agent_left events. So we find the pair (entered, left) WHEN:
    -- 1. agent_email is the same
    -- 2. MIN(ts_left) >= ts_entered, AND ts_left is the closest to ts_entered
    -- 3. id_call is the same
    talk_time AS (
        SELECT
            id_call,
            sum(CAST(ts_created_left_event AS BIGINT) - CAST(ts_created_entered_event AS BIGINT)) AS seconds_talk_time
        FROM (
            SELECT
                enter.id_call,
                enter.ts_created AS ts_created_entered_event,
                MIN(lef.ts_created) AS ts_created_left_event
            FROM
                agent_entered_events enter
            INNER JOIN
                agent_left_events lef
                    ON enter.id_call=lef.id_call
                    AND enter.agent_email=lef.agent_email
                    AND lef.ts_created>=enter.ts_created
            GROUP BY 1,2
        )
        GROUP BY 1
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
    -- wait_time_interactions = time diff between the next riging, queue-abandon or finished event immediately after 'call_waiting' event AND 'call_waiting' event
    -- A call can have multiple call_waiting event. So we find the pair (call_waiting, next_event) WHEN:
    -- 1. the events compared are different
    -- 2. MIN(ts_next_event) >= ts_call_waiting, AND ts_call_ringing is the closest to ts_call_waiting
    -- 3. id_call is the same
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
    wait_time AS (
        SELECT
            id_call,
            SUM(CAST(ts_created_next_wait_event AS BIGINT) - CAST(ts_created_wait_event AS BIGINT)) AS seconds_wait_time
        FROM
            wait_time_interactions
        GROUP BY 1
    ),
    ura AS (
        SELECT
            id_call,
            MIN(ts_created) AS ts_first_ura_event,
            MIN(ts_created_local) AS ts_first_ura_event_local,
            MAX(ts_created) AS ts_last_ura_event,
            MAX(ts_created_local) AS ts_last_ura_event_local
        FROM
            datalake_bigfone_twilio.call_ura_events
        WHERE
            dt_event >= DATE('2019-09-01')
        GROUP BY 1
    ),
    queues AS (
        SELECT
            id_call,
            COUNT(DISTINCT queue_number) AS unique_queues_per_call,
            COUNT(DISTINCT id) AS queues_per_call
        FROM
            wait_time_interactions
        GROUP BY 1
    ),
    agents AS (
        SELECT
            id_call,
            COUNT(DISTINCT id) AS agents_per_call,
            COUNT(DISTINCT agent_email) AS unique_agents_per_call,
            MIN(ts_created) AS ts_created_min,
            MIN(ts_created_local) AS ts_created_min_local
        FROM
            agent_entered_events
        GROUP BY 1
    ),
    agent_ringing_events AS (
        SELECT DISTINCT
            id_call
        FROM
            datalake_bigfone_twilio.agent_ringing_events
        WHERE
            dt_event >= DATE('2019-09-01')
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
    agent_ring_events AS (
        SELECT
            ring.id_call,
            ring.agent_email,
            ring.ts_created_local AS ts_min_local
        FROM
            call_ring_events ring
        INNER JOIN
            agent_entered_events ae
                ON ae.id_call = ring.id_call
                AND ae.ts_created > ring.ts_created
        GROUP BY 1,2,3
    ),
    ring_summary AS (
        SELECT
            are.id_call,
            are.agent_email,
            MIN(are.ts_min_local) AS ts_min_local
        FROM
            agent_ring_events are
        GROUP BY 1,2
    ),
    call_context_data AS (
        SELECT
            id_call,
            call_direction
        FROM
            datalake_bigfone_twilio.call_context_data
        WHERE
            dt_event >= DATE('2019-09-01')
        GROUP BY 1,2
    ),
    last_queue_for_agent AS (
        SELECT DISTINCT
            wti.id_call,
            MAX(wti.ts_created_wait_event_local) AS ts_created_wait_event_local,
            MAX(rs.ts_min_local) AS ts_min_local
        FROM
            wait_time_interactions wti
        INNER JOIN
            agent_entered_events ae
                ON wti.id_call = ae.id_call
        INNER JOIN
            ring_summary rs
                ON rs.id_call = wti.id_call
                AND rs.agent_email = ae.agent_email
        GROUP BY 1
    ),
    last_queued_calls AS (
        SELECT DISTINCT
            c.id_call,
            (aq.id_call IS NOT NULL) AS is_call_abandoned_in_queue,
            COALESCE(a.unique_agents_per_call>0, false) AS is_call_answered_by_agent,
            a.unique_agents_per_call,
            wti.queue_number,
            wti.ts_created_wait_event_local,
            rs.ts_min_local
        FROM
            calls c
        INNER JOIN
            agents a
                ON c.id_call = a.id_call
        LEFT JOIN
            wait_time_interactions wti
                ON wti.id_call = c.id_call
        LEFT JOIN
            abandoned_queue aq
                ON wti.id_call = aq.id_call
                AND wti.queue_number = aq.queue_number
        INNER JOIN
            agent_entered_events ae
                ON wti.id_call = ae.id_call
        INNER JOIN
            ring_summary rs
                ON rs.id_call = wti.id_call
    ),
    distinct_agent_totals AS (
        SELECT DISTINCT
            lq.id_call,
            lq.unique_agents_per_call
        FROM
            last_queued_calls lq
        JOIN
            call_context_data cdc
                ON cdc.id_call = lq.id_call
        JOIN
            last_queue_for_agent lqfa
                ON lqfa.id_call = lq.id_call
        WHERE
            cdc.call_direction = 'inbound'
            AND lq.is_call_answered_by_agent = true
            AND lq.is_call_abandoned_in_queue = false
            AND lq.ts_created_wait_event_local = lqfa.ts_created_wait_event_local
            AND lq.ts_min_local = lqfa.ts_min_local
    )
SELECT
    c.id_call AS sk_call,
    COALESCE(incoming.id_user, dial.id_user) AS sk_user,
    CAST(zt.id_ticket AS BIGINT) AS sk_ticket,
    CAST(DATE_FORMAT(c.ts_created_min, 'yyyyMMdd') AS BIGINT) AS sk_call_date,
    CAST(DATE_FORMAT(c.ts_created_min_local, 'yyyyMMdd') AS BIGINT) AS sk_call_date_local,
    CAST(COALESCE(q.queues_per_call,0) AS TINYINT) AS total_queues,
    CAST(COALESCE(q.unique_queues_per_call,0) AS TINYINT) AS total_unique_queues,
    CAST(COALESCE(a.agents_per_call,0) AS TINYINT) AS total_agents,
    CAST(COALESCE(a.unique_agents_per_call, 0) AS TINYINT) AS total_unique_agents,
    CAST(CAST(c.ts_created_max AS BIGINT) - CAST(c.ts_created_min AS BIGINT) AS INTEGER) AS seconds_total_call_duration,
    CAST(tk.seconds_talk_time AS INTEGER) AS seconds_total_talk_duration,
    CAST(wt.seconds_wait_time AS INTEGER) AS seconds_total_wait_duration,
    CAST(CAST(ura.ts_last_ura_event AS BIGINT) - CAST(ura.ts_first_ura_event AS BIGINT) AS INTEGER) AS seconds_total_ura_duration,
    CAST(csat.csat_rating AS TINYINT) AS csat_rating,
    COALESCE(a.agents_per_call>0, false) AS is_call_answered,
    csat.is_csat_set AS is_csat_answered,
    csat.has_call_satisfied_customer,
    COALESCE(
        ura.id_call IS NOT NULL -- calls classified by Akinator don't have ura events
        AND wait.id_call IS NULL -- no call waiting for available agent
        AND a.id_call IS NULL -- no agent entered
        AND ring.id_call IS NULL, -- no peer ringing
        false
    ) AS is_call_ended_in_ura,
    COALESCE(
        (wait.id_call IS NOT NULL OR ring.id_call IS NOT NULL) -- call waiting for available agent or peer ringing
        AND a.id_call IS NULL, -- no agent entered
        false
    ) AS is_call_missed,
    ura.ts_first_ura_event AS ts_ura_joined,
    ura.ts_first_ura_event_local AS ts_ura_joined_local,
    ura.ts_last_ura_event AS ts_ura_left,
    ura.ts_last_ura_event_local AS ts_ura_left_local,
    a.ts_created_min AS ts_first_call_answered,
    a.ts_created_min_local AS ts_first_call_answered_local,
    COALESCE(dat.unique_agents_per_call = 1, False) AS is_call_ended_and_answered_by_one_agent,
    COALESCE(dat.unique_agents_per_call > 1, False) AS is_call_ended_and_answered_by_multiple_agents,
    c.ts_created_min AS ts_started,
    c.ts_created_min_local AS ts_started_local,
    csat.ts_started AS ts_csat_answered,
    csat.ts_started_local AS ts_csat_answered_local,
    c.ts_created_max AS ts_ended,
    c.ts_created_max_local AS ts_ended_local,
    NOW() AS ts_load
FROM
    calls c
LEFT JOIN
    zendesk_tickets_custom_fields zt
        ON c.id_call=zt.id_call
LEFT JOIN
    incoming_user_phone incoming
        ON c.id_call=incoming.id_call
LEFT JOIN
    dialed_user_phone dial
        ON c.id_call=dial.id_call
LEFT JOIN
    talk_time tk
        ON c.id_call=tk.id_call
LEFT JOIN
    wait_time wt
        ON c.id_call=wt.id_call
LEFT JOIN
    ura
        ON c.id_call=ura.id_call
LEFT JOIN
    queues q
        ON c.id_call=q.id_call
LEFT JOIN
    agents a
        ON c.id_call=a.id_call
LEFT JOIN
    datalake_bigfone_twilio.call_csat_events csat
        ON c.id_call=csat.id_call
LEFT JOIN (
    SELECT DISTINCT
        id_call
    FROM
        waiting_events
    ) wait
        ON c.id_call=wait.id_call
LEFT JOIN
    agent_ringing_events ring
        ON c.id_call=ring.id_call
LEFT JOIN
    distinct_agent_totals dat
        ON c.id_call=dat.id_call
