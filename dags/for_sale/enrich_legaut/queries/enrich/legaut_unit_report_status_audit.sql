SELECT
    al.id AS id_audit_log_entry,
    CAST(al.object_id AS BIGINT) AS id_unit,
    al.ts_audit AS ts_report_status_changed,
    al.audit_action AS audit_action,
    u.email AS email_actor,
    get_json_object(al.changes, '$.report_status[0]') AS report_status_previous,
    get_json_object(al.changes, '$.report_status[1]') AS report_status_new,
    al.changes AS changes_json,
    ct.app_label AS app_label,
    ct.content_model AS content_model
FROM
    datalake_legaut_clean.auditlog_logentry AS al
INNER JOIN
    datalake_legaut_clean.django_content_type AS ct
    ON al.id_content_type = ct.id
LEFT JOIN
    datalake_legaut_clean.accounts_user AS u
    ON al.id_actor = u.id
WHERE
    al.audit_action = 1
    AND LOWER(ct.app_label) = 'meusite'
    AND LOWER(ct.content_model) = 'unit'
    AND get_json_object(al.changes, '$.report_status') IS NOT NULL
