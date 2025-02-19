SELECT
    id,
    task_sid AS id_task,
    GET_JSON_OBJECT(task_attributes,'$.conversations.conversation_attribute_4') AS id_reservation,
    GET_JSON_OBJECT(task_attributes,'$.worker_sid') AS id_worker,
    user_id AS id_user,
    session_id AS id_session,
    task_attributes,
    task_status,
    task_resource,
    user_phone,
    GET_JSON_OBJECT(task_attributes,'$.conversations.communication_channel') AS communication_channel,
    GET_JSON_OBJECT(task_attributes,'$.BPO') AS bpo_name,
    GET_JSON_OBJECT(task_attributes,'$.target') AS queue_name,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_bigfone_raw.scheduledcalltask
