SELECT
    qsp.id AS id_qualification_step_progress,
    q.id_agent_prospect AS id_prospect_agent,
    qsp.id_qualification,
    qsp.id_qualification_step,
    IF(qsp.author_type = "USUARIO", qsp.id_author_identifier, NULL) AS id_user_step_responsible,
    q.uuid_qualification,
    q.state AS qualification_state,
    q.reason AS qualification_state_reason,
    qs.name AS step_name,
    qs.description AS step_description,
    qsp.status AS step_status,
    qsp.reason AS step_reason,
    IF(qs.name = 'CRECI_VALIDATION', IF(cv.status = 'INCONCLUSIVE', cv.reason, cv.status), NULL) AS automatic_creci_status,
    qsp.author_type AS step_author_type,
    IF(qs.name = 'CRECI_VALIDATION', qsp.status = 'APPROVED' AND (automatic_creci_status <> 'ACTIVE' OR automatic_creci_status IS NULL), NULL) AS is_creci_manually_approved,
    qsp.ts_changed AS ts_step_changed,
    qsp.ts_created AS ts_step_created,
    q.ts_created AS ts_qualification_created,
    q.ts_updated AS ts_qualification_updated
FROM
    datalake_ebdb_clean.qualification_step_progress AS qsp
JOIN
    datalake_ebdb_clean.qualification AS q
        ON qsp.id_qualification = q.id
JOIN
    datalake_ebdb_clean.qualification_step AS qs
        ON qs.id = qsp.id_qualification_step
LEFT JOIN
    datalake_ebdb_clean.quintoandar_prospect_agent AS qapa
        ON qapa.id_prospect_agent = q.id_agent_prospect
LEFT JOIN
    datalake_ebdb_clean.creci_validation AS cv
        ON qapa.uuid_creci_validation = cv.uuid_creci_validation
