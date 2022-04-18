WITH explode_results AS (
    SELECT
        id_annotation,
        task['project'] AS id_project,
        task['id_session_data'] AS id_session,
        completed_by['id'] AS id_agent,
        EXPLODE(result) AS result
    FROM
        datalake_label_studio_clean.annotations
)
SELECT
    MD5(CONCAT(a.id_annotation, er.id_project, er.id_session, er.id_agent, er.result['id'])) AS id_task,
    a.id_annotation,
    er.id_project,
    er.id_session,
    er.id_agent,
    er.result['id'] AS id_result,
    CASE
        WHEN a.task['email'] IS NOT NULL THEN a.task['email']
        ELSE SPLIT(a.created_username, '[,]')[0]
    END AS agent_email,
    a.task['user_info_data'] AS session_user,
    CASE
        WHEN a.task['message_data'] IS NOT NULL THEN a.task['message_data']
        ELSE a.task['text_message_data']
    END AS session_message,
    a.task['overlap'] AS session_overlap,
    a.task['hsm_content_data'] AS hsm_content,
    a.task['owner_contract_info_data'] AS owner_contract_info, 
    a.task['tenant_contract_info_data'] AS tenant_contract_info, 
    a.task['house_info_data'] AS house_info, 
    er.result['value'] AS result_choice,
    a.lead_time AS task_lead_time,
    a.task['is_labeled'] AS is_labeled,
    CASE
        WHEN project_name LIKE "%consistencia%" THEN TRUE
        ELSE FALSE
    END is_consistency,
    CAST(a.task['created_at'] AS TIMESTAMP) AS ts_session_created,
    CAST(a.task['updated_at'] AS TIMESTAMP) AS ts_session_updated,
    a.ts_created,
    a.ts_updated
FROM
    datalake_label_studio_clean.annotations a
LEFT JOIN
    explode_results er
        ON a.id_annotation = er.id_annotation
        AND a.task['project'] = er.id_project
        AND a.task['id_session_data'] = er.id_session
        AND a.completed_by['id'] = er.id_agent