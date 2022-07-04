WITH explode_results AS (
    SELECT
        id_annotation,
        id_project,
        GET_JSON_OBJECT(task.data, "$.id_session") AS id_session,
        completed_by.id AS id_agent,
        EXPLODE(result) AS result
    FROM
        datalake_label_studio_clean.annotations
)
SELECT
    MD5(CONCAT(a.id_annotation, a.id_project, er.id_session, er.id_agent, er.result.id)) AS id_task,
    a.id_annotation,
    a.id_project,
    er.id_session,
    er.id_agent,
    er.result.id AS id_result,
    a.project_name,
    CASE
        WHEN a.task.email IS NOT NULL THEN a.task.email
        ELSE SPLIT(a.created_username, '[,]')[0]
    END AS agent_email,
    CASE
        WHEN GET_JSON_OBJECT(a.task.data, "$.message") IS NOT NULL THEN REGEXP_REPLACE(GET_JSON_OBJECT(a.task.data, "$.message"), '<.+?>', '')
        ELSE REGEXP_REPLACE(GET_JSON_OBJECT(a.task.data, "$.text_message"), '<.+?>', '')
    END AS session_message,
    a.task.overlap AS session_overlap,
    GET_JSON_OBJECT(er.result.value, "$.choices") AS result_choice,
    a.task.is_labeled AS is_labeled,
    CASE
        WHEN project_name LIKE "%consistencia%" THEN TRUE
        ELSE FALSE
    END is_consistency,
    CAST(a.task.created_at AS TIMESTAMP) AS ts_session_created,
    CAST(a.task.updated_at AS TIMESTAMP) AS ts_session_updated,
    a.ts_created,
    a.ts_updated
FROM
    datalake_label_studio_clean.annotations a
LEFT JOIN
    explode_results er
        ON a.id_annotation = er.id_annotation
        AND a.id_project = er.id_project
        AND GET_JSON_OBJECT(a.task.data, "$.id_session") = er.id_session
        AND a.completed_by.id = er.id_agent