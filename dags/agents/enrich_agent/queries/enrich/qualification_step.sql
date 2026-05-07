SELECT
    q.id_agent_prospect AS id_prospect_agent,
    qsp.id_qualification,
    qsp.id_qualification_step,
    qsp.id AS id_qualification_step_progress,
    IF(qsp.author_type = "USUARIO", qsp.id_author_identifier, NULL) AS id_user_step_responsible,
    q.uuid_qualification,
    q.state AS qualification_state,
    q.reason AS qualification_state_reason,
    qs.name AS step_name,
    qsp.status AS step_status,
    qsp.reason AS step_reason,
    qsp.ts_changed AS ts_step_changed,
    qsp.ts_created AS ts_step_created,
    q.ts_created AS ts_qualification_created,
    q.ts_updated AS ts_qualification_updated
FROM
    datalake_ebdb_clean.qualification AS q
LEFT JOIN
    datalake_ebdb_clean.qualification_step_progress AS qsp
        ON qsp.id_qualification = q.id
LEFT JOIN
    datalake_ebdb_clean.qualification_step AS qs
        ON qs.id = qsp.id_qualification_step