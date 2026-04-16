SELECT
    id,
    content_type_id AS id_content_type,
    object_pk,
    object_id,
    object_repr,
    action AS audit_action,
    changes,
    actor_id AS id_actor,
    remote_addr,
    `timestamp` AS ts_audit,
    additional_data,
    NOW() AS ts_load
FROM
    datalake_legaut_raw.auditlog_logentry
