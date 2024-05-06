-- AHT stands for Average Handling Time
WITH tasks_last_update AS (
    SELECT
        id,
        MAX(to_date(CONCAT(year,'-',month,'-',day))) AS dt_last_update
    FROM
        datalake_quinto_messenger_clean.task
    GROUP BY 1
),
task_events_last_update AS (
    SELECT
        id,
        MAX(to_date(CONCAT(year,'-',month,'-',day))) AS dt_last_update
    FROM
        datalake_quinto_messenger_clean.task_event
    GROUP BY 1
),
tasks_time_info AS (
    SELECT
        id_task AS id_task_external,
        MAX(CASE WHEN event_type = 'reservation.accepted' THEN (ts_created - INTERVAL '3' HOUR) END) AS ts_reservation_accepted_local,
        MAX(CASE WHEN event_type = 'reservation.completed' THEN (ts_created - INTERVAL '3' HOUR)  END) AS ts_reservation_completed_local,
        MIN(ts_created - INTERVAL '3' HOUR) AS ts_task_created_local,
        MAX(ts_created - INTERVAL '3' HOUR) AS ts_task_ended_local
    FROM
        datalake_quinto_messenger_clean.task_event te
    JOIN
        task_events_last_update lu
            ON lu.id = te.id
            AND lu.dt_last_update = to_date(CONCAT(year,'-',month,'-',day))
    GROUP BY 1
),
tasks_attributes AS (
    SELECT
        id_task AS id_external,
        id_channel AS id_channel_external,
        (ts_created - INTERVAL '3' HOUR) AS ts_task_created_local,
        get_json_object(task_resource, '$.task_queue_friendly_name') AS department_name,
        get_json_object(assigned_to, '$.worker_sid') AS id_agent,
        get_json_object(assigned_to, '$.worker_name') AS agent_email,
        seconds_to_first_response
    FROM
        datalake_quinto_messenger_clean.task t
    JOIN
        tasks_last_update lu
            ON lu.id = t.id
            AND lu.dt_last_update = to_date(CONCAT(year,'-',month,'-',day))
),
chat_tasks_structure AS (
    SELECT
        ta.id_external AS id_task,
        ta.id_channel_external AS id_conversation,
        ta.department_name,
        ta.id_agent,
        ta.agent_email,
        to_date(ta.ts_task_created_local) AS dt_task_created_local,
        ta.ts_task_created_local,
        COALESCE(tti.ts_reservation_accepted_local, ta.ts_task_created_local) AS ts_reservation_accepted_local,
        COALESCE(tti.ts_reservation_completed_local, tti.ts_task_ended_local) AS ts_reservation_completed_local,
        to_unix_timestamp(COALESCE(tti.ts_reservation_completed_local, tti.ts_task_ended_local)) -
            to_unix_timestamp(COALESCE(tti.ts_reservation_accepted_local, ta.ts_task_created_local)) AS seconds_engagement_duration
    FROM
        tasks_attributes AS ta
    LEFT JOIN
        tasks_time_info AS tti
            ON ta.id_external = tti.id_task_external
),
ordered_tasks AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY dt_task_created_local, id_agent, department_name ORDER BY ts_reservation_accepted_local ASC) AS task_index,
        LAG(ts_reservation_completed_local) OVER (PARTITION BY dt_task_created_local, id_agent, department_name ORDER BY ts_reservation_completed_local ASC) AS ts_previous_reservation_completed_local
    FROM
        chat_tasks_structure
),
local_max AS (
    SELECT
        ot1.id_task,
        ot1.id_conversation,
        ot1.department_name,
        ot1.id_agent,
        ot1.agent_email,
        ot1.task_index,
        ot1.seconds_engagement_duration,
        ot1.dt_task_created_local,
        ot1.ts_task_created_local,
        ot1.ts_reservation_accepted_local,
        ot1.ts_reservation_completed_local,
        ot1.ts_previous_reservation_completed_local,
        MAX(ot2.ts_reservation_completed_local) AS ts_local_max_reservation_completed
    FROM
        ordered_tasks AS ot1
    JOIN
        ordered_tasks AS ot2
            ON ot1.dt_task_created_local = ot2.dt_task_created_local
            AND ot1.id_agent = ot2.id_agent
            AND ot1.department_name = ot2.department_name
            AND ot2.task_index <= ot1.task_index
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
previous_local_max AS (
    SELECT
        lm.*,
        LAG(lm.ts_local_max_reservation_completed) OVER (PARTITION BY lm.dt_task_created_local, lm.id_agent, lm.department_name ORDER BY lm.task_index ASC) AS ts_previous_local_max
   FROM
       local_max AS lm
),
delta_task_time AS (
    SELECT
        *,
        to_unix_timestamp(ts_reservation_accepted_local) - to_unix_timestamp(ts_previous_local_max) AS seconds_delta_task
    FROM
        previous_local_max
),
idle_time AS (
    SELECT DISTINCT
        dt_task_created_local,
        id_agent,
        agent_email,
        department_name,
        MIN(ts_reservation_accepted_local) AS ts_start_first_task,
        MAX(ts_local_max_reservation_completed) AS ts_end_last_task,
        COALESCE(SUM((CASE WHEN (seconds_delta_task > 0) THEN seconds_delta_task END)), 0) AS seconds_idle_time
   FROM
       delta_task_time
   GROUP BY 1,2,3,4
),
chatting_duration AS (
    SELECT
        dt_task_created_local,
        id_agent,
        agent_email,
        department_name,
        ts_start_first_task,
        ts_end_last_task,
        seconds_idle_time,
        ((to_unix_timestamp(ts_end_last_task) - to_unix_timestamp(ts_start_first_task)) - seconds_idle_time) AS seconds_chatting_duration
    FROM
        idle_time
),
engagement_metrics AS (
    SELECT
        dt_task_created_local,
        id_agent,
        agent_email,
        department_name,
        count(id_task) AS tasks,
        round(AVG(seconds_engagement_duration), 2) AS average_seconds_task_duration,
        round(SUM(seconds_engagement_duration), 2) AS cumulative_seconds_chatting_duration
   FROM
        chat_tasks_structure
   GROUP BY 1,2,3,4
)
SELECT
    cd.dt_task_created_local,
    a.email AS agent_email,
    a.organization AS agent_organization,
    cd.department_name,
    cd.ts_start_first_task,
    cd.ts_end_last_task,
    cd.seconds_idle_time,
    em.tasks,
    em.average_seconds_task_duration,
    em.cumulative_seconds_chatting_duration,
    cd.seconds_chatting_duration,
    CASE
      WHEN ((1.0 * em.cumulative_seconds_chatting_duration) / cd.seconds_chatting_duration) > 1.0
          THEN ROUND(((1.0 * em.cumulative_seconds_chatting_duration) / cd.seconds_chatting_duration), 2)
      WHEN ((1.0 * em.cumulative_seconds_chatting_duration) / cd.seconds_chatting_duration) <= 1.0
          THEN 1.0
    END AS average_concurrency,
    ROUND((em.average_seconds_task_duration / ((1.0 * em.cumulative_seconds_chatting_duration) / cd.seconds_chatting_duration)), 2) AS average_handling_time_seconds
FROM
    chatting_duration AS cd
JOIN
    engagement_metrics AS em
        ON cd.dt_task_created_local = em.dt_task_created_local
        AND cd.id_agent = em.id_agent
        AND cd.department_name = em.department_name
LEFT JOIN
    datalake_support_users.analysts AS a
        ON cd.agent_email = a.email
ORDER BY 1,2
