SELECT
    se.id_event AS sk_service,
    se.id_event,
    se.id_event_type,
    se.id_session,
    se.id_support_session,
    se.id_task,
    se.id_task_event,
    se.id_channel,
    se.id_reservation,
    se.id_call,
    COALESCE(CAST(se.id_user AS BIGINT), -1) AS id_user,
    MD5(COALESCE(se.worker_email, 'NULL')) AS id_worker,
    MD5(COALESCE(se.queue_name, 'NULL')) AS id_queue,
    se.id_source_ctwa,
    se.worker_email,
    se.database_source,
    se.service_type,
    se.direction,
    se.channel_type,
    se.origin,
    se.bpo_name,
    se.bpo_selection_reason,
    se.queue_name,
    CASE
        WHEN se.service_type = 'chat' THEN
            CASE
                WHEN COALESCE(se.task_completion_reason, se.task_outcome) = 'task idled' THEN 'idled'
                WHEN COALESCE(se.task_completion_reason, se.task_outcome) = 'session expired' THEN 'expired'
                WHEN COALESCE(se.task_completion_reason, se.task_outcome) = 'task completed' THEN 'completed'
                WHEN COALESCE(se.task_completion_reason, se.task_outcome) = 'task transferred' THEN 'transferred'
                ELSE 'transferred'
            END
        WHEN se.service_type = 'call' THEN
            CASE
                WHEN se.task_cancelation_reason IS NOT NULL THEN 'abandoned'
                ELSE 'transferred'
            END
    END AS status,
    se.task_cancelation_reason,
    se.url_source_ctwa,
    se.type_source_ctwa,
    se.waiting_time_sec,
    se.seconds_to_first_response,
    CASE
        WHEN se.service_type = 'call' THEN se.waiting_time_sec
        WHEN se.service_type = 'chat' THEN se.seconds_to_first_response
    END AS first_response_time_sec,
    se.total_inactivity_time,
    se.last_inactivity_time,
    CASE
        WHEN se.service_type = 'chat' THEN
            CASE
                WHEN se.task_status = 'canceled' THEN FALSE
                WHEN COALESCE(se.task_completion_reason, se.task_outcome) = 'Task TTL Exceeded or Max assignment count exceeded' THEN FALSE
                ELSE TRUE
            END
        WHEN se.service_type = 'call' THEN
            CASE
                WHEN se.task_cancelation_reason IS NOT NULL THEN FALSE
                ELSE TRUE
            END
    END AS is_answered,
    CASE
        WHEN se.service_type = 'call'
            AND se.task_cancelation_reason IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_abandoned,
    se.is_forwarded,
    se.is_per_team_task,
    se.is_spoc_task,
    se.is_isaias_session,
    se.direction = 'inbound' AS is_inbound,
    DATE(se.ts_task_created) AS dt_task_created,
    se.ts_task_created,
    se.ts_task_updated,
    se._ts_load,
    se._effective_timestamp,
    se._expired_timestamp,
    se._is_current
FROM
    core_support_journey.services AS se
WHERE
    _last_updated_at >= '{load_start_date}'
    AND _last_updated_at < '{load_end_date}'
